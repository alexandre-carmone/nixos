{
  description = "Nix config for an astrophoto computer";

  inputs = {
    nixpkgs.url = "github:alexandre-carmone/nixpkgs/3fca3558f542c29369b259d2f709c7a1ed45fb03";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    junos = {
      url = "github:alexandre-carmone/Junos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin.url = "github:catppuccin/nix/release-26.05";
    # Official Claude Desktop Linux beta, repackaged from Anthropic's .deb.
    # Not in nixpkgs. Tracks upstream automatically; `just update-input claude-desktop`.
    claude-desktop = {
      url = "github:poeck/claude-desktop-nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, catppuccin, ... }@inputs:
  let
    # Builds a host with one theme.
    # Both args reach the modules through specialArgs.
    # `theme` picks the preset in modules/theme.nix.
    # `host` is the name of the light output. modules/darkman.nix uses it to
    # switch between `host` and `host-dark`.
    mkThemedHost = host: theme: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs theme host; };
      modules = [
        ./hosts/${host}/configuration.nix
        home-manager.nixosModules.home-manager
        catppuccin.nixosModules.catppuccin
      ];
    };
  in
  {
    nixosConfigurations.astronix = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # The rig is dark only. No darkman here.
      # modules/desktop-plasma.nix forces Breeze Dark.
      # This picks the matching Catppuccin flavor (mocha) in modules/home.nix.
      specialArgs = { inherit inputs; theme = "dark"; };
      modules = [
        ./hosts/astronix/configuration.nix
        home-manager.nixosModules.home-manager
        catppuccin.nixosModules.catppuccin
        inputs.junos.nixosModules.default
      ];
    };

    # dev and gamix each have a light and a dark output.
    # They differ in Catppuccin flavor and desktop color scheme.
    # darkman switches between them at sunrise and sunset.
    nixosConfigurations.dev = mkThemedHost "dev" "light";
    nixosConfigurations.dev-dark = mkThemedHost "dev" "dark";

    # The gaming desktop.
    nixosConfigurations.gamix = mkThemedHost "gamix" "light";
    nixosConfigurations.gamix-dark = mkThemedHost "gamix" "dark";
  };
}
