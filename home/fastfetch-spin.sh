# fastfetch con il fiocco NixOS 3D che gira (vedi home/fastfetch-spin.nix).
# Senza argomenti, in un terminale: il logo fa due giri accanto alle info e
# si ferma di fronte; un tasto qualsiasi salta al fotogramma finale.
# Con argomenti, in una pipe o con FASTFETCH_SPIN=off: fastfetch normale,
# con lo stesso fiocco come logo statico (dotfiles/fastfetch/config.jsonc).
# FASTFETCH_SPIN=loop: gira finché non premi un tasto.
#
# Variabili impostate dal pacchetto: SPIN_REAL, SPIN_FRAMES, SPIN_SCHEDULE,
# SPIN_WIDTH, SPIN_HEIGHT, SPIN_COUNT, SPIN_PAD_TOP/LEFT/RIGHT.

mode=${FASTFETCH_SPIN:-on}
if (( $# > 0 )) || [[ $mode == off || ! -t 0 || ! -t 1 || ${TERM:-dumb} == dumb ]]; then
    exec "$SPIN_REAL" "$@"
fi

# Le info sono quelle della config utente, solo senza logo. Le sequenze che
# fastfetch usa per wrap e cursore le gestisce questo script.
info_raw=$("$SPIN_REAL" --logo none --pipe false) || exec "$SPIN_REAL"
for code in $'\e[?7l' $'\e[?7h' $'\e[?25l' $'\e[?25h'; do
    info_raw=${info_raw//"$code"/}
done
# L'ultimo a capo può precedere un codice appena tolto: niente righe vuote.
while [[ $info_raw == *$'\n' ]]; do
    info_raw=${info_raw%$'\n'}
done
mapfile -t info <<< "$info_raw"
mapfile -t frames < "$SPIN_FRAMES"
mapfile -t schedule < "$SPIN_SCHEDULE"

rows=$(( SPIN_PAD_TOP + SPIN_HEIGHT ))
(( ${#info[@]} > rows )) && rows=${#info[@]}
printf -v blank '%*s' "$SPIN_WIDTH" ''
printf -v left '%*s' "$SPIN_PAD_LEFT" ''
printf -v gap '%*s' "$SPIN_PAD_RIGHT" ''

# Tutte le righe: logo (fotogramma $1) e info, come le stampa fastfetch.
print_all() {
    local base=$(( $1 * SPIN_HEIGHT )) r i logo out=''
    for (( r = 0; r < rows; r++ )); do
        i=$(( r - SPIN_PAD_TOP ))
        if (( i >= 0 && i < SPIN_HEIGHT )); then
            logo=${frames[base + i]}
        else
            logo=$blank
        fi
        out+="$left$logo$gap${info[r]:-}"$'\n'
    done
    printf '%s' "$out"
}

# Dal fondo dell'output riscrive solo il logo e torna in fondo. I fotogrammi
# sono larghi esattamente SPIN_WIDTH: coprono il precedente senza cancellare.
redraw() {
    local base=$(( $1 * SPIN_HEIGHT )) i below out
    out=$'\e['"$(( rows - SPIN_PAD_TOP ))A"
    for (( i = 0; i < SPIN_HEIGHT; i++ )); do
        out+=$'\e['"$(( SPIN_PAD_LEFT + 1 ))G${frames[base + i]}"$'\n'
    done
    below=$(( rows - SPIN_PAD_TOP - SPIN_HEIGHT ))
    (( below > 0 )) && out+=$'\e['"${below}B"
    printf '%s' "$out"
}

# Senza autowrap (come fastfetch) le righe lunghe vengono tagliate invece
# di andare a capo, così il numero di righe sullo schermo resta `rows`.
size=$(stty size 2>/dev/null) || size='0 0'
if (( ${size%% *} <= rows )); then
    # Terminale troppo basso per risalire fino al logo: niente animazione.
    printf '\e[?7l'
    print_all 0
    printf '\e[?7h'
    exit 0
fi

saved=$(stty -g)
trap 'stty "$saved"; printf "\e[?25h\e[?7h"' EXIT
interrupted=0
trap 'interrupted=1' INT TERM
stty -echo -icanon
printf '\e[?7l\e[?25l'
print_all "${schedule[0]}"

# Ogni attesa di un tasto è anche il ritmo dei fotogrammi (30 al secondo).
frame=0
tick=1
while (( ! interrupted )); do
    if read -rn1 -t 0.033 _; then
        break
    fi
    if [[ $mode == loop ]]; then
        frame=$(( (frame + 2) % SPIN_COUNT ))
    elif (( tick < ${#schedule[@]} )); then
        frame=${schedule[tick]}
        tick=$(( tick + 1 ))
    else
        break
    fi
    redraw "$frame"
done
# Scarta il resto di un tasto multi-byte (frecce, F1...) prima della shell.
while read -rn1 -t 0.01 _; do :; done
redraw 0
(( interrupted )) && exit 130
exit 0
