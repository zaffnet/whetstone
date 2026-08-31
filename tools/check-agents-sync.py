#!/usr/bin/env python3
"""Check that each reviewer subagent's Claude markdown and Codex TOML carry the same text.

Pairs: ``agents/<n>.md`` with ``codex/agents/<n>.toml``, and the template copies under
``template/project/.claude/agents`` and ``template/project/.codex/agents``. Template files
keep their Jinja as literal text; a TOML file whose body still contains the placeholder is
compared after rendering ``{{ package_name }}`` to a fixed token, so unescaped quotes or
backslashes in the TOML string are caught too.

Every key on both sides is accounted for, not just the two that used to be compared. The
pair in ``SAME`` must be identical; ``MD_ONLY`` and ``TOML_ONLY`` name what each side owns
alone. A key on none of the three is reported rather than ignored, so adding one to a
single side cannot pass unnoticed --
``name`` addresses the subagent, and the two halves used to be free to disagree about who
they are.
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

# Markdown frontmatter key -> Codex TOML key. Codex spells the effort differently; the rest
# pair by the same name.
SAME = {"name": "name", "description": "description", "effort": "model_reasoning_effort"}
# Claude Code's own, with no Codex counterpart: Codex takes the tool set and the model from
# its own config, and `opus` is a Claude model name that means nothing to it.
MD_ONLY = frozenset({"tools", "model"})
# Codex's own: the body lives in a key here rather than after the frontmatter.
TOML_ONLY = frozenset({"developer_instructions"})
MD_KEYS = frozenset(SAME) | MD_ONLY
TOML_KEYS = frozenset(SAME.values()) | TOML_ONLY
UNPAIRED_FIX = "put it in SAME if both halves must agree, or in {only} if this side owns it"


def split_markdown(text: str) -> tuple[dict[str, str], str]:
    """Frontmatter as a key -> value mapping, and the body."""
    match = FRONTMATTER.match(text)
    if match is None:
        msg = "missing frontmatter"
        raise ValueError(msg)
    front: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, separator, value = line.partition(":")
        if separator != "":
            front[key.strip()] = value.strip()
    return front, match.group(2).strip()


def agent_name(path: Path) -> str:
    """File stem without the .jinja suffix and any Jinja conditional around the name."""
    stem = path.name.removesuffix(".jinja")
    stem = JINJA_NAME.sub("", stem)
    return stem.removesuffix(".md").removesuffix(".toml")


def agent_gate(path: Path) -> str:
    """Return the Jinja conditional wrapped around the filename, or "" when there is none.

    agent_name() strips it so a gated file pairs with its twin. That is what lets
    ``{% if use_fastapi %}async-safety-reviewer.md{% endif %}.jinja`` find its TOML half --
    and, until this was compared, what let two halves gated on *different* conditions pair
    and report no problem, shipping half an agent.
    """
    return "".join(JINJA_NAME.findall(path.name))


def render(text: str) -> str:
    return text.replace("{{ package_name }}", "pkg")


def toml_str(data: dict[str, object], key: str) -> str:
    value = data.get(key, "")
    return str(value).strip()


def compare(md_path: Path, toml_path: Path) -> list[str]:
    problems: list[str] = []
    front, md_body = split_markdown(render(md_path.read_text()))
    data: dict[str, object]
    try:
        data = tomllib.loads(render(toml_path.read_text()))
    except tomllib.TOMLDecodeError as exc:
        return [f"{toml_path}: invalid TOML: {exc}"]

    md_gate = agent_gate(md_path)
    toml_gate = agent_gate(toml_path)
    if md_gate != toml_gate:
        md_condition = md_gate if md_gate != "" else "no condition"
        toml_condition = toml_gate if toml_gate != "" else "no condition"
        problems.append(
            f"{md_path}: rendered under {md_condition}, {toml_path} under {toml_condition}"
        )
    for path, keys, present, only in (
        (md_path, MD_KEYS, frozenset(front), "MD_ONLY"),
        (toml_path, TOML_KEYS, frozenset(data), "TOML_ONLY"),
    ):
        problems.extend(
            f"{path}: key {key!r} is compared against nothing; {UNPAIRED_FIX.format(only=only)}"
            for key in sorted(present - keys)
        )
        problems.extend(f"{path}: missing key {key!r}" for key in sorted(keys - present))
    for md_key, toml_key in SAME.items():
        md_value = front.get(md_key, "")
        toml_value = toml_str(data, toml_key)
        if md_value != toml_value:
            problems.append(
                f"{toml_path}: {toml_key} is {toml_value!r}, {md_path} {md_key} is {md_value!r}"
            )
    # `name` is what addresses the subagent, so it also has to be the name of the file the
    # agent is loaded from.
    if front.get("name", "") != agent_name(md_path):
        problems.append(f"{md_path}: name {front.get('name', '')!r} is not the file's name")

    toml_body = toml_str(data, "developer_instructions")
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
    return 1 if len(problems) > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
