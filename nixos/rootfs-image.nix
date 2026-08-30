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
            zstd
          ];
        }
        ''
          set -euo pipefail
          root=$(mktemp -d)

          echo ">>> importing store closure"
          mkdir -p "$root/nix/store" "$root/nix/var/nix/profiles" "$root/etc" "$root/boot"
          while read -r storePath; do
            cp -prd "$storePath" "$root/nix/store/"
          done < "${closureInfo}/store-paths"

          echo ">>> creating profile links"
          ln -sfn ${toplevel} "$root/nix/var/nix/profiles/system-1-link"
          (cd "$root/nix/var/nix/profiles" && ln -sfn system-1-link system)

          echo ">>> /init -> toplevel/init"
          ln -sfn "${toplevel}/init" "$root/init"

          # mark first boot for activation machinery
          touch "$root/etc/NIXOS"

          echo ">>> building ext4 image (mke2fs -d, unprivileged)"
          TOTAL_MB=$(( $(du -sm --apparent-size "$root" | cut -f1) + ${toString config.nabu.image.rootFsExtraSize} ))
          IMG="$out/nabu-rootfs.ext4.img"
          mkdir -p "$out"
          echo "image size: ''${TOTAL_MB} MiB"
          mke2fs -t ext4 -L nixos -d "$root" \
            -E lazy_itable_init=0,lazy_journal_init=0 \
            "$IMG" "''${TOTAL_MB}m"

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
          rm -rf "$root"
        '';
  };
}
