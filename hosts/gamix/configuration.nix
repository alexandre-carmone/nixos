{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./nvidia.nix
    ./cuda.nix
    ../../modules/common.nix
    ../../modules/astro.nix
    ../../modules/rc-astro.nix
    ../../modules/graxpert.nix
    ../../modules/desktop-plasma-wayland.nix
    ../../modules/darkman.nix
    ../../modules/gaming.nix
    ../../modules/syncthing.nix
    ../../modules/foldingathome.nix
  ];

  networking.hostName = "gamix";

  # Syncthing. Starts with no peers and no folders: the first rebuild gives
  # gamix its device ID. Read it with
  #   syncthing --device-id --home=~/.config/syncthing
  # then declare the remotes and folders here. This config is the source of
  # truth; devices or folders added in the GUI (http://127.0.0.1:8384) are
  # dropped at the next rebuild. See modules/syncthing.nix for the options.
  services.astronix.syncthing = {
    enable = true;
    # devices.nas = "PASTE-NAS-DEVICE-ID-HERE";
    # folders.documents = {
    #   path = "/home/alexandre/Sync";
    #   devices = [ "nas" ];
    #   type = "sendreceive"; # sendreceive | sendonly | receiveonly | receiveencrypted
    # };
  };

  # Folding@home on the NVIDIA card. Starts folding on its own after the
  # first rebuild; pause or tweak it at https://app.foldingathome.org.
  # See modules/foldingathome.nix for the options.
  services.astronix.foldingathome = {
    enable = true;
    # user = "alexandre"; # name on the leaderboard; Anonymous when unset
  };

  environment.systemPackages = with pkgs; [
    # For LazyVim in ~/.config/nvim.
    # nvim-treesitter compiles its grammars. Mason builds some servers.
    gcc
    gnumake
  ];
}
