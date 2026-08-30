{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ══ Nix stesso ══════════════════════════════════════════════════════
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;   # discord, steam, nvidia, code...

  # ══ Boot ════════════════════════════════════════════════════════════
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # boot.loader.systemd-boot.configurationLimit = 15; # quante generazioni tenere nel menu

  # ══ Rete ════════════════════════════════════════════════════════════
  networking.hostName = "portatilino";
  networking.networkmanager.enable = true;
  # networking.networkmanager.wifi.backend = "iwd";   # TODO: come su Arch, se lo vuoi
  networking.firewall.enable = true;

  # ══ Localizzazione ══════════════════════════════════════════════════
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";
  # console.keyMap = "us";

  # ══ Utente ══════════════════════════════════════════════════════════
  users.users.dokkan = {
    isNormalUser = true;
    description = "Dokkan";
    extraGroups = [ "wheel" "networkmanager" ];
    # TODO quando abiliti docker/libvirt: aggiungi "docker" "libvirtd"
    shell = pkgs.zsh;
    initialPassword = "cambiami";   # ← primo login: `passwd`!
  };
  programs.zsh.enable = true;   # la login shell va dichiarata a sistema
                                # (finisce in /etc/shells); la CONFIG è in home/

  # ══ Desktop: niri + DMS + SDDM ══════════════════════════════════════
  programs.niri.enable = true;
  programs.dank-material-shell.enable = true;
  # ^ se il rebuild dice che l'opzione non esiste, il nome è cambiato:
  #   cerca "dank" su search.nixos.org/options e correggi.
  # Ricorda: al primo boot, `dms setup` rigenera gli include auto-generati.

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  environment.systemPackages = with pkgs; [
    xwayland-satellite   # X11 apps dentro niri
    vim
    wget
    git
  ];

  # ══ Audio (tutta la pila pipewire di Arch → questo blocco) ══════════
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # ══ Hardware vario ══════════════════════════════════════════════════
  hardware.bluetooth.enable = true;
  services.udisks2.enable = true;      # il demone; udiskie (client) è in home/
  zramSwap.enable = true;
  hardware.cpu.intel.updateMicrocode = true;   # T470s → Kaby Lake, Intel

  # ══ Grafica: Intel HD 620 integrata (T470s, niente nvidia) ══════════
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver   # VAAPI (decodifica video hw) per Gen9.5/Kaby Lake
  ];
  # config.kdl già ripulito dalle env var nvidia ✓

  # ══ Laptop ThinkPad: termiche e batteria ════════════════════════════
  services.thermald.enable = true;
  # TLP: opzionale ma sui ThinkPad dà il meglio — incluse le soglie di
  # carica per la salute della batteria:
  # services.tlp = {
  #   enable = true;
  #   settings = {
  #     START_CHARGE_THRESH_BAT0 = 75;
  #     STOP_CHARGE_THRESH_BAT0 = 90;
  #   };
  # };

  # ══ Il salva-CTF: i binari FHS scaricati partono 🚩 ═════════════════
  programs.nix-ld.enable = true;

  # ══ Font ════════════════════════════════════════════════════════════
  fonts.packages = with pkgs; [
    monaspace
    # TODO: un pacchetto emoji (noto-fonts-color-emoji? apple? cerca tu 😄)
  ];

  # ══ TODO — scommentali QUANDO ti servono, non prima ═════════════════
  # programs.steam.enable = true;
  # virtualisation.docker.enable = true;
  # virtualisation.libvirtd.enable = true;
  # programs.virt-manager.enable = true;
  # services.flatpak.enable = true;
  # services.mullvad-vpn.enable = true;
  # services.smartd.enable = true;
  # (postgresql: NO — vive nelle devshell per-progetto, come deciso!)

  # ══ NON TOCCARE MAI ═════════════════════════════════════════════════
  # Marcatore di compatibilità per i dati stateful, NON una versione da
  # aggiornare: resta al valore della prima install per sempre.
  system.stateVersion = "26.05";
}
