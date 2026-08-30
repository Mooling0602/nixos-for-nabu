#!/bin/bash
# ==============================================================================
# build-image.sh — build flashable images for Xiaomi Pad 5 (nabu)
#
# Outputs (in ./result-images/):
#   nabu-rootfs.ext4.img[.zst]  — flash to the `linux` partition
#   esp-<version>.img.zst       — flashable ESP (rEFInd + UKI), precise FAT32
#                                 geometry matching the device partition table
#   efi-files.zip               — UKI + bootloader files only (manual copy)
#
# Usage:
#   ./scripts/build-image.sh          # both rootfs + esp
#   ./scripts/build-image.sh esp      # esp/uki only
#   ./scripts/build-image.sh rootfs   # rootfs only (needs aarch64 builder)
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="$PWD/result-images"
mkdir -p "$OUT_DIR"

# --- ESP geometry (mirrors the reference project's flashable_esp.img) --------
IMG_SIZE_BYTES=350105600
LOGICAL_SECTOR_SIZE=4096
SECTORS_PER_CLUSTER=1
RESERVED_SECTORS=32
HIDDEN_SECTORS=21234176
VOLUME_LABEL="ESPNABU"
VOLUME_ID="5C7A09AD"

build_uki_and_esp() {
  echo "==> Building UKI (nabu-uki)..."
  nix build .#nabu-uki --print-out-paths
  UKI=$(readlink -f result/nabu.efi)

  echo "==> Packaging EFI files zip"
  STAGE=$(mktemp -d)
  mkdir -p "$STAGE/EFI/nixos"
  cp -v "$UKI" "$STAGE/EFI/nixos/"
  (cd "$STAGE" && zip -qr "$OUT_DIR/efi-files.zip" EFI)
  rm -rf "$STAGE"

  echo "==> Building flashable ESP image"
  ESP_IMG="$OUT_DIR/esp.img"
  truncate -s "$IMG_SIZE_BYTES" "$ESP_IMG"
  mkfs.vfat \
    -F 32 \
    -S "$LOGICAL_SECTOR_SIZE" \
    -s "$SECTORS_PER_CLUSTER" \
    -R "$RESERVED_SECTORS" \
    -h "$HIDDEN_SECTORS" \
    -n "$VOLUME_LABEL" \
    -i "$VOLUME_ID" \
    -f 2 \
    "$ESP_IMG"

  echo "NOTE: the flashable esp also needs rEFInd + EFI/Android from the"
  echo "      reference dualboot package; if your esp partition is already"
  echo "      set up (dualboot installed), flash only efi-files or copy the UKI."
  MNT=$(mktemp -d)
  sudo mount -o loop "$ESP_IMG" "$MNT"
  sudo mkdir -p "$MNT/EFI/nixos"
  sudo cp -v "$UKI" "$MNT/EFI/nixos/"
  sudo umount "$MNT"
  rmdir "$MNT"

  zstd -T0 --no-progress -f "$ESP_IMG" && rm -f "$ESP_IMG"
}

build_rootfs() {
  echo "==> Building rootfs image (requires aarch64 builder or binfmt)..."
  nix build .#nixosConfigurations.nabu.config.system.build.rootfs-image --print-out-paths
  cp -v "$(readlink -f result)"/nabu-rootfs.ext4.img* "$OUT_DIR/" 2>/dev/null || true
}

case "${1:-all}" in
  esp|uki)   build_uki_and_esp ;;
  rootfs)    build_rootfs ;;
  all)       build_uki_and_esp; build_rootfs ;;
  *) echo "usage: $0 [all|esp|rootfs]" >&2; exit 1 ;;
esac

echo
echo "==> Done. Artifacts in $OUT_DIR:"
ls -la "$OUT_DIR"
