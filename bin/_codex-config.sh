#!/usr/bin/env bash

codex_config_value() {
  local key=$1
  local config="${CODEX_HOME:-$HOME/.codex}/config.toml"

  [[ -r $config ]] || return 0
  awk -v key="$key" '
    function end_of_string(line, i, quote,   n, c) {
      n = length(line)
      for (i++; i <= n; i++) {
        c = substr(line, i, 1)
        if (quote == "\"" && c == "\\") { i++; continue }
        if (c == quote) return i
      }
      return n
    }
    function scan(line,   i, n, c, three) {
      n = length(line)
      for (i = 1; i <= n; i++) {
        three = substr(line, i, 3)
        if (open != "") {
          if (three == open) { open = ""; i += 2 }
          continue
        }
        c = substr(line, i, 1)
        if (three == "\"\"\"" || three == "\047\047\047") { open = three; i += 2; continue }
        if (c == "#") return
        if (c == "\"" || c == "\047") { i = end_of_string(line, i, c); continue }
        if (c == "[" || c == "{") depth++
        else if ((c == "]" || c == "}") && depth > 0) depth--
      }
    }

    open == "" && depth == 0 && /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/ { exit }
    open == "" && depth == 0 && $0 ~ "^[[:space:]]*[\"\047]?" key "[\"\047]?[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      if ($0 ~ /^"/) { sub(/^"/, ""); sub(/".*$/, "") }
      else if ($0 ~ /^\047/) { sub(/^\047/, ""); sub(/\047.*$/, "") }
      else { sub(/[[:space:]]*#.*$/, ""); sub(/[[:space:]]+$/, "") }
      print
      exit
    }
    { scan($0) }
  ' "$config"
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
