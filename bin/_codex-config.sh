#!/usr/bin/env bash
# Shared by the bin/ scripts that shell out to `codex exec`. Sourced, not executed; the
# shebang is there so check-shebang-scripts-are-executable keeps it 0755, the same shape
# as hooks/_common.sh. It is symlinked into ~/.local/bin beside its callers, so a caller
# finds it next to itself whether it was reached through the repo or through the symlink.
#
# Those scripts pass --ignore-user-config so a run cannot pick up hooks, plugins, skills or
# rules. That flag also drops the model and the proxy, which are not isolation concerns and
# which every script then had to restate -- three copies of `gpt-5.5` that went stale the
# day the machine moved on, and a proxy taken from $OPENAI_BASE_URL while interactive Codex
# used ~/.codex/config.toml. The two disagreed: the env var was the bare host, the config
# carried the /v1 suffix. Reading the config here means a script cannot reach an endpoint
# or a model that interactive Codex is not already using.

# Top-level keys only. Everything from the first [table] header on belongs to a table, and
# `model` appears inside tables too. awk rather than a TOML parser on purpose: tomllib needs
# Python 3.11 and the system python3 on macOS is 3.9, which is what broke bin/sync-mcp on a
# fresh Mac.
codex_config_value() {
  local key=$1
  local config="${CODEX_HOME:-$HOME/.codex}/config.toml"

  [[ -r $config ]] || return 0
  awk -v key="$key" '
    function is_table_header(line) {
      return line ~ /^[[:space:]]*\[\[?[^]]+\]\]?[[:space:]]*(#.*)?$/
    }
    multiline {
      if ($0 ~ multiline) multiline = ""
      next
    }
    # A bare, "quoted" or \047literal\047 key are the same key, as bin/sync-mcp and the Codex
    # modify script already treat them.
    $0 ~ "^[[:space:]]*[\"\047]?" key "[\"\047]?[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "")
      # A quoted value ends at its closing quote, so a trailing comment goes with it. An
      # escaped quote inside would defeat this; a model name or a URL does not contain one.
      if ($0 ~ /^"/) { sub(/^"/, ""); sub(/".*$/, "") }
      else if ($0 ~ /^\047/) { sub(/^\047/, ""); sub(/\047.*$/, "") }
      else { sub(/[[:space:]]*#.*$/, ""); sub(/[[:space:]]+$/, "") }
      print
      exit
    }
    {
      if (is_table_header($0)) exit
      if ($0 ~ /=[[:space:]]*"""([[:space:]]*(#.*)?)?$/) multiline = "\"\"\""
      else if ($0 ~ /=[[:space:]]*\047\047\047([[:space:]]*(#.*)?)?$/) multiline = "\047\047\047"
      else if (after_equals && $0 ~ /^[[:space:]]*"""/) multiline = "\"\"\""
      else if (after_equals && $0 ~ /^[[:space:]]*\047\047\047/) multiline = "\047\047\047"
      after_equals = ($0 ~ /=[[:space:]]*$/)
    }
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
