{ host, ... }:

# Switches a host between light and dark at sunrise and sunset (gamix).
# The Catppuccin TUI themes are read-only links in the store.
# So switching means a rebuild into the other output: `#<host>` or
# `#<host>-dark`. No files are edited at runtime.
# `host` comes from mkThemedHost in flake.nix.
#
# The rebuild needs root. A sudo rule allows these two exact commands
# without a password. Nothing else.
# Ghostty follows the color scheme on its own (see home.nix).
# So the terminal changes color without waiting for the rebuild.
let
  rebuild = target:
    "/run/current-system/sw/bin/nixos-rebuild switch --flake /home/alexandre/astronix#${target}";
  dark = rebuild "${host}-dark";
  light = rebuild host;
in
{
  security.sudo.extraRules = [
    {
      users = [ "alexandre" ];
      commands = [
        { command = dark; options = [ "NOPASSWD" ]; }
        { command = light; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

  home-manager.users.alexandre.services.darkman = {
    enable = true;
    settings = {
      # Sunrise and sunset use these coordinates (Paris).
      # Fixed coordinates mean no geoclue daemon.
      lat = 48.85;
      lng = 2.35;
      usegeoclue = false;
    };
    darkModeScripts.rebuild = ''
      /run/wrappers/bin/sudo ${dark}
    '';
    lightModeScripts.rebuild = ''
      /run/wrappers/bin/sudo ${light}
    '';
  };
}
