[English](README.md) | [简体中文](README_zh_CN.md)

# NixOS for Nabu

NixOS for Xiaomi Pad 5 (nabu), booted as a UEFI Unified Kernel Image (UKI) — compatible with the [nabu_fedora](https://github.com/jhuang6451/nabu_fedora) dualboot setup.

## How it works

```
UEFI firmware (Project Aloha / DBKP)
  └─ rEFInd (on ESP partition)
       └─ nabu-<version>.efi   ← Unified Kernel Image built by this flake
            ├─ Linux 6.17 (sm8150-mainline + nabu drivers)
            ├─ initramfs (systemd-based, UFS drivers forced in)
            ├─ sm8150-xiaomi-nabu.dtb
            └─ cmdline: init=<closure>/init rw console=tty0 ...
                  └─ ext4 rootfs on the `linux` partition (PARTLABEL=linux)
```

* **Kernel**: mainline 6.17 from the [sm8150-mainline](https://gitlab.com/sm8150-mainline/linux) project, with the same config fragments as the reference Fedora build.
* **UKI output**: a single `.efi` file you can drop into your existing ESP (`EFI/nixos/`) — rEFInd picks it up automatically. Test a new kernel without touching the rootfs.
* **Rootfs output**: a flashable ext4 image (`nabu-rootfs`) containing the NixOS store closure; first boot activates the system and grows the filesystem to fill the partition.
* **Qualcomm userspace**: `qrtr` / `pd-mapper` / `rmtfs` / `tqftpserv` / `q6voiced` services, ALSA UCM profiles for the quad speakers, pm8150 RTC udev rule, ath10k warm-reboot workaround.
* **Firmware**: redistributable Qualcomm firmware via `hardware.enableRedistributableFirmware` + device-specific files (adsp/modem/venus/cirrus/novatek) packaged from the postmarketOS firmware repo.

## Build

On any Linux machine with Nix (flakes enabled):

```Shell
# UKI: EFI kernel image (cross-builds from x86_64, no binfmt needed)
nix build .#nabu-uki
# → result/nabu-<version>.efi

# Rootfs: flashable ext4 image (cross-built with fakeroot, no binfmt needed)
nix build .#nabu-rootfs
# → result/nabu-rootfs.ext4.img[.zst]
```

> [!IMPORTANT]
> Build the UKI and the rootfs **from the same commit in one go** — the UKI's
> `init=` kernel parameter must point at the exact NixOS closure inside the
> rootfs. Mismatched pairs fail to boot (initrd drops to emergency mode).

## Test on your device

1. Copy the UKI to the ESP:
   ```Shell
   # from the running Linux system on the tablet:
   sudo mkdir -p /boot/efi/EFI/nixos
   sudo cp result/nabu-*.efi /boot/efi/EFI/nixos/
   ```
   (or mount the ESP on your PC and copy there)
2. Flash the rootfs image to the `linux` partition (PARTLABEL=linux) — see [docs/testing-uki.md](docs/testing-uki.md) for flashing steps and what to expect on first boot.
3. Reboot; select the `nabu` entry in rEFInd.

## Status

- [x] Flake scaffolding: `nixosConfigurations.nabu`, cross-buildable `nabu-uki` / `nabu-rootfs` outputs
- [x] Kernel 6.17.0-sm8150 packaged (fragment-merged config, reproducible)
- [x] Device packages: `pd-mapper`, `xiaomi-nabu-firmware`, ALSA UCM
- [x] Qualcomm service stack in NixOS config
- [x] Flashable ext4 rootfs image (fakeroot, unprivileged cross-build)
- [x] Boot chain verified in QEMU (initrd → switch-root → activation → autologin)
- [ ] First real device boot
- [ ] CI (GitHub Actions) builds
- [ ] Desktop environment variant (niri/GNOME/KDE)

## References & credits

* [jhuang6451/nabu_fedora](https://github.com/jhuang6451/nabu_fedora) — the reference implementation this project mirrors (kernel config, UKI layout, services, quirks)
* [sm8150-mainline/linux](https://gitlab.com/sm8150-mainline/linux) — mainline kernel for SM8150 devices
* [Project-Aloha](https://github.com/Project-Aloha) — UEFI firmware for nabu
* [map220v](https://github.com/map220v), [timoxa0](https://github.com/timoxa0), [nik012003](https://github.com/nik012003), [panpantepan](https://gitlab.com/panpanpanpan) and the nabu Linux community
* Firmware: [nabu-firmware (postmarketOS)](https://gitlab.postmarketos.org/panpanpanpan/nabu-firmware)

## License

MIT — see [LICENSE](LICENSE). Kernel sources are GPLv2; firmware files remain under their original licenses.
