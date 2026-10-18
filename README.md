# nixos-config — armoredcoreVIP (portatile) & armoredcoreVIF (fisso)

Il sistema come sorgente. Rice versionato, rollback dal bootloader,
no guilt, just restart.

## Struttura

    flake.nix                  ← input (nixpkgs, home-manager, helium, llm-agents, nix-index-database), host, check, devshell, template
    hosts/
      common.nix               ← tutto ciò che è uguale sui due pc: mango+SDDM, pipewire,
                                  utente, steam, docker, libvirt, mullvad, zerotier, wireshark, font...
      armoredcoreVIP/          ← il portatile, ThinkPad T470s: Intel HD 620, thermald, batteria
      armoredcoreVIF/          ← il fisso: RTX 2070 (nvidia-open), profilo VRAM per mango
        configuration.nix      ← le differenze dell'host + `imports = [ ../common.nix ]`
        hardware-configuration.nix  ← PLACEHOLDER: lo genera l'installer, uno per macchina
    home/                      ← la home di dokkan, identica su entrambi
      default.nix              ← entry home-manager
      desktop.nix              ← app, kitty, GTK/Qt, cartelle XDG e app di default
      palette.nix              ← Tokyo Night Storm: l'unica fonte dei colori del desktop
      mango.nix                ← sessione mango, ~/.config/mango, script nel PATH, sfondo al login
      mango-configs.nix        ← theme.conf e host.conf generati, `mango -p` a build-time
      mango-scripts.nix        ← gli script dei bind come comandi (ShellCheck + dipendenze)
      waybar.nix               ← la barra
      rofi.nix                 ← launcher e menu (wifi, bluetooth, Wi-Fi QR)
      notifications.nix        ← swaync (notifiche + centro di controllo) e swayosd (OSD)
      lock.nix + idle.py       ← hyprlock e i profili idle batteria/alimentazione
      session.nix              ← polkit, appunti, sfondo, dischi, luce notturna, batteria
      shell.nix                ← zsh + p10k + alias + CLI belt
      fastfetch-spin.{nix,py,sh} ← il fiocco NixOS 3D che gira in `fastfetch`
      dev.nix                  ← git/gh, direnv, neovim (LazyVim), agenti AI, .gdbinit
      maintenance.nix          ← installa nixup per il repository e l'host corretti
      nixup.nix + nixup.sh     ← update, check, build, confronto pacchetti e conferma
    dotfiles/
      mango/config.conf        ← il tesoro ✓ (uno solo per i due pc: layout e colori
                                  arrivano da host.conf e theme.conf, generati)
      mango/binds.conf         ← le scorciatoie (le righe `#:` finiscono nel cheatsheet)
      mango/rules.conf         ← regole per finestre e layer (opacità, flottanti, privacy)
      mango/gaming.conf        ← include config.conf + gap 0, niente animazioni/blur/ombre
      mango/scripts/           ← script dei bind (screenshot, sfondo, menu, game mode...)
      kitty/theme.conf         ← Tokyo Night Storm
      zsh/p10k.zsh, extra.zsh  ← prompt + alias personali
      nvim/                    ← LazyVim (symlink live: lazy-lock.json resta scrivibile)
      cava/config              ← il gradiente
      fastfetch/               ← config.jsonc (moduli; il logo è il fiocco 3D) + images/
      gtk/Tokyo-Night/         ← il tema GTK di HyDE (Tokyonight-Storm): nautilus & co.
                                  come sul fisso. Vendorizzato: nixpkgs l'ha rimosso
      sddm/bg.png              ← lo sfondo di SDDM, e del desktop finché non ne scegli uno
    patches/
      mango-overview-carousel.patch ← l'overview a carosello (applicata da flake.nix)
    templates/{c,rust,zig,python}/
      shell.nix                ← LA devshell (usata anche da `nix develop ~/nixos-config#c`)
      flake.nix + .envrc       ← il boilerplate che il template copia nel progetto
    tests/                     ← i check del flake, senza sessione grafica: bind e config di
                                  mango, script con comandi finti, idle/lock, LazyVim/Mason,
                                  nixup con Nix/sudo simulati, fiocco di fastfetch
      desktop-preview.nix      ← mango vero in una VM, con screenshot (non è un check)

## Come funziona Nix (per chi arriva da pacman)

**Non esiste `pacman -S`.** Un pacchetto si "installa" scrivendo il suo
nome in un file `.nix` e rilanciando il rebuild. Tre posti possibili:

| dove                                  | per cosa                              | esempio          |
|---------------------------------------|---------------------------------------|------------------|
| `environment.systemPackages` (hosts/) | roba di sistema, serve anche a root   | vim, git         |
| `home.packages` (home/)               | le TUE app e i TUOI tool              | firefox, eza     |
| `shell.nix` di un progetto            | toolchain, librerie: solo lì dentro   | gcc, raylib      |

Molti programmi hanno un **modulo** con opzioni proprie (`programs.kitty`,
`services.pipewire`, `programs.steam`): quello installa il pacchetto E
genera la sua config. Preferiscilo al pacchetto nudo quando esiste.

**Dove finiscono i pacchetti.** Tutto vive in `/nix/store/<hash>-nome/`,
un pacchetto per cartella, immutabile. Non c'è `/usr/bin/firefox`: c'è
`/nix/store/abc…-firefox-140/bin/firefox`, e il rebuild costruisce un
albero di symlink (il "profilo") che finisce nel `PATH`. Per questo:

- un binario scaricato da internet (CTF!) non trova `/lib64/ld-linux…` →
  `programs.nix-ld` glielo fa trovare;
- uno script con `#!/bin/bash` NON parte, `#!/usr/bin/env bash` sì;
- due versioni dello stesso programma convivono senza litigare.

**Il rebuild è atomico e ha memoria.** `nixos-rebuild switch` costruisce
il sistema nuovo accanto a quello vecchio, poi sposta un symlink. Ogni
switch è una *generazione*: la vedi nel menu di systemd-boot, e se hai
rotto qualcosa scegli quella prima e sei a posto. Da terminale:

    sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIP   # applica
    sudo nixos-rebuild switch --rollback                            # torna indietro
    sudo nix-env --list-generations -p /nix/var/nix/profiles/system # storico

**Aggiornare.** Il `flake.lock` inchioda le revisioni di nixpkgs,
home-manager, helium, llm-agents e nix-index-database. Il rebuild usa
quelle revisioni; non cerca automaticamente le ultime versioni.
Il comando assistito, disponibile dopo il rebuild che lo installa, è:

    nixup          # aggiorna tutti gli input, controlla e propone il rebuild
    nixup ai       # aggiorna soltanto llm-agents
    nixup apply    # controlla e propone il rebuild con il lock già presente

Si lancia da qualsiasi cartella, come utente normale: il pacchetto sa
che il repo è `~/nixos-config` e quale host deve aggiornare. Rifiuta
l'esecuzione su Arch o su un host diverso; non passargli `sudo`.

Prima di `nixup`/`nixup ai`, controlla `git status` e committa le modifiche
che vuoi conservare (anche quelle di Neovim). Il comando richiede un
checkout pulito. Non esegue pull, commit o push: sincronizza il repo con
`git pull --ff-only` quando serve. I file nuovi della config vanno tracciati
con `git add`; per applicare modifiche locali già tracciate usa `nixup apply`.

Il flusso è: aggiorna il lock → `nix flake check` → build del sistema
candidato → confronto con il sistema attivo tramite `nvd` → conferma
`[s/N]`. Invio senza risposta annulla. `sudo` viene richiesto soltanto
dopo il consenso, per attivare esattamente il sistema mostrato nel diff.
Check e build usano lo stesso snapshot immutabile del repository e non
possono aggiornare gli input in memoria. L'attivazione usa `--store-path`
insieme a `--no-reexec`: non ricostruisce il sistema né tenta il bootstrap
di `nixos-rebuild` cercando una configurazione tradizionale in `NIX_PATH`.
Il diff mostra i pacchetti,
non ogni cambiamento di configurazione. I dotfiles Neovim restano
symlink live; la config del desktop è tutta nel repo, come spiegato sotto.

Se annulli o un controllo fallisce, il lock aggiornato **rimane nel repo**:
non vengono ripristinati/cancellati file automaticamente. Puoi esaminarlo,
correggere eventuali problemi e riprovare con `nixup apply`; questo comando
non cerca nuove versioni. Se modifichi la lista degli input in `flake.nix`,
allinea prima il lock con `nix flake lock`, poi usa `nixup apply`.

Nessun reboot o pulizia dello store viene fatto da `nixup`. Dopo uno switch,
riapri le applicazioni; un kernel nuovo richiede il riavvio. Quando hai
verificato che tutto funziona, committa e pusha `flake.lock`: sull'altro PC
bastano pull e `nixup apply`, senza un altro aggiornamento degli input.

La via manuale resta disponibile, anche prima di installare `nixup`:

    cd ~/nixos-config
    nix flake update && nix flake check && sudo nixos-rebuild switch --flake .#armoredcoreVIP

Se un vecchio `nixup` fallisce **dopo la conferma** con
`file 'nixos-config' was not found in the Nix search path` mentre cerca
`config.system.build.nixos-rebuild`, non ha ancora attivato il candidato.
Dopo aver portato la correzione nel checkout del PC interessato, installala
una volta con il comando manuale, senza aggiornare gli input:

    sudo nixos-rebuild switch --no-reexec --flake ~/nixos-config#armoredcoreVIP

Usa `#armoredcoreVIF` sul fisso. Poi torna a `nixup apply`: il comando
installato viene dallo store, quindi modificare solo `home/nixup.sh` non
aggiorna la versione già nel `PATH`. Non serve impostare `NIX_PATH`.

Per tornare alla generazione precedente: `sudo nixos-rebuild switch --rollback`,
oppure sceglila al boot. Questo non ripristina il lock Git né i dati delle
applicazioni. `system.stateVersion`/`home.stateVersion` non vanno cambiati
per aggiornare i pacchetti. Plugin Neovim, tool Mason e progetti con un
proprio lock restano aggiornamenti separati.

**Aggiornare solo le app AI.** Claude Code, Codex CLI, Claude Desktop e
ChatGPT/Codex desktop arrivano da
[numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix), con
packaging aggiornato giornalmente. Seguono le release pubblicate, non
build dal ramo di sviluppo; può esserci un ritardo rispetto a upstream.
OpenCode resta nel nixpkgs del sistema, come prima.

Con il comando assistito basta `nixup ai`; manualmente:

    cd ~/nixos-config
    nix flake update llm-agents
    sudo nixos-rebuild switch --flake .#armoredcoreVIP

Sul fisso usa `#armoredcoreVIF`. Il rebuild da solo NON cerca nuove
versioni: usa quelle fissate nel lock. Questo input conserva il proprio
nixpkgs testato da Numtide (senza `follows`), per aggiornarsi senza muovere
il nixpkgs del sistema e mantenere compatibilità con i binari in cache.

La cache firmata `https://cache.numtide.com` è abilitata in `flake.nix`
e `hosts/common.nix`: significa fidarsi dei binari pubblicati da Numtide.
Al primo rebuild accetta le impostazioni della cache quando Nix le chiede;
in un terminale non interattivo aggiungi `--option accept-flake-config true`
al comando di rebuild. Senza cache Nix può compilare Codex da sorgente,
operazione costosa soprattutto sul portatile.

Le CLI si avviano con `claude` e `codex`; le app con `claude-desktop` e
`chatgpt`, oppure dal launcher. Il packaging Nix è comunitario, i payload
desktop sono quelli ufficiali Linux: [Claude è ancora in beta](https://support.claude.com/en/articles/10065433-install-claude-desktop)
e [ChatGPT/Codex in preview](https://learn.chatgpt.com/docs/linux/linux-app).
NixOS non è una distribuzione ufficialmente supportata dalle due app.
ChatGPT è configurato per XWayland: il supporto Wayland nativo è ancora
sperimentale. Le app hanno runtime scaricati e dati aggiornati a runtime:
il lock fissa i pacchetti, non ogni componente scaricato dall'app.

**Cercare un pacchetto.** https://search.nixos.org (pacchetti E opzioni),
oppure `nix search nixpkgs firefox`. Per sapere in che pacchetto sta un
comando che manca: scrivilo e basta, `nix-index` te lo dice (come
`pacman -F`). Il database è già fornito da
[nix-index-database](https://github.com/nix-community/nix-index-database):
**non devi eseguire `nix-index` al primo boot**. L'integrazione zsh e
`nix-locate` usano il database precompilato, fissato dal nuovo input nel lock.

Si aggiorna con `nixup`, oppure soltanto l'indice con:

    cd ~/nixos-config
    nix flake update nix-index-database
    nixup apply

L'indice upstream segue nixos-unstable e non necessariamente l'esatta
revisione del tuo nixpkgs: i suggerimenti sono utili, ma un pacchetto
indicato potrebbe non essere disponibile nella revisione locale.
La configurazione usa il database completo, anche per cercare file non
eseguibili con `nix-locate`; non installa automaticamente i pacchetti suggeriti.

**Provare senza installare.** Il vero superpotere:

    nix shell nixpkgs#cowsay      # shell con cowsay nel PATH, poi sparisce
    nix run nixpkgs#cowsay -- ciao
    nix develop ~/nixos-config#rust   # una devshell "scratch" di questo repo

**Pulizia.** Le generazioni vecchie e i pacchetti orfani restano nello
store finché non li cancelli (è quello che rende possibile il rollback).
È AUTOMATICA (`nix.gc` in `common.nix`): ogni settimana via le generazioni
più vecchie di 14 giorni + gc; nel menu di boot al massimo 10 voci. A mano:

    sudo nix-collect-garbage --delete-older-than 7d    # generazioni + gc
    sudo nix-collect-garbage -d                        # TUTTE tranne l'attiva
    nix store gc                                       # solo orfani, niente generazioni
    sudo nix-env --list-generations -p /nix/var/nix/profiles/system   # cosa c'è

**Dotfiles.** home-manager NON copia i tuoi file in `~/.config`: ci mette
symlink che puntano nello store, quindi sono read-only. Si modificano
nel repo e si fa il rebuild. L'eccezione voluta è `~/.config/nvim`, un
symlink "live" DENTRO `~/nixos-config/dotfiles/nvim`: lazy.nvim scrive il
lockfile e `git status` mostra le modifiche da committare.

Il desktop non ha impostazioni da GUI che vivono fuori dal repo: barra,
menu, notifiche e lock si cambiano nei moduli in `home/`, mango in
`dotfiles/mango/`. Restano locali al PC solo i dati: cronologia degli
appunti, ultimo sfondo scelto (`~/.local/state/wallpaper/current`),
notifiche, reti wifi e dispositivi bluetooth.

**LazyVim, Mason e Nix.** `lazy.nvim` continua a scaricare e aggiornare i
plugin al primo avvio e successivamente; il symlink live e `lazy-lock.json`
restano invariati. Mason gestisce invece gli eseguibili esterni (LSP,
formatter, ecc.): l'override in `dotfiles/nvim/lua/plugins/nix.lua` evita
installazioni doppie quando il tool è già disponibile da Nix.

Su NixOS, o in un ambiente con binari Nix nel `PATH`, i comandi di Nix
hanno precedenza su quelli di Mason. Gli LSP già risolti nello store
usano `mason = false`; per i formatter e gli altri tool viene filtrata
la lista di auto-installazione soltanto dove c'è una sostituzione nota
e disponibile. Per esempio, `lua-language-server`, `nil` e `stylua` sono
già forniti dal wrapper Neovim di Home Manager. I tool mancanti restano
gestiti da Mason: non è una configurazione senza download.

I toolchain/LSP di progetto restano nelle devshell: entra con
`nix develop` oppure attendi `direnv`, **poi avvia `nvim`**. Una devshell
aperta altrove non cambia l'ambiente di un editor già avviato. Nessun
pacchetto Mason preesistente viene cancellato. Su Arch senza un ambiente
Nix l'override non si attiva e resta il comportamento normale di LazyVim.

L'extra Java non aggiunge il jar Lombok di Mason quando `jdtls` viene da
Nix: eventuale supporto Lombok va fornito dal pacchetto/devshell Java.
Adapter come codelldb restano gestiti come prima, perché hanno bisogno
anche delle proprie librerie, non soltanto di un eseguibile nel `PATH`.
Riferimenti: [LSP in LazyVim](https://www.lazyvim.org/plugins/lsp) e
[configurazione Mason](https://github.com/mason-org/mason.nvim#default-configuration).

**Desktop: mango e i suoi pezzi.** Il compositor è
[mango](https://mangowm.github.io) (wlroots, layout a
scorrimento come niri); al posto di una shell tutto-in-uno ci sono
programmi piccoli, ognuno nel suo modulo e con i colori di `home/palette.nix`:

| cosa | programma | modulo |
|------|-----------|--------|
| barra | waybar | `home/waybar.nix` |
| launcher e menu | rofi, networkmanager_dmenu, bzmenu | `home/rofi.nix` |
| notifiche e centro di controllo | swaync | `home/notifications.nix` |
| OSD di volume e luminosità | swayosd | `home/notifications.nix` |
| blocco e inattività | hyprlock, swayidle + `idle.py` | `home/lock.nix` |
| sfondo | awww + `wallpaper.sh` | `home/session.nix`, `home/mango.nix` |
| appunti | cliphist + wl-clip-persist | `home/session.nix` |
| luce notturna | wl-gammarelay-rs | `home/session.nix` |
| password admin, dischi, batteria | polkit-gnome, udiskie, batsignal | `home/session.nix` |

La sessione: SDDM avvia `mango-session` (un wrapper, `hosts/common.nix`),
che avvia mango. L'`exec_once` della config, `mango-session-start`, passa
l'ambiente di mango a systemd e dbus e avvia `mango-session.target`, che
tira su `graphical-session.target`: tutti i programmi della tabella sono
servizi utente legati a quel target. Quando mango esce, il wrapper ferma
il target e con lui i servizi. Per vedere chi non è partito:

    systemctl --user list-units --failed
    journalctl --user -b -u waybar -u swaync -u idle -u hyprlock

**La config di mango.** Sta in `dotfiles/mango/`: `config.conf` (opzioni),
`binds.conf` (tasti), `rules.conf` (regole per finestre e layer),
`gaming.conf`. `theme.conf` (colori e cursore) e `host.conf` (layout
tastiera) li genera `home/mango-configs.nix`. Al build ogni file passa da
`mango -p`: un errore o anche solo un avviso (opzione o comando
sconosciuto, bind doppio, file incluso mancante) e il sistema non si
builda. `~/.config/mango` è read-only nello store: si modifica nel repo,
rebuild, poi `Mod+Shift+C` ricarica la config a caldo senza uscire.

Nei bind mango divide gli argomenti sulle virgole, quindi i comandi non ne
contengono: ciò che è complicato sta negli script. Le righe `#: ...` sopra
un bind finiscono nel cheatsheet (`Mod+Shift+/`); `nix flake check`
controlla i tasti portati da niri, che ogni `#:` abbia il suo bind e che
`Mod+Shift+T`/`Mod+Shift+R` restino liberi.

**Layout: scroller su tutti i tag.** Come in niri le finestre si
affiancano in orizzontale e lo schermo scorre: le nuove nascono a metà
larghezza, `Mod+R` cicla 1/3, 1/2, 2/3 e tutto, `Mod+Shift+←/→` ridimensiona,
`Mod+.`/`Mod+,` impila nella colonna accanto (su/giù per muoversi nella
pila). I tag sono 10 (`Mod+1..0`), visibili tutti nella barra; ripremere
il tag corrente torna al precedente. `Mod+G` unisce la finestra a quella
a destra in un gruppo a schede.

`Mod+S` (o lo swipe a 4 dita) apre l'overview a carosello: le finestre
di tutti i tag in una fila, quella a fuoco grande al centro e le altre
sempre più piccole ai lati. `←`/`→` (anche con `Mod`) o lo swipe a 3 dita
la fanno girare; `Invio`, `Esc`, il click sinistro o di nuovo `Mod+S`
vanno alla finestra scelta, nel suo tag; il click destro la chiude.

Il carosello non c'è in mango: è una nostra patch (per mango 0.18),
`patches/mango-overview-carousel.patch` (opzione `ov_carousel=1`),
applicata da `mangoOverlay` in `flake.nix` a sistema, check e anteprima.
Le finestre nell'overview sono anteprime rimpicciolite, non finestre
ridimensionate: il contenuto non si riadatta.
mango quindi si compila in locale (un minuto circa) invece di arrivare
dalla cache. Se un aggiornamento di nixpkgs la rompe, la build di mango
fallisce e `nix flake check` lo dice prima del rebuild: si riadatta la
patch o, per tornare a mango liscio, si toglie l'overlay e `ov_carousel`
da `config.conf` (senza patch `mango -p` la rifiuta come opzione ignota).

Una finestra da sola in un tag prende tutta la larghezza e, finché resta
sola, `Mod+R` e il ridimensionamento non fanno nulla: è come funziona
mango con `scroller_ignore_proportion_single=0`. Appena arriva una seconda
finestra tornano le larghezze normali. Le alternative, in `config.conf`:
`scroller_ignore_proportion_single=1` (da sola nasce a metà, centrata, e
si ridimensiona), oppure una regola `scroller_proportion_single:0.6` in
`rules.conf` per far nascere più strette da sole certe app.

**Gli script dei bind.** Stanno in `dotfiles/mango/scripts/`;
`home/mango-scripts.nix` li installa come comandi con lo stesso nome,
ognuno con le sue dipendenze e passato da ShellCheck al build.

| script | tasti | cosa fa |
|--------|-------|---------|
| `dontkillsteam.sh` | `Mod+Q`, `Alt+F4` | chiude la finestra; Steam invece va nel tray |
| `windowpin.sh` | `Mod+Shift+F` | flottante, al centro e su tutti i tag (e ritorno) |
| `keyboardswitch.sh` | `Mod+K` | layout successivo e notifica |
| `gamemode.sh` | `Mod+Alt+G` | modalità gioco, vedi sotto |
| `filesearch.sh` | `Mod+Shift+E` | file e cartelle della home (fd) in rofi, apre con l'app giusta |
| `screenshot.sh` | `Mod+P`, `Mod+Ctrl+P`, `Mod+Alt+P`, `Stamp` | zona, zona + swappy, schermo |
| `wallpaper.sh` | `Mod+Alt+←/→`, `Mod+Shift+W` | sfondo prima/dopo, scelta con anteprime |
| `powermenu.sh` | `Mod+Backspace`, ⏻ | blocca, esci, sospendi, riavvia, spegni |
| `clipboard.sh` | `Mod+V`, riquadro appunti | cronologia; `Shift+Canc` cancella una voce |
| `cheatsheet.sh` | `Mod+Shift+/` | tutti i tasti, letti da `binds.conf` |
| `nightlight.sh` | pulsante luna | luce notturna sì/no dal centro di controllo |

Gli screenshot vanno in `~/Pictures/Screenshots` e negli appunti. Gli
sfondi si prendono da `~/Pictures/Wallpapers` (png, jpg, webp, gif); al
login il servizio `wallpaper` rimette l'ultimo scelto, o `bg.png` di SDDM
la prima volta. Per aggiungere uno script: il file nella cartella più una
riga in `home/mango-scripts.nix`. Il check `mango-scripts` fallisce se uno
script non è impacchettato o se un bind, la barra o swaync ne chiamano uno
che non esiste, e prova tutti gli script con mango, rofi & co. finti.

**Modalità gioco.** `Mod+Alt+G` fa caricare a mango `gaming.conf` (include
`config.conf` e toglie gap, animazioni, blur e ombre) con
`mmsg dispatch load_config_file`; ripremendo torna a `config.conf`. Niente
copie di file: i due file sono validati insieme e non vanno fuori sync.
Lo stato è in `$XDG_RUNTIME_DIR/mango-gamemode/`, separato per istanza di
mango: un nuovo login riparte dalla config normale. Un lock mette in fila
due pressioni ravvicinate; se mango rifiuta il cambio lo stato resta
quello di prima, e lo script non gli manda mai un file che non esiste
(mango ripartirebbe dai suoi default, senza nessuna scorciatoia).
`Mod+Shift+C` ricarica la config attiva, qualunque delle due sia.

**Barra e centro di controllo.** Nella barra: i tag a sinistra (quello
attivo in blu, quelli vuoti spenti); a destra volume (click: pavucontrol,
destro: muto, rotella: ±5%), CPU e RAM (click: htop), kernel, wifi (click:
menu wifi, centrale: Wi-Fi QR), bluetooth (click: menu), appunti, batteria
(solo sul portatile), data con il calendario nel tooltip, ⏻. `Ctrl+Alt+W`
la nasconde. Il centro di controllo (`Mod+N` o `Mod+Shift+P`) ha non
disturbare, i pulsanti wifi, bluetooth, Wi-Fi QR, luce notturna e
spegnimento, volume, luminosità (portatile), il player e le notifiche.
`Mod+Ctrl+N` attiva il non disturbare, `Mod+Shift+N` nasconde i popup.

Per credenziali e QR della rete Wi-Fi attiva: cerca **Wi-Fi QR** in rofi,
click centrale sul wifi nella barra, il pulsante nel centro di controllo
o "show password" nel menu wifi. Si apre una finestra Kitty con `nmcli`;
non vengono creati file con password né copiate credenziali negli appunti.
Chiudila quando hai finito.

**Blocco e risparmio energetico.** Il locker è hyprlock (`Mod+L`, o
`loginctl lock-session`), avviato come servizio utente a sé: riavviare gli
altri servizi non può chiuderlo. `home/idle.py` avvia un solo `swayidle`
con questi tempi, misurati dall'ultima attività:

| profilo | blocco schermo | spegnimento schermo | sospensione |
|---------|----------------|---------------------|-------------|
| batteria | 5 minuti | 6 minuti | 20 minuti |
| alimentazione | 15 minuti | 20 minuti | disattivata |

La configurazione è condivisa: il profilo alimentazione vale anche sul
fisso. Cambia i tempi in `home/idle.py` e fai il rebuild. UPower viene
letto ogni 5 secondi: al cambio di alimentazione i timer ripartono da zero
e gli schermi si riaccendono, senza sbloccare. Se UPower non risponde si
usano blocco a 5 minuti e schermo a 6, ma nessuna sospensione automatica.

Prima di spegnere lo schermo o sospendere, `idle.py` aspetta che hyprlock
confermi il blocco (al massimo 4 secondi, dentro il ritardo concesso da
logind); se il blocco non arriva, niente sospensione. Anche una
sospensione da menu o dal coperchio blocca prima lo schermo
(`before-sleep`). La sospensione rispetta gli inibitori di logind.
Per controllare:

    systemctl --user status idle hyprlock
    journalctl --user -b -u idle -u hyprlock

**Batteria del portatile.** `services.upower.enable = true` è in
`hosts/common.nix`: UPower serve alla batteria della barra e ai profili
idle; `power-profiles-daemon` gestisce i profili e non lo sostituisce.
batsignal avvisa al 10% e di nuovo al 5%. Se la batteria non compare:

    systemctl status upower
    upower -d
    systemctl --user status waybar batsignal

Se UPower non elenca batterie, controlla `ls /sys/class/power_supply` e
`journalctl -b -u upower`: il problema è a monte della barra. La verifica
hardware va fatta sul portatile, non sul fisso usato per valutare il flake.

**Claude Code e Codex: lavoro a schermo bloccato.** I comandi `claude`
e `codex` installati da Home Manager impediscono la sospensione con
`systemd-inhibit --what=sleep --mode=block`. Si usano normalmente:

    claude
    codex

Blocco automatico e spegnimento dello schermo restano attivi. La protezione
dura finché la CLI resta aperta, anche in attesa di un prompt, e viene
rilasciata alla sua uscita. Ogni istanza ha il proprio inibitore: chiuderne
una non rimuove quelli delle altre. Vale anche per i sottocomandi, come
`codex exec`, per la durata del processo. Puoi controllarli con:

    systemd-inhibit --list

I wrapper sono in `home/dev.nix` e chiamano i binari originali nello store,
conservandone argomenti, completamenti e risorse. Un avvio diretto del
binario originale o da un'altra installazione bypassa questa protezione.
La chiusura del coperchio conserva il comportamento di logind: per lasciare
un lavoro in corso tienilo aperto. Anche una sospensione manuale ordinaria
può essere bloccata finché una CLI è aperta; termina le CLI prima di sospendere.
Questi wrapper proteggono le CLI nel PATH, NON automaticamente le sessioni
avviate dalle app desktop, che possono usare un proprio runtime incluso.

**Appunti e luce notturna.** cliphist registra testo e immagini (ultime
500 voci) e wl-clip-persist tiene vivo l'ultimo copiato anche quando l'app
che l'ha copiato si chiude. `wl-copy` e `wl-paste` restano per Neovim e
il terminale. `Alt+F8` porta lo schermo a 4000 K, `Alt+F9` a 6500 K (il
pulsante luna nel centro di controllo fa lo stesso): nessuna
programmazione oraria, solo a mano.

**Privacy durante la condivisione.** La finestra Wi-Fi QR ha
`shield_when_capture` (`rules.conf`): negli screencast è un rettangolo
nero, sul tuo monitor resta normale. Nient'altro è oscurato: menu rofi
(compresa la cronologia degli appunti), notifiche e centro di controllo
finiscono nella condivisione come tutto il resto. Prima di condividere
dati reali, prova un'anteprima con una voce degli appunti fittizia.

**Touchpad come sul MacBook.** In `config.conf`, e conta solo sul
portatile: tocco = click, scorrimento naturale, click con due/tre dita
ovunque (`clickfinger`, niente zone-pulsante), touchpad spento mentre
scrivi. Gesture: 3 dita ←/→ la finestra accanto, ↑/↓ il tag dopo/prima,
4 dita ↑/↓ l'overview. Niente angoli caldi. Pinch-to-zoom e
indietro/avanti con due dita funzionano nelle app che li supportano.

**Tastiera e volume.** Sul portatile mango ha `it` + `us` e `Mod+K`
alterna; SDDM e console restano solo `it`, il fisso ha solo `us`. Il
layout sta in `host.conf`, generato dall'host. Il volume è su
`Alt+F11`/`Alt+F12` (muto `Alt+F10`): F11 e F12 da soli restano alle app
(fullscreen e devtools). Volume, luminosità e tasti multimediali
funzionano anche a schermo bloccato.

**mango/NVIDIA (fisso): VRAM e cursore.** Il driver non restituisce al
pool la VRAM liberata dai compositor Wayland e ha un profilo correttivo
per Hyprland, kwin, mutter e altri, ma non per mango: `hosts/armoredcoreVIF`
lo aggiunge per il processo `mango` (era lo stesso fix di niri). Con
`nvtop` mango dovrebbe stare intorno ai 100 MiB, non verso 1 GiB.
`hardware.nvidia.powerManagement.enable` salva la VRAM prima della
sospensione, così al resume le finestre non tornano nere. `GBM_BACKEND` e
`__GLX_VENDOR_LIBRARY_NAME` non sono impostate: con i driver recenti non
servono. Se il cursore sparisce o lascia scie, aggiungi
`WLR_NO_HARDWARE_CURSORS = "1"` alle `sessionVariables` del fisso.

**Anteprima in VM.** Per vedere il desktop senza installarlo:

    nix build .#desktop-preview && ls result/*.png

Avvia una VM NixOS con mango e le config vere del portatile, apre una e
due finestre, rofi, il centro di controllo e hyprlock (sbloccato con la
password), salva gli screenshot e fallisce se waybar, swaync o hyprlock
segnalano errori. Ci mette qualche minuto e serve KVM, per questo non è
tra i check. In VM non c'è una GPU vera: blur, cattura dello schermo e
lo sfondo di hyprlock vanno comunque provati sul portatile.

**Applicare la migrazione.** Sul PC interessato, dopo aver sincronizzato
il repo, usa `nixup apply` oppure
`sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIP`
(`#armoredcoreVIF` sul fisso). Salva il lavoro ed esci dalla sessione
niri; in SDDM scegli **mango** se non è già selezionata. La prima volta lo
sfondo è `bg.png` e la cronologia degli appunti è vuota: quella di
Noctalia non viene importata.

Prima di considerare concluso il passaggio sul portatile, prova `Mod+L`
e lo sblocco, sospensione/ripresa e coperchio, i tasti multimediali,
`Alt+F8/F9`, batteria e appunti, le gesture, i gruppi (`Mod+G`), il
ridimensionamento, un'anteprima di screensharing con dati fittizi e il
blur sulla HD 620. Mantieni una generazione precedente nel bootloader per
il rollback. Le vecchie shell sono nella storia git: DMS fino al commit
`66176da`, niri e Noctalia fino a `a3983cc`.

**Docker.** `dockerd` non parte al boot: lo avvia il socket al primo
comando `docker` (i container `--restart=always` quindi non ripartono da
soli dopo un riavvio). Le porte pubblicate con `-p 8080:80` ascoltano solo
su `127.0.0.1`, perché Docker scrive regole iptables proprie che scavalcano
il firewall di NixOS. Per esporre davvero una porta alla rete:
`-p 0.0.0.0:8080:80`.

**Firmware.** `services.fwupd` è attivo: `fwupdmgr refresh`,
`fwupdmgr get-updates`, `fwupdmgr update` (BIOS/EC del T470s, SSD, periferiche).

**Font: Monaspace Argon.** `pkgs.monaspace` è già installato a sistema.
Il nome della famiglia per GTK, Qt, barra, menu, notifiche, lock e SDDM è `Monaspace Argon`;
`MonaspaceArgon-Regular` è invece il nome PostScript usato da Kitty.
La configurazione imposta:

- `hosts/common.nix`: default fontconfig sans-serif/monospace e login SDDM;
- `home/desktop.nix`: GTK e font monospace dconf a 10 pt, Qt5/Qt6 a 10 pt;
- `home/waybar.nix`, `home/rofi.nix`, `home/notifications.nix`, `home/lock.nix`
  e `home/mango-configs.nix`: barra, menu, notifiche, blocco e gruppi di mango;
- Kitty: conserva il font Regular e la dimensione 9 già scelti.

Qt è gestito da Home Manager con i plugin qt5ct/qt6ct; i due file INI
sono read-only, quindi cambia i font in `home/desktop.nix`, non dalle loro
GUI. Dopo il rebuild esci e rientra,
e riapri le app. Per verificare:

    fc-match sans-serif
    fc-match monospace

I fallback Noto/emoji/simboli restano disponibili; siti e app che impongono
un proprio font possono continuare a usarlo.

**Pacchetti non liberi.** `allowUnfree = true` in `common.nix` sblocca
discord, steam, obsidian, nvidia, claude-code, vintagestory. Senza, nix
rifiuta di buildarli e ti dice il perché. Non essendo nella cache, i
pacchetti non liberi si scaricano dal sito originale al rebuild (Vintage
Story: circa 600 MB).

**`system.stateVersion` / `home.stateVersion`.** NON è la versione del
sistema. Dice ai moduli con dati su disco (database, formati di file)
"sono nato con la 26.05, non migrarmi a sorpresa". Si scrive una volta
e non si tocca più, anche dopo dieci `flake update`.

## SSH: come funziona qui

sshd è acceso su entrambi gli host (`common.nix`), porta 22 aperta nel
firewall, **solo chiavi**: niente password, niente root. Entra chi ha la
privata di una `.pub` elencata in `users.users.dokkan.openssh.authorizedKeys.keyFiles`.

**Collegarsi.** La privata sta sulla macchina DA CUI parti. Oggi ce l'ha
il fisso (`~/.ssh/id_ed25519`, la sua `.pub` è già in `dotfiles/ssh/`):

    ssh dokkan@armoredcoreVIP        # dal fisso, funziona subito dopo l'install
    ssh dokkan@192.168.x.y        # se il nome non si risolve: `ip a` sul portatile

**Aggiungere una macchina** (es. dal portatile vuoi entrare nel fisso):
una chiave nuova per macchina, nessun file segreto da spostare.

    ssh-keygen -t ed25519 -C "dokkan@armoredcoreVIP"          # sul portatile
    cp ~/.ssh/id_ed25519.pub ~/nixos-config/dotfiles/ssh/id_ed25519_armoredcoreVIP.pub

poi in `common.nix`:

    openssh.authorizedKeys.keyFiles = [
      ../dotfiles/ssh/id_ed25519.pub
      ../dotfiles/ssh/id_ed25519_armoredcoreVIP.pub
    ];

rebuild, commit, push: al prossimo rebuild anche l'altro host la accetta.
Persa una macchina? Togli la sua riga, rebuild, e quella chiave è morta.

**Se un giorno vuoi la password** (non è lo standard, ma è una tua scelta):

    # solo dalla rete di casa, chiavi obbligatorie da fuori — il compromesso
    services.openssh.extraConfig = ''
      Match Address 192.168.0.0/16,10.0.0.0/8
        PasswordAuthentication yes
    '';

    # da ovunque — allora la password di `passwd` dev'essere LUNGA
    services.openssh.settings.PasswordAuthentication = true;

`PermitRootLogin = "no"` lascialo: si entra come dokkan, poi `sudo`.

## fastfetch: come si gestisce

Tutto in `dotfiles/fastfetch/config.jsonc` (layout e moduli);
`home/shell.nix` genera la config vera sostituendo i segnaposto `@LOGO@`
e `@IMAGES@` con i percorsi nello store.

**Il fiocco 3D.** `fastfetch` senza argomenti, in un terminale, fa girare
il logo NixOS in 3D accanto alle info: due giri, poi si ferma di fronte.
Un tasto qualsiasi salta al fotogramma finale. Varianti:

    FASTFETCH_SPIN=loop fastfetch   # gira finché non premi un tasto
    FASTFETCH_SPIN=off fastfetch    # fermo, come fastfetch normale
    fastfetch --qualsiasi-opzione   # con argomenti: fastfetch normale

Da fermo (con argomenti, in una pipe, in un terminale troppo basso) il logo
è lo stesso fiocco, nel fotogramma frontale. Come funziona: il fiocco è la
geometria vera dell'SVG ufficiale (`nixos-icons`), sei lambda estrusi in
un solido. `home/fastfetch-spin.py` lo illumina e lo trasforma in caratteri
ASCII con i colori Tokyo Night (blu `#7aa2f7` e `#2ac3de`) **al build**, per
72 angolazioni. `home/fastfetch-spin.sh` (il `fastfetch` nel PATH) le
ristampa accanto all'output di fastfetch vero. Dimensioni, numero di
fotogrammi, giri e durata stanno in `home/fastfetch-spin.nix`.

**Tornare a un'immagine.** Copia il file in `images/`, nel jsonc sostituisci
`@LOGO@` con il blocco d'esempio scritto nel commento in cima (usa
`"@IMAGES@/tuo-file.png"`) e togli `programs.fastfetch.package` da
`home/shell.nix`. `git add` (i flake vedono solo file tracciati!), rebuild.
Le immagini si vedono solo in kitty; in tty o via ssh fastfetch ripiega sul
fiocco ASCII classico.

**Moduli.** La lista `"modules"` è l'ordine delle righe. Nomi con
`fastfetch --list-modules`; un modulo si configura come oggetto, es.
`{ "type": "disk", "folders": "/" }`. Riferimento:
https://github.com/fastfetch-cli/fastfetch/wiki/Configuration

**Provare senza rebuild.** Il jsonc del repo da solo non è valido (`@LOGO@`
diventa JSON solo al build). Dopo `git add`, costruisci la config generata
e passala a fastfetch (con argomenti, quindi logo fermo):

    nix build '.#nixosConfigurations.armoredcoreVIP.config.home-manager.users.dokkan.xdg.configFile."fastfetch/config.jsonc".source'
    fastfetch --config ./result

**All'apertura del terminale?** Oggi parte `pokemon-colorscripts`
(dotfiles/zsh/extra.zsh). Per fastfetch al suo posto, o in aggiunta,
cambia quella riga.

## Devshell: come si usa

Il sistema NON ha compilatori. Ogni progetto ha la sua shell:

    mkdir engine && cd engine
    nix flake init -t ~/nixos-config#c    # o #rust, #zig, #python
    direnv allow                           # da qui in poi entri nella cartella
                                           # e gcc/clangd/raylib ci sono, esci e spariscono
    nvim .                                 # clangd lo trova nel PATH della shell

Per aggiungere una libreria: `shell.nix` del progetto, riga nella lista,
`direnv reload`. Per provare due righe senza progetto:
`nix develop ~/nixos-config#rust`.

**Python e wheel binarie.** Per pacchetti fuori da nixpkgs puoi usare
`uv venv --python python3` e poi `uv pip install X`. Le estensioni native
possono richiedere altre librerie condivise: con Python di nixpkgs,
`nix-ld` non le rende automaticamente disponibili. Il template Python
mostra come dichiarare `LD_LIBRARY_PATH` nella sola devshell, aggiungendo
le librerie effettivamente richieste dal progetto. Vedi la
[FAQ di nix-ld](https://github.com/nix-community/nix-ld#my-pythonnodejsrubyinterpreter-libraries-do-not-find-the-libraries-configured-by-nix-ld).

## Checklist prima dell'install

- [x] script dei bind, p10k, nvim, kitty, cava: dentro e linkati
- [x] `home/dev.nix`: nome/email git
- [x] `hosts/armoredcoreVIP`: microcode Intel, grafica Intel HD 620, niente nvidia
- [x] `hosts/armoredcoreVIF`: RTX 2070 con nvidia-open, env var nvidia nella sessione
- [x] `home/desktop.nix`: lista app (da `pacman -Qe` di Arch — sfoltisci pure)
- [ ] `hardware-configuration.nix`: SOLO durante l'install, per ciascuna macchina
- [ ] `hostname`/`user`: `armoredcoreVIP` (portatile) o `armoredcoreVIF` (fisso), utente `dokkan` (su Arch era `raven`)
- [ ] MAI committare: chiavi PRIVATE ssh/gpg, token, history
      (`dotfiles/ssh/id_ed25519.pub` è la pubblica: quella sì, serve a sshd)
- [ ] ssh: la privata `~/.ssh/id_ed25519` sta sulla macchina DA CUI ti
      colleghi (oggi il fisso, che ce l'ha già). Le nuove macchine ne hanno
      bisogno solo per collegarsi ALTROVE: meglio `ssh-keygen -t ed25519`
      lì e aggiungere la nuova `.pub` in `dotfiles/ssh/` + `keyFiles`

## Comandi

    # da Arch (con nix installato): valuta i due host e costruisce i check:
    # mango -p sulle config dei due host (normale e gaming) e i bind portati
    # da niri, la sessione (wrapper, target, profilo NVIDIA), i pezzi del
    # desktop (waybar, swaync, rofi, hyprlock validati sul serio), gli script
    # dei bind con comandi finti, game mode, ricerca file, profili idle e
    # conferma del lock, LazyVim/Mason e nixup con comandi simulati, UPower
    # e font GTK/Qt/fontconfig, fiocco 3D di fastfetch
    # NB: i flake vedono SOLO i file tracciati da git → `git add` prima
    nix flake check

    # da Arch: costruisce TUTTO il sistema in /nix/store senza installare
    # nulla (prova definitiva; occupa spazio, poi `nix store gc`)
    nix build .#nixosConfigurations.armoredcoreVIP.config.system.build.toplevel

    # da Arch: il desktop in una VM, con screenshot in result/ (qualche minuto)
    nix build .#desktop-preview

    # da Arch: builda la VM di prova e avviala
    nixos-rebuild build-vm --flake .#armoredcoreVIP
    ./result/bin/run-armoredcoreVIP-vm

    # installare da zero: vedi la sezione "Installazione" qui sotto

    # (opzionale) il build fatto da Arch come cache per l'install: dal
    # live installer, con ssh verso il fisso, i pacchetti arrivano dalla LAN
    # invece che da internet. Finché il fisso è Arch, lì serve
    # `sudo systemctl start sshd` (è spento) e la tua chiave sul live.
    nix copy --from ssh://raven@192.168.1.12 /nix/store/<hash>-nixos-system-armoredcoreVIP-*

    # ciclo di vita, per sempre (sul pc giusto!):
    sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIP
    sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIF

    # aggiornamento assistito, sul sistema NixOS installato:
    nixup            # tutti gli input, diff e conferma prima dello switch
    nixup ai         # soltanto llm-agents
    nixup apply      # stesso lock, anche dopo pull o annullamento

    # arsenale CTF ovunque:
    nix develop ~/nixos-config#ctf

## Installazione (da zero, sul portatile)

Prerequisito: questo repo pushato su GitHub (o su una chiavetta). Il
`flake.lock` DEVE essere committato: è lui che garantisce che installi
esattamente il sistema che abbiamo buildato e verificato da Arch.

**1. La chiavetta.** Da https://nixos.org/download scarica la ISO
*Minimal* (solo terminale, basta e avanza). Su Linux non si "monta": si
scrive l'immagine sopra tutta la chiavetta con `dd`, che è quello che fa
Etcher sotto il cofano. Da Arch, sul fisso:

    # 1) integra? confronta con l'hash sulla pagina di download
    sha256sum /home/raven/Downloads/nixos-minimal-*.iso

    # 2) QUALE disco è la chiavetta: guarda dimensione e modello.
    #    sdb è Arch, nvme0n1 Windows, sda l'HDD: NON quelli.
    lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,MOUNTPOINTS

    # 3) smonta eventuali partizioni della chiavetta (in silenzio se non serve)
    sudo umount /dev/sdX* 2>/dev/null

    # 4) scrivi: il DISCO INTERO (sdX), mai una partizione (sdX1). Irreversibile.
    sudo dd if=/home/raven/Downloads/nixos-minimal-26.05.XXXX-x86_64-linux.iso \
            of=/dev/sdX bs=4M status=progress oflag=sync
    sync

Trappole già viste:
- `zsh: no matches found: if=nixos-minimal-*.iso` → non sei nella cartella
  della ISO. zsh si rifiuta di eseguire un jolly che non trova nulla.
- `dd: failed to open '~/Downloads/...'` → dentro `if=~/...` zsh NON
  espande la tilde (solo a inizio parola). Usa il percorso assoluto o `$HOME`.
- la lettera della chiavetta può cambiare se la stacchi e riattacchi:
  `lsblk` ogni volta prima di `dd`.

**2. Boot e rete.** Avvia dalla chiavetta (F12 sul ThinkPad, voce USB in
UEFI, non legacy). Al menu della ISO scegli il kernel **LTS**: vale solo
per la sessione live, il sistema installato prende il suo dalla config.
Con il cavo ethernet la rete c'è già. In wifi, la ISO Minimal 26.05 ha
NetworkManager, ed è l'UNICA via che funziona liscia:

    nmcli device wifi connect "NomeRete" password "password"
    ping -c 3 nixos.org      # ok? avanti

Testato sul T470s (2026-09-04). NON seguire la via `wpa_cli` del manuale:
in questa ISO il servizio wpa_supplicant parte prima che la scheda esista
e non la gestisce (`wpa_cli` risponde "Could not connect"), e non c'è né
dhcpcd né networkd a dare l'IP. Se `nmcli` dice che il device è
"unavailable", `sudo systemctl restart NetworkManager` e riprova.

Piano B, se proprio NetworkManager non ci fosse: wpa_supplicant a mano
(`wpa_passphrase "NomeRete" "password" | sudo tee /tmp/wpa.conf` poi
`sudo wpa_supplicant -B -i wlp58s0 -c /tmp/wpa.conf`) aggancia il router,
ma l'IP va messo a mano: `sudo ip addr add 192.168.1.77/24 dev wlp58s0`,
`sudo ip route add default via 192.168.1.1`,
`echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf`.

**2b. Tastiera italiana nella live** (il T470s ce l'ha, la live parte in US):

    sudo loadkeys it

Nel sistema installato non serve fare nulla: `hosts/armoredcoreVIP` dichiara
`services.xserver.xkb.layout = "it"` e da lì lo prendono SDDM, la console
e mango (che riceve un `host.conf` generato: `config.conf` è condiviso col
fisso, che è US). In mango il portatile ha anche `us` come secondo layout,
su `Mod+K`.

**3. Partizioni.** Il T470s ha un NVMe: `lsblk` per confermare il nome
(`/dev/nvme0n1`). Schema semplice, niente swap (c'è zram), le LABEL sono
quelle che il placeholder e i comandi sotto si aspettano. ⚠️ CANCELLA IL
DISCO.

    sudo -i
    parted /dev/nvme0n1 -- mklabel gpt
    parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
    parted /dev/nvme0n1 -- set 1 esp on
    parted /dev/nvme0n1 -- mkpart root ext4 1GiB 100%
    mkfs.fat -F 32 -n boot /dev/nvme0n1p1
    mkfs.ext4 -L nixos /dev/nvme0n1p2

    mount /dev/disk/by-label/nixos /mnt
    mkdir -p /mnt/boot
    mount -o umask=077 /dev/disk/by-label/boot /mnt/boot

(Vuoi il disco cifrato? Si fa, ma cambia partizioni e hardware-config:
chiedi prima di formattare.)

**4. Il repo e l'hardware-configuration vero.**

    nixos-generate-config --root /mnt
    # ↑ scrive /mnt/etc/nixos/{configuration,hardware-configuration}.nix;
    #   il primo lo ignoriamo, il secondo è il ferro vero (UUID, moduli)

    git clone https://github.com/<tu>/nixos-config /mnt/etc/nixos-config
    # (se manca git: nix shell nixpkgs#git)
    cp /mnt/etc/nixos/hardware-configuration.nix \
       /mnt/etc/nixos-config/hosts/armoredcoreVIP/hardware-configuration.nix
    cd /mnt/etc/nixos-config && git add -A
    # ↑ OBBLIGATORIO: i flake vedono solo i file tracciati, senza `git add`
    #   nixos-install userebbe ancora il placeholder e non troverebbe il disco

**5. Installa.**

    nixos-install --flake /mnt/etc/nixos-config#armoredcoreVIP
    # scarica tutto (o quasi: vedi nota nix copy in "Comandi"), alla fine
    # chiede la password di ROOT. Quella di dokkan è "cambiami".
    reboot

Sul **fisso** è identico con `#armoredcoreVIF`, ma occhio: lì Arch vive su
`/dev/sdb`. Usa un altro disco, oppure chiedi per un dual-boot fatto bene.

## Installazione, variante B: prima NixOS "vanilla", poi il flake

**Solo con la ISO grafica (Calamares).** Con la ISO Minimal questa
variante non ha senso: partizioni e `nixos-generate-config` li fai a mano
comunque, quindi sei già ai passi 3-4 della variante A e ti conviene
finire con `nixos-install --flake` lì. Due install per lo stesso risultato
non servono.

Se invece usi Calamares: funziona, e il repo finisce direttamente in
`~/nixos-config` col proprietario giusto. Ma c'è UN passo che non si può
saltare.

**1. Installa NixOS normale** dalla ISO grafica. Nell'installer scegli:
- utente **`dokkan`** (così coincide con la config; la password che metti
  lì resta, `initialPassword` vale solo se l'utente lo crea il flake)
- desktop: **nessuno** (sarà mango; un GNOME/Plasma scelto qui verrebbe
  comunque tolto al primo switch, è solo tempo perso)
- bootloader: systemd-boot, UEFI

**2. Primo boot, terminale.** git e i flake non ci sono ancora:

    nix-shell -p git
    git clone https://github.com/0xdokkan/nixos-config ~/nixos-config
    cd ~/nixos-config

**3. IL passo: l'hardware-configuration vero nel repo.** Il segnaposto del
repo cerca un disco con label `nixos`, che l'installer classico NON mette
(usa gli UUID). Senza questa copia il rebuild riesce ma la nuova
generazione al boot non trova la root.

    cp /etc/nixos/hardware-configuration.nix hosts/armoredcoreVIP/
    git add hosts/armoredcoreVIP/hardware-configuration.nix     # i flake vedono solo file tracciati
    git diff --cached | head -40    # gli UUID sono lì? bene

**4. Il primo switch** (i flake vanno abilitati a mano solo questa volta:
da qui in poi li abilita la config stessa):

    sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIP \
      --option experimental-features "nix-command flakes"
    reboot     # SDDM → mango

**5. Dopo:** `git commit -am "armoredcoreVIP: hardware-configuration vero" && git push`,
poi i punti 4-7 di "Post primo boot". `/etc/nixos/configuration.nix`
dell'installer non serve più: il flake lo ignora, puoi cancellarlo.

## Post primo boot

1. login `dokkan` / `cambiami`, poi subito `passwd`
2. il repo va in `~/nixos-config` (nvim lo cerca lì) e deve essere tuo:

       sudo mv /etc/nixos-config ~/nixos-config
       sudo chown -R dokkan:users ~/nixos-config

   Finché non lo fai, `~/.config/nvim` è un link rotto e nvim parte
   nudo, senza LazyVim (successo: 2026-09-05).
3. `cd ~/nixos-config && git commit -am "armoredcoreVIP: hardware-configuration vero" && git push`
   (fatto per armoredcoreVIP il 2026-09-05: il suo hardware-config vero è nel repo)
4. apri una nuova zsh: il DB per "comando non trovato → pacchetto" è già pronto
5. apri `nvim`: lazy.nvim scarica i plugin da `dotfiles/nvim/lazy-lock.json`
6. `mullvad account login` / login Steam / `docker run hello-world`
   / `sudo zerotier-cli join <id-rete>` (poi autorizzi il pc dalla rete ZeroTier)
7. da qui in poi: modifica → `sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIP`

Note:
- il desktop (mango, barra, menu, notifiche, lock) è configurato da Home
  Manager ed è read-only nello store: si cambia nel repo, non dalle GUI.
- Game mode (Mod+Alt+G) usa `mmsg dispatch load_config_file`: niente
  copie di file, `gaming.conf` non può andare fuori sync.
- Il repo DEVE stare in `~/nixos-config`: la config nvim è un symlink
  live lì dentro (strategia B in `home/dev.nix`).
- Agenti AI: CLI e app desktop sono dichiarati in `home/dev.nix`.
  Claude Code, Codex, Claude Desktop e ChatGPT/Codex desktop usano
  `llm-agents`; OpenCode resta in nixpkgs. Vedi "Aggiornare solo le app AI".
