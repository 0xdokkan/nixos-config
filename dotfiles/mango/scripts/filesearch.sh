#!/usr/bin/env bash
# Mod+Shift+E: cerca file e cartelle nella home con fd e li mostra in
# rofi; quello scelto si apre con xdg-open (l'app di default per il tipo).
# Il testo scelto non viene mai eseguito come comando. Nascosti e
# ignorati restano fuori (default di fd); nessun indice persistente.
set -euo pipefail

[[ -n ${HOME:-} && -d $HOME ]] || { printf '%s\n' 'Home non disponibile.' >&2; exit 1; }
choices=$(mktemp -t filesearch.XXXXXXXX)
trap 'rm -f -- "$choices"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# rofi -dmenu legge una voce per riga, non separate da NUL: i nomi con
# un a capo vengono scartati invece di diventare voci diverse. Spazi e
# metacaratteri restano dati.
fd --type f --type d --absolute-path --print0 . "$HOME" |
    while IFS= read -r -d '' candidate; do
        [[ $candidate != *$'\n'* && $candidate != *$'\r'* ]] || continue
        printf '%s\n' "$candidate"
    done > "$choices"

if selected=$(rofi -dmenu -i -no-custom -p file < "$choices"); then
    # Per sicurezza si apre solo una voce che è davvero nella lista.
    [[ -n $selected && $selected != *$'\n'* && $selected != *$'\r'* ]] || exit 0
    grep -Fxq -- "$selected" "$choices" || exit 0
    [[ -e $selected ]] || exit 0
    xdg-open "$selected"
else
    result=$?
    [[ $result == 1 ]] && exit 0 # Esc: annullato, va bene così.
    exit "$result"
fi
