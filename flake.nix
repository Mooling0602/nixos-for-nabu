{
  description = "NixOS for Xiaomi Pad 5 (nabu)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      sharedModules = [
        {
          nixpkgs.overlays = [ (import ./pkgs) ];
        }
        ./nixos/configuration.nix
      ];

      /*
        Unified Kernel Image: Linux Image + initramfs + nabu DTB + kernel
        command line packed into a single EFI PE binary, bootable by the
        device's UEFI firmware (via the rEFInd dualboot setup).

        Drop the .efi into the ESP (e.g. EFI/nixos/) to boot/test.
      */
      mkUki =
        {
          kernel,
          initrd,
          cmdline,
          kernelVersion ? (kernel.version or "6.17.0-sm8150"),
          # build-host packages: ukify runs natively
          pkgs,
          # target-arch packages: aarch64 systemd provides the aa64 EFI stub
          targetPkgs,
        }:
        pkgs.stdenv.mkDerivation {
          pname = "nabu-uki";
          version = kernelVersion;

          passAsFile = [ "cmdlineText" "osReleaseText" ];
          cmdlineText = cmdline;
          # ukify defaults to reading /usr/lib/os-release, which does not exist
          # in the build environment (nixos/nix container); provide one
          # explicitly so the UKI .osrel section can be populated.
          osReleaseText = ''
            ID=nixos
            NAME="NixOS"
            PRETTY_NAME="NixOS ${kernelVersion} (Xiaomi Pad 5 / nabu)"
          '';

          nativeBuildInputs = [
            (pkgs.systemd.override { withUkify = true; })
          ];

          stub = "${targetPkgs.systemd}/lib/systemd/boot/efi/linuxaa64.efi.stub";

          buildCommand = ''
            set -euo pipefail

            # nix does not pre-create output dirs; ukify needs $out to exist
            mkdir -p "$out"

            kernel="${kernel}"
            echo ">>> kernel store path: $kernel"

            # Locate the bootable kernel image
            KIMG=""
            for candidate in "$kernel/vmlinuz" "$kernel/Image" "$kernel/zImage" "$kernel/bzImage"; do
              if [ -e "$candidate" ]; then KIMG="$candidate"; break; fi
            done
            if [ -z "$KIMG" ]; then
              echo "ERROR: no bootable kernel image found in $kernel" >&2
              ls -la "$kernel" >&2
              exit 1
            fi
            echo ">>> kernel image: $KIMG"

            # Locate the nabu DTB
            DTB="$(find "$kernel/dtbs" -name 'sm8150-xiaomi-nabu.dtb' -print -quit || true)"
            if [ -z "$DTB" ]; then
              echo "ERROR: sm8150-xiaomi-nabu.dtb not found under $kernel/dtbs" >&2
              find "$kernel" -name '*.dtb' >&2 || true
              exit 1
            fi
            echo ">>> dtb: $DTB"

            CMDLINE="$(cat "$cmdlineTextPath")"
            echo ">>> cmdline: $CMDLINE"

            ukify build \
              --linux="$KIMG" \
              --initrd="${initrd}/initrd" \
              --devicetree="$DTB" \
              --cmdline="$CMDLINE" \
              --os-release="@$osReleaseTextPath" \
              --stub="$stub" \
              --output="$out/nabu-${kernelVersion}.efi"

            # convenience: stable filename for direct ESP deployment
            ln -s "nabu-${kernelVersion}.efi" "$out/nabu.efi"

            ls -la "$out"
          '';

          meta = {
            description = "UKI (EFI) boot image for Xiaomi Pad 5 (nabu)";
            platforms = lib.platforms.linux;
          };
        };

      ukiFromConfig =
        cfg: pkgs:
        mkUki {
          inherit pkgs;
          kernel = cfg.system.build.kernel;
          initrd = cfg.system.build.initialRamdisk;
          # systemd initrd's initrd-find-nixos-closure.service requires the
          # closure's init path on the kernel command line (mirrors nixpkgs'
          # boot.uki module, which prepends exactly this). Without it stage 1
          # fails with "No init= parameter" and drops to emergency mode.
          cmdline =
            "init=${cfg.system.build.toplevel}/init "
            + lib.concatStringsSep " " cfg.boot.kernelParams;
          # aarch64 stub source: native on aarch64 hosts, cross on x86_64
          targetPkgs =
            if pkgs.stdenv.hostPlatform.isAarch64 then pkgs else pkgs.pkgsCross.aarch64-multiplatform;
        };

    in
    {
      # Native aarch64 configuration (build on the device / aarch64 builders)
      nixosConfigurations.nabu = lib.nixosSystem {
        modules = sharedModules;
      };

      packages =
        let
          # Cross-evaluated NixOS config: buildPlatform = current system,
          # hostPlatform = aarch64 (from hardware-nabu.nix).
          crossConfigFor =
            system:
            lib.nixosSystem {
              modules =
                [
                  {
                    nixpkgs.buildPlatform.system = system;
                  }
                ]
                ++ sharedModules;
            };
        in
        lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            cfg =
              if system == "aarch64-linux" then
                self.nixosConfigurations.nabu.config
              else
                (crossConfigFor system).config;
          in
          {
            # Single-file EFI kernel image — drop into ESP to test on device
            nabu-uki = ukiFromConfig cfg pkgs;
            # kernel alone (use .configfile passthru to inspect the config)
            nabu-kernel = cfg.system.build.kernel;
            # Flashable ext4 rootfs image (cross-built: buildPlatform = system,
            # hostPlatform = aarch64). The nixosConfigurations.nabu entry has
            # buildPlatform = aarch64, which is wrong/impractical on an x86_64
            # host — so build rootfs via the cross config, like nabu-uki.
            nabu-rootfs = cfg.system.build.rootfs-image;
            default = self.packages.${system}.nabu-uki;
          }
        );
    };
}
