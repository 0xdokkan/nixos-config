# ╔════════════════════════════════════════════════════════════════════╗
# ║  armoredcoreVIF — il fisso: i7-9700K, GeForce RTX 2070 (nvidia-open)║
# ║  Tutto il resto (desktop, audio, app, utente...) è in ../common.nix║
# ╚════════════════════════════════════════════════════════════════════╝
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../common.nix
  ];

  networking.hostName = "armoredcoreVIF";

  # Tastiera: US, cioè il default di services.xserver.xkb.layout.
  # (il portatile invece dichiara "it" — vedi hosts/armoredcoreVIP)

  # ══ CPU ═════════════════════════════════════════════════════════════
  hardware.cpu.intel.updateMicrocode = true;   # Coffee Lake, i7-9700K

  # ══ Grafica: RTX 2070 ═══════════════════════════════════════════════
  # Su Arch: nvidia-open-dkms + nvidia-utils. Qui il modulo del kernel lo
  # compila nix per il kernel che stai usando, niente dkms da tenere in vita.
  services.xserver.videoDrivers = [ "nvidia" ];   # vale anche per wayland
  hardware.nvidia = {
    # obbligatorio con driver >= 560: la RTX 2070 (Turing) è supportata
    # dai moduli open, esattamente come nvidia-open-dkms su Arch
    open = true;
    # DRM KMS: senza questo niri/wayland non partono con nvidia
    modesetting.enable = true;
    # nvidia-settings (GUI)
    nvidiaSettings = true;
    # Il default è il ramo "stable" di nixpkgs. Su Arch avevi il 610.x,
    # cioè il più recente: se lo rivuoi, scommenta (può rompersi con i
    # kernel nuovissimi, a te la scelta)
    # package = config.boot.kernelPackages.nvidiaPackages.latest;
    # Sospensione/ripresa con nvidia: attivalo solo se S3 ti dà problemi
    powerManagement.enable = false;
  };
  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver   # VAAPI via NVDEC (era l'extension flatpak su Arch)
  ];

  # ══ Le env var nvidia che erano nel config.kdl di Hyprland/HyDE ═════
  # config.kdl è condiviso col portatile e non le ha più: qui le mettiamo
  # nella sessione utente, così niri e tutto ciò che lancia le ereditano.
  environment.sessionVariables = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
    __GL_VRR_ALLOWED = "1";
    # cursore software: con nvidia il cursore hardware a volte sparisce/lagga
    NIRI_DISABLE_HARDWARE_CURSORS = "1";
  };

  # ══ NON TOCCARE MAI ═════════════════════════════════════════════════
  # Marcatore di compatibilità per i dati stateful, NON una versione da
  # aggiornare: resta al valore della prima install per sempre.
  system.stateVersion = "26.05";
}
