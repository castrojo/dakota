#!/usr/bin/env python3
"""apply-xattrs.py — physically set user.component xattrs from filemap.json.

Reads usr/lib/chunkah/filemap.json from the rootfs (or a provided path) and
calls os.setxattr() on every listed file. This writes real kernel xattrs that
rustix-based tools (including chunkah) can read via raw syscalls.

Intended to run on a writable overlay of the OCI rootfs before chunkah is
invoked (see just chunkify).

TODO: remove this script and the overlay setup in chunkify once
coreos/chunkah#113 lands. Once chunkah falls back to libc for xattr reads,
an LD_PRELOAD sidecar can serve user.component without physically mutating
the rootfs.

Usage:
    sudo python3 apply-xattrs.py <rootfs> [filemap.json]
"""
from __future__ import annotations
import json, os, sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <rootfs> [filemap.json]", file=sys.stderr)
        return 1

    rootfs = Path(sys.argv[1])
    filemap_path = (Path(sys.argv[2]) if len(sys.argv) > 2
                    else rootfs / "usr/lib/chunkah/filemap.json")

    filemap: dict = json.loads(filemap_path.read_text())

    ok = skip = err = 0
    for element, info in filemap.items():
        for file_path in info.get("files", []):
            rel = file_path.lstrip("/")
            target = rootfs / rel
            if not target.exists() and not target.is_symlink():
                skip += 1
                continue
            try:
                os.setxattr(str(target), b"user.component",
                            element.encode(), follow_symlinks=False)
                interval = info.get("interval", "weekly")
                os.setxattr(str(target), b"user.update-interval",
                            interval.encode(), follow_symlinks=False)
                ok += 1
            except OSError as e:
                err += 1
                if err <= 5:
                    print(f"warn: {target}: {e}", file=sys.stderr)

    print(f"set {ok} xattrs, skipped {skip}, errors {err}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
