#!/usr/bin/env bash
# Stop hook, backgrounded through "asyncRewake": true. Asks a headless Claude whether
# the prose in the ending turn's markdown and text diff -- READMEs, design docs, ADRs,
# handbook pages -- is honest, and reports what it finds at the start of the next turn
# without delaying this one. Comments and docstrings in code are
# code_prose_honesty.sh's business.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

HONESTY_NAME=prose_honesty
HONESTY_BRIEF=agents/prose-honesty-auditor.md
HONESTY_GLOBS=('*.md' '*.markdown' '*.rst' '*.txt')
HONESTY_LEAD="Prose a reader arriving next year cannot use, in what the turn that just
ended changed. Cut it. Where a finding names one clause worth keeping, keep that clause
and delete the rest; where it names none, delete the whole sentence or section.
Line numbers are from that turn and may have shifted; re-read before editing."

# shellcheck source-path=SCRIPTDIR source=_honesty.sh
source "${BASH_SOURCE[0]%/*}/_honesty.sh"
