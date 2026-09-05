{ config, osConfig, pkgs, ... }:

let
  # ══ niri: config.kdl + config-gaming.kdl + host.kdl validati a BUILD-TIME ══
  # (la derivazione è in niri-configs.nix: la usa anche `checks` nel flake)
  # osConfig = la config NixOS dell'host: da lì arriva il layout tastiera.
  niriConfigs = import ./niri-configs.nix {
    inherit pkgs;
    layout = osConfig.services.xserver.xkb.layout;
  };
in
{
  xdg.configFile."niri/config.kdl".source        = "${niriConfigs}/config.kdl";
  xdg.configFile."niri/config-gaming.kdl".source = "${niriConfigs}/config-gaming.kdl";
  xdg.configFile."niri/host.kdl".source          = "${niriConfigs}/host.kdl";

  # Gli script che config.kdl chiama (dontkillsteam.sh & co.), con exec bit
  xdg.configFile."niri/scripts" = {
    source = ../dotfiles/niri/scripts;
    recursive = true;
  };

  # ══ Gli attrezzi wayland che config.kdl / gli script usano ══════════
  home.packages = with pkgs; [
    # screenshot pipeline (bind Mod+Ctrl+P)
    grim
    slurp
    swappy
    # clipboard (spawn-at-startup usa wl-paste! è nel pacchetto wl-clipboard)
    wl-clipboard
    cliphist
    # colore/luminosità/audio
    wl-gammarelay-rs     # la riscrittura Rust: è quella con il bus rs.wl-gammarelay
    brightnessctl
    pamixer
    pavucontrol
    # dischi removibili (il client; il demone udisks2 è a sistema)
    udiskie
    # notifiche da script
    libnotify
    # dontkillsteam.sh: unmap della finestra X11 di Steam
    xdotool
    # SENZA questo, nessuna icona delle app qui sotto viene trovata:
    # è lui che mette share/icons/hicolor/index.theme nel profilo utente,
    # e chi cerca un'icona per nome (DMS, Qt, GTK) senza index.theme non
    # guarda nemmeno nella cartella. Scoperto al primo boot: si vedevano
    # solo steam (profilo di sistema, che l'index ce l'ha) e helium
    # (percorso assoluto nel .desktop).
    hicolor-icon-theme

    # ══ Le app (da `pacman -Qe` di Arch, con le stesse config.kdl rules) ══
    # browser — librewolf è il default (xdg.mimeApps sotto), firefox è Mod+F,
    # helium (PDF) è sotto come programs.helium
    librewolf
    firefox
    tor-browser
    # editor: neovim (dev.nix), Mod+C apre `kitty nvim`. vscode è stato tolto.
    # chat
    webcord
    discord
    # studio / note / libri
    obsidian
    anki-bin
    calibre
    # office (fresh/still non esistono più upstream: -stable è l'unico nome)
    libreoffice-stable
    onlyoffice-desktopeditors
    # media & grafica
    qbittorrent
    gimp
    cava
    # dev GUI (i toolchain restano nelle devshell)
    godot
    # file manager: quello di DMS (Mod+E). Dolphin e il suo seguito KDE
    # sono stati tolti; resta solo ark per gli archivi.
    kdePackages.ark
  ];

  # ══ Icone: tema selezionato (NON theming estetico, quello lo fa DMS) ══
  # hicolor sopra copre le app che portano la propria icona. Restano i nomi
  # generici che nessuna app fornisce ("multimedia-volume-control" di
  # pavucontrol, "media-optical" di udiskie) e le icone interne di Ark:
  # serve un tema vero, selezionato. breeze è quello che le app KDE
  # (ark, virt-manager via qt) si aspettano. Lo legge DMS quando
  # l'icon theme è "System Default", via dconf (programs.dconf a sistema ✓).
  # Vuoi il Tela-circle-purple di Arch? pkgs.tela-circle-icon-theme,
  # name "Tela-circle-purple".
  gtk = {
    enable = true;
    iconTheme = {
      name = "breeze";
      package = pkgs.kdePackages.breeze-icons;
    };
  };

  # ══ Cursore: Bibata-Modern-Ice a 20px, com'era su Arch ══════════════
  # Il modulo lo propaga ovunque in un colpo: GTK (settings.ini), Qt/X11
  # (~/.icons/default + XCURSOR_*), e Wayland (niri, che lo legge dalle
  # env var). Niente pacchetti tema oltre a questo: è funzionale, come le icone.
  home.pointerCursor = {
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 20;
    gtk.enable = true;
  };

  # ══ DMS: le impostazioni (bar, widget, tema tokyoNightStorm, firefox.css) ══
  # Stessa strategia di nvim: symlink "live" dentro il repo. DMS ci SCRIVE
  # ogni volta che cambi qualcosa dalla sua UI, quindi non può stare nello
  # store read-only; così invece le modifiche finiscono nel working tree e
  # le committi (`git status` te le mostra). Il fisso le eredita al primo
  # boot: i percorsi assoluti dentro settings.json sono /home/dokkan/..., uguali.
  # (lo stato — sessione, wallpaper corrente, notepad — resta in
  #  ~/.local/state/DankMaterialShell, per-macchina, com'è giusto)
  xdg.configFile."DankMaterialShell".source = config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/nixos-config/dotfiles/dms";

  # Helium (input helium-flake nel flake.nix, modulo HM in sharedModules).
  # Il wrapper aggiunge da solo --ozone-platform-hint=auto quando vede
  # NIXOS_OZONE_WL, che il sistema esporta: wayland nativo, zero flag qui.
  programs.helium.enable = true;

  # virt-manager: si connette a qemu:///system da solo, altrimenti la
  # finestra è vuota. (richiede programs.dconf a sistema ✓)
  dconf.settings."org/virt-manager/virt-manager/connections" = {
    autoconnect = [ "qemu:///system" ];
    uris = [ "qemu:///system" ];
  };

  # ══ Terminale ═══════════════════════════════════════════════════════
  # kitty.conf lo GENERA home-manager da queste opzioni (non si può linkare
  # il file com'era: HM scrive lui ~/.config/kitty/kitty.conf).
  programs.kitty = {
    enable = true;
    settings = {
      # Il font per nome PostScript, inequivocabile: nixpkgs `monaspace`
      # installa anche le varianti Var/Frozen/NF con lo stesso prefisso.
      # (pacchetto a sistema in fonts.packages; `fc-list : postscriptname`)
      font_family = "postscript_name=MonaspaceArgon-Regular";
      font_size = 9;
      enable_audio_bell = false;
      window_padding_width = 25;
      bold_font = "auto";
      italic_font = "auto";
      bold_italic_font = "auto";
    };
    keybindings = {
      "shift+enter" = "send_text all \\e\\r";
    };
    # il tema Tokyo Night Storm, com'era su Arch
    extraConfig = "include theme.conf";
  };
  xdg.configFile."kitty/theme.conf".source = ../dotfiles/kitty/theme.conf;

  # ══ Gli altri dotfiles ══════════════════════════════════════════════
  # cava: solo il gradiente custom (il resto sono i default)
  xdg.configFile."cava/config".source = ../dotfiles/cava/config;

  # swappy: path assoluto → generato, così segue home.homeDirectory.
  # (su Arch il formato era rimasto "espanso" da un salvataggio dalla GUI:
  #  qui torna a essere un pattern strftime)
  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=${config.home.homeDirectory}/Pictures/Screenshots
    save_filename_format=%y%m%d_%Hh%Mm%Ss_screenshot.png
  '';
  # la cartella deve esistere: la usano swappy e screenshot-path di niri
  home.file."Pictures/Screenshots/.keep".text = "";

  # hyprlock: NON portato — il lock è DMS (Mod+L → dms ipc call lock lock).
  # fastfetch: dotfiles/fastfetch (config + immagini), wiring in shell.nix.
  # .gdbinit: in dev.nix 🚩

  # ══ XDG: cartelle utente e app di default (era ~/.config/mimeapps.list) ══
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    extraConfig.XDG_PROJECTS_DIR = "${config.home.homeDirectory}/Projects";
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html"                = "librewolf.desktop";
      "x-scheme-handler/http"    = "librewolf.desktop";
      "x-scheme-handler/https"   = "librewolf.desktop";
      "x-scheme-handler/about"   = "librewolf.desktop";
      "x-scheme-handler/unknown" = "librewolf.desktop";
      # PDF e fumetti → helium, come su Arch
      "application/pdf"               = "helium.desktop";
      "application/x-ext-pdf"         = "helium.desktop";
      "application/x-bzpdf"           = "helium.desktop";
      "application/x-gzpdf"           = "helium.desktop";
      "application/vnd.comicbook+zip" = "helium.desktop";
      "application/vnd.comicbook-rar" = "helium.desktop";
      "application/json"         = "nvim.desktop";
      "application/x-zerosize"   = "nvim.desktop";
      "text/plain"               = "nvim.desktop";
      "text/markdown"            = "nvim.desktop";
      "text/x-csrc"              = "nvim.desktop";
      "text/x-c++src"            = "nvim.desktop";
      "text/x-python"            = "nvim.desktop";
      "text/x-shellscript"       = "nvim.desktop";
    };
  };
}
