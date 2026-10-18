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
  ];

  networking.hostName = "gamix";

  environment.systemPackages = with pkgs; [
    # For LazyVim in ~/.config/nvim.
    # nvim-treesitter compiles its grammars. Mason builds some servers.
    gcc
    gnumake
  ];
}
