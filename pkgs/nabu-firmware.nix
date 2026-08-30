{
  lib,
  stdenv,
  fetchFromGitLab,
  # linux-firmware provides qcom-sm8150 etc.; this package adds the
  # device-specific files extracted from the Android vendor partition
  linux-firmware,
}:

let
  firmwareFiles = fetchFromGitLab {
    domain = "gitlab.postmarketos.org";
    owner = "panpanpanpan";
    repo = "nabu-firmware";
    rev = "1";
    hash = "sha256-Pjd0UOGJRieau94MNERWfOFvFZItu4X3wLlBPp1atmg=";
  };
in
stdenv.mkDerivation {
  pname = "xiaomi-nabu-firmware";
  version = "1";

  src = firmwareFiles;

  # no build step, only file installation
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    fw="$out/lib/firmware"
    mkdir -p \
      "$fw/qcom" \
      "$fw/qcom/sm8150/xiaomi/nabu" \
      "$fw/cirrus" \
      "$fw/novatek"

    # GPU (Adreno 640)
    cp -a a630_sqe.fw a640_gmu.bin "$fw/qcom/"
    cp -a a640_zap.mbn "$fw/qcom/" 2>/dev/null || true

    # remoteproc / modem / video / wlan firmware
    cp -a adsp.mbn cdsp.mbn modem* venus.mbn wlanmdsp.mbn \
      "$fw/qcom/sm8150/xiaomi/nabu/" 2>/dev/null || true

    # audio amplifiers (quad speakers)
    cp -a cs35l41* "$fw/cirrus/" 2>/dev/null || true

    # touchscreen (Novatek NT36523)
    cp -a novatek_nt36523_fw.bin "$fw/novatek/" 2>/dev/null || true

    runHook postInstall
  '';

  meta = {
    description = "Device-specific firmware files for Xiaomi Pad 5 (nabu)";
    homepage = "https://gitlab.postmarketos.org/panpanpanpan/nabu-firmware";
    license = lib.licenses.unfreeRedistributableFirmware;
    platforms = lib.platforms.linux;
    priority = 10;
  };
}
