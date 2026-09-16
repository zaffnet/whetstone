# shellcheck shell=bash
# Sourced by statusline-command.sh and subagent-statusline.sh. The caller defines the
# colour variables and SEP these read: the two scripts print differently, one through
# printf '%b' on literal escapes and one on real escape bytes.

traffic() {
  local pct=${1%.*}
  pct=${pct:-0}
  if ((pct >= 90)); then
    printf '%s' "$RED"
  elif ((pct >= 70)); then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

meter() {
  local pct=${1%.*} width=${2:-10}
  pct=${pct:-0}
  ((pct < 0)) && pct=0
  ((pct > 100)) && pct=100
  local filled=$((pct * width / 100))
  local empty=$((width - filled))
  local out fill pad
  out="$(traffic "$pct")"
  if ((filled > 0)); then
    printf -v fill '%*s' "$filled" ''
    out+="${fill// /▓}"
  fi
  out+="${BAR_EMPTY}"
  if ((empty > 0)); then
    printf -v pad '%*s' "$empty" ''
    out+="${pad// /░}"
  fi
  printf '%s%s' "$out" "$RESET"
}

fmt_duration() {
  local sec=$((${1:-0} / 1000))
  if ((sec >= 3600)); then
    printf '%dh%dm' $((sec / 3600)) $(((sec % 3600) / 60))
  elif ((sec >= 60)); then
    printf '%dm' $((sec / 60))
  else
    printf '%ds' "$sec"
  fi
}

fmt_tokens() {
  local n=${1:-0}
  if ((n >= 1000000)); then
    printf '%d.%dM' $((n / 1000000)) $(((n % 1000000) / 100000))
  elif ((n >= 1000)); then
    printf '%dk' $((n / 1000))
  else
    printf '%s' "$n"
  fi
}

join_dots() {
  local out="" item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    [[ -n "$out" ]] && out+="$SEP"
    out+="$item"
  done
  printf '%s' "$out"
}
