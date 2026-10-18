#!/usr/bin/env bash
# Mod+Shift+/: le scorciatoie di mango in rofi, lette dalle righe "#:" di
# binds.conf (quella che mango sta usando). Solo da consultare: si scrive
# per filtrare, Esc chiude. Con --list le stampa soltanto (lo usa il test).
#
#   #: descrizione         vale per il bind subito sotto
#   #: TASTI | descrizione  vale per il gruppo sotto, mostrato come TASTI
# Due bind con la stessa descrizione diventano una riga: "Mod+Q / Alt+F4".
set -euo pipefail

binds=${CHEATSHEET_BINDS:-${XDG_CONFIG_HOME:-$HOME/.config}/mango/binds.conf}

list() {
    # C.UTF-8: gawk conta i caratteri (le frecce), non i byte, e le
    # colonne restano allineate.
    LC_ALL=C.UTF-8 gawk '
        function key(k) {
            if (k == "code:61") return "/"
            if (k ~ /^[a-z]$/) return toupper(k)
            if (k in names) return names[k]
            return k
        }
        function combo(mods, k,    out, n, parts, i) {
            n = split(mods, parts, "+")
            for (i = 1; i <= n; i++)
                if (parts[i] in modnames) out = out modnames[parts[i]] "+"
            return out key(k)
        }
        function add(keys, desc) {
            if (desc in row) {
                keysof[row[desc]] = keysof[row[desc]] " / " keys
            } else {
                row[desc] = ++count
                keysof[count] = keys
                descof[count] = desc
            }
        }
        BEGIN {
            modnames["SUPER"] = "Mod"; modnames["SHIFT"] = "Shift"
            modnames["CTRL"] = "Ctrl"; modnames["ALT"] = "Alt"
            names["Left"] = "←"; names["Right"] = "→"
            names["Up"] = "↑"; names["Down"] = "↓"
            names["space"] = "Spazio"; names["Return"] = "Invio"
            names["BackSpace"] = "Backspace"; names["Escape"] = "Esc"
            names["Delete"] = "Canc"; names["Print"] = "Stamp"
            names["period"] = "."; names["comma"] = ","
        }
        /^#:/ {
            text = $0
            sub(/^#:[ \t]*/, "", text)
            split_at = index(text, " | ")
            if (split_at) {
                add(substr(text, 1, split_at - 1), substr(text, split_at + 3))
                pending = ""
            } else {
                pending = text
            }
            next
        }
        /^[a-z]*bind[a-z]*=/ && pending != "" {
            line = $0
            sub(/^[^=]*=/, "", line)
            split(line, field, ",")
            add(combo(field[1], field[2]), pending)
            pending = ""
        }
        END {
            for (i = 1; i <= count; i++)
                if (length(keysof[i]) > width) width = length(keysof[i])
            for (i = 1; i <= count; i++)
                printf "%-*s   %s\n", width, keysof[i], descof[i]
        }
    ' "$binds"
}

if [[ ${1:-} == --list ]]; then
    list
    exit 0
fi

list | rofi -dmenu -i -no-custom -p tasti \
    -theme-str 'window { width: 780px; } listview { lines: 16; }' > /dev/null || true
