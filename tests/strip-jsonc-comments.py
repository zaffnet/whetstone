#!/usr/bin/env python3
"""Strip `//` comments from JSONC on stdin or argv[1], leaving strings alone.

Used by tests/home.bats to check that a merged settings.json parses. Deliberately simple:
it tracks string boundaries and escapes, and nothing else -- no keys, no depth -- so it is
independent of the merge logic it validates. `jq` cannot read comments, and CI installs no
node.
"""

import sys
from pathlib import Path


def strip(text: str) -> str:
    out: list[str] = []
    index = 0
    length = len(text)
    while index < length:
        if text[index] == '"':
            end = index + 1
            while end < length and text[end] != '"':
                end += 2 if text[end] == "\\" else 1
            out.append(text[index : end + 1])
            index = end + 1
        elif text[index : index + 2] == "//":
            newline = text.find("\n", index)
            index = length if newline < 0 else newline
        else:
            out.append(text[index])
            index += 1
    return "".join(out)


if __name__ == "__main__":
    text = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else sys.stdin.read()
    sys.stdout.write(strip(text))
