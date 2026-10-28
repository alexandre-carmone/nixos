"""Enable every supported GPU in the Folding@home client, then start folding.

Run by foldingathome-gpu.service once the client is up. It talks to the
client's WebSocket API on 127.0.0.1:7396, the same API the Web Control
uses, so nothing is written behind the client's back.

Why this exists: the v8 client starts paused with every GPU disabled, and
the only official way to flip either is the Web Control. Each of those
toggles is stored in the client's own database (/var/lib/foldingathome), so
this script does the same thing, once:

  1. wait for the client to list its GPUs (it needs GPUs.txt from the
     Folding@home servers first, so this can take a moment after boot);
  2. enable every GPU reported as supported in the default resource group,
     keeping other groups and any GPU already enabled untouched;
  3. the first time only, switch the machine to "fold". A marker file in the
     state directory remembers that, so a pause set in the Web Control
     survives restarts and rebuilds.

Exit status is always 0. A timeout is logged, not fatal: the client keeps
running on the CPU, and the GPU can still be enabled in the Web Control.

    enable-gpus.py [--url ws://...] [--dry-run] [--marker PATH]
"""

import argparse
import json
import os
import sys
import time

from websockets.sync.client import connect

DEFAULT_URL = "ws://127.0.0.1:7396/api/websocket"
TRIES = 120  # x DELAY seconds: 10 minutes
DELAY = 5


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def get_state(url):
    """The client sends its full state as the first message."""
    with connect(url, open_timeout=5) as ws:
        return json.loads(ws.recv(timeout=10))


def send(url, msg, dry_run):
    if dry_run:
        log("dry-run, would send: " + json.dumps(msg))
        return
    with connect(url, open_timeout=5) as ws:
        ws.recv(timeout=10)  # the state dump, unused here
        ws.send(json.dumps(msg))
        time.sleep(1)  # let the client read it before the close frame


def supported_gpus(state):
    gpus = state.get("info", {}).get("gpus", {})
    return sorted(gid for gid, gpu in gpus.items() if gpu.get("supported"))


def wait_for_gpus(url):
    """Poll until the client reports at least one supported GPU."""
    for attempt in range(TRIES):
        try:
            state = get_state(url)
        except Exception as e:  # not up yet, or restarting
            log(f"client not reachable ({e}), retrying")
            time.sleep(DELAY)
            continue

        gpus = supported_gpus(state)
        if gpus:
            return state, gpus

        if attempt % 12 == 0:
            seen = list(state.get("info", {}).get("gpus", {}))
            log(f"no supported GPU yet (seen: {seen}), waiting")
        time.sleep(DELAY)

    return None, []


def enable(url, state, gpus, dry_run):
    groups = state.get("groups", {})
    default = groups.get("", {}).get("config", {})
    enabled = default.get("gpus", {})

    missing = [g for g in gpus if not enabled.get(g, {}).get("enabled")]
    if not missing:
        log(f"GPUs already enabled: {gpus}")
        return

    new = {gid: dict(cfg) for gid, cfg in enabled.items()}
    for gid in missing:
        new.setdefault(gid, {})["enabled"] = True

    # Groups left out of a config message are deleted, so name them all.
    msg = {"cmd": "config", "config": {"groups": {n: {} for n in groups}}}
    msg["config"]["groups"][""] = {"gpus": new}
    send(url, msg, dry_run)
    log(f"enabled GPUs: {missing}")


def fold(url, marker, dry_run):
    if os.path.exists(marker):
        return
    send(url, {"cmd": "state", "state": "fold"}, dry_run)
    log("folding started")
    if not dry_run:
        with open(marker, "w") as f:
            f.write("foldingathome-gpu set the client to fold once.\n")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--url", default=DEFAULT_URL)
    p.add_argument("--dry-run", action="store_true",
                   help="print the messages instead of sending them")
    p.add_argument("--marker",
                   default=os.path.join(
                       os.environ.get("STATE_DIRECTORY", "."), "folding"),
                   help="file that records the one-time switch to fold")
    args = p.parse_args()

    state, gpus = wait_for_gpus(args.url)
    if not gpus:
        log("gave up waiting for a supported GPU; "
            "enable it in the Web Control (https://app.foldingathome.org)")
        return 0

    enable(args.url, state, gpus, args.dry_run)
    fold(args.url, args.marker, args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main())
