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
#   - Sunshine, streamed to a Moonlight client. Lower latency than RDP.
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

  # Sunshine, for Moonlight clients (moonlight-qt on the laptop, apps on
  # phones). KMS capture reads the framebuffer KWin draws on HDMI-A-1, so
  # it needs no Wayland protocol and no dialog. It needs cap_sys_admin:
  # the module makes a setuid-less wrapper with that capability.
  # Input goes through uinput; the module loads it and ships udev rules
  # that grant the seat user access.
  # Web UI (pairing) on https://astronomix:47990, LAN only. Its login is
  # alexandre with the password from /etc/astronix/sunshine.env (owned by
  # alexandre, 0600):
  #   SUNSHINE_PASSWORD=supersecret
  # preStart below writes the credentials file Sunshine expects from it at
  # each start. Without the file, Sunshine starts and the web UI asks to
  # create a login. Pair a client: open Moonlight, note the PIN, enter it
  # on the web UI's PIN tab.
  # openFirewall opens 47984/47989/47990/48010 TCP and 47998-48002 UDP.
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    settings = {
      capture = "kms";
      encoder = "vaapi";
      adapter_name = "/dev/dri/renderD128";
      origin_web_ui_allowed = "lan";
      sunshine_name = "astronomix";
      credentials_file = "/home/alexandre/.config/sunshine/credentials.json";
      # The web UI only answers state-changing requests (PIN, settings)
      # from these origins; the default is localhost only. https, no port.
      csrf_allowed_origins = "https://10.0.0.7,https://astronomix,https://astronomix.local,https://astronix,https://astro.lan";
    };
  };

  # Sunshine stores {username, salt, password} where password is
  # SHA-256(password + salt), bytes in reverse order, uppercase hex (what
  # `sunshine --creds` writes; checked against the binary). The module
  # forces an empty PATH on the unit, hence the absolute tool paths.
  systemd.user.services.sunshine = {
    serviceConfig.EnvironmentFile = "-/etc/astronix/sunshine.env";
    preStart = let c = "${pkgs.coreutils}/bin"; in ''
      [ -n "''${SUNSHINE_PASSWORD:-}" ] || exit 0
      f="$HOME/.config/sunshine/credentials.json"
      ${c}/mkdir -p "$(${c}/dirname "$f")"
      salt=$(${c}/head -c 64 /dev/urandom | ${c}/base64 | ${c}/tr -dc 'A-Za-z0-9' | ${c}/head -c 16)
      hash=$(${c}/printf '%s%s' "$SUNSHINE_PASSWORD" "$salt" | ${c}/sha256sum | ${c}/cut -c1-64 \
        | ${c}/fold -w2 | ${c}/tac | ${c}/tr -d '\n' | ${c}/tr a-f A-F)
      umask 077
      ${c}/printf '{"username":"alexandre","salt":"%s","password":"%s"}\n' "$salt" "$hash" > "$f"
    '';
  };

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
