#!/usr/bin/env python3
"""Verify the fetched source of each first-party pinned Phenix flake input.

A cached fixed-output store path is not proof that a changed GitHub revision
matches a retained narHash. Prefetch the exact revision without its narHash and
compare the resulting NAR hash with flake.lock.
"""

import json
import re
import subprocess
from pathlib import Path
from typing import Callable

INPUTS = {
    "phenix-ai": "phenix-ai",
    "phenix-ai-nvim": "phenix-ai.nvim",
}


def verify(lock: dict, prefetch_hash: Callable[[str], str]) -> list[str]:
    verified = []
    for node, repository in INPUTS.items():
        try:
            source = lock["nodes"][node]["locked"]
            owner = source["owner"]
            repo = source["repo"]
            rev = source["rev"]
            expected = source["narHash"]
        except (KeyError, TypeError) as exc:
            raise ValueError(f"{node}: incomplete locked source") from exc

        if source.get("type") != "github" or owner != "matthis-k" or repo != repository:
            raise ValueError(f"{node}: unexpected source repository")
        if not isinstance(rev, str) or re.fullmatch(r"[0-9a-f]{40}", rev) is None:
            raise ValueError(f"{node}: expected immutable full Git revision")
        if not isinstance(expected, str) or re.fullmatch(
            r"sha256-[A-Za-z0-9+/]{43}=", expected
        ) is None:
            raise ValueError(f"{node}: invalid NAR hash")

        url = f"github:{owner}/{repo}/{rev}"
        actual = prefetch_hash(url)
        if actual != expected:
            raise ValueError(
                f"{node}: {rev} resolves to {actual}, but flake.lock pins {expected}"
            )
        verified.append(f"{node}: {rev} {actual}")
    return verified


def nix_prefetch_hash(url: str) -> str:
    result = subprocess.run(
        ["nix", "flake", "prefetch", "--refresh", "--json", url],
        check=False,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Nix prefetch failed for {url}: {result.stderr.strip()}")
    value = json.loads(result.stdout)
    if not isinstance(value, dict) or not isinstance(value.get("hash"), str):
        raise RuntimeError(f"Nix prefetch returned no hash for {url}")
    return value["hash"]


def main() -> None:
    lock_file = Path(__file__).resolve().parent.parent / "flake.lock"
    lock = json.loads(lock_file.read_text(encoding="utf-8"))
    for line in verify(lock, nix_prefetch_hash):
        print(f"verified {line}")


if __name__ == "__main__":
    main()
