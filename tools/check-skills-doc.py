#!/usr/bin/env python3
"""Check that ``docs/skills.md`` lists exactly the skills this repo writes and installs.

Two sources own the truth and the doc only reports them: the directories under ``skills/``,
and the ``owner/repo skill ...`` lines in ``home/dot_agents/skills.txt``. Each names a set of
skills; each has its own table in the doc, matched by the section heading. A skill missing a
row, or a row naming a skill neither source produces, is the drift this catches -- the doc is
hand-written, so nothing else notices when a skill is added and the table is not.

The plugin table is not checked. A plugin's skill set is versioned upstream, so there is no
file here to compare it against.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "docs" / "skills.md"
SKILLS_DIR = ROOT / "skills"
SKILLS_TXT = ROOT / "home" / "dot_agents" / "skills.txt"

# The doc's headings, and where each section's rows end: the next heading, or the end.
WRITTEN_HERE = "## Written here"
INSTALLED = "## Installed from elsewhere"
FROM_PLUGINS = "## From plugins"
# A row's first cell, when it holds a single backticked name. Rows whose first cell is prose
# (the `superpowers` row says its set is not enumerated) yield no name and are ignored.
ROW_NAME = re.compile(r"^\|\s*`([^`]+)`\s*\|")


def section(text: str, start: str, end: str | None) -> str:
    """Return the doc between two headings. Raises if `start` is missing."""
    head = text.index(start) + len(start)
    tail = text.index(end, head) if end is not None else len(text)
    return text[head:tail]


def row_names(block: str) -> set[str]:
    return {match.group(1) for line in block.splitlines() if (match := ROW_NAME.match(line))}


def txt_skills(path: Path) -> tuple[set[str], list[str]]:
    """Return every skill named in skills.txt, and a problem per line that names none.

    A line of just ``owner/repo`` is a form the installer supports: it expands to every
    skill in that repo. What that set contains is only knowable from the network, so a
    table row for it cannot be verified here. Rather than pass such a line silently --
    which would let the whole repo go missing from the doc -- it is reported, and the
    fix is to list the skills the line means.
    """
    names: set[str] = set()
    problems: list[str] = []
    for number, line in enumerate(path.read_text().splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        repo, *skills = stripped.split()
        if not skills:
            problems.append(
                f"{path}:{number}: {repo} names no skills, so it means every skill in the "
                f"repo and this check cannot tell what those are; name them here"
            )
        names.update(skills)
    return names, problems


def compare(label: str, listed: set[str], actual: set[str]) -> list[str]:
    return [
        *(f"{DOC}: {label} table has no row for {name!r}" for name in sorted(actual - listed)),
        *(
            f"{DOC}: {label} table names {name!r}, which no source produces"
            for name in sorted(listed - actual)
        ),
    ]


def main() -> int:
    text = DOC.read_text()
    written = row_names(section(text, WRITTEN_HERE, INSTALLED))
    installed = row_names(section(text, INSTALLED, FROM_PLUGINS))
    on_disk = {p.name for p in SKILLS_DIR.iterdir() if (p / "SKILL.md").is_file()}
    in_txt, problems = txt_skills(SKILLS_TXT)

    problems += compare("written-here", written, on_disk) + compare(
        "installed-from-elsewhere", installed, in_txt
    )
    for problem in problems:
        print(problem, file=sys.stderr)  # noqa: T201  -- CLI report
    counted = len(on_disk) + len(in_txt)
    print(f"check-skills-doc: {counted} skills checked, {len(problems)} problems")  # noqa: T201  -- CLI report
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
