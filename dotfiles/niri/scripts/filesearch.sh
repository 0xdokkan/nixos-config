#!/usr/bin/env bash
# Cerca nella home tramite fd e il picker nativo Noctalia, senza eseguire
# mai il testo selezionato come comando. File/cartelle nascosti e ignorati
# restano esclusi secondo i default di fd; nessun indice persistente.
set -euo pipefail

[[ -n ${HOME:-} && -d $HOME ]] || { printf '%s\n' 'Home non disponibile.' >&2; exit 1; }
choices=$(mktemp -t noctalia-files.XXXXXXXX)
trap 'rm -f -- "$choices"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# dmenu è delimitato da newline, non NUL. Scarta questi nomi anomali invece
# di dividerli in candidati differenti; spazi e metacaratteri restano dati.
fd --type f --type d --absolute-path --print0 . "$HOME" |
    while IFS= read -r -d '' candidate; do
        [[ $candidate != *$'\n'* && $candidate != *$'\r'* ]] || continue
        printf '%s\n' "$candidate"
    done > "$choices"

if selected=$(noctalia dmenu --prompt 'Cerca file e cartelle nella home' < "$choices"); then
    # dmenu accetta anche testo libero: apri soltanto un candidato esatto.
    [[ -n $selected && $selected != *$'\n'* && $selected != *$'\r'* ]] || exit 0
    grep -Fxq -- "$selected" "$choices" || exit 0
    [[ -e $selected ]] || exit 0
    xdg-open "$selected"
else
    result=$?
    [[ $result == 1 ]] && exit 0 # Esc/annullamento è un esito normale.
    exit "$result"
fi
