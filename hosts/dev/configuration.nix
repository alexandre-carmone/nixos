{ config, lib, pkgs, ... }:

let
  # Orca 2.4.2 crashes on every slice under native Wayland (EGL) since
  # Mesa 26.2.4. The plate thumbnail calls glDrawElements with no index
  # buffer, and Mesa reads from NULL. Under XWayland (GLX) it works.
  # Remove this wrapper once Mesa or Orca ships a fix.
  orca-slicer = pkgs.symlinkJoin {
    name = "orca-slicer-x11";
    paths = [ pkgs.orca-slicer ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/orca-slicer" --set GDK_BACKEND x11
    '';
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/astro.nix
    ../../modules/desktop-gnome.nix
    ../../modules/darkman.nix
    ../../modules/docker.nix
    ../../modules/wine.nix
    ../../modules/autostakkert.nix
    ../../modules/graxpert.nix
    ../../modules/rc-astro.nix
    ../../modules/syncthing.nix
    ../../modules/printing.nix
    ../../modules/ina-vpn.nix
    ../../modules/ina-proxy.nix
    ./displaylink.nix
  ];

  networking.hostName = "inix";

  # Syncthing sync with the NAS.
  # Paste the NAS device ID below.
  # Get this host's ID with `syncthing --device-id --home=~/.config/syncthing`,
  # then add it on the NAS.
  #services.astronix.syncthing = {
  #  enable = true;
  #  devices.nas = "PASTE-NAS-DEVICE-ID-HERE";
  #  folders.documents = {
  #    path = "/home/alexandre/Sync";
  #    devices = [ "nas" ];
  #    type = "sendreceive"; # sendreceive | sendonly | receiveonly | receiveencrypted
      # To store this folder encrypted on the NAS:
      #   encryptionPasswordFiles.nas = "/etc/astronix/syncthing/nas.key";
  #  };
  #};

  # SCSI generic driver. It creates the /dev/sgN nodes.
  # MakeMKV talks to the optical drive through /dev/sg*, not /dev/sr0.
  # Needed to read UHD Blu-rays.
  boot.kernelModules = [ "sg" ];

  # Synaptics fingerprint reader (USB 06cb:00f0), driven by libfprint.
  # NixOS hooks it into GDM login, screen unlock and sudo.
  # Enroll a finger with `fprintd-enroll` after the rebuild.
  services.fprintd.enable = true;

  environment.systemPackages = with pkgs; [
    gcc
    gnumake
    gpclient
    teams-for-linux
    signal-desktop
    vlc
    #makemkv # rips UHD Blu-rays to mkv (libaacs/VLC can't)
    claude-code
    ffmpeg
    freecad
    orca-slicer
    kubectl
    awscli
    kubelogin-oidc # `kubectl oidc-login`. ~/.kube/config uses it for the SSO clusters
  ];

  # Corporate CA bundle and legacy TLS renegotiation.
  # Needed for the corp VPN and proxy.
  security.pki.certificateFiles = [
    ./certs/bundle.crt
  ];
  environment.sessionVariables.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  environment.etc."ssl/openssl-legacy.cnf".text = ''
    openssl_conf = default_conf

    [default_conf]
    ssl_conf = ssl_sect

    [ssl_sect]
    system_default = ssl_default_sect

    [ssl_default_sect]
    Options = UnsafeLegacyRenegotiation
  '';

  environment.variables.OPENSSL_CONF = "/etc/ssl/openssl-legacy.cnf";
}
