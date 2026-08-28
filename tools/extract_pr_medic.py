#!/usr/bin/env python3
"""Extract marked regions from pr-medic.yml, and render the template copy from it.

Markers are ``# BEGIN <name>`` / ``# END <name>`` inside ``run:`` blocks. A region is
sliced from the start of the BEGIN line, so the common YAML indent can be stripped and the
result is valid jq or bash on its own. Regions may nest: ``pr-medic-common.jq`` sits inside
both ``pr-medic-gate.jq`` and ``pr-medic-pick.jq``, and jq reads the marker lines as
comments.

The template copy is not byte-identical: it ships disarmed, and ``workflow_run`` names a
generated project's workflows rather than this repo's. TEMPLATE_SUBSTITUTIONS is the whole
of that difference, and ``--sync`` regenerates the copy so it cannot drift.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "pr-medic.yml"
TEMPLATE = ROOT / "template" / "project" / ".github" / "workflows" / "pr-medic.yml"

# How many copies of each region the file must hold. Asserting the count is what catches a
# deleted or misspelt marker: a bare "at least one" check passes on half a two-copy region
# and lets the unextracted half drift or hold invalid jq.
EXPECTED_COPIES = {
    "pr-medic-common.jq": 2,  # inside pr-medic-pick.jq and pr-medic-gate.jq
    "pr-medic-checks.jq": 2,  # the pick step and the medic step
    "pr-medic-gate.jq": 1,
    "pr-medic-pick.jq": 1,
    "pr-medic-preflight.sh": 1,
    "pr-medic-after.sh": 1,
}
# (line in the root copy, line in the template copy). Every difference between the two
# files lives here. A generated project should not merge on its own until its owner says so.
TEMPLATE_SUBSTITUTIONS = (
    (
        '    workflows: ["lint", "macos", "secrets", "template", "CodeQL"]',
        '    workflows: ["CI"]',
    ),
    (
        '  ARM_AUTO_MERGE: "true"',
        '  ARM_AUTO_MERGE: "false"                # opt in when this repo has a ruleset',
    ),
    (
        '  DRY_RUN: "false"                       # true = decide and report, change nothing',
        '  DRY_RUN: "true"                        # true = decide and report, change nothing',
    ),
)


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
        # From the start of the BEGIN line, not from the marker: slicing at the marker left
        # the first line at zero indent, so min() below was always 0 and nothing dedented.
        chunk = text[text.rfind("\n", 0, a) + 1 : b + len(end)]
        lines = chunk.splitlines(keepends=True)
        inds = [len(line) - len(line.lstrip(" ")) for line in lines if line.strip()]
        n = min(inds) if inds else 0
        parts.append("".join(line[n:] if len(line) >= n else line for line in lines))
        i = b + len(end)
    return parts


def render_template(text: str) -> str:
    """Return the template copy of the workflow, from the root copy."""
    for root_line, template_line in TEMPLATE_SUBSTITUTIONS:
        if text.count(root_line + "\n") != 1:
            missing = f"template substitution has no unique match: {root_line!r}"
            raise SystemExit(missing)
        text = text.replace(root_line + "\n", template_line + "\n", 1)
    return text


def check_template(text: str, *, write: bool) -> int:
    """Compare (or rewrite) the template copy. Rewriting is an error, like ruff --fix."""
    want = render_template(text)
    have = TEMPLATE.read_text() if TEMPLATE.exists() else ""
    if have == want:
        return 0
    if write:
        TEMPLATE.write_text(want)
        _err(f"{TEMPLATE.relative_to(ROOT)}: rewritten from the root copy; review and stage it")
    else:
        _err(f"{TEMPLATE.relative_to(ROOT)}: does not match the root copy; run --sync")
    return 1


def check(text: str) -> int:
    """Check copy counts, that copies match, that jq parses, and shellcheck."""
    jq = shutil.which("jq")
    shellcheck = shutil.which("shellcheck")
    errors = 0
    for name, expected in EXPECTED_COPIES.items():
        parts = extract(name, text)
        if len(parts) != expected:
            _err(f"{name}: found {len(parts)} copies, expected {expected}")
            errors += 1
            if not parts:
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
        help="assert copy counts, copies match, jq parses, and shellcheck passes",
    )
    parser.add_argument(
        "--check-template",
        action="store_true",
        help="assert the template copy matches the root copy through the substitutions",
    )
    parser.add_argument(
        "--sync",
        action="store_true",
        help="--check, then rewrite the template copy from the root copy",
    )
    args = parser.parse_args()
    if args.check or args.check_template or args.sync:
        text = WORKFLOW.read_text()
        n = 0
        if args.check or args.sync:
            n += check(text)
        if args.check_template or args.sync:
            n += check_template(text, write=args.sync)
        if n:
            _err(f"{n} problem(s)")
            return 1
        return 0
    if not args.name:
        parser.error("name, --check, --check-template or --sync is required")
    parts = extract(args.name)
    if not parts:
        _err(f"{args.name}: missing")
        return 1
    sys.stdout.write(parts[0] if parts[0].endswith("\n") else parts[0] + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
