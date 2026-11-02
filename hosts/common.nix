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

  # ══ La chiave dei segreti di libvirt, senza TPM ══════════════════════
  # libvirt la crea con `systemd-creds encrypt` e i default: se c'è un
  # TPM, la chiave resta legata al TPM. Basta il Security Chip spento o
  # un aggiornamento del BIOS (cambiano i PCR) e libvirtd non parte più
  # (status=243/CREDENTIALS: successo sul T470s dal 24 ottobre 2026, e
  # ogni switch finiva con "failed (status 4)"). Questa versione usa
  # solo la chiave dell'host in /var/lib/systemd/credential.secret.
  # In /var/lib/libvirt/secrets c'era solo la chiave, nessun segreto:
  # legarla al TPM non proteggeva niente e rendeva fragile libvirtd.
  # Il check system-baseline nel flake controlla che l'unità upstream
  # scriva ancora lo stesso file con lo stesso nome.
  libvirtSecretKey = pkgs.writeShellScript "virt-secret-init-encryption-host-key" ''
    set -o errexit -o nounset -o pipefail
    ${pkgs.coreutils}/bin/dd if=/dev/random status=none bs=32 count=1 \
      | ${config.systemd.package}/bin/systemd-creds encrypt --with-key=host \
          --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key
  '';
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
  # Il sistema viene dal flake: il canale "nixos" che l'installer lascia
  # a root è vecchio e nessuno lo usa. `nix-shell -p` e `nixpkgs#...`
  # puntano già al nixpkgs del flake.lock (registry e NIX_PATH).
  nix.channel.enable = false;

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
  # Niente modifica della riga del kernel dal menu: con l'editor acceso
  # (il default di NixOS) basta aggiungere init=/bin/sh per avere una
  # shell root senza password. Il rollback resta: si sceglie una
  # generazione dal menu, non serve modificarla.
  boot.loader.systemd-boot.editor = false;

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

  # gvfs per Nautilus: Cestino, telefoni (MTP), smb:// e sftp://. Senza,
  # il Cestino nella barra laterale non si apre e "Altre posizioni" non
  # monta niente.
  services.gvfs.enable = true;

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
    man-pages            # man 2 open, man 3 printf: syscall e libc
    man-pages-posix      # man 3p ...: le pagine POSIX
    sddmTheme            # SDDM cerca i temi in /run/current-system/sw/share/sddm/themes
  ];
  # Le man page "da programmatore" (sezione 3 e simili) dei pacchetti di
  # sistema. Le man page dei toolchain arrivano con le devshell.
  documentation.dev.enable = true;

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
  # RAM finita: earlyoom chiude il processo più grosso prima che tutto si
  # blocchi, con una notifica (systembus-notify, parte con la sessione).
  # systemd-oomd è già attivo, ma con i default di NixOS non sorveglia
  # niente; accenderlo sulle sessioni utente non va bene qui: le app
  # aperte da mango stanno tutte nello scope della sessione, e oomd
  # chiuderebbe lo scope intero, cioè mango con tutte le finestre.
  services.earlyoom = {
    enable = true;
    enableNotifications = true;
  };
  # La GPU (Intel o nvidia) è per-host; questo è il pezzo in comune:
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;   # steam e i giochi a 32 bit

  # ══ Steam ═══════════════════════════════════════════════════════════
  # (dontkillsteam.sh su Mod+Q lo manda in tray invece di chiuderlo)
  programs.steam.enable = true;
  # GameMode di Feral: governor della CPU e priorità mentre un gioco gira.
  # Su Steam, nelle opzioni di avvio: `gamemoderun %command%`. Non è la
  # modalità gioco di mango (Mod+Alt+G, gaming.conf), che toglie gap,
  # animazioni e blur: le due cose si sommano.
  programs.gamemode.enable = true;

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
    # Ogni settimana `docker system prune`: container fermi, immagini
    # senza tag, reti inutilizzate e cache di build (le immagini con un
    # tag restano). Come nix.gc per lo store. Se dockerd era spento, la
    # pulizia lo avvia.
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;   # TPM emulato: serve alle VM Windows 11
  };
  # Le chiavette USB dentro le VM di virt-manager (SPICE), senza root.
  virtualisation.spiceUSBRedirection.enable = true;
  programs.virt-manager.enable = true;   # la GUI; la connessione è in home/
  # La chiave dei segreti senza TPM (libvirtSecretKey, in cima al file).
  # Vale solo quando la chiave viene creata: l'unità parte solo se il
  # file non esiste. Per rigenerare una chiave rimasta legata al TPM:
  #   sudo mv /var/lib/libvirt/secrets/secrets-encryption-key{,.prev}
  #   sudo systemctl restart virt-secret-init-encryption libvirtd
  systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart =
    [ "" "${libvirtSecretKey}" ];

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
  # Gli avvisi SMART arrivano anche come notifica desktop (swaync), via
  # systembus-notify: lo stesso canale delle notifiche di earlyoom, che
  # lo accende. I due moduli devono essere d'accordo, altrimenti la
  # valutazione fallisce ("conflicting definition values"). Il bus di
  # sistema accetta notifiche da qualunque utente locale: qui ci sei
  # solo tu.
  services.smartd = {
    enable = true;
    notifications.systembus-notify.enable = true;
  };
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
  # services.printing.enable = true;  # stampa; per le stampanti di rete senza
  #                                   # driver anche services.avahi (nssmdns4)
  # Backup: ancora niente. services.restic.backups su un disco esterno,
  # oppure Syncthing tra i due pc passando da ZeroTier.
  # proton-ge-bin: programs.steam.extraCompatPackages, se un gioco lo chiede.
}
