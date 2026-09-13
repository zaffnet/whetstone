#!/usr/bin/env bash
# Shared by the bin/ scripts that shell out to `codex exec`. Sourced, not executed; the
# shebang is there so check-shebang-scripts-are-executable keeps it 0755. It is symlinked
# into ~/.local/bin beside its callers, so a caller finds it next to itself whether it was
# reached through the repo or through the symlink.
#
# Those scripts pass --ignore-user-config so a run cannot pick up hooks, plugins, skills or
# rules. That flag also drops the model and the proxy, which are not isolation concerns, so
# they are read back from the config here: a script cannot then reach an endpoint or a model
# that interactive Codex is not already using. Do not substitute $OPENAI_BASE_URL for the
# config value -- the env var is the bare host, the config carries the /v1 suffix.

# Top-level keys only. Everything from the first [table] header on belongs to a table, and
# `model` appears inside tables too. awk rather than a TOML parser: tomllib needs Python 3.11
# and the system python3 on macOS is 3.9.
#
# Finding that first header takes tracking where a value ends, not a per-line guess: an
# array element and a line inside a multiline string both look like a header on their own.
codex_config_value() {
  local key=$1
  local config="${CODEX_HOME:-$HOME/.codex}/config.toml"

  [[ -r $config ]] || return 0
  awk -v key="$key" '
    # A value stays on its key line unless it is an array, which runs until its brackets
    # balance, or a multiline string, which runs until its delimiter repeats. Comments and
    # quoted text are skipped, so a bracket inside either does not count.
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

    # The header shape is the one home/dot_codex/modify_private_config.toml.tmpl uses.
    open == "" && depth == 0 && /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/ { exit }
    # A bare, "quoted" or \047literal\047 key are the same key.
    open == "" && depth == 0 && $0 ~ "^[[:space:]]*[\"\047]?" key "[\"\047]?[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      # A quoted value ends at its closing quote, so a trailing comment goes with it. An
      # escaped quote inside would defeat this; a model name or a URL does not contain one.
      if ($0 ~ /^"/) { sub(/^"/, ""); sub(/".*$/, "") }
      else if ($0 ~ /^\047/) { sub(/^\047/, ""); sub(/\047.*$/, "") }
      else { sub(/[[:space:]]*#.*$/, ""); sub(/[[:space:]]+$/, "") }
      print
      exit
    }
    { scan($0) }
  ' "$config"
}

# Precedence: explicit environment, then the Codex config, then the argument as a last
# resort so a machine with no Codex config still runs.
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

# The API rejects an oversized request rather than truncating it, so a prompt that embeds a
# diff has to bound it first. One generated lockfile or vendored JSON tree exceeds this alone.
CODEX_MAX_INPUT_CHARS=1048576

# The diff is the only part of a prompt that scales with the change; the rest is small and
# bounded, so half the limit is a generous share.
CODEX_MAX_DIFF_CHARS=$((CODEX_MAX_INPUT_CHARS / 2))

# Without the marker a truncated diff reads as the whole change, and the model names a branch
# or writes a message for the part it saw.
CODEX_DIFF_TRUNCATION_MARKER='[diff truncated; the file list above is complete]'
CODEX_PROMPT_TRUNCATION_MARKER='[prompt truncated; the file list above is complete]'

# Write path $1 to stdout, cut to $2 characters and bytes (whichever is stricter) with
# marker $3 appended when cut. Reads the path; does not pass contents as argv.
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

  # head -c is bytes. Git diffs are ASCII-heavy; the byte cap is the stricter of the two.
  head -c "$budget" "$file"
  printf '\n%s' "$marker"
}

# Replace path $1 in place when it exceeds $2 (default: CODEX_MAX_INPUT_CHARS), using
# marker $3 (default: CODEX_PROMPT_TRUNCATION_MARKER).
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

# The limit counts characters, but bytes are the unit most transports measure, so the result
# stays under whichever is stricter.
#
# ${var:0:n} slices characters, not bytes, in a UTF-8 locale; `cut -c` counts per line and so
# bounds nothing on a multi-line diff. The loop covers mostly multi-byte text, where a
# character slice still leaves too many bytes.
#
# A ~2MB string as $1 hits ARG_MAX. Callers with a file must use
# codex_bound_diff_from_file instead of wrapping this in command substitution.
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
