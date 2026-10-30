{ pkgs, ... }:

# Base config for every host.
# Nix and flakes, boot, networking, the user account and CLI tools.
# It also imports the small shared modules below.
{
  imports = [
    ./locale.nix
    ./audio.nix
    ./input.nix
    ./home.nix
    ./zsh.nix
    ./keyring.nix
  ];
  nix.settings.trusted-users = [ "alexandre" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.enable = true;

  users.users.alexandre = {
    isNormalUser = true;
    description = "alexandre";
    extraGroups = [ "networkmanager" "wheel" "plugdev" ];
  };

  nixpkgs.config.allowUnfree = true;
  programs.nix-ld.enable = true;

  programs.fzf.fuzzyCompletion = true;
  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;
  programs.lazygit.enable = true;

  programs.chromium = {
    enable = true;
    extensions = [
      "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
    ];
  };

  programs.firefox.enable = true;
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    fd
    ripgrep
    wget
    unzip
    git
    just
    uv
    cargo
    zellij
    lua
    luarocks
    qwerty-fr
    lazygit
    btop
    wl-clipboard
  ];

  system.stateVersion = "26.05";
}
