{ config, lib, osConfig, pkgs, ... }:

let
  desktopFont = "Monaspace Argon";
  # Qt richiede il valore QFont tra virgolette anche nel file INI.
  qtFonts = {
    general = ''"${desktopFont},10"'';
    fixed = ''"${desktopFont},10"'';
  };

  # ══ niri: config.kdl + config-gaming.kdl + host.kdl validati a BUILD-TIME ══
  # (la derivazione è in niri-configs.nix: la usa anche `checks` nel flake)
  # osConfig = la config NixOS dell'host: da lì arriva il layout tastiera.
  # Sul portatile niri aggiunge "us" come secondo layout (Mod+K alterna);
  # SDDM e la console restano sul solo layout dichiarato dall'host.
  niriConfigs = import ./niri-configs.nix {
    inherit pkgs;
    layout = osConfig.services.xserver.xkb.layout
      + lib.optionalString (osConfig.networking.hostName == "armoredcoreVIP") ",us";
    # Workaround opzionale per bug del cursore NVIDIA: scommenta SOLO se
    # necessario. Il confronto evita di applicarlo al portatile Intel.
    # disableCursorPlane = osConfig.networking.hostName == "armoredcoreVIF";
  };

  # ══ Il tema GTK del fisso: "Tokyo-Night" di HyDE (= Tokyonight-Storm di ══
  # ══ Fausto-Korpsvart), vendorizzato in dotfiles/gtk/ ═══════════════════
  # nixpkgs ha rimosso tokyonight-gtk-theme (dipendeva da gtk-engine-murrine),
  # quindi lo impacchettiamo noi: home-manager vuole un pacchetto con
  # share/themes/<nome>/gtk-{3,4}.0 e per GTK4 (nautilus, libadwaita) lo
  # importa da ~/.config/gtk-4.0/gtk.css; gli url('assets/…') relativi nel
  # css si risolvono dentro il pacchetto. È ciò che rende Nautilus viola
  # scuro sul fisso.
  tokyoNightGtk = pkgs.runCommandLocal "tokyo-night-gtk-theme" { } ''
    mkdir -p $out/share/themes/Tokyo-Night
    cp -r ${../dotfiles/gtk/Tokyo-Night}/. $out/share/themes/Tokyo-Night/
  '';
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
    # wl-copy/wl-paste servono anche a nvim e agli script da terminale.
    # La cronologia clipboard è gestita dal backend nativo di Noctalia.
    wl-clipboard
    # luminosità/audio (il filtro luce blu è gestito da Noctalia)
    brightnessctl
    pamixer
    pavucontrol
    # dischi removibili (il client; il demone udisks2 è a sistema)
    udiskie
    # notifiche da script
    libnotify
    # Helper ricerca file (Mod+Shift+E): risultati dmenu aperti via MIME.
    xdg-utils
    gnugrep
    # dontkillsteam.sh: unmap della finestra X11 di Steam
    xdotool
    # SENZA questo, nessuna icona delle app qui sotto viene trovata:
    # è lui che mette share/icons/hicolor/index.theme nel profilo utente,
    # e chi cerca un'icona per nome (Noctalia, Qt, GTK) senza index.theme non
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
    # file manager: nautilus = "Files" in Spotlight, com'è sul fisso (Mod+E).
    # programs.niri lo ha già come servizio nascosto per il file picker,
    # ma senza il pacchetto qui non compare nel menu e non è nel PATH.
    # Mod+Shift+E resta la ricerca file; Mod+E apre il file manager.
    nautilus
    # archivi: ark, e nautilus li apre da lì. file-roller sarebbe l'alternativa GNOME.
    kdePackages.ark
  ];

  # ══ GTK: icone Tela viola, Monaspace Argon, tema Tokyo-Night ════════
  # Noctalia fa il theming della SUA shell; per le app GTK (nautilus in testa)
  # il look del fisso viene da queste tre cose, che HM scrive in
  # gtk-3.0/settings.ini, gtk-4.0/settings.ini + gtk.css, e in dconf
  # (org/gnome/desktop/interface: le app GTK4 lo leggono via portale).
  # hicolor (sopra) resta necessario: senza il suo index.theme nessuna
  # icona per-app viene trovata, qualunque tema tu scelga.
  gtk = {
    enable = true;
    theme = {
      name = "Tokyo-Night";
      package = tokyoNightGtk;
    };
    # con stateVersion ≥ 26.05 gtk4 NON eredita gtk.theme: va detto
    gtk4.theme = {
      name = "Tokyo-Night";
      package = tokyoNightGtk;
    };
    iconTheme = {
      name = "Tela-circle-purple";
      # il pacchetto di default costruisce solo la variante blu
      package = pkgs.tela-circle-icon-theme.override { colorVariants = [ "purple" ]; };
    };
    font = {
      name = desktopFont;
      size = 10;
      package = pkgs.monaspace;
    };
    colorScheme = "dark";   # prefer-dark, com'è nel dconf del fisso
  };

  # GTK propaga già il font UI in dconf; questo copre il font monospace.
  dconf.settings."org/gnome/desktop/interface".monospace-font-name = "${desktopFont} 10";

  # Installa ENTRAMBI i plugin: la sola variabile QT_QPA_PLATFORMTHEME
  # non basta. Il theming delle app di Noctalia è disabilitato: li gestisce HM.
  qt = {
    enable = true;
    platformTheme.name = "qtct";
    qt5ctSettings.Fonts = qtFonts;
    qt6ctSettings.Fonts = qtFonts;
  };

  # ══ Cursore: Bibata-Modern-Ice a 20px, com'era su Arch ══════════════
  # Il modulo lo propaga ovunque in un colpo: GTK (settings.ini), Qt/X11
  # (~/.icons/default + XCURSOR_*), e Wayland (niri, che lo legge dalle
  # env var). Niente pacchetti tema oltre a questo: è funzionale, come le icone.
  home.pointerCursor = {
    enable = true;   # HM recente lo vuole esplicito (altrimenti warning)
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 20;
    gtk.enable = true;
  };

  # Noctalia: configurazione e palette in home/noctalia.nix. La vecchia
  # config DMS è nella storia git (fino al commit 66176da); lo stato DMS
  # locale (wallpaper, notepad, cronologia) non viene cancellato.

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

  # hyprlock: NON portato — il lock è Noctalia (Mod+L).
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
      # cartelle → nautilus: lo usano Noctalia ("apri
      # cartella" nelle notifiche/download) e xdg-open. Senza, si aprono in kitty.
      "inode/directory"          = "org.gnome.Nautilus.desktop";
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
