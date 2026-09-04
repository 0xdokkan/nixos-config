# ╔════════════════════════════════════════════════════════════════════╗
# ║  Tutto ciò che è UGUALE su portatilino e fisso.                    ║
# ║  Le differenze (CPU, GPU, batteria) stanno in hosts/<nome>/.       ║
# ╚════════════════════════════════════════════════════════════════════╝
{ config, pkgs, ... }:

{
  # ══ Nix stesso ══════════════════════════════════════════════════════
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;   # discord, steam, obsidian, claude-code, nvidia...

  # ══ Boot ════════════════════════════════════════════════════════════
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # boot.loader.systemd-boot.configurationLimit = 15; # quante generazioni tenere nel menu

  # ══ Rete (l'hostName è per-host) ════════════════════════════════════
  networking.networkmanager.enable = true;
  # Su Arch iwd è installato ma inattivo: NetworkManager usa wpa_supplicant.
  # Se un giorno vuoi iwd, è una riga:
  # networking.networkmanager.wifi.backend = "iwd";
  networking.firewall.enable = true;

  # ══ Localizzazione ══════════════════════════════════════════════════
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";
  # Layout tastiera: services.xserver.xkb.layout, per-host (il fisso ha il
  # default "us", il portatile "it"). La console lo deriva da lì:
  console.useXkbConfig = true;

  # ══ Utente ══════════════════════════════════════════════════════════
  users.users.dokkan = {
    isNormalUser = true;
    description = "Dokkan";
    extraGroups = [
      "wheel"
      "networkmanager"
      "wireshark"     # cattura pacchetti senza root (programs.wireshark sotto)
      "docker"        # = root sul container host, ricordatelo 😄
      "libvirtd"      # virt-manager su qemu:///system senza password
    ];
    shell = pkgs.zsh;
    initialPassword = "cambiami";   # ← primo login: `passwd`!
    # chi può entrare via ssh: SOLO chi ha la privata di questa .pub
    # (la .pub è pubblica per definizione, committarla è ok; la privata
    #  la porti tu in ~/.ssh delle nuove macchine, o ne generi una nuova
    #  e aggiungi qui la sua .pub)
    openssh.authorizedKeys.keyFiles = [ ../dotfiles/ssh/id_ed25519.pub ];
  };
  programs.zsh.enable = true;   # la login shell va dichiarata a sistema
                                # (finisce in /etc/shells); la CONFIG è in home/

  # ══ SSH in ingresso ═════════════════════════════════════════════════
  # Apre la 22 nel firewall da solo. Niente password: un laptop in wifi
  # pubblico con PasswordAuthentication sarebbe un bersaglio per i bot.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # ══ Desktop: niri + DMS + SDDM ══════════════════════════════════════
  # programs.niri porta con sé: sessione per SDDM, xdg-desktop-portal
  # (gnome + gtk, come su Arch), gnome-keyring, xwayland-satellite.
  programs.niri.enable = true;

  # DankMaterialShell è in nixpkgs da 26.05 (opzione `programs.dms-shell`,
  # NON `programs.dank-material-shell`: quello è il nome nel flake DMS).
  # NB: config.kdl non fa `include "dms/..."`, come su Arch — quindi
  # `dms setup` non serve (e non potrebbe comunque scrivere in config.kdl,
  # che è read-only nello store).
  programs.dms-shell = {
    enable = true;
    # parte come user service agganciato alla sessione di niri, quindi
    # NON va in spawn-at-startup (config.kdl lo sa già)
    systemd.enable = true;
    enableSystemMonitoring = true;   # dgop: widget cpuUsage/memUsage della bar
    enableAudioWavelength = true;    # cava: visualizzatore nel widget media
    enableDynamicTheming = true;     # matugen: se mai scegli il tema "auto"
  };

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  security.polkit.enable = true;   # DMS ha il suo agent, ma il demone è qui
  programs.dconf.enable = true;    # serve a HM dconf.settings (virt-manager)

  # Il widget "power profile" del control-center DMS parla con questo
  # (su Arch non c'era: il widget era vuoto). Sul portatile, se un giorno
  # attivi TLP, SPEGNI questo: sono in conflitto.
  services.power-profiles-daemon.enable = true;

  # Le app Electron (discord, obsidian, webcord...) in wayland nativo.
  # Sostituisce i vari ~/.config/*-flags.conf di Arch. Lo legge anche il
  # wrapper di helium.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Dolphin fuori da Plasma: senza un menu XDG il "Apri con..." è vuoto.
  # È il plasma-applications.menu di KDE, vendorizzato per non tirarsi
  # dentro tutto plasma-workspace (vedi wiki.nixos.org/wiki/Dolphin).
  environment.etc."xdg/menus/applications.menu".source =
    ../dotfiles/xdg/applications.menu;

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

  # ══ Hardware comune ═════════════════════════════════════════════════
  hardware.bluetooth.enable = true;
  services.udisks2.enable = true;      # il demone; udiskie (client) è in home/
  zramSwap.enable = true;
  # La GPU (Intel o nvidia) è per-host; questo è il pezzo in comune:
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;   # steam e i giochi a 32 bit

  # ══ Steam ═══════════════════════════════════════════════════════════
  # (dontkillsteam.sh su Mod+Q lo manda in tray invece di chiuderlo)
  programs.steam.enable = true;

  # ══ Container e VM ══════════════════════════════════════════════════
  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;   # la GUI; la connessione è in home/

  # ══ VPN ═════════════════════════════════════════════════════════════
  services.mullvad-vpn = {
    enable = true;
    gui.enable = true;   # il default è solo daemon + CLI
  };

  # ══ Salute del disco ════════════════════════════════════════════════
  services.smartd.enable = true;

  # ══ Il salva-CTF: i binari FHS scaricati partono 🚩 ═════════════════
  programs.nix-ld.enable = true;

  # wireshark (GUI) con dumpcap setuid + gruppo: su Arch c'era wireshark-qt.
  # termshark/tshark stanno nella devshell ctf.
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  # ══ Font ════════════════════════════════════════════════════════════
  fonts.packages = with pkgs; [
    monaspace                    # kitty: Monaspace Argon
    nerd-fonts.jetbrains-mono    # era ttf-jetbrains-mono-nerd (solo il font!)
    nerd-fonts.symbols-only      # era ttf-nerd-fonts-symbols: p10k è in
                                 # modalità nerdfont-complete e Monaspace
                                 # non ha i glifi → fallback via fontconfig
    noto-fonts-color-emoji       # ttf-apple-emoji non è in nixpkgs
                                 # (licenza Apple), questo è lo standard
  ];
  fonts.fontconfig.defaultFonts.emoji = [ "Noto Color Emoji" ];

  # ══ Rimandati di proposito ══════════════════════════════════════════
  # services.flatpak.enable = true;   # su Arch c'era, ma quasi tutto è in nixpkgs
  # (postgresql: NO — vive nelle devshell per-progetto, come deciso!)
}
