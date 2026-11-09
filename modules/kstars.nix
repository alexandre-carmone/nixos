{ lib, inputs, ... }:

# KStars built from the `kstars` flake input (see flake.nix) instead of the
# nixpkgs release tarball. Same derivation as nixpkgs, other source.
#
# Master needs a few things the 3.8.5 package does not list:
#   - Qt Graphs replaces Qt Data Visualization. Optional, but without it
#     the Aberration Inspector and the 3D star profile are compiled out.
#   - KF6 ConfigWidgets, Crash, Notifications and DBusAddons are required
#     find_package components. They come in through other frameworks today,
#     listed here so a nixpkgs bump can't silently drop them.
#
# Other overlays wrap pkgs.kstars (./ekoslive.nix). They must see this
# package as `prev.kstars`, so this overlay goes first.
let
  src = inputs.kstars;
in
{
  nixpkgs.overlays = lib.mkBefore [
    (final: prev: {
      kstars = prev.kstars.overrideAttrs (old: {
        # A dirty checkout has no rev. Nix then builds the working tree.
        version = "3.8.6-${src.shortRev or "dirty"}";
        inherit src;
        buildInputs = old.buildInputs ++ (with final.kdePackages; [
          qtgraphs
          kconfigwidgets
          kcrash
          knotifications
          kdbusaddons
        ]);
      });
    })
  ];
}
