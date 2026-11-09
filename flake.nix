{
  description = "Nix config for an astrophoto computer";

  inputs = {
    nixpkgs.url = "github:alexandre-carmone/nixpkgs/76a9f913e97bd77ca1d97a97c314f8996fea5865";
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
    # KStars sources, built by modules/kstars.nix in place of the nixpkgs
    # release. Points at the local checkout: it carries commits the fork
    # does not have yet. `just update-input kstars` after each commit there.
    # Only tracked files are used (git input), so build/ stays out.
    # Once pushed, switch to "github:alexandre-carmone/kstars" so the other
    # hosts can build it without this checkout.
    kstars = {
      url = "git+file:///home/alexandre/Projects/kstars";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, catppuccin, ... }@inputs:
  let
    # Builds a host with one theme.
    # Both args reach the modules through specialArgs.
    # `theme` picks the preset in modules/theme.nix.
    # `host` is the name of the light output. modules/darkman.nix uses it to
    # switch between `host` and `host-dark` on the hosts that import it.
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

    # The workstation. Light only, no darkman.
    nixosConfigurations.dev = mkThemedHost "dev" "light";

    # The gaming desktop has a light and a dark output.
    # They differ in Catppuccin flavor and desktop color scheme.
    # darkman switches between them at sunrise and sunset.
    nixosConfigurations.gamix = mkThemedHost "gamix" "light";
    nixosConfigurations.gamix-dark = mkThemedHost "gamix" "dark";
  };
}
