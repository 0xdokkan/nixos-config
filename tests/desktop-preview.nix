# Anteprima del desktop in una VM: mango vero, con le config generate da
# home-manager per il portatile, più waybar, rofi, swaync e hyprlock.
# Non è in `checks` (ci mette qualche minuto e nixup lancia i check a ogni
# aggiornamento): si lancia a mano e lascia gli screenshot in result/.
#
#   nix build .#desktop-preview && ls result/*.png
#
# Verifica anche che i programmi partano senza errori di config: waybar e
# swaync non hanno un controllo offline, qui girano davvero.
{ pkgs, home, wallpaper }:

let
  file = name: home.xdg.configFile.${name}.source;
  # La stessa cartella ~/.config che avrebbe l'utente, solo i pezzi grafici.
  configHome = pkgs.linkFarm "preview-config" {
    "mango" = file "mango";
    "waybar/config" = file "waybar/config";
    "waybar/style.css" = file "waybar/style.css";
    "swaync/config.json" = file "swaync/config.json";
    "swaync/style.css" = file "swaync/style.css";
    "hypr/hyprlock.conf" = file "hypr/hyprlock.conf";
    "rofi/config.rasi" = home.home.file."${home.home.homeDirectory}/.config/rofi/config.rasi".source;
    "gtk-3.0/settings.ini" = file "gtk-3.0/settings.ini";
  };

  # Al posto di mango-session-start (che avvierebbe i servizi utente veri):
  # lancia direttamente i pezzi da guardare e salva l'ambiente di mango
  # per i comandi del test.
  sessionStart = pkgs.writeShellScriptBin "mango-session-start" ''
    export -p > /tmp/mango-env
    awww-daemon > /tmp/awww.log 2>&1 &
    waybar > /tmp/waybar.log 2>&1 &
    swaync > /tmp/swaync.log 2>&1 &
    sleep 2
    awww img --transition-type none ${wallpaper}
  '';
in
pkgs.testers.runNixOSTest {
  name = "desktop-preview";

  nodes.machine = { pkgs, ... }: {
    virtualisation = {
      memorySize = 3072;
      cores = 4;
    };
    boot.kernelParams = [ "video=1920x1080" ];
    hardware.graphics.enable = true;
    programs.mango.enable = true;
    security.pam.services.hyprlock = { };
    services.pipewire = { enable = true; pulse.enable = true; };
    networking.networkmanager.enable = true;

    fonts.packages = [ pkgs.monaspace pkgs.nerd-fonts.symbols-only pkgs.noto-fonts ];
    fonts.fontconfig.defaultFonts = {
      sansSerif = [ "Monaspace Argon" ];
      monospace = [ "Monaspace Argon" "Symbols Nerd Font Mono" ];
    };

    users.users.dokkan = {
      isNormalUser = true;
      password = "anteprima";
    };
    services.getty.autologinUser = "dokkan";
    environment.systemPackages = [
      sessionStart
      pkgs.waybar pkgs.rofi pkgs.swaynotificationcenter pkgs.hyprlock
      pkgs.awww pkgs.kitty pkgs.libnotify
      home.gtk.iconTheme.package pkgs.hicolor-icon-theme
    ];
    environment.variables = {
      XDG_CONFIG_HOME = "${configHome}";
      # Nella VM non c'è una GPU vera: Mesa disegna in software.
      WLR_RENDERER_ALLOW_SOFTWARE = "1";
    };
    # Login automatico sulla tty1 → mango con la config vera.
    programs.bash.loginShellInit = ''
      if [ "$(tty)" = /dev/tty1 ]; then
        exec mango -c ${configHome}/mango/config.conf > /tmp/mango.log 2>&1
      fi
    '';
  };

  testScript = ''
    import json
    import shlex

    def user(command):
        return machine.succeed("su dokkan -c " + shlex.quote(". /tmp/mango-env; " + command))

    def clients():
        return json.loads(user("mmsg get all-clients"))

    def logs():
        print(machine.execute("tail -n 40 /tmp/mango.log /tmp/waybar.log /tmp/swaync.log /tmp/awww.log")[1])

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_file("/tmp/mango-env", timeout=120)
    # Sono wrappati da nixpkgs: il nome del processo è .waybar-wrapped.
    try:
        machine.wait_until_succeeds("pgrep -x .waybar-wrapped && pgrep -x .swaync-wrapped", timeout=60)
    except Exception:
        logs()
        machine.screenshot("0-errore")
        raise
    machine.sleep(5)
    logs()

    # Niente errori di config o di CSS nei programmi avviati. Nel log di
    # mango finisce anche Xwayland (senza GPU, rumoroso): di mango contano
    # solo le righe [ERROR] di wlroots.
    machine.succeed("! grep -F '[ERROR]' /tmp/mango.log")
    machine.succeed("! grep -iE 'error|warning' /tmp/waybar.log | grep -vE 'no bluetooth|No batteries|portal'")
    machine.succeed("! grep -iE 'error|critical|warning' /tmp/swaync.log | grep -vE 'portal|backlight'")
    machine.screenshot("1-desktop")

    # Due finestre: la prima prende tutta la larghezza, poi si affiancano.
    user("kitty >/dev/null 2>&1 &")
    machine.sleep(4)
    machine.screenshot("2-una-finestra")
    user("kitty >/dev/null 2>&1 &")
    machine.sleep(4)
    machine.screenshot("3-due-finestre")
    print(json.dumps(clients(), indent=1))

    user("rofi -show drun >/dev/null 2>&1 &")
    machine.sleep(3)
    machine.screenshot("4-rofi")
    machine.send_key("esc")
    machine.sleep(1)

    user("notify-send -a prova 'Notifica di prova' 'Tokyo Night Storm' || true")
    user("swaync-client -op -sw")
    machine.sleep(3)
    machine.screenshot("5-centro-di-controllo")
    user("swaync-client -cp -sw")
    machine.sleep(1)

    # hyprlock: si blocca, poi la password vera (PAM) sblocca.
    user("hyprlock > /tmp/hyprlock.log 2>&1 &")
    machine.wait_until_succeeds("grep -q 'onLockLocked called' /tmp/hyprlock.log", timeout=30)
    machine.sleep(3)
    machine.screenshot("6-lock")
    machine.send_chars("anteprima\n")
    machine.wait_until_fails("pgrep -x hyprlock", timeout=30)
    machine.succeed("! grep -iE 'config error' /tmp/hyprlock.log")
  '';
}
