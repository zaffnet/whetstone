#!/usr/bin/env bash
# Shared preamble for the hook scripts in this directory. Source it right after
# the script's header comment:
#
#   source "${BASH_SOURCE[0]%/*}/_common.sh"
#
# It enables strict mode, reads the JSON hook payload from stdin once into
# HOOK_INPUT, and exposes hook_field for pulling fields out of the payload
# without re-reading stdin.
set -euo pipefail

HOOK_INPUT="$(cat)"

# hook_field <jq-filter>
# Print a field from the hook payload. Pass the full jq filter including any
# fallback, e.g. hook_field '.session_id // "nosession"' (string fallback) or
# hook_field '.tool_name // empty' (jq's empty keyword, prints nothing).
hook_field() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1"
}
