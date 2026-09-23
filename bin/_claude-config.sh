#!/usr/bin/env bash

require_command() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf "Required command '%s' was not found.\n" "$command_name" >&2
    exit 127
  fi
}

cleanup() {
  rm -rf -- "$TEMP_DIR"
}

usage_error() {
  printf '%s\n' "$1" >&2
  usage >&2
  exit 2
}

claude_model() {
  printf '%s' "${CLAUDE_MODEL:-opus}"
}

CLAUDE_MAX_INPUT_CHARS=1048576

CLAUDE_MAX_DIFF_CHARS=$((CLAUDE_MAX_INPUT_CHARS / 2))

CLAUDE_DIFF_TRUNCATION_MARKER='[diff truncated; the file list above is complete]'
CLAUDE_PROMPT_TRUNCATION_MARKER='[prompt truncated; the file list above is complete]'

prompt_bound_file() {
  local file=$1
  local limit=$2
  local marker=$3
  local budget=$((limit - ${#marker} - 1))
  local bounded_file
  local utf8_file

  utf8_file=$(mktemp)
  LC_ALL=C iconv -c -f UTF-8 -t UTF-8 "$file" >"$utf8_file"

  if ((budget < 0)); then
    budget=0
  fi

  if (($(wc -c <"$utf8_file") <= limit)); then
    cat "$utf8_file"
    rm "$utf8_file"
    return
  fi

  bounded_file=$(mktemp)
  head -c "$budget" "$utf8_file" >"$bounded_file"
  cat "$bounded_file"
  printf '\n%s' "$marker"
  rm "$bounded_file" "$utf8_file"
}

prompt_cap_file() {
  local file=$1
  local limit=${2:-$CLAUDE_MAX_INPUT_CHARS}
  local marker=${3:-$CLAUDE_PROMPT_TRUNCATION_MARKER}
  local tmp

  tmp=$(mktemp "${file}.XXXXXX")
  prompt_bound_file "$file" "$limit" "$marker" >"$tmp"
  mv "$tmp" "$file"
}

prompt_bound_diff_from_file() {
  local file=$1
  local limit=${2:-$CLAUDE_MAX_DIFF_CHARS}

  prompt_bound_file "$file" "$limit" "$CLAUDE_DIFF_TRUNCATION_MARKER"
}

prompt_bound_diff() {
  local diff=$1
  local limit=${2:-$CLAUDE_MAX_DIFF_CHARS}
  local tmp

  tmp=$(mktemp)
  printf '%s' "$diff" >"$tmp"
  prompt_bound_diff_from_file "$tmp" "$limit"
  rm "$tmp"
}

claude_structured_output() {
  local schema_file=$1
  local prompt_file=$2
  local result_file=$3
  local effort=$4
  local response_file="${result_file}.response"
  local stderr_file="${result_file}.stderr"

  if ! claude -p \
    --output-format json \
    --json-schema "$(cat "$schema_file")" \
    --tools '' \
    --safe-mode \
    --strict-mcp-config \
    --no-session-persistence \
    --model "$CLAUDE_MODEL" \
    --effort "$effort" \
    <"$prompt_file" >"$response_file" 2>"$stderr_file"; then
    cat "$stderr_file" >&2
    return 1
  fi

  if ! jq -e '.structured_output | select(type == "object")' \
    "$response_file" >"$result_file"; then
    jq -r '.result // "Claude did not return structured output."' \
      "$response_file" >&2
    return 1
  fi
}
