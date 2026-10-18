# ╔════════════════════════════════════════════════════════════════════╗
# ║  Tutto ciò che è UGUALE su armoredcoreVIP (portatile) e             ║
# ║  armoredcoreVIF (fisso).                                           ║
# ║  Le differenze (CPU, GPU, batteria) stanno in hosts/<nome>/.       ║
# ╚════════════════════════════════════════════════════════════════════╝
{ config, pkgs, ... }:

let
  # ══ Il tema di SDDM ══════════════════════════════════════════════════
  # Su Arch c'era "Candy" (Sugar Candy di HyDE), che è Qt5: SDDM in nixpkgs
  # da 25.11 è solo Qt6 e non lo carica. sddm-astronaut DISCENDE da Sugar
  # Candy, è Qt6 ed è in nixpkgs: gli passiamo lo stesso sfondo e le stesse
  # impostazioni di Candy (theme.conf di Arch) e il risultato è quello.
  sddmTheme = pkgs.sddm-astronaut.override {
    embeddedTheme = "astronaut";
    themeConfig = {
      Background = "${../dotfiles/sddm/bg.png}";   # il bg.png di Candy
      ScreenWidth = "1920";
      ScreenHeight = "1080";
      CropBackground = "true";
      DimBackground = "0.0";
      FullBlur = "false";
      PartialBlur = "true";
      HaveFormBackground = "true";
      FormPosition = "left";
      BackgroundColor = "#444";
      RoundCorners = "20";
      Font = "Monaspace Argon";
      HourFormat = "hh:mm A";
      DateFormat = "dddd, d of MMMM";
      HeaderText = "码农万岁";
      ForceLastUser = "true";
      PasswordFocus = "true";
      HideCompletePassword = "false";
    };
  };

  # ══ La sessione mango ════════════════════════════════════════════════
  # Il .desktop di mango lancia solo `mango`: nessun target systemd parte
  # e nessuno lo ferma all'uscita. Il target lo avvia la config di mango
  # (exec_once=mango-session-start, home/mango.nix); questo wrapper fa la
  # parte finale: quando mango esce ferma i servizi grafici (waybar,
  # swaync, swayidle...) e pulisce l'ambiente, così il login successivo
  # riparte da zero.
  mangoSession = pkgs.writeShellApplication {
    name = "mango-session";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      ${pkgs.mango}/bin/mango "$@" && status=0 || status=$?
      systemctl --user stop mango-session.target || true
      systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY \
        MANGO_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE || true
      exit "$status"
    '';
  };
  # Lo stesso pacchetto mango, con la voce di SDDM che passa dal wrapper.
  mangoPackage = pkgs.symlinkJoin {
    name = "mango-session-${pkgs.mango.version}";
    paths = [ pkgs.mango mangoSession ];
    postBuild = ''
      rm $out/share/wayland-sessions/mango.desktop
      substitute ${pkgs.mango}/share/wayland-sessions/mango.desktop \
        $out/share/wayland-sessions/mango.desktop \
        --replace-fail 'Exec=mango' 'Exec=${mangoSession}/bin/mango-session'
    '';
    passthru.providedSessions = [ "mango" ];
  };
in
{
  # ══ Nix stesso ══════════════════════════════════════════════════════
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;   # discord, steam, obsidian, claude-code, nvidia...
  # Cache pubblicata da Numtide per llm-agents: evita di compilare Codex.
  # È una fonte di binari fidata aggiuntiva, con verifica della firma.
  nix.settings.extra-substituters = [ "https://cache.numtide.com" ];
  nix.settings.extra-trusted-public-keys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
  ];

  # ══ Pulizia automatica dello store ══════════════════════════════════
  # Ogni rebuild lascia la generazione precedente (è il rollback). Senza
  # questo, /nix/store cresce per sempre. Ogni settimana: via le
  # generazioni più vecchie di 14 giorni, poi gc di ciò che nessuno usa più.
  # (La generazione ATTIVA e quelle recenti restano sempre.)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
    persistent = true;   # se il pc era spento al momento giusto, lo fa al boot
  };
  # Deduplica i file identici nello store con hardlink: 20-30% di spazio
  nix.settings.auto-optimise-store = true;
  # Pulizia a mano, quando vuoi:
  #   sudo nix-collect-garbage --delete-older-than 7d   (o -d = tutte tranne l'attiva)

  # ══ Boot ════════════════════════════════════════════════════════════
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Nel menu di boot al massimo 10 generazioni: il file /boot è piccolo (1 GB)
  # e ogni voce porta con sé kernel + initrd. La gc sopra fa il resto.
  boot.loader.systemd-boot.configurationLimit = 10;

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

  # ══ Desktop: mango + SDDM ═══════════════════════════════════════════
  # programs.mango porta con sé: la sessione per SDDM (qui col wrapper
  # mango-session, vedi sopra) e i portali wlr (screenshot e condivisione
  # schermo) + gtk (tutto il resto). XWayland è dentro mango.
  # Barra, notifiche, lock e il resto del desktop stanno in home/ e
  # partono con graphical-session.target.
  programs.mango = {
    enable = true;
    package = mangoPackage;
  };

  # Password, chiavi SSH e segreti delle app; si sblocca al login di SDDM.
  # (Con niri lo accendeva programs.niri, mango non lo fa.)
  services.gnome.gnome-keyring.enable = true;

  # Lo stack PAM per hyprlock (il lock, configurato in home/). Non uso
  # programs.hyprlock perché accenderebbe anche hypridle: l'idle lo
  # gestiscono swayidle e home/idle.py.
  security.pam.services.hyprlock = { };

  # UPower serve ai profili idle (AC/batteria), anche sul fisso (che senza
  # batterie viene trattato come alimentato da rete).
  services.upower.enable = true;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    theme = "sddm-astronaut-theme";   # = sddmTheme (in systemPackages sotto)
    # i moduli QML che il tema importa devono stare nel path del greeter
    extraPackages = with pkgs.kdePackages; [ qtsvg qtmultimedia qtvirtualkeyboard ];
  };

  security.polkit.enable = true;   # l'agent (polkit-gnome) è in home/, il demone è qui
  programs.dconf.enable = true;    # serve a HM dconf.settings (virt-manager)

  # Profili energetici (powerprofilesctl). Sul portatile, se un giorno
  # attivi TLP, SPEGNI questo: sono in conflitto.
  services.power-profiles-daemon.enable = true;

  # Le app Electron (discord, obsidian, webcord...) in wayland nativo.
  # Sostituisce i vari ~/.config/*-flags.conf di Arch. Lo legge anche il
  # wrapper di helium.
  # mango-session-start importa l'ambiente prima di avviare i servizi
  # utente: queste variabili arrivano anche a waybar, rofi e alle app.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    # Come qt.platformTheme.name = "qtct" in home/desktop.nix:
    # qt5ct è anche l'alias riconosciuto dal plugin Qt6 di qt6ct.
    QT_QPA_PLATFORMTHEME = "qt5ct";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    QT_AUTO_SCREEN_SCALE_FACTOR = "1";
    MOZ_ENABLE_WAYLAND = "1";
    GDK_SCALE = "1";
  };

  # Le app con Terminal=true nel .desktop (nvim.desktop, htop...) aperte
  # da Nautilus/xdg-open: GLib non conosce kitty e cerca prima
  # xdg-terminal-exec. Senza, "apri con nvim" non trova un terminale.
  xdg.terminal-exec = {
    enable = true;
    settings.default = [ "kitty.desktop" ];
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    sddmTheme            # SDDM cerca i temi in /run/current-system/sw/share/sddm/themes
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
  virtualisation.docker = {
    enable = true;
    # dockerd parte via socket al primo comando `docker`, non a ogni boot.
    # (I container con --restart=always però non ripartono da soli al boot.)
    enableOnBoot = false;
    # Le porte pubblicate (-p 8080:80) scrivono regole iptables proprie e
    # scavalcano il firewall di NixOS: di default ascoltano solo in locale.
    # Per esporne una alla rete apposta: -p 0.0.0.0:8080:80
    daemon.settings.ip = "127.0.0.1";
  };
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;   # la GUI; la connessione è in home/

  # ══ VPN ═════════════════════════════════════════════════════════════
  services.mullvad-vpn = {
    enable = true;
    gui.enable = true;   # il default è solo daemon + CLI
  };
  # ZeroTier: rete virtuale tra i propri pc (o con gli amici). Il demone
  # apre da solo la porta UDP 9993; a una rete ci si unisce una volta:
  #   sudo zerotier-cli join <id-rete>   (e la si autorizza da my.zerotier.com)
  services.zerotierone.enable = true;

  # ══ Salute del disco e firmware ═════════════════════════════════════
  services.smartd.enable = true;
  # Aggiornamenti firmware da LVFS (BIOS/EC del T470s, SSD, periferiche):
  #   fwupdmgr refresh && fwupdmgr get-updates && fwupdmgr update
  services.fwupd.enable = true;

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
    monaspace                    # Monaspace Argon: desktop, login e kitty
    nerd-fonts.jetbrains-mono    # era ttf-jetbrains-mono-nerd (solo il font!)
    nerd-fonts.symbols-only      # era ttf-nerd-fonts-symbols: p10k è in
                                 # modalità nerdfont-complete e Monaspace
                                 # non ha i glifi → fallback via fontconfig
    noto-fonts-color-emoji       # ttf-apple-emoji non è in nixpkgs
                                 # (licenza Apple), questo è lo standard
    noto-fonts                   # fallback per i caratteri mancanti
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Monaspace Argon" "Noto Sans" ];
    monospace = [ "Monaspace Argon" "Symbols Nerd Font Mono" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # ══ Rimandati di proposito ══════════════════════════════════════════
  # services.flatpak.enable = true;   # su Arch c'era, ma quasi tutto è in nixpkgs
  # (postgresql: NO — vive nelle devshell per-progetto, come deciso!)
}
