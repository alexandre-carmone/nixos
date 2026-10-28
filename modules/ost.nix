# OST, "Observatoire Sans Tête": a headless astrophotography server driven
# from a browser. Backend in ./ost/package.nix.
#
# Three pieces run on the host:
#   - `ostserver`. It talks INDI, exposes a WebSocket on port 9624 and
#     writes captures under `webroot`. With `user` unset it is a system
#     service under its own `ost` account. With `user = "alexandre"` it
#     is a user service in that session, like junos-web on the rig: same
#     account as KStars, so profiles and captures are that user's files.
#     SDDM autologin starts the session, and the service, at boot.
#   - nginx, serving the web frontend and `webroot` (as /ostmedia/).
#     The frontend derives both from the page's hostname: the WebSocket
#     at <host>:9624 and the media at http://<host>/ostmedia/, with no
#     port. So nginx has to listen on 80 for captures to show in the UI.
#   - avahi, so the frontend's Android app finds the server by mDNS.
#     ostserver only logs an error without it.
#
# ostserver also spawns its own `indiserver`, from `indiPackages`. The
# UI's driver list comes from the share/indi XML files of those same
# packages. Drivers started by that indiserver see `extraPackages` on
# PATH: that is where `gsc` goes, for the CCD Simulator (see ./gsc.nix).
#
# Plate solving (Navigator, Polar) uses StellarSolver's internal solver
# with astrometry.net index files from `astrometryDir`. Nothing fetches
# them. Pick the series for your field of view, then:
#   sudo wget -P /var/lib/ost/astrometry \
#     http://data.astrometry.net/4200/index-42{08..14}.fits
# 4208-4214 cover fields wider than 5 degrees (~150 MB in total).
# 4207 and below are for longer focal lengths, each split in 12 or 48
# files. See documentation.ostserver.fr for the table.
#
# Example (in a host's configuration.nix):
#
#   services.astronix.ost = {
#     enable = true;
#     user = "alexandre";
#     openFirewall = true;
#     extraPackages = [ pkgs.gsc ];
#   };
#
# First visit: http://<host>/. With `grant = 0` there is no login.
# Logs: journalctl -u ostserver, or `journalctl --user -u ostserver`
# for a user service. State and database: /var/lib/ost.
# The upstream option list is in
# $(nix build ...)/share/ostserver/ostserver.parms.skel, or `ostserver -h`.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.astronix.ost;

  # The account that owns stateDir and webroot.
  user = if cfg.user == null then "ost" else cfg.user;
  group = if cfg.user == null then "ost" else config.users.users.${cfg.user}.group;

  # One tree with every INDI binary and driver XML. indiserver finds the
  # drivers on PATH; ostserver reads the XML list from one directory.
  indi = pkgs.symlinkJoin {
    name = "ost-indi";
    paths = cfg.indiPackages;
  };

  args = [
    "--webroot=${cfg.webroot}"
    # The server appends "ost.db" to this, without a separator.
    "--dbpath=${cfg.stateDir}/"
    "--libpath=${cfg.package}/lib"
    "--indiserver=${if cfg.indiServer then "Y" else "N"}"
    "--grant=${toString cfg.grant}"
    "--loglevel=${toString cfg.logLevel}"
    "--lng=${cfg.language}"
  ] ++ cfg.extraArgs;

  # Shared by the system and the user unit.
  unit = {
    description = "OST, Observatoire Sans Tête";

    # procps for `pgrep -x indiserver`, coreutils for mkfifo.
    path = [ indi pkgs.procps pkgs.coreutils ] ++ cfg.extraPackages;

    environment = {
      # No display. The Qt widgets it links still need a platform.
      QT_QPA_PLATFORM = "offscreen";
      # Both read by patches in ./ost/package.nix.
      OST_INDI_DRIVERS_DIR = "${indi}/share/indi";
      OST_ASTROMETRY_DIR = cfg.astrometryDir;
    };

    serviceConfig = {
      WorkingDirectory = cfg.stateDir;
      ExecStart = "${cfg.package}/bin/ostserver ${lib.escapeShellArgs args}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
in
{
  options.services.astronix.ost = {
    enable = lib.mkEnableOption "OST, the headless observatory server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./ost/package.nix { };
      defaultText = "pkgs.callPackage ./ost/package.nix { }";
      description = "The ostserver build to run. Its share/ost/www is the frontend.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alexandre";
      description = ''
        null runs a system service under a dedicated `ost` account, in
        the dialout group for serial mounts and focusers.

        A user name runs it as a user service in that account's session
        instead. It then starts with the session (autologin on the rig)
        and ends with it. The account needs dialout itself; ./astro.nix
        gives it to alexandre. Keep `webroot` outside the home: nginx
        can't read a 0700 home, and the default is fine.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ost";
      description = "Working directory: the sqlite database, logs, profiles.";
    };

    webroot = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ost/media";
      description = ''
        Where captures and generated images go. Must be writable by
        `user`, readable by nginx. Served as http://<host>/ostmedia/.
      '';
    };

    astrometryDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ost/astrometry";
      description = "Directory holding the astrometry.net index-*.fits files.";
    };

    indiPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ pkgs.indi-full ];
      defaultText = "[ pkgs.indi-full ]";
      description = ''
        INDI server and drivers. Each package's bin/ goes on the service's
        PATH and its share/indi XML files feed the UI's driver list.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.gsc ]";
      description = ''
        More programs on the service's PATH, for the INDI drivers it
        starts. The CCD Simulator calls `gsc` to draw stars.
      '';
    };

    indiServer = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let ostserver start and own an indiserver. Off, it only connects
        to one already running, on localhost:7624 by default.
      '';
    };

    grant = lib.mkOption {
      type = lib.types.enum [ 0 1 2 ];
      default = 0;
      description = ''
        Security level: 0 no login, 1 read-only for anonymous visitors,
        2 per-user grants. With 1 or 2, set the admin password once with
        `--setadminpassword=...` in `extraArgs`, then remove it.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ 0 1 2 3 4 ];
      default = 1;
      description = "0 debug, 1 info, 2 warning, 3 error, 4 critical.";
    };

    language = lib.mkOption {
      type = lib.types.enum [ "fr" "en" "de" "es" "it" ];
      default = "en";
      description = "Language of the server's messages and the UI labels.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--banner=Observatoire" "--minfree=10" ];
      description = "More ostserver options. `ostserver -h` lists them.";
    };

    web = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Serve the frontend and the media directory with nginx.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 80;
        description = ''
          nginx port. Keep 80 unless another server owns it: the
          frontend builds its media URLs without a port.
        '';
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the WebSocket port (9624) and the nginx port.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # nginx traverses stateDir to reach the default webroot.
      systemd.tmpfiles.rules = [
        "d ${cfg.stateDir} 0755 ${user} ${group} -"
        "d ${cfg.webroot} 0755 ${user} ${group} -"
        "d ${cfg.astrometryDir} 0755 ${user} ${group} -"
      ];
    }

    (lib.mkIf (cfg.user == null) {
      users.users.ost = {
        isSystemUser = true;
        group = "ost";
        home = cfg.stateDir;
        extraGroups = [ "dialout" ];
        description = "OST observatory server";
      };
      users.groups.ost = { };

      systemd.services.ostserver = unit // {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "avahi-daemon.service" ];
        wants = [ "avahi-daemon.service" ];
        serviceConfig = unit.serviceConfig // {
          User = user;
          Group = group;
        };
      };
    })

    # User units are installed for every account; ConditionUser keeps the
    # others from starting a second server on 9624.
    (lib.mkIf (cfg.user != null) {
      systemd.user.services.ostserver = unit // {
        wantedBy = [ "default.target" ];
        unitConfig.ConditionUser = cfg.user;
      };
    })

    {
      services.avahi = {
        enable = true;
        publish.enable = true;
        publish.userServices = true;
      };

      services.nginx = lib.mkIf cfg.web.enable {
        enable = true;

        # The planetarium's sky background is HiPS tiles, proxied and
        # cached here (see front/js/hips-background.js upstream). A tile
        # seen once is served from this cache to every client after.
        # proxy_cache_path belongs in the http block.
        appendHttpConfig = ''
          proxy_cache_path /var/cache/nginx/hips levels=1:2
            keys_zone=hips_cache:10m max_size=2g inactive=90d use_temp_path=off;
        '';

        virtualHosts.ost = {
          default = true;
          listen = [
            { addr = "0.0.0.0"; port = cfg.web.port; }
            { addr = "[::]"; port = cfg.web.port; }
          ];
          root = "${cfg.package}/share/ost/www";

          locations."/".tryFiles = "$uri $uri/ =404";

          locations."/ostmedia/".extraConfig = ''
            alias ${cfg.webroot}/;
            autoindex on;
          '';

          locations."/hips-proxy/dss2color/".extraConfig = ''
            proxy_pass https://alasky.cds.unistra.fr/DSS/DSSColor/;
            proxy_ssl_server_name on;
            proxy_set_header Host alasky.cds.unistra.fr;
            proxy_cache hips_cache;
            proxy_cache_valid 200 90d;
            proxy_cache_valid 404 10m;
            add_header X-Cache-Status $upstream_cache_status always;
          '';
        };
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall
        ([ 9624 ] ++ lib.optional cfg.web.enable cfg.web.port);

      environment.systemPackages = [ cfg.package ];
    }
  ]);
}
