# Script referenziati da config.kdl

Linkati in `~/.config/niri/scripts/` da `home/desktop.nix`. Git preserva
l'exec bit e home-manager linka i file con i permessi che hanno nel repo:
se ne aggiungi uno, `chmod +x` PRIMA di committare.

| script               | bind      | dipendenze (home o sistema)             |
|----------------------|-----------|-----------------------------------------|
| dontkillsteam.sh     | Mod+Q     | niri, jq, xdotool (solo per Steam/X11)  |
| gamemode.sh          | Mod+Alt+G | niri, libnotify, coreutils, util-linux   |
| keyboardswitch.sh    | Mod+K     | niri, jq, libnotify                     |
| windowpin.sh         | Mod+Shift+F | niri, jq                              |

`gamemode.sh` è stato riscritto per NixOS: config.kdl è read-only nello
store, quindi invece di copiare file usa
`niri msg action load-config-file --path ~/.config/niri/config-gaming.kdl`.
`config-gaming.kdl` (in `dotfiles/niri/`) fa `include "config.kdl"` e
sovrascrive solo gap e animazioni: non può più andare fuori sync.

Il toggle richiede `XDG_RUNTIME_DIR` e `NIRI_SOCKET` della sessione niri.
Salva lo stato in `$XDG_RUNTIME_DIR/niri-gamemode/<hash-socket>.state`:
ogni istanza ha il proprio stato e la vecchia cache
`~/.cache/niri-gamemode.state` è ignorata (non cancellata). Un lock `flock`
serializza due pressioni ravvicinate; un errore IPC non modifica lo stato,
mentre un errore di notifica non annulla un cambio riuscito. `coreutils`
e `util-linux` sono già disponibili a sistema.

La prima pressione presuppone l'avvio con la config normale. Caricare
manualmente una config fuori dallo script non aggiorna il suo stato.
`nix flake check` esegue `tests/gamemode.nix` con comandi niri/notifiche
simulati: verifica ON/OFF, sessioni separate, errori e concorrenza, senza
interagire con il compositor reale.

`keybinds_hint.sh` (rofi) è rimasto su Arch: niri ha l'overlay nativo
su Mod+Shift+Slash.
