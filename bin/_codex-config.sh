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
  local fallback=${1:-gpt-5.5}
  local value=${CODEX_MODEL:-}

  [[ -n $value ]] || value=$(codex_config_value model)
  printf '%s' "${value:-$fallback}"
}

codex_base_url() {
  local from_config
  from_config=$(codex_config_value openai_base_url)
  printf '%s' "${CODEX_BASE_URL:-${from_config:-${OPENAI_BASE_URL:-}}}"
}
