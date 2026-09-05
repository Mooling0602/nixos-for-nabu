[English](README.md) | [简体中文](README_zh_CN.md)

# NixOS for Nabu（小米平板 5）

以 UEFI Unified Kernel Image（UKI）方式启动的小米平板 5（nabu）NixOS —— 与 [nabu_fedora](https://github.com/jhuang6451/nabu_fedora) 双系统方案完全兼容。

## 工作原理

```
UEFI 固件（Project Aloha / DBKP）
  └─ rEFInd（ESP 分区）
       └─ nabu-<version>.efi   ← 本 flake 构建的 Unified Kernel Image
            ├─ Linux 6.17（sm8150-mainline + nabu 驱动）
            ├─ initramfs（基于 systemd，强制包含 UFS 驱动）
            ├─ sm8150-xiaomi-nabu.dtb
            └─ cmdline: init=<closure>/init rw console=tty0 ...
                  └─ `linux` 分区上的 ext4 根文件系统（PARTLABEL=linux）
```

* **内核**：来自 [sm8150-mainline](https://gitlab.com/sm8150-mainline/linux) 项目的 mainline 6.17，配置片段与参考 Fedora 构建一致。
* **UKI 产物**：单个 `.efi` 文件，直接放进现有 ESP（`EFI/nixos/`）即可，rEFInd 自动识别 —— 不动 rootfs 就能测试新内核。
* **Rootfs 产物**：可刷写的 ext4 镜像（`nabu-rootfs`），内含 NixOS store 闭包；首次启动自动完成系统激活，并把文件系统扩容到整个分区。
* **高通用户态服务**：`qrtr` / `pd-mapper` / `rmtfs` / `tqftpserv` / `q6voiced`，四扬声器 ALSA UCM 配置，pm8150 RTC udev 规则，ath10k 热重启规避。
* **固件**：可再分发的高通固件（`hardware.enableRedistributableFirmware`）+ 设备专属文件（adsp/modem/venus/cirrus/novatek，来自 postmarketOS 固件仓库）。

## 构建

任何装了 Nix（启用 flakes）的 Linux 机器：

```Shell
# UKI：EFI 内核镜像（x86_64 交叉编译，无需 binfmt）
nix build .#nabu-uki
# → result/nabu-<version>.efi

# Rootfs：可刷写 ext4 镜像（fakeroot 无特权交叉构建，无需 binfmt）
nix build .#nabu-rootfs
# → result/nabu-rootfs.ext4.img[.zst]
```

> [!IMPORTANT]
> UKI 和 rootfs 必须在**同一提交一次性构建** —— UKI 的 `init=` 内核参数
> 必须指向 rootfs 里那个确切的 NixOS 闭包。两者不配对会无法启动
> （initrd 落入 emergency mode）。

## 在设备上测试

1. 把 UKI 复制进 ESP：
   ```Shell
   # 在平板上运行的 Linux 系统里执行：
   sudo mkdir -p /boot/efi/EFI/nixos
   sudo cp result/nabu-*.efi /boot/efi/EFI/nixos/
   ```
   （也可以在 PC 上挂载 ESP 分区复制）
2. 把 rootfs 镜像刷入 `linux` 分区（PARTLABEL=linux）—— 刷入步骤与首启预期见 [docs/testing-uki.md](docs/testing-uki.md)。
3. 重启，在 rEFInd 里选择 `nabu` 启动项。

## 进度

- [x] Flake 骨架：`nixosConfigurations.nabu`、可交叉构建的 `nabu-uki` / `nabu-rootfs` 产物
- [x] 内核 6.17.0-sm8150 打包（片段合并配置，可复现）
- [x] 设备软件包：`pd-mapper`、`xiaomi-nabu-firmware`、ALSA UCM
- [x] NixOS 配置中的高通服务栈
- [x] 可刷写 ext4 rootfs 镜像（fakeroot 无特权交叉构建）
- [x] 启动链已在 QEMU 验证（initrd → switch-root → 激活 → 自动登录）
- [ ] 首次真机启动
- [ ] CI（GitHub Actions）构建
- [ ] 桌面环境变体（niri/GNOME/KDE）

## 参考与致谢

* [jhuang6451/nabu_fedora](https://github.com/jhuang6451/nabu_fedora) —— 本项目镜像参考的实现（内核配置、UKI 布局、服务、设备规避）
* [sm8150-mainline/linux](https://gitlab.com/sm8150-mainline/linux) —— SM8150 设备的 mainline 内核
* [Project-Aloha](https://github.com/Project-Aloha) —— nabu 的 UEFI 固件
* [map220v](https://github.com/map220v)、[timoxa0](https://github.com/timoxa0)、[nik012003](https://github.com/nik012003)、[panpantepan](https://gitlab.com/panpanpanpan) 与 nabu Linux 社区
* 固件：[nabu-firmware（postmarketOS）](https://gitlab.postmarketos.org/panpanpanpan/nabu-firmware)

## 许可

MIT —— 见 [LICENSE](LICENSE)。内核源码为 GPLv2；固件文件保留其原始许可。
