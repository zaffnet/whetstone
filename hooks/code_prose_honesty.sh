#!/usr/bin/env bash
# Stop hook. Asks a headless Claude whether the comments, docstrings, and checker
# suppressions in this turn's Python diff are honest about the code, reports what it
# finds, and lets the turn end. Python only: the brief is written around `# noqa` and
# `# type: ignore`. Markdown and text files are prose_honesty.sh's business.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

HONESTY_NAME=code_prose_honesty
HONESTY_BRIEF=agents/code-honesty-auditor.md
HONESTY_GLOBS=('*.py' '*.pyi')
HONESTY_LEAD="Comment text that a later reader cannot use. Cut it. Where a finding
names one clause worth keeping, keep that clause and delete the rest; where it
names none, delete the whole comment. For a suppression, remove it and fix what
the checker reported.

Shrink a docstring rather than deleting it, or pre-commit will fail on a public
interface with none."

# shellcheck source-path=SCRIPTDIR source=_honesty.sh
source "${BASH_SOURCE[0]%/*}/_honesty.sh"
