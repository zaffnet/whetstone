#!/usr/bin/env python3
"""Report checker-suppression comments on given lines of a file.

Suppressions are read as comment tokens, not as raw line text, so the same words
inside a string literal are not a suppression and a directive is recognised
wherever the tokenizer says a comment is.

Usage: find-suppressions.py FILE[:LINE,LINE,...] ...
A file with no line list is read whole.
Exit status is 1 when a suppression is reported, 0 when clean.
"""

from __future__ import annotations

import io
import re
import sys
import tokenize
from pathlib import Path

# Every form the four checkers accept, including the file-level directives that
# silence a whole module: `# mypy: ignore-errors` disables the file, and
# `# pyright: reportAny=false` disables a rule for it.
_SUPPRESSION = re.compile(
    r"""^\#\s*(?:
        noqa
        | type:\s*ignore
        | ruff:\s*(?:noqa|isort:\s*skip)
        | mypy:\s*(?:ignore-errors|disable(?:-next)?-error-code|disallow|allow|no-)
        | pyright:\s*(?:ignore|basic|standard|strict|off|report[A-Za-z]+\s*=)
        | pyrefly:\s*(?:ignore|deprecated)
        | pylint:\s*disable
        | flake8:\s*noqa
        | isort:\s*skip
        | nopycln
        | coverage:\s*ignore
        | pragma:\s*no\s*cover
    )""",
    re.IGNORECASE | re.VERBOSE,
)


def _target(argument: str) -> tuple[Path, set[int] | None]:
    """Split FILE:LINE,LINE from a bare FILE.

    Rsplit on the last colon so a Windows drive letter or a colon in a directory
    name stays part of the path.
    """
    if ":" in argument:
        head, _, tail = argument.rpartition(":")
        if head != "" and re.fullmatch(r"\d+(?:,\d+)*", tail) is not None:
            return Path(head), {int(n) for n in tail.split(",")}
    return Path(argument), None


def suppressions(path: Path, lines: set[int] | None) -> list[tuple[int, str]]:
    try:
        source = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        # An unparseable file is the checkers' problem to report, not this one's.
        return []

    found: list[tuple[int, str]] = []
    for token in tokens:
        if token.type != tokenize.COMMENT:
            continue
        line = token.start[0]
        if lines is not None and line not in lines:
            continue
        if _SUPPRESSION.match(token.string.strip()) is not None:
            found.append((line, token.line.strip()))
    return found


def main(argv: list[str]) -> int:
    reports: list[str] = []
    for argument in argv:
        path, lines = _target(argument)
        reports.extend(f"  {path}:{line}  {text}" for line, text in suppressions(path, lines))
    if len(reports) == 0:
        return 0
    _ = sys.stdout.write("\n".join(reports) + "\n")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
