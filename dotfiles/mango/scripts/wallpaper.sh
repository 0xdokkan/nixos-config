#!/usr/bin/env bash
# Sfondo con awww (servizio utente, home/session.nix).
#   next / prev  immagine dopo / prima in ~/Pictures/Wallpapers
#                (Mod+Alt+→ / ←), in ordine di nome, ricomincia in fondo
#   pick         scegli da rofi con le anteprime (Mod+Shift+W)
#   restore      al login (servizio wallpaper): l'ultima scelta oppure,
#                la prima volta, lo sfondo di serie ($WALLPAPER_DEFAULT)
# L'ultima scelta sta in ~/.local/state/wallpaper/current.
set -euo pipefail

dir=${WALLPAPER_DIR:-$HOME/Pictures/Wallpapers}
state=${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper/current
# Un cerchio che si allarga dal centro dello schermo.
transition=(--transition-type grow --transition-duration 1 --transition-fps 60)

# Le immagini della cartella, una per elemento di "images". I nomi con un
# a capo non starebbero né in rofi né nel file di stato: si saltano.
load() {
    images=()
    local image
    while IFS= read -r -d '' image; do
        if [[ $image != *$'\n'* ]]; then
            images+=("$image")
        fi
    done < <(find -L "$dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' \
        -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' \) -print0 2> /dev/null |
        sort -z)
    if (( ${#images[@]} == 0 )); then
        notify-send -a wallpaper 'Nessuno sfondo' "Metti delle immagini in ${dir/#"$HOME"/\~}" || true
        exit 1
    fi
}

current() {
    if [[ -f $state ]]; then
        cat -- "$state"
    fi
}

show() {
    local image=$1
    shift
    awww img "$@" "$image"
    mkdir -p "${state%/*}"
    printf '%s\n' "$image" > "$state"
}

step() {
    load
    local now index=-1 i count=${#images[@]}
    now=$(current)
    for i in "${!images[@]}"; do
        if [[ ${images[i]} == "$now" ]]; then
            index=$i
            break
        fi
    done
    if (( index < 0 )); then
        # Lo sfondo attuale non è nella cartella: si parte da un estremo.
        if (( $1 > 0 )); then index=-1; else index=$count; fi
    fi
    show "${images[(index + $1 + count) % count]}" "${transition[@]}"
}

pick() {
    load
    local image choice
    choice=$(for image in "${images[@]}"; do
            printf '%s\0icon\x1f%s\n' "${image##*/}" "$image"
        done | rofi -dmenu -i -no-custom -show-icons -format i -p sfondo \
            -theme-str 'element-icon { size: 64px; } listview { lines: 5; }') || exit 0
    [[ $choice =~ ^[0-9]+$ ]] && (( choice < ${#images[@]} )) || exit 0
    show "${images[choice]}" "${transition[@]}"
}

restore() {
    # awww-daemon parte insieme a questo servizio: lo si aspetta (max 10 s).
    local _ image
    for _ in {1..100}; do
        awww query > /dev/null 2>&1 && break
        sleep 0.1
    done
    image=$(current)
    if [[ -z $image || ! -f $image ]]; then
        image=${WALLPAPER_DEFAULT:?WALLPAPER_DEFAULT non impostato}
    fi
    awww img --transition-type none "$image"
}

case ${1:-} in
    next) step 1 ;;
    prev) step -1 ;;
    pick) pick ;;
    restore) restore ;;
    *)
        printf 'uso: %s next|prev|pick|restore\n' "${0##*/}" >&2
        exit 2
        ;;
esac
