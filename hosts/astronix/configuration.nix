{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/astro.nix
    ../../modules/desktop-plasma.nix
    ../../modules/wifi-hotspot.nix
    ../../modules/ekoslive.nix
  ];

  networking.hostName = "astronomix";

  services.astronix.wifi = {
    enable = true;
    networks = {
      home = {
        priority = 20;
        security = "sae";
      };
    };
    hotspot = {
      ssid = "astronix";
      # Passphrase is HOTSPOT_PSK in /etc/astronix/wifi.env, not here.
      security = "wpa-psk";
    };
  };

  # The astrophoto data disk (internal NVMe, ext4, label "datas").
  # Declared here so it mounts at boot.
  # Plasma used to mount it on demand with udisks2. That asked for a polkit
  # password at every boot, and junos-web crash-looped until someone typed it.
  #
  # Keep this mount point. capturesDir below and the KStars/Ekos sequences
  # on the disk all use /run/media/alexandre/datas.
  #
  # nosuid and nodev match what udisks2 used.
  # nofail: a dead disk breaks junos-web, not the boot.
  fileSystems."/run/media/alexandre/datas" = {
    device = "/dev/disk/by-uuid/27246b7d-d14b-46b1-a3e6-606ef3a1da2a";
    fsType = "ext4";
    options = [ "nosuid" "nodev" "nofail" "x-systemd.device-timeout=10s" ];
  };
  # Lower power draw. The rig idles most of the night.
  # Plasma enables power-profiles-daemon. TLP replaces it; both = flapping.
  # Do not set powerManagement.cpuFreqGovernor / cpufreq.*: the TLP module
  # nulls them.
  services.power-profiles-daemon.enable = false;
  services.tlp = {
    enable = true;
    settings = {
      # No battery on the rig, so TLP applies the *_ON_AC keys.
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "power";
      CPU_BOOST_ON_AC = 0;                # no turbo: the biggest saving
      CPU_MAX_PERF_ON_AC = 50;            # % of max frequency
      PLATFORM_PROFILE_ON_AC = "low-power";
      # Cameras, mount and focuser hang off USB and serial. Never autosuspend.
      USB_AUTOSUSPEND = 0;
      # Hotspot and junos-web clients. Keep wifi awake.
      WIFI_PWR_ON_AC = "off";
    };
  };

  security.sudo.wheelNeedsPassword = false;

  services.junos-web = {
    enable = true;
    openFirewall = true;

    # Run as a user service in alexandre's Plasma session.
    # This way the Launch buttons open KStars and PHD2 on this desktop.
    # The hardened system unit could not run them. Its PATH had only
    # coreutils ("failed to spawn kstars: No such file or directory").
    # It also had no display, D-Bus or home.
    # SDDM autologin starts the session, and the server, at boot.
    #
    # Running as alexandre also gives access to capturesDir. It is on the
    # astrophoto disk, owned by alexandre, behind a 0700 mount point.
    user = "alexandre";
    apps.enable = true;
    # The Profiles tab's Power off / Reboot buttons: a polkit rule lets
    # alexandre run `systemctl poweroff` / `reboot` from the user unit.
    hostPower.enable = true;
    # KStars looks up each driver's binary on PATH before starting it.
    # The module default (kstars and phd2 only) has no camera drivers.
    apps.packages = with pkgs; [
      kstars
      phd2
      indi-full
      indi-3rdparty.indi-toupbase
      indi-3rdparty.indi-playerone
    ];

    capturesDir = "/run/media/alexandre/datas/astrophoto";
    # Offline DSS2 sky map: a HiPS mirror in the CDS layout
    # (Norder{k}/Dir{d}/Npix{n}.jpg + info.json + allsky.jpg), written by
    # `scripts/fetch_skymap.py` or restored with `scripts/pack_skymap.py pull`.
    # On the astrophoto disk too (~25 GB at order 7). Replaces dsoTileDir:
    # the old /home/alexandre/junos-data/dso cutouts are no longer read.
    skymapDir = "/run/media/alexandre/datas/junos-data/skymap";
    # skymapOnline = true;  # fetch missing tiles from CDS on demand (needs internet)
    httpAddr  = "0.0.0.0:8080";
    httpsAddr = "0.0.0.0:8443";

    tls.subjectAltNames = [
      "DNS:localhost"
      "IP:127.0.0.1"
      "DNS:astronomix"
      "DNS:astronomix.local"
      "DNS:astro.lan"
      # Add the host's LAN IP ("IP:192.168.x.y"): iOS Safari only trusts the
      # cert for a name or address listed here.
    ];
    # Self-signed cert. To use your own, set tls.cert and tls.key instead.
    tls.autoGenerate = true;
    #tls.cert = "/run/secrets/junos-cert.pem";
    #tls.key  = "/run/secrets/junos-key.pem";
  };

  # With nofail, nothing waits for the disk. So junos-web waits for it here.
  # Without capturesDir it retries every 5s forever.
  systemd.user.services.junos-web.unitConfig.RequiresMountsFor =
    "/run/media/alexandre/datas";

  # At launch, KStars connects Ekos Live to junos-web.
  # junos-web's httpAddr is on port 8080.
  # junos-server accepts any username and password.
  services.astronix.ekosLive = {
    enable = true;
    server = "http://localhost:8080";
    username = "alexandre";
    password = "junos";
  };

  environment.systemPackages = with pkgs; [
    rustup
    ghostty
  ];

  nix.settings = {
    max-jobs = 1;        # un seul build à la fois
    cores = 0;           # tous les cores pour ce build
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    IdleAction = "ignore";
  };
}
