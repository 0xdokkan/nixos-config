# nixos-config — armoredcoreVIP (portatile) & armoredcoreVIF (fisso)

Il sistema come sorgente. Rice versionato, rollback dal bootloader,
no guilt, just restart.

## Struttura

    flake.nix                  ← input (nixpkgs, home-manager, helium, llm-agents), host, devshell, template
    hosts/
      common.nix               ← tutto ciò che è uguale sui due pc: niri+DMS+SDDM, pipewire,
                                  utente, steam, docker, libvirt, mullvad, wireshark, font...
      armoredcoreVIP/          ← il portatile, ThinkPad T470s: Intel HD 620, thermald, batteria
      armoredcoreVIF/          ← il fisso: RTX 2070 (nvidia-open), env var nvidia per niri
        configuration.nix      ← le differenze dell'host + `imports = [ ../common.nix ]`
        hardware-configuration.nix  ← PLACEHOLDER: lo genera l'installer, uno per macchina
    home/                      ← la home di dokkan, identica su entrambi
      default.nix              ← entry home-manager
      desktop.nix              ← niri (config + game mode validate a build-time), app, kitty, xdg
      niri-configs.nix         ← la derivazione che fa `niri validate` (usata anche da `checks`)
      shell.nix                ← zsh + p10k + alias + CLI belt
      dev.nix                  ← git/gh, direnv, neovim (LazyVim), agenti AI, .gdbinit
    dotfiles/
      niri/config.kdl          ← il tesoro ✓ (uno solo: sul fisso le env var nvidia
                                  arrivano dalla sessione, non dal file)
      niri/config-gaming.kdl   ← include config.kdl + gap 0 + animazioni off
      niri/scripts/            ← i 4 script dei bind (gamemode.sh riscritto per NixOS)
      kitty/theme.conf         ← Tokyo Night Storm
      zsh/p10k.zsh, extra.zsh  ← prompt + alias personali
      nvim/                    ← LazyVim (symlink live: lazy-lock.json resta scrivibile)
      dms/                     ← impostazioni DMS (symlink live: la UI di DMS scrive qui,
                                  poi `git commit`; il tema tokyoNightStorm è dentro)
      cava/config              ← il gradiente
      fastfetch/               ← config.jsonc + images/ (le immagini del logo vanno qui)
      gtk/Tokyo-Night/         ← il tema GTK di HyDE (Tokyonight-Storm): nautilus & co.
                                  come sul fisso. Vendorizzato: nixpkgs l'ha rimosso
    templates/{c,rust,zig,python}/
      shell.nix                ← LA devshell (usata anche da `nix develop ~/nixos-config#c`)
      flake.nix + .envrc       ← il boilerplate che il template copia nel progetto
    tests/                     ← regressioni privacy/scratch e toggle gaming, senza sessione grafica

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

**Aggiornare.** Il `flake.lock` inchioda la versione ESATTA di nixpkgs,
home-manager, helium e llm-agents: due rebuild con lo stesso lock danno lo stesso
sistema. Per aggiornare tutto (`pacman -Syu`) si sposta il lock:

    nix flake update          # scarica le versioni nuove nel lock
    sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIP
    git commit -am "bump"     # il lock è versionato: rollback anche dell'update

**Aggiornare solo le app AI.** Claude Code, Codex CLI, Claude Desktop e
ChatGPT/Codex desktop arrivano da
[numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix), con
packaging aggiornato giornalmente. Seguono le release pubblicate, non
build dal ramo di sviluppo; può esserci un ritardo rispetto a upstream.
OpenCode resta nel nixpkgs del sistema, come prima.

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
`pacman -F`, DB da generare una volta con `nix-index`).

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
nel repo e si fa il rebuild. Due eccezioni volute, i symlink "live" che
puntano DENTRO `~/nixos-config/dotfiles/`: `~/.config/nvim` (lazy.nvim
scrive il lockfile) e `~/.config/DankMaterialShell` (la UI di DMS scrive
settings.json). Lì le modifiche le fai dal programma, e poi le committi:
`git status` in `~/nixos-config` te le mostra.

**DMS: blocco e risparmio energetico.** In `dotfiles/dms/settings.json`
il blocco prima della sospensione è attivo. I timeout sono in secondi,
misurati dall'ultima attività:

| profilo | blocco schermo | spegnimento schermo | sospensione |
|---------|----------------|---------------------|-------------|
| batteria | 5 minuti | 6 minuti | 20 minuti |
| alimentazione | 15 minuti | 20 minuti | disattivata |

La configurazione è condivisa: il profilo alimentazione vale anche sul
fisso. Puoi cambiare i tempi dalla UI di DMS e committare `settings.json`.
Il comportamento sul portatile va verificato anche chiudendo il coperchio:
alla riapertura la sessione deve richiedere lo sblocco.

**DMS: batteria del portatile.** `services.upower.enable = true` è in
`hosts/armoredcoreVIP/configuration.nix`: UPower espone le batterie a DMS.
`power-profiles-daemon` gestisce i profili e non lo sostituisce; il widget
batteria è già incluso nella barra. Dopo il rebuild, se non compare:

    systemctl status upower
    upower -d
    systemctl --user restart dms

Se UPower non elenca batterie, controlla `ls /sys/class/power_supply` e
`journalctl -b -u upower`: il problema è a monte del widget. La verifica
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

**DMS: clipboard e luce notturna.** La cronologia è quella nativa di DMS
(`Mod+V`), senza watcher `cliphist` aggiuntivi. `wl-copy` e `wl-paste`
restano disponibili per Neovim e il terminale. `Alt+F8` abilita la luce
notturna di DMS, `Alt+F9` la disabilita; temperatura e programmazione si
regolano dalla UI di DMS e restano nello stato della singola macchina.

Dopo il rebuild, esci dalla sessione e rientra per applicare l'ambiente
aggiornato e terminare i vecchi watcher clipboard e `wl-gammarelay`.
I portali sono avviati dalla sessione senza restart manuali; controlla
condivisione schermo e selettore file dopo il nuovo login.

**DMS: privacy durante la condivisione.** Le regole in
`dotfiles/niri/config.kdl` oscurano negli screencast gestiti da niri la
clipboard (modale, popout dalla barra e menu contestuale), il QR Wi-Fi,
il dialogo password Wi-Fi e quello di pairing Bluetooth. Non nascondono
questi elementi sul tuo schermo e non sono una protezione universale
contro qualsiasi metodo di cattura.

Il dialogo principale di autenticazione Polkit di DMS è una finestra,
non un layer: **non è ancora coperto**. Il match `dms:polkit…` protegge
solo le eventuali superfici layer incorporate. Per completare la regola,
sul portatile apri una richiesta di autenticazione senza digitare password
e identifica `app_id` e `title` con:

    niri msg --json windows

Prima di condividere dati reali, verifica l'anteprima di una registrazione
o condivisione di prova con una voce clipboard fittizia e un QR Wi-Fi di
una rete di test. I test automatici controllano sintassi e match dei
namespace, non il risultato visivo della cattura.

**Niri: workspace scratch.** Ora è dichiarato per nome e rimane disponibile
anche vuoto; è un workspace normale, visibile nella barra e nell'overview,
non uno spazio nascosto in stile Hyprland. Non usa più l'indice `99`.
Gli indici numerici degli altri workspace possono cambiare.

- `Mod+Alt+S`: invia la colonna a `scratch` senza seguirla;
- `Mod+Ctrl+S`: raggiunge `scratch`;
- `Mod+S`: conserva l'overview.

**Niri: modalità gaming.** `Mod+Alt+G` carica alternativamente la config
gaming e quella normale. Lo stato è in `XDG_RUNTIME_DIR/niri-gamemode/`,
separato per `NIRI_SOCKET`: al riavvio di niri non viene riutilizzato lo
stato della vecchia istanza. La vecchia cache è ignorata, non cancellata.
Un lock serializza pressioni ravvicinate; se niri rifiuta il cambio, lo
stato precedente viene conservato. Usa il bind dalla sessione niri: lo
script richiede il suo ambiente. Caricare manualmente una config fuori
dallo script non aggiorna lo stato del toggle.

**Font: Monaspace Argon.** `pkgs.monaspace` è già installato a sistema.
Il nome della famiglia per GTK, Qt, DMS e SDDM è `Monaspace Argon`;
`MonaspaceArgon-Regular` è invece il nome PostScript usato da Kitty.
La configurazione imposta:

- `hosts/common.nix`: default fontconfig sans-serif/monospace e login SDDM;
- `home/desktop.nix`: GTK e font monospace dconf a 10 pt, Qt5/Qt6 a 10 pt;
- `dotfiles/dms/settings.json`: font UI e monospace della shell, peso 400;
- Kitty: conserva il font Regular e la dimensione 9 già scelti.

Qt è gestito da Home Manager con i plugin qt5ct/qt6ct; i due file INI
sono read-only, quindi cambia i font in `home/desktop.nix`, non dalle loro
GUI. Lascia `qtThemingEnabled=false` in DMS per non avere due gestori sugli
stessi file. Dopo il rebuild esci e rientra, e riapri le app. Per verificare:

    fc-match sans-serif
    fc-match monospace

I fallback Noto/emoji/simboli restano disponibili; siti e app che impongono
un proprio font possono continuare a usarlo.

**Pacchetti non liberi.** `allowUnfree = true` in `common.nix` sblocca
discord, steam, obsidian, nvidia, claude-code. Senza, nix rifiuta di
buildarli e ti dice il perché.

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

Tutto in `dotfiles/fastfetch/`: `config.jsonc` (layout e moduli) e
`images/` (le immagini del logo). `home/shell.nix` genera la config vera
sostituendo `@IMAGES@` con il percorso della cartella nello store.

**Cambiare immagine.** Copia il file in `images/`, poi nel jsonc:

    "source": "@IMAGES@/pikachu.png",     // il nome del TUO file
    "width": 30, "height": 15,            // dimensioni in celle del terminale

`git add` (i flake vedono solo file tracciati!), rebuild. Le immagini si
vedono solo in kitty; in tty o via ssh fastfetch ripiega sul fiocco ASCII.

**Tornare al logo ASCII.** Nel blocco `"logo"`: `"type": "builtin"` e
togli `source`. Oppure `"source": "arch"` per ridere.

**Moduli.** La lista `"modules"` è l'ordine delle righe. Nomi con
`fastfetch --list-modules`; un modulo si configura come oggetto, es.
`{ "type": "disk", "folders": "/" }`. Riferimento:
https://github.com/fastfetch-cli/fastfetch/wiki/Configuration

**Provare senza rebuild.** Il jsonc è JSON con commenti, fastfetch lo
legge anche direttamente (ma con `@IMAGES@` non sostituito: usa un
percorso assoluto per il test):

    fastfetch --config ~/nixos-config/dotfiles/fastfetch/config.jsonc

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

- [x] script niri, p10k, nvim, kitty, cava: dentro e linkati
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
    # niri validate (normale/gaming, layout us/it), privacy/scratch,
    # toggle gaming con IPC simulato, UPower e font GTK/Qt/DMS/fontconfig
    # NB: i flake vedono SOLO i file tracciati da git → `git add` prima
    nix flake check

    # da Arch: costruisce TUTTO il sistema in /nix/store senza installare
    # nulla (prova definitiva; occupa spazio, poi `nix store gc`)
    nix build .#nixosConfigurations.armoredcoreVIP.config.system.build.toplevel

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

    # aggiornare gli input (nixpkgs, HM, helium) e poi rebuild:
    nix flake update

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
e niri (che riceve un `host.kdl` generato: `config.kdl` è condiviso col
fisso, che è US). Vuoi entrambi con Mod+K per ciclare? `"it,us"`.

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
- desktop: **nessuno** (sarà niri; un GNOME/Plasma scelto qui verrebbe
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
    reboot     # SDDM → niri → DMS

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
4. `nix-index` (una volta: il DB per "comando non trovato → pacchetto")
5. apri `nvim`: lazy.nvim scarica i plugin da `dotfiles/nvim/lazy-lock.json`
6. `mullvad account login` / login Steam / `docker run hello-world`
7. da qui in poi: modifica → `sudo nixos-rebuild switch --flake ~/nixos-config#armoredcoreVIP`

Note:
- `dms setup` NON serve: config.kdl non usa gli include DMS (come su Arch)
  e comunque è read-only nello store.
- Game mode (Mod+Alt+G) usa `niri msg action load-config-file --path`:
  niente più copie di file, `config-gaming.kdl` non può andare fuori sync.
- Il repo DEVE stare in `~/nixos-config`: la config nvim è un symlink
  live lì dentro (strategia B in `home/dev.nix`).
- Agenti AI: CLI e app desktop sono dichiarati in `home/dev.nix`.
  Claude Code, Codex, Claude Desktop e ChatGPT/Codex desktop usano
  `llm-agents`; OpenCode resta in nixpkgs. Vedi "Aggiornare solo le app AI".
