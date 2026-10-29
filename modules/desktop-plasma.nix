{ config, pkgs, ... }:

# Headless Plasma desktop for the rig.
# Plasma 6 on Wayland, SDDM autologin, a fake EDID for the virtual display,
# RustDesk for remote access.
#
# Plasma 6.8 dropped the X11 session, so no Xorg and no xrdp (X only).
# Remote access is RustDesk, the user service in hosts/astronix.
#
# The fake EDID makes HDMI-A-1 a connected 1920x1080 output from boot, with
# or without a monitor. It is a kernel setting (drm.edid_firmware), so KWin
# sees the output the same way Xorg did. Without an output, KWin runs on an
# internal placeholder screen that nothing can capture.
# Another size at runtime: `kscreen-doctor output.HDMI-A-1.mode.<id>`.
{
  # The Plasma module makes "plasma" (Wayland) the default session and runs
  # SDDM on Wayland with KWin.
  services.displayManager.sddm.enable = true;
  services.displayManager.autoLogin = {
    enable = true;
    user = "alexandre";
  };
  services.desktopManager.plasma6.enable = true;

  # Keyboard layout for local and remote sessions.
  # Overrides the qwerty-fr default from modules/input.nix.
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  # KWin reads kxkbrc, empty until the layout is changed in System Settings,
  # then falls back to XKB_DEFAULT_LAYOUT. Same as desktop-plasma-wayland.nix.
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = config.services.xserver.xkb.layout;

  # The EDID of a real HDMI-only 1080p monitor (Dell E2219HN), from the
  # linuxhw/EDID database. Not hardware.display.edid.modelines: that makes a
  # 128-byte analog EDID with no HDMI block, i915 takes the sink for DVI
  # and prunes every mode. HDMI-A-1 then shows "connected" with an empty
  # modes list, and KWin has no output. A command line mode
  # (video=HDMI-A-1:1920x1080@60e) is pruned the same way.
  # Another monitor: the patterns must match one row of DigitalDisplay.md
  # in github.com/linuxhw/EDID, and edid-decode must show a CTA-861 block
  # with an HDMI vendor block.
  hardware.display.edid.linuxhw."E2219HN" = [ "E2219HN" "00071E42C96A" ];
  hardware.display.outputs."HDMI-A-1".edid = "E2219HN.bin";
  hardware.display.outputs."HDMI-A-1".mode = "e";

  users.users.alexandre.packages = with pkgs; [
    kdePackages.kate
  ];

  # Dark only. At each login:
  #   - apply the Breeze Dark color scheme
  #   - turn off Plasma's automatic light/dark switching
  # Plasma's own tool also recolours GTK apps (PHD2). It also sets the portal
  # color scheme that Ghostty follows. It does nothing once the scheme is set.
  # Only the color scheme, not the Breeze Dark global theme. The global theme
  # would also reset the wallpaper and cursor at every login.
  systemd.user.services.plasma-dark = {
    description = "Apply the Breeze Dark color scheme";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    # After kded. Its gtkconfig module recolours GTK on the change.
    after = [ "graphical-session.target" "plasma-kded6.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kdeglobals \
        --group KDE --key AutomaticLookAndFeel false
      ${pkgs.kdePackages.plasma-workspace}/bin/plasma-apply-colorscheme BreezeDark
    '';
  };
}
