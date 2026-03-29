#!/usr/bin/env python3
"""
steam-asahi: NixOS launcher for Steam on Apple Silicon via muvm + FEX-Emu.

Based on Fedora Asahi's shim.py by Alyssa Rosenzweig.
Adapted for NixOS with declarative Steam bootstrap packaging.

SPDX-License-Identifier: MIT
"""

import json
import os
import shutil
import subprocess
import sys
import tarfile

from xdg import BaseDirectory

LAUNCHER_NAME = "steam-asahi"

# These are the files we need from the Steam bootstrap tarball.
MANIFEST = [
    "steam-launcher/steam_subscriber_agreement.txt",
    "steam-launcher/bin_steam.sh",
    "steam-launcher/bootstraplinux_ubuntu12_32.tar.xz",
]

# Nix store paths (substituted at build time)
MUVM = "@muvm@"
INIT_SCRIPT = "@initScript@"
FEX_ROOTFS_FETCHER = "@fexRootFSFetcher@"
STEAM_BOOTSTRAP = "@steamBootstrap@"

# Steam launch args
STEAM_ARGS = ["-cef-force-occlusion"]


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def is_fex_rootfs_configured():
    """Check if FEX has a rootfs configured."""
    fex_emu_dir = os.path.expanduser("~/.fex-emu")
    rootfs_dir = os.path.join(fex_emu_dir, "RootFS")

    if os.path.isdir(rootfs_dir):
        for f in os.listdir(rootfs_dir):
            full = os.path.join(rootfs_dir, f)
            if f.endswith((".ero", ".sqsh", ".img")) or os.path.isdir(full):
                return True

    config_path = os.path.join(fex_emu_dir, "Config.json")
    if os.path.isfile(config_path):
        try:
            with open(config_path) as f:
                config = json.load(f)
            if config.get("Config", {}).get("RootFS", ""):
                return True
        except (json.JSONDecodeError, KeyError):
            pass

    return False


def setup_fex_rootfs():
    """Download FEX rootfs using FEXRootFSFetcher."""
    print("FEX rootfs not found. Downloading Fedora 43 rootfs...")
    print("This is a one-time setup (~1.3GB download).")
    print()

    result = subprocess.run([
        FEX_ROOTFS_FETCHER,
        "--assume-yes",
        "--distro-name=Fedora",
        "--distro-version=43",
        "--distro-list-first",
        "--as-is",
    ])

    if result.returncode != 0:
        print("Automatic download failed. Trying interactive mode...")
        subprocess.run([FEX_ROOTFS_FETCHER])


def ensure_steam_bootstrap(data_dir):
    """Extract Steam bootstrap from the Nix store into the data directory."""
    marker = os.path.join(data_dir, "bootstrap-installed")
    bootstrap_script = os.path.join(data_dir, "steam-launcher", "bin_steam.sh")

    if os.path.isfile(marker) and os.path.isfile(bootstrap_script):
        return

    print("Setting up Steam bootstrap...")
    os.makedirs(data_dir, exist_ok=True)

    # Clean old install
    install_dir = os.path.join(data_dir, "steam-launcher")
    if os.path.isdir(install_dir):
        for item in MANIFEST:
            path = os.path.join(data_dir, item)
            if os.path.exists(path):
                os.unlink(path)

    # Extract from Nix store copy
    with tarfile.open(STEAM_BOOTSTRAP, mode="r:gz") as tar:
        members = [m for m in tar.getmembers() if m.name in MANIFEST]
        tar.extractall(path=data_dir, members=members, filter="data")

    open(marker, "w").write("ok")
    print("Steam bootstrap ready.")


def run_steam(data_dir):
    """Launch Steam via muvm + FEXBash."""
    steam_args = " ".join(STEAM_ARGS + sys.argv[1:])

    env_flags = [
        "-e", "PULSE_CLIENTCONFIG=/run/pulse.conf",
        # Workaround for CEF/steamwebhelper crashes
        "-e", "STEAM_ENABLE_CEF_SHUTDOWN=0",
    ]

    cmd = [
        MUVM,
        "--execute-pre", INIT_SCRIPT,
        *env_flags,
        "--interactive",
        "--",
        "FEXBash",
        "-c",
        f"{data_dir}/steam-launcher/bin_steam.sh {steam_args}",
    ]

    print(f"Launching Steam via muvm + FEX...")
    proc = subprocess.Popen(cmd)
    ret = proc.wait()

    if ret != 0:
        print(f"muvm exited with code {ret}")
    sys.exit(ret)


def main():
    if os.geteuid() == 0:
        die(f"Do not run `{sys.argv[0]}` as root")

    # Step 1: Ensure FEX rootfs
    if not is_fex_rootfs_configured():
        setup_fex_rootfs()
    if not is_fex_rootfs_configured():
        die("FEX rootfs not configured. Run FEXRootFSFetcher manually.")

    # Step 2: Ensure Steam bootstrap
    data_dir = BaseDirectory.save_data_path(LAUNCHER_NAME)
    ensure_steam_bootstrap(data_dir)

    # Step 3: Launch Steam
    run_steam(data_dir)


if __name__ == "__main__":
    main()
