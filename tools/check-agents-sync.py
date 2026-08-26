#!/usr/bin/env python3
"""Check that each reviewer subagent's Claude markdown and Codex TOML carry the same text.

Pairs: ``agents/<n>.md`` with ``codex/agents/<n>.toml``, and the template copies under
``template/project/.claude/agents`` and ``template/project/.codex/agents``. The TOML's
``description`` must equal the markdown frontmatter description, and ``developer_instructions``
must equal the markdown body. Template files keep their Jinja as literal text; a TOML file
whose body still contains the placeholder is compared after rendering ``{{ package_name }}``
to a fixed token, so unescaped quotes or backslashes in the TOML string are caught too.
"""

from __future__ import annotations

import difflib
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAIRS = (
    (ROOT / "agents", ROOT / "codex" / "agents"),
    (
        ROOT / "template" / "project" / ".claude" / "agents",
        ROOT / "template" / "project" / ".codex" / "agents",
    ),
)
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n(.*)\Z", re.DOTALL)
JINJA_NAME = re.compile(r"\{%.*?%\}")


def split_markdown(text: str) -> tuple[str, str]:
    match = FRONTMATTER.match(text)
    if match is None:
        msg = "missing frontmatter"
        raise ValueError(msg)
    description = ""
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        if key.strip() == "description":
            description = value.strip()
    return description, match.group(2).strip()


def agent_name(path: Path) -> str:
    """File stem without the .jinja suffix and any Jinja conditional around the name."""
    stem = path.name.removesuffix(".jinja")
    stem = JINJA_NAME.sub("", stem)
    return stem.removesuffix(".md").removesuffix(".toml")


def render(text: str) -> str:
    return text.replace("{{ package_name }}", "pkg")


def compare(md_path: Path, toml_path: Path) -> list[str]:
    problems: list[str] = []
    md_description, md_body = split_markdown(render(md_path.read_text()))
    try:
        data = tomllib.loads(render(toml_path.read_text()))
    except tomllib.TOMLDecodeError as exc:
        return [f"{toml_path}: invalid TOML: {exc}"]
    if data.get("description", "").strip() != md_description:
        problems.append(f"{toml_path}: description differs from {md_path}")
    toml_body = str(data.get("developer_instructions", "")).strip()
    if toml_body != md_body:
        diff = difflib.unified_diff(
            md_body.splitlines(),
            toml_body.splitlines(),
            fromfile=str(md_path),
            tofile=str(toml_path),
            lineterm="",
            n=1,
        )
        problems.append("\n".join(diff))
    return problems


def main() -> int:
    problems: list[str] = []
    checked = 0
    for md_dir, toml_dir in PAIRS:
        toml_by_name = {agent_name(p): p for p in toml_dir.glob("*.toml*")}
        for md_path in sorted(md_dir.glob("*.md*")):
            name = agent_name(md_path)
            toml_path = toml_by_name.pop(name, None)
            if toml_path is None:
                problems.append(f"{md_path}: no Codex TOML twin in {toml_dir}")
                continue
            problems.extend(compare(md_path, toml_path))
            checked += 1
        problems.extend(f"{p}: no markdown twin in {md_dir}" for p in toml_by_name.values())
    if checked == 0:
        problems.append("no agent pairs found; check PAIRS")
    for problem in problems:
        print(problem, file=sys.stderr)  # noqa: T201  -- CLI report
    print(f"check-agents-sync: {checked} pairs checked, {len(problems)} problems")  # noqa: T201  -- CLI report
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
