# Script referenziati da config.kdl

Linkati in `~/.config/niri/scripts/` da `home/desktop.nix`. Git preserva
l'exec bit e home-manager linka i file con i permessi che hanno nel repo:
se ne aggiungi uno, `chmod +x` PRIMA di committare.

| script               | bind      | dipendenze (tutte in home.packages)     |
|----------------------|-----------|-----------------------------------------|
| dontkillsteam.sh     | Mod+Q     | niri, jq, xdotool (solo per Steam/X11)  |
| gamemode.sh          | Mod+Alt+G | niri, libnotify                         |
| keyboardswitch.sh    | Mod+K     | niri, jq, libnotify                     |
| windowpin.sh         | Mod+Shift+F | niri, jq                              |

`gamemode.sh` è stato riscritto per NixOS: config.kdl è read-only nello
store, quindi invece di copiare file usa
`niri msg action load-config-file --path ~/.config/niri/config-gaming.kdl`.
`config-gaming.kdl` (in `dotfiles/niri/`) fa `include "config.kdl"` e
sovrascrive solo gap e animazioni: non può più andare fuori sync.

`keybinds_hint.sh` (rofi) è rimasto su Arch: niri ha l'overlay nativo
su Mod+Shift+Slash.
