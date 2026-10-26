{ lib, pkgs, theme ? "light", ... }:

# GNOME for the dev workstation.
# GDM, a trimmed GNOME, purple accent, qwerty-fr keyboard, a few extensions.
# Light/dark settings come from the theme preset (./theme.nix).
# They follow the `theme` flake argument.
let
  preset = import ./theme.nix theme;
in
{
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Keep the core apps. Drop the developer tools and the games.
  services.gnome.core-apps.enable = true;
  services.gnome.core-developer-tools.enable = false;
  services.gnome.games.enable = false;
  # Remove the core apps we don't use.
  # What's left: Files, Disk Usage Analyzer, Settings and Disks.
  # Disks is enabled on its own, via programs.gnome-disks.
  environment.gnome.excludePackages = with pkgs; [
    gnome-tour
    gnome-user-docs
    decibels
    epiphany
    gnome-text-editor
    gnome-calculator
    gnome-calendar
    gnome-characters
    gnome-clocks
    gnome-console
    gnome-contacts
    gnome-font-viewer
    gnome-logs
    gnome-maps
    gnome-music
    gnome-system-monitor
    gnome-tecla
    gnome-weather
    loupe
    papers
    gnome-connections
    showtime
    simple-scan
    snapshot
    yelp
    seahorse
  ];

  programs.dconf.profiles.user.databases = [
    {
      lockAll = true; # the GUI can't override these
      settings = {
        "org/gnome/desktop/interface" = {
          # GNOME has no "mauve" accent. "purple" is the closest to the
          # Catppuccin accent set in home.nix.
          accent-color = "purple";
          color-scheme = preset.colorScheme;
        };
        # Wallpaper slideshow, from the Wallpaper Slideshow extension.
        # It sets picture-uri itself. So keep that key out of this locked
        # database.
        "org/gnome/desktop/background".picture-options = "zoom";
        "org/gnome/shell/extensions/azwallpaper" = {
          slideshow-directory = "/home/alexandre/Pictures/wallpapers";
          # (hours, minutes, seconds) per wallpaper.
          slideshow-slide-duration = lib.gvariant.mkTuple [
            (lib.gvariant.mkInt32 0)
            (lib.gvariant.mkInt32 15)
            (lib.gvariant.mkInt32 0)
          ];
          # Updates come from nixpkgs, not extensions.gnome.org.
          update-notifier-enabled = false;
        };
        # The extension skips the lock screen. It gets one fixed image.
        "org/gnome/desktop/screensaver".picture-uri =
          "file:///home/alexandre/Pictures/wallpapers/IMG_2668.jpeg";
        "org/gnome/shell/extensions/tilingshell" = {
          inner-gaps = lib.gvariant.mkUint32 8;
          outer-gaps = lib.gvariant.mkUint32 8;
        };
        # With the light scheme, blur-my-shell turns the top bar text dark
        # when a light window is maximized. Keep it light so Vitals stays
        # readable.
        "org/gnome/shell/extensions/blur-my-shell/panel" = {
          force-light-text = preset.forceLightText;
        };
        "org/gnome/desktop/input-sources" = {
          xkb-options = [ "nocaps:escape" ];
          sources = [ (lib.gvariant.mkTuple [ "xkb" "us_qwerty-fr" ]) ];
        };
        "org/gnome/shell" = {
          disable-user-extensions = false;
          enabled-extensions = [
            "tilingshell@ferrarodomenico.com"
            "blur-my-shell@aunetx"
            "just-perfection-desktop@just-perfection"
            "arcmenu@arcmenu.com"
            "rounded-window-corners@fxgn"
            "Vitals@CoreCoding.com"
            "space-bar@luchrioh"
            "azwallpaper@azwallpaper.gitlab.com"
          ];
        };
      };
    }
  ];

  environment.systemPackages = with pkgs; [
    gnomeExtensions.tiling-shell
    gnomeExtensions.blur-my-shell
    gnomeExtensions.just-perfection
    gnomeExtensions.arc-menu
    gnomeExtensions.rounded-window-corners-reborn
    gnomeExtensions.vitals
    gnomeExtensions.space-bar
    gnomeExtensions.wallpaper-slideshow
    adwaita-icon-theme
  ];
}
