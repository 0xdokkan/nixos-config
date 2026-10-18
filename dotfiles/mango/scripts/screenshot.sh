#!/usr/bin/env bash
# Screenshot con grim (+ slurp per la zona, swappy per annotare).
#   region  una zona scelta col mouse (Mod+P)
#   edit    una zona, aperta in swappy (Mod+Ctrl+P): salva lui, nella
#           stessa cartella (home/desktop.nix)
#   screen  lo schermo a fuoco (Mod+Alt+P, Stamp)
# Finisce in ~/Pictures/Screenshots col nome che usava niri, negli appunti
# e in una notifica. Esc durante la selezione annulla senza errori.
set -euo pipefail

dir=${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}
file=$dir/$(date '+screenshot from %Y-%m-%d %H-%M-%S.png')

case ${1:-} in
    region)
        geometry=$(slurp -d) || exit 0
        mkdir -p "$dir"
        grim -g "$geometry" "$file"
        ;;
    edit)
        geometry=$(slurp -d) || exit 0
        grim -g "$geometry" - | swappy -f -
        exit 0
        ;;
    screen)
        output=$(mmsg get all-monitors | jq -r 'first(.monitors[] | select(.active)) | .name')
        mkdir -p "$dir"
        grim -o "$output" "$file"
        ;;
    *)
        printf 'uso: %s region|edit|screen\n' "${0##*/}" >&2
        exit 2
        ;;
esac

wl-copy --type image/png < "$file"
notify-send -a screenshot -i "$file" 'Screenshot salvato' "${file/#"$HOME"/\~}" || true
