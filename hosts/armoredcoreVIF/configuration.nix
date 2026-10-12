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
    # Sospensione/ripresa: salva la VRAM prima dello sleep
    # (NVreg_PreserveVideoMemoryAllocations), altrimenti su Wayland al
    # resume le finestre possono tornare nere o corrotte. Con driver open
    # >= 595 NixOS usa i suspend notifier del kernel, senza servizi systemd.
    powerManagement.enable = true;
  };
  hardware.graphics.extraPackages = with pkgs; [
    nvidia-vaapi-driver   # VAAPI via NVDEC (era l'extension flatpak su Arch)
  ];

  # ══ Le env var nvidia che erano nel config.kdl di Hyprland/HyDE ═════
  # config.kdl è condiviso col portatile e non le ha più: qui le mettiamo
  # nella sessione utente, così niri e tutto ciò che lancia le ereditano.
  # GBM_BACKEND e __GLX_VENDOR_LIBRARY_NAME non servono più con i driver
  # recenti (GBM e glvnd trovano nvidia da soli) e GBM_BACKEND è il primo
  # sospettato quando Firefox/Electron crashano: rimettile solo se servono.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    __GL_VRR_ALLOWED = "1";
  };

  # ══ niri su NVIDIA: VRAM ════════════════════════════════════════════
  # Il driver non restituisce al pool la VRAM liberata dai compositor
  # Wayland: niri arriva verso 1 GiB invece di ~100 MiB (controlla con
  # nvtop). NVIDIA ha già un profilo "No VidMem Reuse" per Hyprland, kwin,
  # mutter, wlroots, Xwayland... ma non per niri: questo è il fix della
  # wiki di niri (docs/wiki/Nvidia.md).
  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json".text =
    builtins.toJSON {
      rules = [
        {
          pattern = { feature = "procname"; matches = "niri"; };
          profile = "Limit Free Buffer Pool On Wayland Compositors";
        }
      ];
      profiles = [
        {
          name = "Limit Free Buffer Pool On Wayland Compositors";
          settings = [ { key = "GLVidHeapReuseRatio"; value = 0; } ];
        }
      ];
    };

  # NIRI_DISABLE_HARDWARE_CURSORS non è un'opzione di niri.
  # Se il cursore dà problemi, abilita il workaround KDL disable-cursor-plane
  # SOLO per questo host: vedi il parametro commentato in home/desktop.nix.
  # Di default resta disabilitato: non tutti i sistemi NVIDIA ne hanno bisogno.

  # ══ NON TOCCARE MAI ═════════════════════════════════════════════════
  # Marcatore di compatibilità per i dati stateful, NON una versione da
  # aggiornare: resta al valore della prima install per sempre.
  system.stateVersion = "26.05";
}
