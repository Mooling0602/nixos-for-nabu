# Base NixOS configuration for Xiaomi Pad 5 (nabu).
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
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.waylandFrontend = true;
    fcitx5.addons = with pkgs; [
      fcitx5-chinese-addons
      fcitx5-gtk
      fcitx5-qt
    ];
  };

  # == Console / fonts ========================================================
  console = {
    earlySetup = true;
    font = "ter-132n";
    packages = [ pkgs.terminus_font ];
  };
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    nerd-fonts.terminus
  ];

  # == Essentials =============================================================
  environment.systemPackages = with pkgs; [
    vim
    nano
    git
    usbutils
    alsa-utils
    networkmanagerapplet
    # Qualcomm debugging
    qrtr
    pd-mapper
    rmtfs
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true; # initial setup convenience
    };
  };

  # Auto-grow rootfs partition on first boot (image ships minimized)
  boot.growPartition = true;

  # Tablet-friendly: power button suspends
  services.logind.settings.Login.HandlePowerKey = "suspend";

  # The system is stateless enough for this; speeds up shutdown
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";
}
