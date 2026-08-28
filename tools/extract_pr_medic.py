#!/usr/bin/env python3
"""Extract marked jq/bash regions from .github/workflows/pr-medic.yml.

Markers are ``# BEGIN <name>`` / ``# END <name>`` inside ``run:`` blocks. YAML
indent is stripped so the region is valid jq or bash on its own.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "pr-medic.yml"
JQ_MARKERS = ("pr-medic-gate.jq", "pr-medic-pick.jq")
SH_MARKERS = ("pr-medic-preflight.sh", "pr-medic-after.sh")


def _err(msg: str) -> None:
    print(msg, file=sys.stderr)  # noqa: T201  -- CLI report


def extract(name: str, text: str | None = None) -> list[str]:
    """Return every copy of a named region, dedented."""
    if text is None:
        text = WORKFLOW.read_text()
    start, end = f"# BEGIN {name}", f"# END {name}"
    parts: list[str] = []
    i = 0
    while True:
        a = text.find(start, i)
        if a < 0:
            break
        b = text.find(end, a)
        if b < 0:
            missing_end = f"{name}: BEGIN without END"
            raise SystemExit(missing_end)
        chunk = text[a : b + len(end)]
        lines = chunk.splitlines(keepends=True)
        inds = [len(line) - len(line.lstrip(" ")) for line in lines if line.strip()]
        n = min(inds) if inds else 0
        parts.append("".join(line[n:] if len(line) >= n else line for line in lines))
        i = b + len(end)
    return parts


def check() -> int:
    """Identical copies, jq compiles, shellcheck on extracted bash."""
    text = WORKFLOW.read_text()
    jq = shutil.which("jq")
    shellcheck = shutil.which("shellcheck")
    errors = 0
    for name in JQ_MARKERS + SH_MARKERS:
        parts = extract(name, text)
        if not parts:
            _err(f"{name}: missing")
            errors += 1
            continue
        if any(p != parts[0] for p in parts):
            _err(f"{name}: copies differ")
            errors += 1
        if name.endswith(".jq"):
            if jq is None:
                _err("jq: not on PATH")
                errors += 1
                continue
            proc = subprocess.run(  # noqa: S603  -- jq from PATH, stdin is this repo's workflow
                [jq, "-n", "-f", "/dev/stdin"],
                input=parts[0],
                capture_output=True,
                text=True,
                check=False,
            )
            if "syntax error" in proc.stderr:
                _err(f"{name}: jq will not parse\n{proc.stderr}")
                errors += 1
        else:
            if shellcheck is None:
                _err("shellcheck: not on PATH")
                errors += 1
                continue
            proc = subprocess.run(  # noqa: S603  -- shellcheck from PATH, stdin is this repo's workflow
                [shellcheck, "-s", "bash", "-"],
                input=parts[0],
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode != 0:
                _err(f"{name}: shellcheck\n{proc.stdout}{proc.stderr}")
                errors += 1
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "name",
        nargs="?",
        help="print the first copy of this marker (e.g. pr-medic-gate.jq)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="assert copies match, jq parses, and shellcheck passes",
    )
    args = parser.parse_args()
    if args.check:
        n = check()
        if n:
            _err(f"{n} problem(s)")
            return 1
        return 0
    if not args.name:
        parser.error("name or --check is required")
    parts = extract(args.name)
    if not parts:
        _err(f"{args.name}: missing")
        return 1
    sys.stdout.write(parts[0] if parts[0].endswith("\n") else parts[0] + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
