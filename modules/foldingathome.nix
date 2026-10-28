# Folding@home on the NVIDIA GPU.
#
# Runs the Folding@home client (v8, `fahclient` in nixpkgs) as a system
# service and folds on every supported GPU out of the box.
#
# The GPU side works without extra wiring:
#   - the client ships as an FHS env (bubblewrap). Its loader path includes
#     /run/opengl-driver/lib, which is where the nvidia driver puts
#     libcuda.so.1 and libnvidia-opencl.so.1;
#   - ocl-icd inside the env reads /run/opengl-driver/etc/OpenCL/vendors,
#     where the nvidia module installs its ICD;
#   - /dev/nvidia* are world-accessible, so the DynamicUser can open them.
# The FahCore binaries the client downloads run in the same env and find
# the same libraries.
#
# What the client does NOT do by itself is use the GPU: v8 starts paused,
# with every GPU disabled, and expects a click in the Web Control. The
# `foldingathome-gpu` oneshot does those clicks through the client's own
# WebSocket API (see foldingathome/enable-gpus.py). A pause set later in the
# Web Control is respected: only the very first start is switched to fold.
#
# Web Control: https://app.foldingathome.org. It connects to the local
# client on 127.0.0.1:7396 by itself (localhost only, no firewall change).
# The client's log: /var/lib/foldingathome/log.txt, and journalctl -u
# foldingathome. GPU load: nvtop.
#
# Example (in a host's configuration.nix):
#
#   services.astronix.foldingathome = {
#     enable = true;
#     user = "alexandre";       # name on the leaderboard, default Anonymous
#     team = 236565;            # NixOS team, the default
#     cpus = 2;                 # CPU slots; null keeps the client's default
#   };
#
# Reset: `systemctl stop foldingathome foldingathome-gpu`, then
# `rm -r /var/lib/foldingathome /var/lib/foldingathome-gpu`.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.astronix.foldingathome;

  withNvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;

  enableGpus = pkgs.writers.writePython3Bin "fah-enable-gpus" {
    libraries = [ pkgs.python3Packages.websockets ];
  } (builtins.readFile ./foldingathome/enable-gpus.py);
in
{
  options.services.astronix.foldingathome = {
    enable = lib.mkEnableOption "Folding@home on the GPU";

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Folding@home user name, for the stats. null folds as Anonymous.";
    };

    team = lib.mkOption {
      type = lib.types.int;
      default = 236565;
      description = "Folding@home team number. The default is the NixOS team.";
    };

    cpus = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 2;
      description = ''
        CPUs the client may use. null keeps the client's default (all but
        one). Each GPU work unit also takes one CPU; the rest go to CPU
        work units, so set this low for a GPU-only setup.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = withNvidia;
        message = "services.astronix.foldingathome needs the nvidia driver (services.xserver.videoDrivers).";
      }
    ];

    services.foldingathome = {
      enable = true;
      inherit (cfg) user team;
      # Lowest CPU priority. Games and the desktop come first.
      daemonNiceLevel = 19;
      extraArgs = lib.optionals (cfg.cpus != null) [ "--cpus" (toString cfg.cpus) ];
    };

    systemd.services.foldingathome = {
      # GPUs.txt and the work servers are on the network.
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };

    # Enables the GPU and starts folding, through the client's API.
    # Restarting foldingathome restarts this too (PartOf).
    systemd.services.foldingathome-gpu = {
      description = "Folding@home: enable the GPU";
      requires = [ "foldingathome.service" ];
      after = [ "foldingathome.service" ];
      partOf = [ "foldingathome.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        DynamicUser = true;
        # Holds the marker file of the one-time switch to fold.
        StateDirectory = "foldingathome-gpu";
        ExecStart = lib.getExe enableGpus;
        # The script polls for up to 10 minutes.
        TimeoutStartSec = "12min";
      };
    };
  };
}
