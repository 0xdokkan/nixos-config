# Gli script di dotfiles/mango/scripts come comandi nel PATH, ognuno con
# le sue dipendenze (runtimeInputs) e controllato da ShellCheck a
# build-time. Li chiamano i bind di mango, waybar e swaync per nome
# (wallpaper.sh, powermenu.sh...). È una funzione a sé perché la usa
# anche `checks` nel flake.
{ pkgs
, rofi ? pkgs.rofi
, wallpaper ? ../dotfiles/sddm/bg.png
}:

let
  script = name: runtimeInputs: extra: pkgs.writeShellApplication ({
    inherit name runtimeInputs;
    # writeShellApplication mette già il suo shebang e set -euo pipefail.
    text = pkgs.lib.removePrefix "#!/usr/bin/env bash\n"
      (builtins.readFile (../dotfiles/mango/scripts + "/${name}"));
  } // extra);
  only = name: runtimeInputs: script name runtimeInputs { };
in
with pkgs;
{
  "dontkillsteam.sh" = only "dontkillsteam.sh" [ mango jq xdotool ];
  "windowpin.sh" = only "windowpin.sh" [ mango jq ];
  "keyboardswitch.sh" = only "keyboardswitch.sh" [ mango jq libnotify ];
  "gamemode.sh" = only "gamemode.sh" [ mango coreutils util-linux libnotify ];
  "filesearch.sh" = only "filesearch.sh" [ fd rofi coreutils gnugrep xdg-utils ];
  "screenshot.sh" = only "screenshot.sh" [ grim slurp swappy wl-clipboard mango jq coreutils libnotify ];
  "wallpaper.sh" = script "wallpaper.sh" [ awww rofi findutils coreutils libnotify ] {
    runtimeEnv.WALLPAPER_DEFAULT = "${wallpaper}";
  };
  "powermenu.sh" = only "powermenu.sh" [ rofi mango systemd ];
  "clipboard.sh" = only "clipboard.sh" [ cliphist rofi wl-clipboard ];
  "cheatsheet.sh" = only "cheatsheet.sh" [ gawk rofi ];
  "nightlight.sh" = only "nightlight.sh" [ systemd gawk ];
}
