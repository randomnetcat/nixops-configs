{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  config = {
    boot.loader.grub.device = "/dev/sda";
    fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
  };
}
