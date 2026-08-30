# ╔════════════════════════════════════════════════════════════════════╗
# ║  PLACEHOLDER — DA SOSTITUIRE DURANTE L'INSTALL!                    ║
# ║                                                                    ║
# ║  Nel live environment, dopo mount su /mnt:                         ║
# ║    nixos-generate-config --root /mnt                               ║
# ║    cp /mnt/etc/nixos/hardware-configuration.nix  ← QUI             ║
# ║  e committa: descrive il ferro (UUID, moduli kernel, mount).       ║
# ║                                                                    ║
# ║  Il dummy sotto serve solo a far valutare la config da Arch        ║
# ║  (nix flake check / nixos-rebuild build-vm) prima dell'install.    ║
# ╚════════════════════════════════════════════════════════════════════╝
{ ... }:

{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
