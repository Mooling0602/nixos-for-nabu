# Custom package set for nixos-for-nabu.
# Exposed as an overlay so `pkgs.kernel-sm8150` etc. work inside the
# NixOS configuration.
final: prev: {
  # Mainline sm8150 kernel (6.17) with nabu support
  kernel-sm8150 = final.callPackage ./kernel { };

  # Qualcomm protection domain mapper (missing from nixpkgs)
  pd-mapper = final.callPackage ./pd-mapper.nix { };

  # Device firmware from the postmarketOS firmware repo
  xiaomi-nabu-firmware = final.callPackage ./nabu-firmware.nix { };

  # ALSA UCM profile for sm8150-nabu audio
  nabu-alsa-ucm = final.stdenv.mkDerivation {
    pname = "nabu-alsa-ucm";
    version = "1";
    src = ./alsa-ucm;
    installPhase = ''
      install -Dm644 sm8150.conf "$out/sm8150.conf"
      install -Dm644 HiFi.conf "$out/HiFi.conf"
    '';
    meta = {
      description = "ALSA UCM profiles for Xiaomi Pad 5 (nabu)";
      platforms = final.lib.platforms.linux;
    };
  };
}
