#!/usr/bin/env bash
# Stop hook. The turn does not end while the type checkers fail or the diff adds a
# suppression comment. Both checks answer the same question -- is the work actually
# done -- so they report together and Claude gets one list.
#
# A suppression silences a checker instead of fixing what it found, which makes a
# green typecheck meaningless. Adding one is therefore a failure here even when
# every checker passes.
#
# Blocking is `{"decision": "block", "reason": ...}` on stdout. Claude Code sets
# stop_hook_active once it is already continuing because of a Stop hook, and gives
# up after 8 consecutive blocks; this hook checks the flag and stands down, so a
# problem Claude cannot fix costs one extra turn rather than eight.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

# Already continuing from a Stop hook: report nothing and let the turn end.
[[ "$(hook_field '.stop_hook_active // false')" == true ]] && exit 0

cwd="$(hook_field '.cwd // empty')"
[[ -n $cwd ]] || cwd="$PWD"
cd "$cwd" 2>/dev/null || exit 0

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# No Python in the repository means no opinion.
[[ -f pyproject.toml ]] || exit 0

problems=""
add() { problems+="$1"$'\n'; }

# The plugin copy when the plugin is installed, the project's own copy in a
# generated project, where CLAUDE_PLUGIN_ROOT is unset.
for candidate in \
  "${CLAUDE_PLUGIN_ROOT:-}/tools/find-suppressions.py" \
  "$root/tools/find-suppressions.py" \
  "${BASH_SOURCE[0]%/*}/../../tools/find-suppressions.py"; do
  [[ -f $candidate ]] && finder="$candidate" && break
done
[[ -n ${finder:-} ]] || exit 0

# --- Suppressions added by this session ------------------------------------
# The added lines (^+) of the working-tree diff, so a suppression that was
# already committed is not this session's to answer for. Untracked files have no
# diff, so they are read whole through --no-index against /dev/null, which exits
# non-zero whenever it prints anything; `|| true` keeps that from ending the hook.
#
# awk emits FILE:LINE,LINE for the finder, which reads comment tokens rather than
# raw line text: the same words inside a string literal are not a suppression.
targets="$(
  {
    git diff HEAD -U0 -- '*.py' '*.pyi' 2>/dev/null || true
    while IFS= read -r -d '' f; do
      git diff --no-index -U0 -- /dev/null "$f" 2>/dev/null || true
    done < <(git ls-files -z --others --exclude-standard -- '*.py' '*.pyi' 2>/dev/null)
  } | awk '
    /^\+\+\+ / {
      file = substr($0, 7)
      sub(/^b\//, "", file)
      # `git diff --no-index` pads the path with a tab, which would otherwise
      # become part of the filename.
      sub(/[ \t]+$/, "", file)
      next
    }
    /^@@/ {
      match($0, /\+[0-9]+/)
      line = substr($0, RSTART + 1, RLENGTH - 1) + 0
      next
    }
    /^\+/ {
      if (file != "") added[file] = (file in added ? added[file] "," line : line)
      line++
    }
    END { for (f in added) printf "%s:%s\n", f, added[f] }
  '
)"

suppressions=""
if [[ -n $targets ]]; then
  # A path is kept only if it is still a regular file: it can be deleted or
  # replaced between the diff and this read.
  present=()
  while IFS= read -r target; do
    [[ -f ${target%%:*} ]] && present+=("$target")
  done <<<"$targets"
  if ((${#present[@]})); then
    # Exit 0 is clean, 1 is findings, anything else is the finder failing to run:
    # reported on stderr rather than passing as clean, since a finder that cannot
    # start would otherwise silently retire this check.
    errfile="$(mktemp)"
    # `|| status=$?`, because `set -e` would abort on the assignment's own
    # nonzero status before it could be read, and exit 1 is the reporting case.
    status=0
    suppressions="$(python3 "$finder" "${present[@]}" 2>"$errfile")" || status=$?
    case "$status" in
      0 | 1) ;;
      *)
        {
          printf 'typecheck: the suppression finder failed; suppressions were not checked\n'
          cat "$errfile"
        } >&2
        suppressions=""
        ;;
    esac
    rm -f "$errfile"
  fi
fi

if [[ -n $suppressions ]]; then
  add "This diff adds suppression comments. A suppression hides the finding
instead of fixing it, so the checkers below prove nothing while these
are present. Remove each one and fix what the checker actually reported:"
  add "$suppressions"
fi

# --- Type checkers ---------------------------------------------------------
# The repository's own script wins, so a project can define its own tools and
# flags; whetstone's copy in bin/ is the fallback.
if [[ -x ./run-typecheck.sh ]]; then
  checker=(./run-typecheck.sh)
elif [[ -x "${CLAUDE_PLUGIN_ROOT:-}/bin/run-typecheck.sh" ]]; then
  checker=("${CLAUDE_PLUGIN_ROOT}/bin/run-typecheck.sh")
else
  checker=()
fi

if ((${#checker[@]})); then
  # Interleaved into one stream: a checker's complaint is on stdout or stderr
  # depending on the tool, and the report needs both.
  if ! output="$("${checker[@]}" 2>&1)"; then
    # A missing venv or uvx is the machine's problem, not the code's, so it is
    # reported without blocking. Any suppression found above still blocks: that
    # finding does not depend on the checkers having run.
    if [[ ${output} == *"Run: uv sync"* || ${output} == *"uvx not found"* ]]; then
      printf '%s\n' "$output" >&2
    else
      add "The type checkers failed. The work is not done until they pass.
Fix the root cause of every finding; do not silence a checker."
      add "$output"
    fi
  fi
fi

[[ -n $problems ]] || exit 0

jq -n --arg reason "$problems" '{decision: "block", reason: $reason}'
exit 0
