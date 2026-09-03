# Minimal NixOS configuration for Xiaomi Pad 5 (nabu).
# Desktop environment, input methods, fonts etc. are intentionally left out —
# configure them yourself on the running system.
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-nabu.nix
    ./rootfs-image.nix
  ];

  # == Identity ===============================================================
  networking.hostName = "nabu";
  system.stateVersion = "25.11";

  # == Users ==================================================================
  users.users.nabu = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "input"
    ];
    initialPassword = "nabu";
  };

  # Minimal image (no DE): drop straight into a tty as $USER automatically.
  services.getty.autologinUser = "nabu";

  # == Nix ====================================================================
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  # == Locale =================================================================
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };
  # Note: no i18n.inputMethod here — add fcitx5 + addons yourself later.

  # == Console font (TTY only; no desktop fonts) ==============================
  console = {
    earlySetup = true;
    font = "ter-132n";
    packages = [ pkgs.terminus_font ];
  };

  # == Minimal essentials ======================================================
  environment.systemPackages = with pkgs; [
    vim
    nano
    git
    usbutils
    alsa-utils
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true; # initial setup convenience
    };
  };

  # Auto-grow rootfs on first boot (image ships minimized)
  boot.growPartition = true;

  # Produce an uncompressed raw ext4 .img — directly flashable via
  # `fastboot flash linux nabu-rootfs.ext4.img`
  nabu.image.compress = false;

  # Tablet-friendly: power button suspends
  services.logind.settings.Login.HandlePowerKey = "suspend";

  # The system is stateless enough for this; speeds up shutdown
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";
}
