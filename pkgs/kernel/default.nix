{
  lib,
  stdenv,
  buildPackages,
  fetchFromGitLab,
  buildLinux,
  # device-specific fragment merged on top of the upstream sm8150 fragment
  extraFragment ? ./configs/extra-sm8150.config,
  ...
}@args:

let
  # The reference (nabu_fedora) build deletes CONFIG_LOCALVERSION and passes
  # LOCALVERSION= / EXTRAVERSION=... to make; inside nixpkgs we keep the
  # plain release: the fork's arm64 defconfig leaves LOCALVERSION at its ""
  # default and the source tarball has no .git, so the kernel release is
  # "${modDirVersion}" with no suffix.
  modDirVersion = "6.17.0";
  version = "6.17.0-sm8150";

  src = fetchFromGitLab {
    domain = "gitlab.com";
    owner = "sm8150-mainline";
    repo = "linux";
    rev = "v${version}";
    hash = "sha256-K+cbu6aGdNxLiM2YimsEQLrL5YQvpPyOcUCvQ2M92Yk=";
  };

  /*
    Produce the final kernel .config with the exact semantics of the
    reference RPM build (kernel-sm8150.spec):

        make defconfig sm8150.config    # fork's arm64 defconfig + in-tree
                                        # upstream fragment (kconfig merge)
        sed -i '/^CONFIG_LOCALVERSION=/d' .config
        cat extra-sm8150.config >> .config
        make olddefconfig

    plus one fix: SPI_MT65XX disabled (see comment in `extraConfig` below).

    Kconfig tools must run on the BUILD machine — buildPackages.stdenv
    keeps this working for cross builds (x86_64 builder).
  */
  mergedConfig = buildPackages.stdenv.mkDerivation {
    pname = "nabu-kconfig-merge";
    inherit version src;

    nativeBuildInputs = with buildPackages; [
      flex
      bison
      bc
      perl
      openssl
      rsync
      python3Minimal
      pkg-config
      ncurses
    ];

    buildPhase = ''
      runHook preBuild

      echo ">>> defconfig + in-tree sm8150 fragment"
      make ARCH=arm64 defconfig sm8150.config

      echo ">>> drop CONFIG_LOCALVERSION (Kconfig empty default applies)"
      sed -i '/^CONFIG_LOCALVERSION=/d' .config

      echo ">>> extra fragment"
      sed 's/\r$//' ${extraFragment} >> .config

      echo ">>> platform fix"
      cat <<'FIX' >> .config
      # nabu is a Qualcomm SM8150 board: the nt36523 touchscreen driver has
      # MediaTek-only SPI code paths (guarded by CONFIG_SPI_MT65XX) that do
      # not compile against mainline SPI core headers, and the fork's
      # defconfig wrongly enables the MTK SPI controller driver.
      CONFIG_SPI_MT65XX=n
      FIX

      echo ">>> olddefconfig"
      make ARCH=arm64 olddefconfig

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp .config $out
      runHook postInstall
    '';
  };

  # Patch adding the merged config as a named defconfig, so nixpkgs'
  # buildLinux can consume it through its `defconfig` parameter (its
  # generate-config.pl pass then only layers nixpkgs' common settings on
  # top instead of re-deriving the whole config interactively).
  defconfigPatch = buildPackages.stdenv.mkDerivation {
    pname = "nabu-defconfig-patch";
    inherit version;

    buildCommand = ''
      target=arch/arm64/configs/nabu_defconfig
      {
        printf '%s\n' \
          "diff --git a/$target b/$target" \
          "new file mode 100644" \
          "--- /dev/null" \
          "+++ b/$target"
        # diff exits 1 when the files differ, which is the success case here
        diff -u /dev/null "${mergedConfig}" | tail -n +3 || true
      } > $out
    '';
  };
in
buildLinux (args
  // {
  inherit version modDirVersion src;
  defconfig = "nabu_defconfig";
  kernelPatches = args.kernelPatches or [ ] ++ [
    {
      name = "nabu-defconfig";
      patch = defconfigPatch;
    }
  ];

  # Belt and braces: the merged defconfig already disables SPI_MT65XX; the
  # interactive refinement pass could only re-enable it if asked — pin the
  # answer as well. LOCALVERSION_AUTO keeps the release at "${modDirVersion}".
  # NR_CPUS: nixpkgs' common config forces 384; the device has 8 CPUs.
  extraConfig = ''
    SPI_MT65XX n
    LOCALVERSION_AUTO n
    NR_CPUS 8
  '';

  # The sm8150 fork's Kconfig differs from mainline expectations (e.g.
  # renamed DRM_NOVA) and nixpkgs' common config may reference symbols the
  # fork dropped; don't hard-fail on those.
  ignoreConfigErrors = true;

  extraMeta = {
    branch = "sm8150/6.17";
    description = "Mainline Linux kernel for SM8150 devices (Xiaomi Pad 5 / nabu)";
    maintainers = with lib.maintainers; [ ];
    platforms = [ "aarch64-linux" ];
  };
})
