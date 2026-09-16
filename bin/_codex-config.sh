#!/usr/bin/env bash

codex_config_value() {
  local config="${CODEX_HOME:-$HOME/.codex}/config.toml"

  [[ -r $config ]] || return 0
  # Both keys this reads are top-level scalars above the first [table], so stopping at
  # that line keeps a same-named key inside a table from matching. macOS system python3
  # is 3.9 and has no tomllib, and these scripts run outside uv.
  sed -n "/^\\[/q; s/^$1[[:space:]]*=[[:space:]]*\"\\(.*\\)\"[[:space:]]*\$/\\1/p" "$config" | head -1
}

require_command() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf "Required command '%s' was not found.\n" "$command_name" >&2
    exit 127
  fi
}

# Callers set TEMP_DIR before the trap that runs this.
cleanup() {
  rm -rf -- "$TEMP_DIR"
}

# Callers define usage().
usage_error() {
  printf '%s\n' "$1" >&2
  usage >&2
  exit 2
}

codex_model() {
  local fallback=${1:-gpt-5.6-sol}
  local value=${CODEX_MODEL:-}

  [[ -n $value ]] || value=$(codex_config_value model)
  printf '%s' "${value:-$fallback}"
}

codex_base_url() {
  local from_config
  from_config=$(codex_config_value openai_base_url)
  printf '%s' "${CODEX_BASE_URL:-${from_config:-${OPENAI_BASE_URL:-}}}"
}

CODEX_MAX_INPUT_CHARS=1048576

CODEX_MAX_DIFF_CHARS=$((CODEX_MAX_INPUT_CHARS / 2))

CODEX_DIFF_TRUNCATION_MARKER='[diff truncated; the file list above is complete]'
CODEX_PROMPT_TRUNCATION_MARKER='[prompt truncated; the file list above is complete]'

codex_bound_file() {
  local file=$1
  local limit=$2
  local marker=$3
  local budget=$((limit - ${#marker} - 1))

  if ((budget < 0)); then
    budget=0
  fi

  if (($(wc -m <"$file") <= limit)) && (($(wc -c <"$file") <= limit)); then
    cat "$file"
    return
  fi

  head -c "$budget" "$file"
  printf '\n%s' "$marker"
}

codex_cap_file() {
  local file=$1
  local limit=${2:-$CODEX_MAX_INPUT_CHARS}
  local marker=${3:-$CODEX_PROMPT_TRUNCATION_MARKER}
  local tmp

  if (($(wc -m <"$file") <= limit)) && (($(wc -c <"$file") <= limit)); then
    return
  fi

  tmp=$(mktemp "${file}.XXXXXX")
  codex_bound_file "$file" "$limit" "$marker" >"$tmp"
  mv "$tmp" "$file"
}

codex_bound_diff_from_file() {
  local file=$1
  local limit=${2:-$CODEX_MAX_DIFF_CHARS}

  codex_bound_file "$file" "$limit" "$CODEX_DIFF_TRUNCATION_MARKER"
}

codex_bound_diff() {
  local diff=$1
  local limit=${2:-$CODEX_MAX_DIFF_CHARS}
  local marker=$CODEX_DIFF_TRUNCATION_MARKER
  local budget=$((limit - ${#marker} - 1))

  if (($(printf '%s' "$diff" | wc -m) <= limit)) \
    && (($(printf '%s' "$diff" | wc -c) <= limit)); then
    printf '%s' "$diff"
    return
  fi

  diff=${diff:0:budget}
  while (($(printf '%s' "$diff" | wc -c) > budget)); do
    diff=${diff:0:$((${#diff} - ($(printf '%s' "$diff" | wc -c) - budget)))}
  done
  printf '%s\n%s' "$diff" "$marker"
}
