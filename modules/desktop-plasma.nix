{ config, pkgs, ... }:

# Headless Plasma desktop for the rig.
# Plasma 6 on Wayland, SDDM autologin, a fake EDID for the virtual display,
# krdp and RustDesk for remote access.
#
# Plasma 6.8 dropped the X11 session, so no Xorg and no xrdp (X only).
#
# Remote access:
#   - krdp, Plasma's RDP server, as a user service below. Any RDP client:
#       xfreerdp /v:astronomix /u:alexandre /cert:ignore
#   - RustDesk, the user service in hosts/astronix. On Wayland it captures
#     through the XDG portal, and the KDE portal asks "which screen?" on the
#     rig itself. RustDesk 1.5 keeps the portal's restore token, so that
#     dialog shows once per RustDesk config. Answer it over krdp.
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

  # krdp in the autologin session. Login is alexandre with the password in
  # /etc/astronix/krdp.env (owned by alexandre, 0600, the user unit reads it):
  #   KRDP_PASSWORD=supersecret
  # No file, no server: ConditionPathExists keeps the unit quiet.
  # krdpserver refuses to start without a TLS certificate (its --help says
  # it makes a temporary one, 6.8 does not). preStart makes a self-signed
  # one once, in ~/.local/share/krdpserver. Hence /cert:ignore on the client.
  #
  # The unit name matters. krdp uses two privileged Wayland protocols, fake
  # input and screencast. KWin only grants them to a process it can match
  # to a desktop file listing them (X-KDE-Wayland-Interfaces in
  # org.kde.krdpserver.desktop), and it does that match by the systemd unit
  # name: app-<desktop file id>.service. Under any other name krdpserver
  # aborts at start. Ordering and target are the ones from the unit that
  # ships with krdp (share/systemd/user/app-org.kde.krdpserver.service),
  # which NixOS does not install.
  systemd.user.services."app-org.kde.krdpserver" = {
    description = "KRDP Server";
    wantedBy = [ "plasma-workspace.target" ];
    after = [ "plasma-core.target" "plasma-xdg-desktop-portal-kde.service" ];
    unitConfig.ConditionPathExists = "/etc/astronix/krdp.env";
    path = [ pkgs.openssl ];
    preStart = ''
      d="$HOME/.local/share/krdpserver"
      if [ ! -s "$d/key.pem" ] || [ ! -s "$d/cert.pem" ]; then
        mkdir -p "$d"
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
          -subj "/CN=$(uname -n)" -keyout "$d/key.pem" -out "$d/cert.pem"
        chmod 600 "$d/key.pem"
      fi
    '';
    serviceConfig = {
      Type = "exec";
      EnvironmentFile = "/etc/astronix/krdp.env";
      ExecStart = ''${pkgs.kdePackages.krdp}/bin/krdpserver --plasma -u alexandre -p "''${KRDP_PASSWORD}" --certificate %h/.local/share/krdpserver/cert.pem --certificate-key %h/.local/share/krdpserver/key.pem'';
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  networking.firewall.allowedTCPPorts = [ 3389 ];

  # krdp encodes the stream in H.264 through VA-API. Without a driver it
  # logs "VAAPI: Failed to initialize display". The rig has an Intel N150:
  # iHD is the driver for Broadwell and later.
  hardware.graphics.extraPackages = [ pkgs.intel-media-driver ];

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
