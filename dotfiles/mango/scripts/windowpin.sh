#!/usr/bin/env bash
# Mod+Shift+F: "pin" come in Hyprland. La finestra diventa flottante, va
# al centro e resta visibile su tutti i tag (global in mango); ripremendo
# torna nel layout, solo nel tag corrente.
set -euo pipefail

dispatch() {
    local reply
    reply=$(mmsg dispatch "$1")
    [[ $reply == *'"success":true'* ]] || { printf 'windowpin: %s: %s\n' "$1" "$reply" >&2; exit 1; }
}

focused=$(mmsg get focusing-client)
[[ -n $(jq -r '.id // empty' <<< "$focused") ]] || exit 0
floating=$(jq -r '.is_floating' <<< "$focused")
global=$(jq -r '.is_global' <<< "$focused")

if [[ $floating == true && $global == true ]]; then
    dispatch toggleglobal
    dispatch togglefloating
else
    [[ $floating == true ]] || dispatch togglefloating
    dispatch centerwin
    [[ $global == true ]] || dispatch toggleglobal
fi
