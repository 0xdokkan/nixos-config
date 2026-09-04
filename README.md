# nixos-config — portatilino & fisso

Il sistema come sorgente. Rice versionato, rollback dal bootloader,
no guilt, just restart.

## Struttura

    flake.nix                  ← input (nixpkgs, home-manager, helium), host, devshell, template
    hosts/
      common.nix               ← tutto ciò che è uguale sui due pc: niri+DMS+SDDM, pipewire,
                                  utente, steam, docker, libvirt, mullvad, wireshark, font...
      portatilino/             ← ThinkPad T470s: Intel HD 620, thermald, batteria
      fisso/                   ← desktop: RTX 2070 (nvidia-open), env var nvidia per niri
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
      cava/config              ← il gradiente
      xdg/applications.menu    ← menu KDE per il "Apri con..." di Dolphin
    templates/{c,rust,zig,python}/
      shell.nix                ← LA devshell (usata anche da `nix develop ~/nixos-config#c`)
      flake.nix + .envrc       ← il boilerplate che il template copia nel progetto

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

    sudo nixos-rebuild switch --flake ~/nixos-config#portatilino   # applica
    sudo nixos-rebuild switch --rollback                            # torna indietro
    sudo nix-env --list-generations -p /nix/var/nix/profiles/system # storico

**Aggiornare.** Il `flake.lock` inchioda la versione ESATTA di nixpkgs,
home-manager e helium: due rebuild con lo stesso lock danno lo stesso
sistema. Per aggiornare tutto (`pacman -Syu`) si sposta il lock:

    nix flake update          # scarica le versioni nuove nel lock
    sudo nixos-rebuild switch --flake ~/nixos-config#portatilino
    git commit -am "bump"     # il lock è versionato: rollback anche dell'update

**Cercare un pacchetto.** https://search.nixos.org (pacchetti E opzioni),
oppure `nix search nixpkgs firefox`. Per sapere in che pacchetto sta un
comando che manca: scrivilo e basta, `nix-index` te lo dice (come
`pacman -F`, DB da generare una volta con `nix-index`).

**Provare senza installare.** Il vero superpotere:

    nix shell nixpkgs#cowsay      # shell con cowsay nel PATH, poi sparisce
    nix run nixpkgs#cowsay -- ciao
    nix develop ~/nixos-config#rust   # una devshell "scratch" di questo repo

**Pulizia.** Le generazioni vecchie e i pacchetti orfani restano nello
store finché non li cancelli (è quello che rende possibile il rollback):

    sudo nix-collect-garbage --delete-older-than 14d   # generazioni + gc
    nix store gc                                       # solo orfani

**Dotfiles.** home-manager NON copia i tuoi file in `~/.config`: ci mette
symlink che puntano nello store, quindi sono read-only. Si modificano
nel repo e si fa il rebuild. Eccezione voluta: `~/.config/nvim` punta
DENTRO `~/nixos-config/dotfiles/nvim` (symlink "live"), perché lazy.nvim
deve scrivere il lockfile.

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

    ssh dokkan@portatilino        # dal fisso, funziona subito dopo l'install
    ssh dokkan@192.168.x.y        # se il nome non si risolve: `ip a` sul portatile

**Aggiungere una macchina** (es. dal portatile vuoi entrare nel fisso):
una chiave nuova per macchina, nessun file segreto da spostare.

    ssh-keygen -t ed25519 -C "dokkan@portatilino"          # sul portatile
    cp ~/.ssh/id_ed25519.pub ~/nixos-config/dotfiles/ssh/id_ed25519_portatilino.pub

poi in `common.nix`:

    openssh.authorizedKeys.keyFiles = [
      ../dotfiles/ssh/id_ed25519.pub
      ../dotfiles/ssh/id_ed25519_portatilino.pub
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

## Checklist prima dell'install

- [x] script niri, p10k, nvim, kitty, cava: dentro e linkati
- [x] `home/dev.nix`: nome/email git
- [x] `hosts/portatilino`: microcode Intel, grafica Intel HD 620, niente nvidia
- [x] `hosts/fisso`: RTX 2070 con nvidia-open, env var nvidia nella sessione
- [x] `home/desktop.nix`: lista app (da `pacman -Qe` di Arch — sfoltisci pure)
- [ ] `hardware-configuration.nix`: SOLO durante l'install, per ciascuna macchina
- [ ] `hostname`/`user`: `portatilino` o `fisso`, utente `dokkan` (su Arch era `raven`)
- [ ] MAI committare: chiavi PRIVATE ssh/gpg, token, history
      (`dotfiles/ssh/id_ed25519.pub` è la pubblica: quella sì, serve a sshd)
- [ ] ssh: la privata `~/.ssh/id_ed25519` sta sulla macchina DA CUI ti
      colleghi (oggi il fisso, che ce l'ha già). Le nuove macchine ne hanno
      bisogno solo per collegarsi ALTROVE: meglio `ssh-keygen -t ed25519`
      lì e aggiungere la nuova `.pub` in `dotfiles/ssh/` + `keyFiles`

## Comandi

    # da Arch (con nix installato): la config valuta? costruisce anche il
    # check che fa `niri validate` sui due config.kdl
    # NB: i flake vedono SOLO i file tracciati da git → `git add` prima
    nix flake check

    # da Arch: costruisce TUTTO il sistema in /nix/store senza installare
    # nulla (prova definitiva; occupa spazio, poi `nix store gc`)
    nix build .#nixosConfigurations.portatilino.config.system.build.toplevel

    # da Arch: builda la VM di prova e avviala
    nixos-rebuild build-vm --flake .#portatilino
    ./result/bin/run-portatilino-vm

    # installare da zero: vedi la sezione "Installazione" qui sotto

    # (opzionale) il build fatto da Arch come cache per l'install: dal
    # live installer, con ssh verso il fisso, i pacchetti arrivano dalla LAN
    # invece che da internet. Finché il fisso è Arch, lì serve
    # `sudo systemctl start sshd` (è spento) e la tua chiave sul live.
    nix copy --from ssh://raven@fisso /nix/store/<hash>-nixos-system-portatilino-*

    # ciclo di vita, per sempre (sul pc giusto!):
    sudo nixos-rebuild switch --flake ~/nixos-config#portatilino
    sudo nixos-rebuild switch --flake ~/nixos-config#fisso

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

**2. Boot e rete.** Avvia dalla chiavetta (UEFI, non legacy). Con il cavo
ethernet la rete c'è già. In wifi:

    sudo systemctl start wpa_supplicant
    wpa_cli
    > add_network
    > set_network 0 ssid "NomeRete"
    > set_network 0 psk "password"
    > enable_network 0
    > quit
    ping nixos.org      # ok? avanti

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
       /mnt/etc/nixos-config/hosts/portatilino/hardware-configuration.nix
    cd /mnt/etc/nixos-config && git add -A
    # ↑ OBBLIGATORIO: i flake vedono solo i file tracciati, senza `git add`
    #   nixos-install userebbe ancora il placeholder e non troverebbe il disco

**5. Installa.**

    nixos-install --flake /mnt/etc/nixos-config#portatilino
    # scarica tutto (o quasi: vedi nota nix copy in "Comandi"), alla fine
    # chiede la password di ROOT. Quella di dokkan è "cambiami".
    reboot

Sul **fisso** è identico con `#fisso`, ma occhio: lì Arch vive su
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

    cp /etc/nixos/hardware-configuration.nix hosts/portatilino/
    git add hosts/portatilino/hardware-configuration.nix     # i flake vedono solo file tracciati
    git diff --cached | head -40    # gli UUID sono lì? bene

**4. Il primo switch** (i flake vanno abilitati a mano solo questa volta:
da qui in poi li abilita la config stessa):

    sudo nixos-rebuild switch --flake ~/nixos-config#portatilino \
      --option experimental-features "nix-command flakes"
    reboot     # SDDM → niri → DMS

**5. Dopo:** `git commit -am "portatilino: hardware-configuration vero" && git push`,
poi i punti 4-7 di "Post primo boot". `/etc/nixos/configuration.nix`
dell'installer non serve più: il flake lo ignora, puoi cancellarlo.

## Post primo boot

1. login `dokkan` / `cambiami`, poi subito `passwd`
2. il repo va in `~/nixos-config` (nvim lo cerca lì) e deve essere tuo:

       sudo mv /etc/nixos-config ~/nixos-config
       sudo chown -R dokkan:users ~/nixos-config

3. `cd ~/nixos-config && git commit -am "portatilino: hardware-configuration vero" && git push`
4. `nix-index` (una volta: il DB per "comando non trovato → pacchetto")
5. apri `nvim`: lazy.nvim scarica i plugin da `dotfiles/nvim/lazy-lock.json`
6. `mullvad account login` / login Steam / `docker run hello-world`
7. da qui in poi: modifica → `sudo nixos-rebuild switch --flake ~/nixos-config#portatilino`

Note:
- `dms setup` NON serve: config.kdl non usa gli include DMS (come su Arch)
  e comunque è read-only nello store.
- Game mode (Mod+Alt+G) usa `niri msg action load-config-file --path`:
  niente più copie di file, `config-gaming.kdl` non può andare fuori sync.
- Il repo DEVE stare in `~/nixos-config`: la config nvim è un symlink
  live lì dentro (strategia B in `home/dev.nix`).
- Agenti AI: le CLI (claude-code, codex, opencode) sono in nixpkgs, in
  `home/dev.nix`. Claude Desktop per Linux (beta ufficiale, solo .deb) NON
  è in nixpkgs: esiste `github:poeck/claude-desktop-nix-flake` (modulo
  `programs.claude-desktop.enable`), sarebbe un quarto input. Un client
  desktop di ChatGPT/Codex per Linux non esiste, né ufficiale né in nix.
