#!/usr/bin/env bash
# Most variables are assigned by the jq-driven eval below, which shellcheck cannot follow.
# shellcheck disable=SC2154
# Two-line Claude Code status line.
# Line 1: p10k Pure identity (dir, vcs, worktree, PR, venv)
# Line 2: session HUD (model, effort, context, cost, duration, last turn, diff, quota,
#         agent, vim mode, session name)

input=$(cat)

# p10k Pure 256-color palette, plus green for healthy meters.
GREY='\033[38;5;242m'
RED='\033[38;5;1m'
YELLOW='\033[38;5;3m'
GREEN='\033[38;5;2m'
BLUE='\033[38;5;4m'
MAGENTA='\033[38;5;5m'
CYAN='\033[38;5;6m'
BAR_EMPTY='\033[38;5;250m'
RESET='\033[0m'
SEP="${GREY} · ${RESET}"

# Every variable the rest of the script reads (cwd, model, cost_usd, ctx_size, ...) is
# assigned here; each value passes through jq's @sh, so it is quoted.
eval "$(printf '%s' "$input" | jq -r '
  def s: (. // "") | tostring | @sh;
  def n: (. // 0) | tostring | @sh;
  [
    "cwd=" + (.workspace.current_dir // .cwd | s),
    "transcript_path=" + (.transcript_path | s),
    "model=" + (.model.display_name | s),
    "effort=" + (.effort.level | s),
    "fast_mode=" + ((.fast_mode // false) | tostring | @sh),
    "used_pct=" + (if .context_window.used_percentage == null then "" else (.context_window.used_percentage | tostring) end | @sh),
    "ctx_size=" + (.context_window.context_window_size | n),
    "input_tokens=" + (.context_window.total_input_tokens | n),
    "cost_usd=" + (.cost.total_cost_usd | n),
    "duration_ms=" + (.cost.total_duration_ms | n),
    "lines_add=" + (.cost.total_lines_added | n),
    "lines_del=" + (.cost.total_lines_removed | n),
    "pr_number=" + (.pr.number | s),
    "pr_url=" + (.pr.url | s),
    "pr_review=" + (.pr.review_state | s),
    "rl5=" + (if .rate_limits.five_hour.used_percentage == null then "" else (.rate_limits.five_hour.used_percentage | tostring) end | @sh),
    "rl5_reset=" + (.rate_limits.five_hour.resets_at | n),
    "rl7=" + (if .rate_limits.seven_day.used_percentage == null then "" else (.rate_limits.seven_day.used_percentage | tostring) end | @sh),
    "agent=" + (.agent.name | s),
    "vim_mode=" + (.vim.mode | s),
    "session_name=" + (.session_name | s),
    "worktree=" + (.worktree.name // .workspace.git_worktree | s)
  ] | join("\n")
')"

abbrev_path() {
  local p="${1/#$HOME\//~/}"
  [[ $1 != "$HOME" ]] || p="~"
  local prefix="" rest="$p"
  # The literal "~" is the display prefix, not a path to expand.
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* ]]; then
    prefix="~"
    rest="${p:2}"
  elif [[ "$p" == /* ]]; then
    prefix=""
    rest="${p#/}"
  else
    printf '%s' "$p"
    return
  fi
  local -a segs
  IFS=/ read -r -a segs <<<"$rest"
  local n=${#segs[@]}
  if ((n <= 2)); then
    printf '%s' "$p"
    return
  fi
  local out="$prefix" i s
  for ((i = 0; i < n - 1; i++)); do
    s="${segs[i]}"
    [[ -z "$s" ]] && continue
    if [[ "$s" == .* ]]; then
      out+="/${s:0:2}"
    else
      out+="/${s:0:1}"
    fi
  done
  out+="/${segs[n - 1]}"
  printf '%s' "$out"
}

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

fmt_until() {
  local epoch=${1%.*} now d
  [[ -z "$epoch" || "$epoch" == 0 ]] && return
  now=$(date +%s)
  d=$((epoch - now))
  ((d < 0)) && d=0
  if ((d >= 3600)); then
    printf '%dh' $((d / 3600))
  elif ((d >= 60)); then
    printf '%dm' $((d / 60))
  else
    printf '%ds' "$d"
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

int_pct() {
  local v=${1%.*}
  printf '%s' "${v:-0}"
}

line1=()

if [[ -n "$cwd" ]]; then
  line1+=("$(printf '%b%s%b' "$BLUE" "$(abbrev_path "$cwd")" "$RESET")")
fi

branch="" dirty="" arrows=""
if [[ -n "$cwd" ]]; then
  if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
    if [[ -z "$branch" ]]; then
      branch="@$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)"
    fi
    if ! git -C "$cwd" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null; then
      dirty="*"
    fi
    upstream=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref '@{u}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
      read -r behind ahead <<<"$(git -C "$cwd" --no-optional-locks rev-list --left-right --count "$upstream...HEAD" 2>/dev/null)"
      [[ "${behind:-0}" -gt 0 ]] && arrows+="⇣${behind}"
      [[ "${ahead:-0}" -gt 0 ]] && arrows+="⇡${ahead}"
    fi
  fi
fi
if [[ -n "$branch" ]]; then
  vcs="${GREY}${branch}${dirty}${RESET}"
  [[ -n "$arrows" ]] && vcs+="${CYAN}${arrows}${RESET}"
  line1+=("$vcs")
fi

if [[ -n "$worktree" ]]; then
  line1+=("$(printf '%b[%s]%b' "$CYAN" "$worktree" "$RESET")")
fi

if [[ -n "$pr_number" ]]; then
  case "$pr_review" in
    approved) pr_color="$GREEN" ;;
    changes_requested) pr_color="$RED" ;;
    draft) pr_color="$GREY" ;;
    *) pr_color="$YELLOW" ;;
  esac
  pr_label="#${pr_number}"
  [[ -n "$pr_review" && "$pr_review" != "pending" ]] && pr_label+=" ${pr_review}"
  if [[ -n "$pr_url" ]]; then
    line1+=("$(printf '%b\033]8;;%s\a%s\033]8;;\a%b' "$pr_color" "$pr_url" "$pr_label" "$RESET")")
  else
    line1+=("$(printf '%b%s%b' "$pr_color" "$pr_label" "$RESET")")
  fi
fi

if [[ -n "$VIRTUAL_ENV" ]]; then
  line1+=("$(printf '%b%s%b' "$GREY" "$(basename "$VIRTUAL_ENV")" "$RESET")")
fi

line2=()

if [[ -n "$model" ]]; then
  line2+=("$(printf '%b%s%b' "$MAGENTA" "$model" "$RESET")")
fi

if [[ "$fast_mode" == "true" ]]; then
  line2+=("$(printf '%bfast%b' "$YELLOW" "$RESET")")
elif [[ -n "$effort" ]]; then
  line2+=("$(printf '%b%s%b' "$GREY" "$effort" "$RESET")")
fi

if [[ -n "$used_pct" ]]; then
  pct=$(int_pct "$used_pct")
  ctx="$(meter "$pct" 10) $(traffic "$pct")${pct}%${RESET}"
  if [[ -n "$input_tokens" && "$input_tokens" != 0 ]]; then
    ctx+="${GREY} $(fmt_tokens "$input_tokens")${RESET}"
  fi
  if ((ctx_size >= 1000000)); then
    ctx+="${GREY} 1M${RESET}"
  fi
  line2+=("$ctx")
else
  line2+=("$(printf '%b%s --%%%b' "$BAR_EMPTY" "░░░░░░░░░░" "$RESET")")
fi

cost_color="$GREY"
if awk -v c="$cost_usd" 'BEGIN { exit !(c + 0 >= 5) }' 2>/dev/null; then
  cost_color="$RED"
elif awk -v c="$cost_usd" 'BEGIN { exit !(c + 0 >= 1) }' 2>/dev/null; then
  cost_color="$YELLOW"
fi
if awk "BEGIN { exit !($cost_usd > 0) }" 2>/dev/null; then
  line2+=("$(printf '%b$%.2f%b' "$cost_color" "$cost_usd" "$RESET")")
fi

if [[ -n "$duration_ms" && "$duration_ms" != 0 ]]; then
  line2+=("$(printf '%b%s%b' "$GREY" "$(fmt_duration "$duration_ms")" "$RESET")")
fi

if [[ "${lines_add:-0}" != 0 || "${lines_del:-0}" != 0 ]]; then
  diff=""
  ((lines_add > 0)) && diff+="${GREEN}+${lines_add}${RESET}"
  ((lines_add > 0 && lines_del > 0)) && diff+=" "
  ((lines_del > 0)) && diff+="${RED}−${lines_del}${RESET}"
  line2+=("$diff")
fi

if [[ -n "$rl5" ]]; then
  rl5i=$(int_pct "$rl5")
  rl="$(traffic "$rl5i")5h ${rl5i}%${RESET}"
  until=$(fmt_until "$rl5_reset")
  [[ -n "$until" ]] && rl+="${GREY} ~${until}${RESET}"
  line2+=("$rl")
fi

cols=${COLUMNS:-120}
if [[ -n "$rl7" && "${cols:-0}" -ge 100 ]]; then
  rl7i=$(int_pct "$rl7")
  line2+=("$(printf '%b7d %s%%%b' "$(traffic "$rl7i")" "$rl7i" "$RESET")")
fi

if [[ -n "$agent" ]]; then
  line2+=("$(printf '%b%s%b' "$CYAN" "$agent" "$RESET")")
fi

if [[ -n "$vim_mode" ]]; then
  line2+=("$(printf '%b%s%b' "$GREY" "$vim_mode" "$RESET")")
fi

if [[ -n "$session_name" ]]; then
  line2+=("$(printf '%b%s%b' "$GREY" "$session_name" "$RESET")")
fi

join_spaces() {
  local out="" item
  for item in "$@"; do
    [[ -z "$item" ]] && continue
    [[ -n "$out" ]] && out+="  "
    out+="$item"
  done
  printf '%s' "$out"
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

printf '%b\n' "$(join_spaces "${line1[@]}")"
printf '%b\n' "$(join_dots "${line2[@]}")"
