# Declarative Syncthing sync, e.g. laptop <-> NAS.
#
# This config is the source of truth. Devices and folders declared here
# override anything set in the GUI. Add device IDs and folders, rebuild,
# and it syncs.
#
# Each folder sets its direction (`type`). Per remote, it can also store the
# data encrypted there (`encryptionPasswordFiles`).
#
# Example (in a host's configuration.nix):
#
#   services.astronix.syncthing = {
#     enable = true;
#     devices.nas = "AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH";
#
#     # Two-way sync, plaintext at both ends:
#     folders.documents = {
#       path = "/home/alexandre/Sync";
#       devices = [ "nas" ];
#       type = "sendreceive";
#     };
#
#     # Upload-only backup, unreadable on the NAS:
#     folders.backup = {
#       path = "/home/alexandre/Backup";
#       devices = [ "nas" ];
#       type = "sendonly";
#       encryptionPasswordFiles.nas = "/etc/astronix/syncthing/nas.key";
#     };
#   };
#
# Pairing, once:
#   1. The first rebuild gives this host a device ID.
#   2. Add that ID on the NAS and share the same folder back.
#   3. Put the NAS's ID in `devices.nas`.
# Read this host's ID with:
#   syncthing --device-id --home=/home/alexandre/.config/syncthing
{ config, lib, ... }:

let
  cfg = config.services.astronix.syncthing;
in
{
  options.services.astronix.syncthing = {
    enable = lib.mkEnableOption "declarative Syncthing folder sync";

    user = lib.mkOption {
      type = lib.types.str;
      default = "alexandre";
      description = "User that owns the Syncthing process and synced folders.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/alexandre";
      description = ''
        Base directory for Syncthing state. Relative folder paths resolve
        under it; the config lives in `<dataDir>/.config/syncthing`.
      '';
    };

    devices = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { nas = "AAAAAAA-BBBBBBB-CCCCCCC-DDDDDDD-EEEEEEE-FFFFFFF-GGGGGGG-HHHHHHH"; };
      description = ''
        Remote devices, as name -> Syncthing device ID. Folder `devices` lists
        use these names. Device IDs are public, so committing them is fine.
      '';
    };

    folders = lib.mkOption {
      default = { };
      description = ''
        Folders to sync, keyed by Syncthing folder id. Each folder's `devices`
        list holds keys of `devices`.
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Local filesystem path of the synced folder.";
          };

          devices = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Names (keys of `devices`) to share this folder with.";
          };

          type = lib.mkOption {
            type = lib.types.enum [
              "sendreceive"
              "sendonly"
              "receiveonly"
              "receiveencrypted"
            ];
            default = "sendreceive";
            description = ''
              What this folder does on THIS host:
              - "sendreceive":      two-way sync.
              - "sendonly":         upload only, ignore remote changes.
              - "receiveonly":      download only, never push local changes.
              - "receiveencrypted": hold an encrypted copy for a peer that keeps
                                    the password. This host can't read it. Use
                                    it when this host is the storage target.
              See https://docs.syncthing.net/users/config.html#config-option-folder.type
            '';
          };

          encryptionPasswordFiles = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            example = { nas = "/etc/astronix/syncthing/nas.key"; };
            description = ''
              Per-remote encryption. Maps a device name (a key of `devices`)
              to a file holding the password. That remote then stores this
              folder encrypted and cannot read it; it must set the folder type
              to "receiveencrypted" with the same password. The file is read at
              activation and never enters the nix store, so keep it root-owned
              and 0600 under e.g. /etc/astronix/syncthing/.
            '';
          };
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    # The CLI on PATH, for `syncthing --device-id`.
    environment.systemPackages = [ config.services.syncthing.package ];

    services.syncthing = {
      enable = true;
      user = cfg.user;
      group = "users";
      dataDir = cfg.dataDir;
      configDir = "${cfg.dataDir}/.config/syncthing";
      openDefaultPorts = true; # TCP/UDP 22000 sync + UDP 21027 local discovery
      overrideDevices = true; # this config wins over the GUI
      overrideFolders = true;
      guiAddress = "127.0.0.1:8384"; # localhost only
      settings = {
        devices = lib.mapAttrs (_: id: { inherit id; }) cfg.devices;
        folders = lib.mapAttrs (_: f: {
          inherit (f) path type;
          # A device is a plain name. With an encryption password, it becomes
          # { name; encryptionPasswordFile; }.
          devices = map (
            dev:
            if f.encryptionPasswordFiles ? ${dev} then
              {
                name = dev;
                encryptionPasswordFile = f.encryptionPasswordFiles.${dev};
              }
            else
              dev
          ) f.devices;
        }) cfg.folders;
      };
    };
  };
}
