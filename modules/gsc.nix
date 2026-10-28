{ pkgs, ... }:

# GSC, the HST Guide Star Catalog. Not in nixpkgs.
# The `gsc` query tool and the ~9,500 region files it reads.
# On Ubuntu it comes from the INDI PPA. That is why the CCD Simulator shows
# stars there and none here.
#
# This module exists only for that simulator.
# indi_simulator_ccd draws its fake stars by calling the catalog:
#
#   popen("gsc -c <ra> <dec> -r <radius> -m 0 <mag> -n 3000")
#
# Without `gsc` on PATH, popen() still succeeds (sh exits 127).
# So the driver reads zero stars and logs "No stars found in field", not
# "Error launching gsc". Frames show sky glow and noise, but no stars.
# Ekos' align, guide and focus then have nothing to work with.
#
# gsc looks for the catalog in this order:
#   - $GSCDAT
#   - a guess from argv[0], only for /usr/bin/gsc
#   - /usr/share/GSC
# None exist here. So we wrap the binary and point GSCDAT at its store path.
# $GSCBIN stays unset. gsc defaults it to $GSCDAT/bin, where CMake puts
# regions.bin.
# A wrapper beats environment.variables. gsc inherits the environment of
# whatever started indiserver, maybe on another machine. The wrapper always
# goes with the binary.
#
# The catalog is inside the source tree. So src and output both weigh
# ~235 MB. That is the whole cost of this module.
let
  gsc = pkgs.stdenv.mkDerivation {
    pname = "gsc";
    version = "1.3-unstable-2026-09-08";

    src = pkgs.fetchgit {
      url = "https://git.launchpad.net/gsc";
      rev = "a0405c4257096a2a53763def1a617c15953ab7ff";
      hash = "sha256-nkdxHRZgFFfejdp10J+kafwVJt+G7o3Fq/Ly06FAV3s=";
    };

    nativeBuildInputs = with pkgs; [ cmake makeWrapper ];

    # 1990s C: K&R definitions, implicit declarations, `void main`.
    # GCC 15 defaults to -std=gnu23, where the first two are hard errors.
    # Pin the old dialect instead of silencing errors one flag at a time.
    env.NIX_CFLAGS_COMPILE = "-std=gnu89";

    postInstall = ''
      wrapProgram "$out/bin/gsc" --set GSCDAT "$out/share/GSC"
    '';

    meta = with pkgs.lib; {
      description = "HST Guide Star Catalog and its query tool, used by INDI's CCD Simulator";
      homepage = "https://launchpad.net/gsc";
      license = licenses.gpl2Plus;
      platforms = platforms.linux;
      mainProgram = "gsc";
    };
  };
in
{
  # Also as pkgs.gsc, so services can put it on their PATH
  # (services.astronix.ost.extraPackages, in ./ost.nix).
  nixpkgs.overlays = [ (final: prev: { inherit gsc; }) ];

  environment.systemPackages = [ gsc ];
}
