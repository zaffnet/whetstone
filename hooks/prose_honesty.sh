#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

HONESTY_NAME=prose_honesty
HONESTY_BRIEF=agents/prose-honesty-auditor.md
HONESTY_GLOBS=('*.md' '*.markdown' '*.rst' '*.txt' '*.html' '*.htm')
HONESTY_SHEBANG_GLOBS=()
HONESTY_LEAD="The turn that just ended changed some prose. Cut the parts a reader
arriving next year cannot use. Where a finding names one clause worth keeping, keep
that clause and delete the rest. Where it names none, delete the whole sentence or
section. The line numbers come from that turn and may have moved, so re-read the file
before you edit it."

# shellcheck source-path=SCRIPTDIR source=_honesty.sh
source "${BASH_SOURCE[0]%/*}/_honesty.sh"
