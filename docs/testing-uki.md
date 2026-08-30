# 在设备上测试 UKI（小米平板 5 / nabu）

适用于设备上已有 nabu_fedora 双系统环境（UEFI + DBKP + rEFInd 已就位）的场景。

## 前置条件

- 平板已解锁 BootLoader、已刷 DBKP、esp 分区已存在（rEFInd 引导菜单能看到）
- PC 上有 `adb`/`fastboot`（或平板上已运行任意 Linux）

## 方式一：在平板上的 Linux 系统里直接复制（推荐）

```Shell
# PC: 把构建产物传到平板（假设平板 Linux 已通过 USB 网络或 adb 可达）
adb push result/nabu-*.efi /tmp/

# 平板: 复制到 ESP
sudo mkdir -p /boot/efi/EFI/nixos
sudo cp /tmp/nabu-*.efi /boot/efi/EFI/nixos/
```

## 方式二：在 PC 上挂载 ESP 复制

```Shell
# 平板进入 TWRP/自建 Linux 后挂载 esp 分区，或用 fastboot 侧工具
# esp 分区一般在 /dev/block/sda21 附近（分区表里 PARTLABEL=esp）
```

## 启动测试

1. 重启平板，出现 rEFInd 菜单
2. rEFInd 会自动扫描 ESP 上的 `.efi`；选择 **nabu-6.17.0-sm8150.efi**
3. 观察：
   - 屏幕出现内核启动画面（fbcon=rotate:1 横屏控制台）= UKI 结构正确
   - 若 rootfs（`linux` 分区）不是 NixOS，会在挂载 root 后失败/进入紧急 shell——
     这是预期：**UKI 本身能被 UEFI 加载并解压内核，即证明 EFI 格式正确**

## 判定标准

| 现象 | 含义 |
|------|------|
| rEFInd 能列出 nabu-*.efi | UKI 是合法 EFI PE 二进制 ✅ |
| 选择后屏幕有显示输出（哪怕花屏/旋转异常） | 内核+DTB 被正确加载执行 ✅ |
| 串口/adb 无输出但设备不重启 | 内核早期挂了，需查 cmdline/DTB |
| 设备瞬间重启回 rEFInd | EFI stub 或签名问题 |

## 完整启动（rootfs 就绪后）

刷入 rootfs 镜像后，UKI 的 `root=PARTLABEL=linux` 会挂载 ext4 根分区，
进入 NixOS activation（首次开机自动完成 /etc、用户、服务等初始化）。

```Shell
# 之后的系统更新：重新构建 UKI + rootfs 内 toplevel，替换 ESP 上的 .efi 即可
```
