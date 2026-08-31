#!/usr/bin/env bash
# Shared preamble for the hook scripts in this directory:
#
#   source "${BASH_SOURCE[0]%/*}/_common.sh"
#
# Enables strict mode and consumes stdin: the JSON hook payload is read once into
# HOOK_INPUT, and hook_field reads fields from there rather than from stdin again.
set -euo pipefail

HOOK_INPUT="$(cat)"

# Takes the full jq filter including any fallback, e.g.
# hook_field '.session_id // "nosession"' (string fallback) or
# hook_field '.tool_name // empty' (jq's empty keyword, prints nothing).
hook_field() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1"
}
