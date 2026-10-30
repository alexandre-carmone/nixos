# astronix — task runner for this flake.
# `just` alone lists every recipe. Recipes default to the host you are on.

# Flake attribute for the running machine. Override it on any recipe:
# `just switch astronix`.
host := if `hostname` == "astronomix" { "astronix" } else if `hostname` == "gamix" { "gamix" } else { "dev" }
flake := justfile_directory()

_default:
    @just --list

# Rebuild and activate this host's configuration.
switch target=host:
    sudo nixos-rebuild switch --flake {{flake}}#{{target}}

# Build and make it the next boot's default, without activating now.
boot target=host:
    sudo nixos-rebuild boot --flake {{flake}}#{{target}}

# Activate temporarily — reverts on reboot.
try target=host:
    sudo nixos-rebuild test --flake {{flake}}#{{target}}

# Build without touching the running system; result lands in ./result.
build target=host:
    nixos-rebuild build --flake {{flake}}#{{target}}

# Build here, then copy and activate on another host over SSH.
# `just deploy astronix`. Asks the remote sudo password once.
deploy target ssh_host=("alexandre@" + if target == "astronix" { "astronomix" } else { target }):
    nixos-rebuild switch --flake {{flake}}#{{target}} --target-host {{ssh_host}} --ask-sudo-password

# Same, as the next boot's default: for a kernel or EDID change.
deploy-boot target ssh_host=("alexandre@" + if target == "astronix" { "astronomix" } else { target }):
    nixos-rebuild boot --flake {{flake}}#{{target}} --target-host {{ssh_host}} --ask-sudo-password

# Build this host and list what would change versus the running system.
diff target=host:
    nixos-rebuild build --flake {{flake}}#{{target}}
    nix store diff-closures /run/current-system ./result

# Evaluate every host without building. The cheap "did I break it?" check.
check:
    nix flake check {{flake}}

# Bump every flake input.
update:
    nix flake update --flake {{flake}}

# Bump a single input, e.g. `just update-input nixpkgs`.
update-input input:
    nix flake update {{input}} --flake {{flake}}

# Switch this host to dark, as darkman does at dusk.
dark:
    sudo nixos-rebuild switch --flake {{flake}}#{{host}}-dark

# Switch this host back to the light variant.
light:
    sudo nixos-rebuild switch --flake {{flake}}#{{host}}

# List system generations.
generations:
    nixos-rebuild list-generations

# Roll back to the previous generation.
rollback:
    sudo nixos-rebuild switch --rollback

# Drop generations older than DAYS (default 7), system and user, then collect.
gc days="7":
    sudo nix-collect-garbage --delete-older-than {{days}}d
    nix-collect-garbage --delete-older-than {{days}}d

# Free the store of everything unreachable, then optimise it.
prune: (gc "0")
    nix store optimise
