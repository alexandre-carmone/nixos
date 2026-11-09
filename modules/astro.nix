{ pkgs, lib, ... }:

# Astro stack for every host:
#   - INDI drivers, with their udev rules
#   - capture and processing apps (kstars, phd2, siril, gimp)
#
# KStars comes from the `kstars` flake input, see ./kstars.nix.
# ImPPG has its own module, ./imppg.nix.
# So does the GSC star catalog, ./gsc.nix. INDI's CCD Simulator needs it.
# It weighs ~235 MB and only serves simulated sessions.
# To spare the rig, move that import to hosts/dev.
let
  # Siril 1.4 runs its Python scripts in its own venv.
  # It pip-installs numpy, scipy, PyQt6 and sirilpy into it.
  # Those wheels are dynamically linked. At import, they can't find
  # libstdc++, libz, Qt or X.
  # nix-ld does not help. The venv's python is a Nix binary, so it reads
  # LD_LIBRARY_PATH, not NIX_LD_LIBRARY_PATH.
  # So the wrapper below passes these libraries to the python child.
  sirilVenvLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    glib
    # PyQt6, for GUI scripts like HDR_multiscale and VeraLux
    fontconfig
    freetype
    dbus
    libGL
    libxkbcommon
    libxcb-cursor
    libx11
    libxcb
    libxext
    libxrender
    libxcb-util
    libxcb-wm
    libxcb-image
    libxcb-keysyms
    libxcb-render-util
  ];

  siril = pkgs.symlinkJoin {
    name = "siril-venv-wrapped";
    paths = [ pkgs.siril ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for b in siril siril-cli; do
        if [ -e "$out/bin/$b" ]; then
          wrapProgram "$out/bin/$b" \
            --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath sirilVenvLibs}"
        fi
      done
    '';
  };
in
{
  imports = [ ./kstars.nix ./imppg.nix ./gsc.nix ];

  services.udev.packages = [
    pkgs.indi-full
    pkgs.indi-3rdparty.indi-toupbase
    pkgs.indi-3rdparty.indi-playerone
  ];

  environment.systemPackages = with pkgs; [
    kstars
    phd2
    siril
    gimp
    nomacs # fast viewer for captured and stacked frames
    indi-full
    indi-3rdparty.indi-toupbase
    indi-3rdparty.indi-playerone

    # On PATH so Siril can build its venv for .py scripts.
    python3
  ];

  # Serial access for INDI-controlled mounts/focusers.
  users.users.alexandre.extraGroups = [ "dialout" ];
}
