# MEMORY.md — 项目交接文档

> 给"下一个会话 / 下一台设备"的完整上下文，读完即可接手。更新：2026-09-05。

## 1. 项目目标与当前状态

把 NixOS 移植到 **Xiaomi Pad 5（nabu）**（SD860/SM8150，aarch64，UFS），基于
nabu_fedora 双启动栈（Project-Aloha UEFI + DBKP + rEFInd + ESP + ext4 rootfs）。

| 项目 | 状态 |
|---|---|
| Flake / NixOS 配置 / 设备软件包 | ✅ 完成 |
| 内核 6.17.0-sm8150 配置管线 | ✅ 验证通过（本机容器内复验） |
| UKI + rootfs 构建 | ✅ 完成（fakeroot 无特权交叉构建，无需 binfmt） |
| 启动链验证 | ✅ QEMU（aarch64 virt, TCG）到 Multi-User + 自动登录 |
| 首次真机启动 | 🔄 等待用户刷机测试（产物已在 ~/Downloads） |
| CI / DE 变体 | ❌ 未开始 |

## 2. 构建环境（本机 = 平板本身，Fedora 43 aarch64）

- 本机即 mipad5-fedora：8 核 / 11G 内存，无 KVM（QEMU 用 TCG 即可，启动链验证够用）
- **构建走 rootless Podman 容器 `nabu-builder`**（镜像 nixos/nix:latest）：
  - 主仓库挂载 `/repo`，QEMU 测试 flake 在容器内 `/test`（path flake，钉死主仓库 rev）
  - 20G nix store 在容器 overlay 层（**不在 volume**，删容器即丢；新容器需 `podman commit` 烘焙或迁 store 到 bind mount）
  - `/usr/bin/newuidmap`、`/usr/bin/newgidmap` 已 setcap（rootless podman 前提，勿回退）
  - 复用命令：
    ```bash
    podman exec -w /repo nabu-builder nix --extra-experimental-features 'nix-command flakes' \
      build -L --no-link --print-out-paths --option sandbox false --cores 4 --max-jobs 2 .#nabu-uki .#nabu-rootfs
    ```
- **长耗时命令放 zellij 会话**（用户要求可观察；DSH 侧通过
  `zellij --session <name> action write-chars -p terminal_0` 写入、`dump-screen -p terminal_0` 读结果，不新建窗格）
- 电量：平板编译时充电跟不上负载（§7.7 旧经验），长构建保持外接电源，`/sys/class/power_supply/qcom-battery/{capacity,status}`
- 网络：Clash Verge TUN 7897；用户规矩**不考虑镜像方案**

## 3. 关键技术决策（血泪教训，勿回退）

### 3.1 内核配置（pkgs/kernel/default.nix）

- nixpkgs 新版 buildLinux 无 `configfile` 参数；管线：源码树内 fragment
  `make defconfig sm8150.config` → 剥 LOCALVERSION → extra fragment →
  `olddefconfig`，产物以 defconfigPatch 注入 `nabu_defconfig`
- **SPI_MT65XX 必须禁用**（否则 nt36523 触摸屏驱动引用不存在的 MTK 符号编译失败）
- `extraConfig` 钉死：`SPI_MT65XX n` / `LOCALVERSION_AUTO n` / `NR_CPUS 8`
- 交互式答案机制坑：y 答案被钳成 m 时会 die "repeated question"；字符串值裸传

### 3.2 systemd initrd 启动要求（2026-09-05 QEMU 冒烟发现，已修）

- **当前 nixpkgs `boot.initrd.systemd` 默认 true**。两个硬性要求：
  1. **cmdline 不能有 `root=`** —— fstab-generator 会与 initrd-fstab 生成的
     sysroot.mount 重名冲突 → initrd-parse-etc 失败 → emergency（fix ccef6a7）
  2. **cmdline 必须有 `init=<toplevel>/init`** —— initrd-find-nixos-closure
     靠它定位闭包，缺了报 "No init= parameter" → emergency（fix 44193fb）
- UKI 与 rootfs 必须同源构建：`init=` 指向的 closure hash 必须等于 rootfs 内
  `system-1-link`；校验：`grep -aoE 'init=/nix/store/[^ ]*' *.efi` 对比镜像内链接

### 3.3 rootfs 镜像（nixos/rootfs-image.nix）

- mke2fs -d 在 **fakeroot** 下跑：归一化 root:root 属主（否则 setuid 全坏）
- 无特权交叉构建，不需要 binfmt/KVM；首启 `boot.growPartition` + `x-systemd.growfs` 自动扩容

### 3.4 其他

- **flake dirty-tree**：nix 读 git index，改完必须 `git add -A` 再 build
- 交叉求值：flake `crossConfigFor` 设 `nixpkgs.buildPlatform.system`
- 平板本机是 aarch64 原生（主仓库 flake 会走 `nixosConfigurations.nabu` 路径）
- GPT 分区名是启动依赖（PARTLABEL=linux/esp）；sfdisk 不支持 name= 字段，用 sgdisk -c

## 4. QEMU 冒烟测试（刷机前验证，强烈建议做）

- 测试 flake：宿主 `~/Documents/Workspace/nabu-qemu-test/`，容器内 `/test`
  （README 有完整说明；input 钉死主仓库 rev，改配置后需同步更新 rev）
- 与真机 UKI 的差异（有意为之）：不嵌 DTB（QEMU 固件提供 virt 设备树）、
  `console=ttyAMA0`、关 plymouth、关 zram、ESP noauto
- 已验证到的程度：initrd → switch-root → activation → Multi-User → 自动登录
- TCG 下注意：设备 .device 单元可能冷插拔超时（ttyAMA0/zram），属模拟慢，非 bug

## 5. 用户规矩

- 任务清单与沟通**用中文**
- **未获明确指示不主动推进**：不启动构建、不改文件、不部署产物
- Git 提交信息必须先给用户审查（`feat:`/`fix:` 英文标题+正文）；推送前确认
- 校验类构建通过后停下等用户确认再启动全量编译
- 提交文档整理类改动用 `docs: xxx`

## 6. 文件导览

```
flake.nix                     # nixosConfigurations.nabu + packages.{nabu-uki,nabu-rootfs,nabu-kernel}
pkgs/kernel/default.nix       # 内核打包与配置管线（§3.1）
pkgs/{pd-mapper,nabu-firmware}.nix, pkgs/alsa-ucm/   # 设备包
nixos/hardware-nabu.nix       # 内核参数/initrd 模块/挂载/高通服务栈/quirks
nixos/configuration.nix       # 用户 nabu、fcitx5、NetworkManager+iwd
nixos/rootfs-image.nix        # fakeroot ext4 镜像（§3.3）
scripts/build-image.sh        # esp/uki/rootfs 封装（rootfs 模式指向 flake 输出）
docs/testing-uki.md           # 刷入步骤与启动判定
MEMORY.md                     # 本文件
（QEMU 测试在仓库外：~/Documents/Workspace/nabu-qemu-test/）
```

## 7. 下一步队列

1. 真机刷机测试（UKI + rootfs 均已带 §3.2 两个修复）
2. 测试通过后：CI（GitHub Actions）、DE 变体、清理 README 状态清单
3. 可选：store 迁宿主 bind mount（摆脱容器 overlay 生命周期）；`nixos-rebuild --target-host` 远程部署链路（需先加 SSH）

## 8. 历史教训存档（浓缩）

- nix-portable proot 路线已弃用（大规模解包崩）；bwrap 建不了 /nix 顶层挂载点
- podman commit 20G 容器曾超时失败且磁盘吃紧——新容器优先考虑迁 store 而非烘焙
- 早期 agent 会话因模型 content_filter 中断过：长技术会话避免用易拒答模型
