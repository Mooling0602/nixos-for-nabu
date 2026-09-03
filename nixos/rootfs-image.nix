# Flashable ext4 rootfs image for nabu.
#
# Follows the nixpkgs sd-image populate pattern:
#   store closure + /init symlink -> toplevel/init + profile links.
# Activation (/etc, users, ...) completes on first boot by the NixOS
# initrd/activation scripts.
#
# Partition layout on the device (created by the reference TWRP):
#   esp   (vfat, PARTLABEL=esp)   <- flashed separately (UKI + rEFInd)
#   linux (ext4, PARTLABEL=linux) <- this image
{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.nabu.image = {
    rootFsExtraSize = lib.mkOption {
      type = lib.types.int;
      default = 512; # MiB slack beyond the store closure
      description = "Extra free space (MiB) reserved in the ext4 image.";
    };
    compress = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "zstd-compress the final image.";
    };
  };

  config = {
    # Grow the partition + resize the fs on first boot
    boot.growPartition = true;

    system.build.rootfs-image =
      let
        toplevel = config.system.build.toplevel;
        closureInfo = pkgs.closureInfo { rootPaths = [ toplevel ]; };
      in
      pkgs.runCommand "nabu-rootfs-image"
        {
          nativeBuildInputs = with pkgs; [
            e2fsprogs
            fakeroot
            zstd
          ];
        }
        ''
          set -euo pipefail
          root=$(mktemp -d)
          export root out IMG="$out/nabu-rootfs.ext4.img" \
            toplevel="${toplevel}"
          export rootFsExtraSize="${toString config.nabu.image.rootFsExtraSize}"

          echo ">>> importing store closure"
          mkdir -p \
            "$root/nix/store" "$root/nix/var/nix/profiles" \
            "$root/etc" "$root/boot" \
            "$root/var" "$root/tmp" "$root/home" "$root/root" \
            "$root/run" "$root/dev" "$root/proc" "$root/sys"
          while read -r storePath; do
            cp -prd "$storePath" "$root/nix/store/"
          done < "${closureInfo}/store-paths"

          # -> Under fakeroot so mke2fs records root:root ownership (mirrors
          #    nixpkgs sd-image).  Without this, an unprivileged build leaves
          #    the whole tree owned by the builder uid (e.g. 30001), breaking
          #    setuid binaries and producing a non-standard rootfs.
          fakeroot bash -c '
            set -euo pipefail

            echo ">>> creating profile links"
            ln -sfn "$toplevel" "$root/nix/var/nix/profiles/system-1-link"
            (cd "$root/nix/var/nix/profiles" && ln -sfn system-1-link system)

            echo ">>> /init -> toplevel/init"
            ln -sfn "$toplevel/init" "$root/init"
            touch "$root/etc/NIXOS"

            echo ">>> normalizing ownership to root:root"
            chown -R 0:0 "$root"

            echo ">>> building ext4 image (mke2fs -d, under fakeroot)"
            TOTAL_MB=$(( $(du -sm --apparent-size "$root" | cut -f1) + rootFsExtraSize ))
            mkdir -p "$out"
            echo "image size: $TOTAL_MB MiB"
            mke2fs -t ext4 -L nixos -d "$root" \
              -E lazy_itable_init=0,lazy_journal_init=0 \
              "$IMG" "$TOTAL_MB"m
          '

          ${
            if config.nabu.image.compress then
              ''
                echo ">>> zstd compressing"
                zstd -T0 --no-progress "$IMG" && rm "$IMG"
              ''
            else
              ""
          }

          ls -la "$out"

          # copied store paths are read-only; make them writable before cleanup
          # or rm -rf fails with Permission denied (image itself is done here)
          chmod -R u+w "$root"
          rm -rf "$root"
        '';
  };
}
