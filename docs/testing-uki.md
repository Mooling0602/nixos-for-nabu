# 测试与刷入指南（小米平板 5 / nabu）

前置条件：设备已解锁 BL、刷好 DBKP、ESP 分区就位（rEFInd 可见）。

> 两种产物必须同源构建：UKI 的 `init=` 参数指向 rootfs 内的 NixOS 闭包，
> 不配对会卡在 initrd emergency mode（见 README 的 IMPORTANT 提示）。

## 1. 刷入 rootfs

`nix build .#nabu-rootfs` 产出的 `nabu-rootfs.ext4.img[.zst]` 刷入 `linux`
分区（PARTLABEL=linux，勿刷 esp）。压缩版先 `zstd -d` 解压。

```Shell
# 在设备已运行的 Linux 里（分区名以 lsblk 为准，nabu 上通常 sda 整盘）：
sudo zstd -d nabu-rootfs.ext4.img.zst          # 若为压缩产物
sudo dd if=nabu-rootfs.ext4.img of=/dev/sdXN bs=4M status=progress oflag=direct
```

## 2. 部署 UKI 到 ESP

```Shell
sudo mkdir -p /boot/efi/EFI/nixos
sudo cp result/nabu-*.efi /boot/efi/EFI/nixos/
```

（或在 PC 上挂载 ESP 复制；旧版 `.efi` 记得替换，避免混用不配对的产物）

## 3. 启动判定

重启 → rEFInd → 选择 `nabu-*.efi`。

预期流程：plymouth splash → `console=tty0` 内核日志（loglevel=7 早期详细，
后期降为 4）→ NixOS activation（首次启动自动完成 /etc、用户、服务初始化，
并自动扩容 rootfs 填满分区）→ getty 直登 `nabu` 用户。

| 现象 | 含义 |
|------|------|
| rEFInd 能列出 nabu-*.efi | UKI 是合法 EFI PE 二进制 ✅ |
| 选择后屏幕有显示输出（哪怕花屏/旋转异常） | 内核+DTB 被正确加载执行 ✅ |
| 卡 plymouth / 黑屏但有背光 | initrd 或显示栈问题，见下节排查 |
| initrd 报 "No init= parameter" 或进 emergency shell | UKI 与 rootfs 不配对，重新同源构建 |
| 瞬间重启回 rEFInd | EFI stub 问题 |

## 4. 排查工具

- **QEMU 冒烟测试**（强烈建议刷机前先做）：需要 aarch64 主机或已缓存的
  内核产物。参考测试仓库思路：变体 UKI（不嵌 DTB、`console=ttyAMA0`）、
  GPT 测试盘（esp+linux 分区名与真机一致）、`qemu-system-aarch64 -M virt`
  TCG 运行，串口日志可直接看到 initrd → switch-root → activation 全链路。
  两个已知的 initrd 启动 bug（root= 冲突、缺 init= 参数）就是这么发现的。
- **真机黑屏时**：cmdline 已带 `console=tty0` + `loglevel=7`，早期内核日志
  会滚在屏幕上，拍照即可定位卡点。
- 系统启动后 `journalctl -b` 查看本次启动日志。

## 5. 日常更新

改配置/内核后：

```Shell
nix build .#nabu-uki .#nabu-rootfs   # 同一次构建
sudo cp result-*/nabu-*.efi /boot/efi/EFI/nixos/   # 替换 ESP 上的 UKI
```

rootfs 更新可整体重刷；或后续改用 `nixos-rebuild --target-host` 推送
（当前最小 rootfs 未启用 SSH，重刷更简单）。
