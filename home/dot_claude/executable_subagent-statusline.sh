#!/usr/bin/env bash
# Claude Code subagent status line: one NDJSON row override per visible task.
# p10k Pure palette, matching ~/.claude/statusline-command.sh.

input=$(cat)

# Real ESC bytes (ANSI-C quoting) so jq --arg embeds them correctly.
GREY=$'\033[38;5;242m'
RED=$'\033[38;5;1m'
YELLOW=$'\033[38;5;3m'
GREEN=$'\033[38;5;2m'
MAGENTA=$'\033[38;5;5m'
CYAN=$'\033[38;5;6m'
BAR_EMPTY=$'\033[38;5;250m'
RESET=$'\033[0m'
SEP="${GREY} · ${RESET}"

# shellcheck source-path=SCRIPTDIR source=statusline-lib.sh
source "${BASH_SOURCE[0]%/*}/statusline-lib.sh"

short_model() {
  local m=$1
  m=${m#claude-}
  m=${m%-latest}
  printf '%s' "$m"
}

visible_len() {
  local s=$1
  s=$(printf '%s' "$s" | sed -E $'s/\033\\[[0-9;]*m//g; s/\033\\]8;;[^\007]*\007//g')
  printf '%s' "${#s}"
}

truncate_desc() {
  local text=$1 max=$2
  ((max < 4)) && {
    printf '%s' ""
    return
  }
  local len=${#text}
  if ((len <= max)); then
    printf '%s' "$text"
    return
  fi
  printf '%s…' "${text:0:$((max - 1))}"
}

status_color() {
  case "$1" in
    running | in_progress | active | working) printf '%s' "$YELLOW" ;;
    completed | complete | done | success | succeeded) printf '%s' "$GREEN" ;;
    failed | error | cancelled | canceled) printf '%s' "$RED" ;;
    *) printf '%s' "$GREY" ;;
  esac
}

columns=$(printf '%s' "$input" | jq -r '.columns // 80')
now_ms=$(($(date +%s) * 1000))

while IFS= read -r task; do
  [[ -z "$task" ]] && continue

  # jq aborts the whole eval on a non-numeric field; start clean so a bad task
  # cannot borrow the previous one's values.
  id='' name='' task_status='' description='' label='' start_time='' model='' effort=''
  ctx_size=0 token_count=0
  eval "$(printf '%s' "$task" | jq -r '
    def s: (. // "") | tostring | @sh;
    def n: (. // 0) | tonumber | tostring | @sh;
    [
      "id=" + (.id | s),
      "name=" + (.name | s),
      "task_status=" + (.status | s),
      "description=" + (.description | s),
      "label=" + (.label | s),
      "start_time=" + (if .startTime == null then "" else (.startTime | tostring) end | @sh),
      "model=" + (.model | s),
      "effort=" + (if .effort == null then "" else (.effort | tostring) end | @sh),
      "ctx_size=" + (.contextWindowSize | n),
      "token_count=" + (.tokenCount | n)
    ] | join("\n")
  ')"

  [[ -z "$id" ]] && continue

  parts=()

  if [[ -n "$task_status" ]]; then
    parts+=("$(printf '%s[%s]%s' "$(status_color "$task_status")" "$task_status" "$RESET")")
  fi

  if [[ -n "$name" ]]; then
    parts+=("$(printf '%s%s%s' "$CYAN" "$name" "$RESET")")
  fi

  if [[ -n "$model" ]]; then
    parts+=("$(printf '%s%s%s' "$MAGENTA" "$(short_model "$model")" "$RESET")")
  fi

  if [[ -n "$effort" ]]; then
    parts+=("$(printf '%s%s%s' "$GREY" "$effort" "$RESET")")
  fi

  tokens=${token_count:-0}
  ctx=${ctx_size:-0}

  if ((ctx > 0)); then
    pct=$((tokens * 100 / ctx))
    ((pct > 100)) && pct=100
    ctx_seg="$(meter "$pct" 10) $(traffic "$pct")${pct}%${RESET}"
    if ((tokens > 0)); then
      ctx_seg+="${GREY} $(fmt_tokens "$tokens")${RESET}"
    fi
    parts+=("$ctx_seg")
  elif ((tokens > 0)); then
    parts+=("$(printf '%s%s%s' "$GREY" "$(fmt_tokens "$tokens")" "$RESET")")
  fi

  if [[ -n "$start_time" && "$start_time" != "0" ]]; then
    st=${start_time%.*}
    # Accept seconds or milliseconds epoch.
    if ((st < 100000000000)); then
      st=$((st * 1000))
    fi
    elapsed=$((now_ms - st))
    ((elapsed < 0)) && elapsed=0
    parts+=("$(printf '%s%s%s' "$GREY" "$(fmt_duration "$elapsed")" "$RESET")")
  fi

  prefix="$(join_dots "${parts[@]}")"
  prefix_len=$(visible_len "$prefix")

  desc=""
  if [[ -n "$description" ]]; then
    desc=$description
  elif [[ -n "$label" ]]; then
    desc=$label
  fi

  if [[ -n "$desc" ]]; then
    budget=$((columns - prefix_len - 3))
    ((budget < 8)) && budget=8
    desc_trunc=$(truncate_desc "$desc" "$budget")
    content="$(join_dots "$prefix" "$(printf '%s%s%s' "$GREY" "$desc_trunc" "$RESET")")"
  else
    content="$prefix"
  fi

  jq -nc --arg id "$id" --arg content "$content" '{id: $id, content: $content}'
done < <(printf '%s' "$input" | jq -c '(.tasks // [])[]')
