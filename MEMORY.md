# MEMORY.md — 项目交接文档

> 更新：2026-09-25 晚。本文件是给"下一个会话/下一台设备"的完整上下文，读完即可接手。

## 1. 项目目标

把 NixOS 移植到 **Xiaomi Pad 5（nabu）**：
- SoC：Snapdragon 860（SM8150 家族），aarch64，UFS 存储
- 用户设备已运行 [nabu_fedora](https://github.com/jhuang6451/nabu_fedora) 双启动栈：Project-Aloha UEFI + DBKP + rEFInd + ESP 分区（PARTLABEL=esp）+ ext4 rootfs（PARTLABEL=linux）
- **一级交付物：UKI `.efi`**（内核 + initrd + DTB + cmdline 打包的单文件），直接复制进平板 ESP 的 `EFI/nixos/` 即可在 rEFInd 菜单选择启动测试，不动现有系统

## 2. 当前状态

| 项目 | 状态 |
|---|---|
| flake 骨架 / NixOS 配置 / 设备软件包 | ✅ 完成，`nix flake check --no-build` 零错误零警告 |
| 内核配置管线 | ✅ 修复并**验证通过**（见 §3，这是本会话的核心成果） |
| 内核全量编译 | ⏸ 进行到最后一部 rsync 拷贝时因**磁盘满**失败；重试又因用户暂停中止。**需要在新设备重新跑**（约 50-60 分钟） |
| UKI 组装 / 上机测试 | ❌ 未开始（依赖编译完成） |

失败原因详情：x86_64 交叉编译内核峰值吃约 20G 磁盘（构建 chroot 在 /nix/store 同盘），当时只剩 9.5G，死在 `rsync: Broken pipe`（ENOSPC）。GC 已回收 10.8G。**新设备请确保 ≥ 25G 可用**。

## 3. 关键技术决策（血泪教训，勿回退）

### 3.1 nixpkgs 新版 buildLinux 已移除 `configfile` 参数

pinned nixpkgs（nixos-unstable，rev 83199d0）的 buildLinux **不再接受** `configfile`/`config` 传入——传了会被 `...}@args` 静默吞掉。可用参数只有：`defconfig`（目标名字符串）、`extraConfig`（legacy 答案字符串）、`structuredExtraConfig`（attrset）、`kernelPatches`、`modDirVersion`、`ignoreConfigErrors`。

其内部管线：`make ${defconfig}` 打底 → `generate-config.pl` 跑两遍交互式 `make config`，答案来自 intermediate config（common-config.nix 默认值 + structuredExtraConfig + extraConfig 拼接，**后行覆盖前行**）。

**交互式答案机制的坑**（本会话踩过）：
- `SYMBOL y` 答案在符号被依赖钳制为 m 时是非法答案 → kconfig 重复提问 → perl `die "repeated question"` 构建失败（实例：BRIDGE_NETFILTER=y 但 BRIDGE=m）
- 字符串值必须**去引号裸传**；空字符串值无法表达
- common-config.nix 无条件强制 `NR_CPUS=384`，会覆盖 fragment，需在 extraConfig 末尾钉死
- aarch64 默认 preferBuiltin=true + autoModules=true → 大量 n→m 模块膨胀（正常，勿惊慌）

### 3.2 本项目的内核配置方案（已验证）

`pkgs/kernel/default.nix`：
1. `mergedConfig` derivation（buildPackages.stdenv，构建机上跑 kconfig）复刻 reference RPM 的合并流程：`make ARCH=arm64 defconfig sm8150.config`（源码树内 fragment）→ `sed -i '/^CONFIG_LOCALVERSION=/d'` → `cat extra-sm8150.config`（CRLF 已 sed 剥离）→ 追加 `CONFIG_SPI_MT65XX=n` → `olddefconfig`
2. 产物通过 `defconfigPatch` derivation 生成 unified diff，作为 kernelPatches 注入源码树 `arch/arm64/configs/nabu_defconfig`
3. `buildLinux { defconfig = "nabu_defconfig"; ... }` —— olddefconfig 语义（y 钳制 m 等）完整保留
4. `extraConfig` 额外钉死：`SPI_MT65XX n` / `LOCALVERSION_AUTO n` / `NR_CPUS 8`

**已验证的最终配置**（`nix build .#nabu-kernel.configfile`，几分钟即可复现检查）：
- `CONFIG_LOCALVERSION=""` + AUTO not set → kernel release = `6.17.0`（与 modDirVersion 一致，模块目录 `lib/modules/6.17.0` 已在编译日志证实）
- `CONFIG_SPI_MT65XX` 完全消失（COMPILE_TEST=n 使其不可见 = MTK 驱动不编译）✓
- `CONFIG_TOUCHSCREEN_NT36523_SPI=m`、`CONFIG_DRM_MSM=y`、`CONFIG_SCSI_UFS_QCOM=y`、`NR_CPUS=8`、`CONFIG_HZ_1000=y`、`CONFIG_BRIDGE_NETFILTER=m`（正确钳制）✓
- 设备关键符号全部保留：PINCTRL_SM8150/SM_GCC_8150/SM_GPUCC_8150=y、面板 NT36523/AMS639RQ08=m、KTZ8866 背光=m、CS35L41 音频=m、IDTP9418 充电=m、BATTERY_QCOM_FG/CHARGER_QCOM_SMB2=y、ATH10K_SNOC=m、QRTR 系列齐 ✓

### 3.3 SPI_MT65XX 编译错误（已修复，勿回退）

源码 gitlab.com/sm8150-mainline/linux tag v6.17.0-sm8150（hash `sha256-K+cbu6aGdNxLiM2YimsEQLrL5YQvpPyOcUCvQ2M92Yk=`）。其 arm64 defconfig 被 fork 改成设备就绪版，含 `CONFIG_SPI_MT65XX=y`（错误地为 Qualcomm 板启用 MTK SPI 控制器）。nt36523 触摸屏驱动 `drivers/input/touchscreen/nt36523/nt36xxx.c:1280` 有 `#ifdef CONFIG_SPI_MT65XX` 保护的 MTK 专用代码（引用不存在的 `mtk_chip_config`/`spi_ctrl`/`spi_ctrdata`）→ 编译失败。**禁用 SPI_MT65XX 即根治**，该文件其余部分正常。

### 3.4 其他要点

- 上游 sm8150.config fragment 是 **CRLF 行尾**，且有一行 `CONIG_SERIAL_TEGRA_TCU` typo（上游自己的，无害）。树内 fragment 方式使用则无此问题
- reference RPM 用 `EXTRAVERSION=-sm8150-1 LOCALVERSION=`，其模块目录是 6.17.0-sm8150-1；nixpkgs 内我们用 `modDirVersion="6.17.0"` 自洽命名，**不要**改成带后缀（nixpkgs 自己装配模块）
- 交叉求值：flake 里 `nixpkgs.buildPlatform.system = system` + hostPlatform=aarch64（见 flake.nix `crossConfigFor`）；x86_64 无 aarch64 binfmt，只能交叉
- ukify 的 aarch64 EFI stub 取自 `pkgsCross.aarch64-multiplatform.systemd`（x86_64 主机时）

## 4. 在新设备上继续（操作指引）

```bash
git clone <repo> && cd nixos-for-nabu
nix flake check --no-build          # 应零错误
nix build --no-link --print-out-paths .#nabu-kernel.configfile   # 快速验证配置（几分钟）
grep -E 'NR_CPUS|NT36523_SPI|DRM_MSM=|LOCALVERSION' <上面的输出路径>
nix build .#nabu-uki --print-out-paths   # 全量编译 ~50-60 分钟，需 ≥25G 磁盘
# 产物：<store路径>/nabu-6.17.0-sm8150.efi（另有 nabu.efi 符号链接）
```

上机测试：按 `docs/testing-uki.md`（复制进 ESP、rEFInd 选择、串口/现象判断标准）。

### 下一步任务队列
1. 全量构建 nabu-uki（新设备上）
2. 失败则读 `nix log <drv>` 修（触摸屏已过，若再挂大概率在 drivers/ 后段或 modules-shrunk/initrd/ukify 环节）
3. 成功后上机：UEFI → rEFInd → nabu.efi，按 docs/testing-uki.md 判定
4. rootfs 镜像（`nixos/rootfs-image.nix` 已写好，`scripts/build-image.sh rootfs`；交叉构建 ext4 偶发 flaky，必要时上 aarch64 机器）
5. 首次真机启动调通后：清理 README 状态清单、加 CI、DE 变体（见 README）

## 5. 环境注意事项（跨设备经验）

- **flake dirty-tree**：nix 读 git index，改完文件必须 `git add -A` 再 build/eval，否则用旧内容
- 网络（若还在国内环境）：GitHub 直连慢；镜像 `https://proxy.staringplanet.top/gh/<owner>/<repo>.git`；Clash 代理 `127.0.0.1:7897`（时有时无）
- nixpkgs 内核交叉编译磁盘峰值 ~20G；磁盘紧张时先 `nix-collect-garbage`
- Git 提交流程（用户规矩）：**提交信息必须先给用户审查确认**，格式 `feat: ...` 标题 + 英文正文

## 6. 文件导览

```
flake.nix                     # nixosConfigurations.nabu + packages.{nabu-uki,nabu-kernel}
pkgs/kernel/default.nix       # 内核（本会话重写的核心，见 §3.2）
pkgs/kernel/configs/extra-sm8150.config   # 设备附加 fragment（上游 sm8150.config 用树内版）
pkgs/pd-mapper.nix            # andersson/pd-mapper（qrtr 服务链必需，nixpkgs 无此包）
pkgs/nabu-firmware.nix        # pmOS 设备固件（adsp/cdsp/modem/wlan/触摸）
pkgs/alsa-ucm/                # SM8150 UCM 音频配置
nixos/hardware-nabu.nix       # UFS/ESP 挂载、qrtr→pd-mapper→rmtfs/tqftpserv/q6voiced、RTC、ath10k、zram
nixos/configuration.nix       # 用户 nabu、fcitx5、NetworkManager+iwd
nixos/rootfs-image.nix        # 无特权 mke2fs ext4 rootfs 镜像
scripts/build-image.sh        # esp/uki/rootfs 三种构建模式
docs/testing-uki.md           # 上机测试步骤与判定标准
README.md / README_zh_CN.md   # 双语文档（启动链图、状态清单）
```
