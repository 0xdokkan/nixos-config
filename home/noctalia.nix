{ noctaliaPackage, pkgs, ... }:

let
  wifiQr = pkgs.writeShellApplication {
    name = "noctalia-wifi-qr";
    text = ''
      # Solo su richiesta esplicita: niente file, log, clipboard o shell history.
      # La finestra ha app-id/titolo dedicati alle regole privacy di niri.
      exec ${pkgs.kitty}/bin/kitty --class noctalia-wifi-qr --title 'Wi-Fi QR' \
        --hold --env PAGER= ${pkgs.networkmanager}/bin/nmcli device wifi show-password
    '';
  };
in
{
  # Noctalia riproduce i feedback audio dai sound theme XDG (non dai suoni DMS).
  home.packages = [ pkgs.sound-theme-freedesktop wifiQr ];

  # La 5.2.1 non ha il QR Wi-Fi nel Control Center. Lo stesso dato è disponibile
  # con nmcli, in una finestra esclusa dagli screencast gestiti da niri.
  # Cercare "Wi-Fi QR" nel launcher oppure cliccare il Control Center col medio.
  xdg.desktopEntries.noctalia-wifi-qr = {
    name = "Wi-Fi QR";
    comment = "Mostra password e QR della rete Wi-Fi attiva in una finestra privata";
    exec = "${wifiQr}/bin/noctalia-wifi-qr";
    icon = "network-wireless";
    terminal = false;
    categories = [ "Network" "Utility" ];
    settings.StartupWMClass = "noctalia-wifi-qr";
  };

  # Noctalia v5 nativo: config.toml contiene i default condivisi dai due host.
  # Le modifiche dalla GUI restano scrivibili in
  # ~/.local/state/noctalia/settings.toml e hanno precedenza sui default HM.
  # Non serve un symlink live nel repo: cronologia, wallpaper e posizione
  # rimangono locali alla macchina; le preferenze comuni si portano qui.
  programs.noctalia = {
    enable = true;
    package = noctaliaPackage;
    systemd.enable = true;
    checkConfig = true;

    customPalettes.TokyoNightStorm = ../dotfiles/noctalia/palettes/TokyoNightStorm.json;

    settings = {
      shell = {
        font_family = "Monaspace Argon";
        time_format = "{:%H:%M}";
        telemetry_enabled = false;
        setup_wizard_enabled = false;
        settings_show_advanced = true;
        # Un solo agente polkit, con la stessa UI e palette della shell.
        polkit_agent = true;
        # Un restart della shell non deve terminare le app aperte dal launcher.
        launch_apps_as_systemd_services = true;
        clipboard_enabled = true;
        clipboard_keep_from_closed_apps = true;
        # Come DMS: selezionare una voce copia, senza incollare nella finestra.
        clipboard_auto_paste = "off";
      };

      theme = {
        mode = "dark";
        shell_mode = "follow";
        source = "custom";
        custom_palette = "TokyoNightStorm";
        # GTK, Qt, Kitty e Neovim mantengono i temi gestiti separatamente.
        templates = {
          enable_builtin_templates = false;
          enable_community_templates = false;
          builtin_ids = [ ];
          community_ids = [ ];
        };
      };

      # Stesse tre sezioni e stesso ordine dei widget della barra DMS.
      # Il visualizzatore, integrato in Music su DMS, qui è un widget vicino.
      bar.default = {
        enabled = true;
        position = "top";
        auto_hide = false;
        reserve_space = true;
        layer = "top";
        margin_ends = 0;
        margin_edge = 0;
        padding = 4;
        widget_spacing = 4;
        font_weight = 400;
        radius = 12;
        concave_edge_corners = false;
        shadow = false;
        compositor_blur = false;
        background_opacity = 0.0;
        capsule = true;
        capsule_fill = "surface";
        capsule_opacity = 1.0;
        start = [ "launcher" "workspaces" "active_window" ];
        center = [ "media" "audio_visualizer" "clock" "weather" ];
        end = [ "tray" "clipboard" "cpu" "ram" "notifications" "battery" "control-center" ];
      };

      widget = {
        "control-center".actions.middle = "exec ${wifiQr}/bin/noctalia-wifi-qr";
        workspaces = {
          style = "regular";
          show_labels = false;
          hide_when_empty = false;
        };
        media = {
          hide_when_no_media = true;
          title_scroll = "always";
          show_progress = true;
        };
        audio_visualizer = {
          width = 48;
          show_when_idle = false;
          color_1 = "primary";
          color_2 = "secondary";
        };
        cpu = {
          type = "sysmon";
          stat = "cpu_usage";
          show_value = true;
        };
        ram = {
          type = "sysmon";
          stat = "ram_pct";
          show_value = true;
        };
        battery = {
          device = "auto";
          display_mode = "glyph";
          show_label = true;
          label_content = "percent";
          hide_when_plugged = false;
          hide_when_full = false;
        };
      };

      dock.enabled = false;
      control_center = {
        sidebar = "compact";
        # Audio e luminosità restano disponibili nelle rispettive schede.
        shortcuts = map (type: { inherit type; }) [
          "wifi" "bluetooth" "audio" "mic_mute" "nightlight" "dark_mode"
        ];
      };
      system.monitor.enabled = true;
      audio.enable_sounds = true;
      weather.enabled = true;
      # La località non era versionata nella config DMS: sceglierla dalla GUI.
      # Nessuna geolocalizzazione IP viene attivata implicitamente.
      location.auto_locate = false;
      nightlight.enabled = false;
      battery.warning_threshold = 10;
      notification = {
        enable_daemon = true;
        position = "top_right";
        layer = "top";
        follow_focused_output = false;
        history_retention_hours = 168;
      };
      osd.kinds = {
        volume = true;
        brightness = true;
        lock_keys = true;
        media = false;
      };

      lockscreen = {
        enabled = true;
        lock_before_suspend = true;
        fingerprint = false;
        allow_empty_password = false;
        blurred_desktop = false;
        transition = [ "fade" ];
      };
    };
  };
}
