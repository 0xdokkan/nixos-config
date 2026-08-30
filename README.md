# nixos-config — portatilino

Il sistema come sorgente. Rice versionato, rollback dal bootloader,
no guilt, just restart.

## Struttura

    flake.nix                  ← input (nixpkgs unstable + home-manager) e wiring
    hosts/portatilino/
      configuration.nix        ← sistema: boot, rete, niri+DMS+SDDM, pipewire...
      hardware-configuration.nix  ← PLACEHOLDER: lo genera l'installer
    home/
      default.nix              ← entry home-manager
      desktop.nix              ← niri config validata, script, tool wayland
      shell.nix                ← zsh + p10k + CLI belt
      dev.nix                  ← git, neovim (toolchain → devshell!)
    dotfiles/
      niri/config.kdl          ← il tesoro, già dentro ✓
      niri/scripts/            ← TODO: copiare gli .sh (vedi README lì)
      zsh/, nvim/              ← TODO: da riempire

## Checklist prima dell'install

- [ ] `dotfiles/niri/scripts/`: copiare i 4 script + `chmod +x`
- [ ] `dotfiles/zsh/p10k.zsh`: copiare e scommentare la riga in `home/shell.nix`
- [ ] `dotfiles/nvim/`: copiare la config e scommentare in `home/dev.nix`
- [ ] `home/dev.nix`: nome/email git
- [ ] `configuration.nix`: microcode CPU (intel o amd?)
- [ ] `configuration.nix`: NVIDIA sì/no (`lspci | grep -i vga`) —
      se NO, togliere anche le env var nvidia da `dotfiles/niri/config.kdl`
- [ ] `home/desktop.nix`: lista app da completare
- [ ] MAI committare: chiavi ssh/gpg, token, history

## Comandi

    # da Arch (con nix installato): la config valuta?
    nix flake check

    # da Arch: builda la VM di prova e avviala
    nixos-rebuild build-vm --flake .#portatilino
    ./result/bin/run-portatilino-vm

    # sul portatile, dal live installer (dopo mount e hw-config):
    nixos-install --flake /mnt/etc/nixos-config#portatilino

    # ciclo di vita, per sempre:
    sudo nixos-rebuild switch --flake ~/nixos-config#portatilino

    # arsenale CTF ovunque:
    nix develop ~/nixos-config#ctf

## Post primo boot

1. `passwd`
2. `dms setup` (rigenera gli include auto-generati di niri)
3. commit + push dell'hardware-configuration.nix vero
