#!/usr/bin/env bash
# Stop hook. Asks a headless Claude whether the comments, docstrings, and checker
# suppressions in this session's Python diff are honest about the code, and blocks
# the turn while they are not. Python only: the auditor's brief is written around
# `# noqa` and `# type: ignore`.
#
# It never edits a file: it reports, and Claude makes the edit.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

# awk, not sed: the BSD sed on macOS rejects the address form this needs.
strip_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { in_fm = 0; next }
    !in_fm { print }
  ' "$1"
}

# stop_hook_active is deliberately not consulted: the findings are reported again on
# every stop for as long as the comments are still there. Standing down on the second
# pass would make the block cheaper to wait out than to answer.

if ! command -v claude >/dev/null 2>&1; then
  printf 'audit_comments: claude was not found; comments were not checked\n' >&2
  exit 0
fi

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# Guarded with :+ because unset, the first entry would be the absolute path
# /agents/code-honesty-auditor.md. An empty candidate falls through to the next.
for candidate in \
  "${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/agents/code-honesty-auditor.md}" \
  "$root/.claude/agents/code-honesty-auditor.md" \
  "${BASH_SOURCE[0]%/*}/../agents/code-honesty-auditor.md"; do
  [[ -f $candidate ]] && brief="$candidate" && break
done
[[ -n ${brief:-} ]] || exit 0

# Before the first commit there is no HEAD to diff against, and staged files are not
# untracked either, so that state reaches neither command below. The empty tree
# stands in for the absent commit.
base=HEAD
git rev-parse --verify -q HEAD >/dev/null \
  || base="$(git hash-object -t tree /dev/null)"

# Tracked changes plus untracked files, as one patch. --no-color and no pager so the
# model reads the diff and not terminal escapes. Untracked files have no diff, so they
# go through --no-index against /dev/null, which exits non-zero whenever it prints
# anything -- hence the `|| true`.
diff_text="$(
  {
    git --no-pager diff "$base" --no-color -U3 -- '*.py' '*.pyi' 2>/dev/null || true
    while IFS= read -r -d '' f; do
      git --no-pager diff --no-index --no-color -U3 -- /dev/null "$f" 2>/dev/null || true
    done < <(git ls-files -z --others --exclude-standard -- '*.py' '*.pyi' 2>/dev/null)
  }
)"
[[ -n $diff_text ]] || exit 0

# A rewrite this large is reviewed by a person rather than by this.
if (($(wc -l <<<"$diff_text") > 4000)); then
  printf 'audit_comments: diff over 4000 lines; not audited\n' >&2
  exit 0
fi

# --setting-sources "" and --strict-mcp-config keep this machine's settings, MCP
# servers, and CLAUDE.md out of the subprocess: none of them bear on the question, and
# loading them costs.
# --tools "" with --max-turns 1: the diff is on stdin, so the answer is one message.
# With any tool enabled the model can spend the single turn on it and return nothing.
# --allowed-tools "" is not a substitute -- it grants the full set.
errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT

status=0
envelope="$(
  printf 'Audit this diff and reply with the JSON described in your instructions.\n\n%s\n' "$diff_text" \
    | claude -p \
      --model sonnet \
      --output-format json \
      --max-turns 1 \
      --strict-mcp-config \
      --setting-sources "" \
      --tools "" \
      --append-system-prompt "$(strip_frontmatter "$brief")" \
      2>"$errfile"
)" || status=$?

# Exit 0 is an answer; anything else is the call failing to complete. A failure
# is reported and does not block: a checker that cannot run must not hold a turn, but
# must not pass as a clean audit either.
if ((status != 0)); then
  {
    printf 'audit_comments: the auditor did not run (exit %s); comments were not checked\n' "$status"
    head -c 2000 "$errfile"
  } >&2
  exit 0
fi

# --output-format json returns the event stream as an array, the result last. Guarded
# because a zero-exit claude can still leave unparseable stdout behind, and set -e
# would otherwise end the hook on the failing jq, without the message below.
result="$(jq -c 'if type == "array" then .[-1] else . end' <<<"$envelope" 2>/dev/null)" || result=""

if [[ -z $result ]]; then
  printf "audit_comments: the auditor's output did not parse; comments were not checked\n" >&2
  exit 0
fi

# The envelope reports its own failures in is_error, with the text in result.
if [[ "$(jq -r '.is_error // false' <<<"$result" 2>/dev/null)" != false ]]; then
  {
    printf 'audit_comments: the auditor reported an error; comments were not checked\n'
    jq -r '.result // empty' <<<"$result" 2>/dev/null | head -c 2000
  } >&2
  exit 0
fi

# Anything but a findings array -- prose, or JSON of another shape -- is a failure to
# follow the format, not a clean audit. Fenced output is tolerated. The type is checked
# because `length` is defined on objects and strings too: {"findings": {}} would
# otherwise read as nothing to report.
findings="$(
  jq -r '.result // empty' <<<"$result" \
    | sed -e '/^[[:space:]]*```/d' \
    | jq -c 'if (.findings | type) == "array" then .findings else empty end' 2>/dev/null
)" || findings=""

if [[ -z $findings ]]; then
  printf 'audit_comments: the auditor did not answer with a findings array; comments were not checked\n' >&2
  exit 0
fi

count="$(jq -r 'length' <<<"$findings")"
((count > 0)) || exit 0

report="$(jq -r '.[] | "  \(.file):\(.line)  \(.why)"' <<<"$findings")"

reason="Comment text that a later reader cannot use. Cut it. Where a finding
names one clause worth keeping, keep that clause and delete the rest; where it
names none, delete the whole comment. For a suppression, remove it and fix what
the checker reported.

Shrink a docstring rather than deleting it, or pre-commit will fail on a public
interface with none.

$report"

jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
