# astronix

NixOS flake for two astrophotography machines and a gaming desktop.

## Hosts

| Host | hostName | Role |
| --- | --- | --- |
| `astronix` | `astronomix` | The rig. Headless Plasma 6 on X11, SDDM autologin, xrdp, a fake EDID for the virtual display, a WiFi hotspot fallback, and the `junos-web` capture app. |
| `dev` | `inix` | The workstation. GNOME, DisplayLink dock, corporate CA and VPN bits, dev tooling, RC-Astro CLI on the CPU. |
| `gamix` | `gamix` | The gaming desktop. Plasma 6 on Wayland on an NVIDIA card (open modules), CUDA libs on `LD_LIBRARY_PATH`, RC-Astro CLI on the GPU, Folding@home on the GPU, Steam with Proton-GE and a gamescope session, Heroic, GameMode, MangoHud, Discord. |

All three run user `alexandre` and share the astro stack: INDI, KStars, PHD2, Siril.
`dev` and `gamix` each have a `-dark` twin for darkman.

## Layout

```
flake.nix              inputs (nixpkgs fork, home-manager, junos, catppuccin) + the hosts
justfile               rebuild/update/gc recipes
modules/
  common.nix           base config; imports the modules below
  locale.nix           timezone + locale
  audio.nix            PipeWire
  input.nix            QMK, keyd esc<->caps, qwerty-fr layout
  home.nix             home-manager + Catppuccin, Ghostty, Zellij
  theme.nix            light/dark settings, shared by both layers
  darkman.nix          rebuilds into the other theme at sunrise/sunset (dev, gamix)
  keyring.nix          keyring opt-out
  zsh.nix              zsh + oh-my-zsh
  astro.nix            astro stack (INDI + apps)
  imppg.nix            ImPPG, built from source
  gsc.nix              GSC star catalog, for INDI's CCD Simulator
  graxpert.nix         GraXpert, from the upstream bundle
  autostakkert.nix     AutoStakkert!4, under Wine (dev)
  rc-astro.nix         RC-Astro CLI (BlurX/NoiseX/StarXTerminator), from the upstream installer; CUDA on nvidia hosts (dev, gamix)
  desktop-plasma.nix   headless Plasma + xrdp (astronix)
  desktop-plasma-wayland.nix  Plasma on Wayland, real monitor (gamix)
  desktop-gnome.nix    GNOME (dev)
  gaming.nix           Steam, Proton-GE, gamescope, GameMode, MangoHud, Heroic, Discord (gamix)
  docker.nix           Docker (dev)
  wine.nix             Wine + bottles (dev)
  printing.nix         CUPS + the office printer (dev)
  ina-vpn.nix          `inavpn`: INA VPN in one command, 2FA from tb-otp (dev)
  ina-vpn-auto/tb-otp/ tb-otp + the VPN script; vendor/ is built from the AppImage
  syncthing.nix        services.astronix.syncthing (dev, gamix)
  foldingathome.nix    services.astronix.foldingathome: Folding@home on the NVIDIA GPU, enabled through the client API (gamix)
  foldingathome/       the script that enables the GPU and starts folding
  wifi-hotspot.nix     services.astronix.wifi (astronix)
hosts/
  astronix/            configuration.nix + hardware-configuration.nix
  dev/                 configuration.nix + hardware-configuration.nix + displaylink.nix + certs/
  gamix/               configuration.nix + hardware-configuration.nix + nvidia.nix + cuda.nix
```

Each host's `configuration.nix` only composes modules and adds what is unique
to that machine.

## Rebuild

`just` is installed on every host (see `modules/common.nix`); run it from this
repo. Recipes default to the host you are on — `astronomix` maps to `astronix`,
`gamix` to `gamix`, anything else to `dev` — and take a flake attribute for any
other:

```sh
just              # list every recipe
just switch       # rebuild + activate this host
just switch dev-dark
just diff         # build, then show what would change versus the running system
just check        # evaluate every host without building
just update       # bump every flake input
just gc 14        # drop generations older than 14 days, then collect garbage
```

The raw command still works:

```sh
sudo nixos-rebuild switch --flake .#astronix   # the rig
sudo nixos-rebuild switch --flake .#dev        # the workstation
```

`update` is also a shell alias for `sudo nixos-rebuild switch` (see `modules/zsh.nix`).
