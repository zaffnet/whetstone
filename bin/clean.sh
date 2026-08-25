#!/usr/bin/env bash
set -euo pipefail

# Removes build and tool detritus from a working tree.
#
# Matches an allowlist of names that are junk by construction. It never consults
# git: .git/info/exclude and .gitignore often hide valuable untracked files
# (local notes, agent config, reference data), so "ignored" is not "disposable".
#
# Lists what it would remove and exits without deleting unless given --apply.

usage() {
  cat <<'USAGE'
Usage: clean.sh [--apply] [--venv] [PATH...]

  (no flags)  List what would be deleted, with sizes and a total. Deletes nothing.
  --apply     Delete the listed paths.
  --venv      Also treat .venv/ as junk. Off by default: recovery costs a full
              uv sync, and every pre-commit hook shells through uv run.
  PATH...     Roots to clean. Defaults to the current directory.
USAGE
}

junk_dirs=(
  '__pycache__'
  '.mypy_cache'
  '.ruff_cache'
  '.pytest_cache'
  '.pyrefly_cache'
  '.hypothesis'
  '.tox'
  '.nox'
  '.eggs'
  '.ipynb_checkpoints'
  'htmlcov'
  'build'
  'dist'
  '*.egg-info'
  'node_modules'
  '__MACOSX'
)

junk_files=(
  '*.pyc'
  '*.pyo'
  '*.pyd'
  '.DS_Store'
  '._*'
  'Thumbs.db'
  'desktop.ini'
  '.Spotlight-V100'
  '.Trashes'
  '.coverage'
  '.coverage.*'
  'coverage.xml'
  '*.orig'
  '*.rej'
  '*.bak'
  '*~'
  '.*.sw[a-p]'
)

apply=0
clean_venv=0
roots=()

while (($# > 0)); do
  case "$1" in
    --apply) apply=1 ;;
    --venv) clean_venv=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      printf 'clean.sh: unknown option %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *) roots+=("$1") ;;
  esac
  shift
done

((${#roots[@]} > 0)) || roots=(.)

for root in "${roots[@]}"; do
  if [[ ! -d $root ]]; then
    printf 'clean.sh: not a directory: %s\n' "$root" >&2
    exit 2
  fi
  resolved=$(cd "$root" && pwd -P)
  if [[ $resolved == / || $resolved == "$HOME" ]]; then
    printf 'clean.sh: refusing to clean %s\n' "$resolved" >&2
    exit 2
  fi
done

# Builds "( -name A -o -name B ... )" in name_group. Every pattern stays quoted:
# an unquoted -name *.pyc would be glob-expanded against the invoking directory
# before find ever saw it. The result lands in a global because bash 3.2, the
# version macOS ships, has neither namerefs nor a way to return an array.
name_group=()
build_name_group() {
  local pattern
  name_group=('(')
  for pattern in "$@"; do
    ((${#name_group[@]} == 1)) || name_group+=('-o')
    name_group+=('-name' "$pattern")
  done
  name_group+=(')')
}

# Directories every find pass refuses to enter. .venv moves from the protected
# list to the junk list under --venv, so it is deleted whole rather than walked:
# descending into it would strip caches out of site-packages instead.
protected_names=('.git')
if ((clean_venv == 1)); then
  junk_dirs+=('.venv')
else
  protected_names+=('.venv')
fi
build_name_group "${protected_names[@]}"
protect=("${name_group[@]}" '-prune')

build_name_group "${junk_dirs[@]}"
dir_group=("${name_group[@]}")

build_name_group "${junk_files[@]}"
file_group=("${name_group[@]}")

# Junk directories are pruned as well as printed, so a doomed tree is named once
# and never descended into. Log files are junk; the logs/ directory itself is
# not, so it survives the empty-directory pass below.
select_junk() {
  local root=$1

  find "$root" \
    "${protect[@]}" -o \
    "${dir_group[@]}" -type d -prune -print0 -o \
    "${file_group[@]}" -type f -print0

  # -not excludes what the pass above already selected, so the two never name
  # the same path and a dry-run counts exactly what --apply removes.
  find "$root" "${protect[@]}" -o \
    -path '*/logs/*' -type f -not "${file_group[@]}" -print0
}

human_size() {
  local kb=$1
  if ((kb >= 1048576)); then
    printf '%.1fG' "$(bc -l <<<"$kb/1048576")"
  elif ((kb >= 1024)); then
    printf '%.1fM' "$(bc -l <<<"$kb/1024")"
  else
    printf '%dK' "$kb"
  fi
}

if ((apply == 1)); then
  printf 'DELETING\n'
else
  printf 'WOULD DELETE (dry-run, pass --apply to remove)\n'
fi

total_kb=0
count=0

for root in "${roots[@]}"; do
  while IFS= read -r -d '' path; do
    size_kb=$(du -sk "$path" | cut -f1)
    total_kb=$((total_kb + size_kb))
    count=$((count + 1))
    printf '  %-60s %8s\n' "$path" "$(human_size "$size_kb")"
    ((apply == 0)) || rm -rf -- "$path"
  done < <(select_junk "$root")
done

# Removing __pycache__ can leave a directory holding nothing else. find caches
# directory state, so a parent emptied during a pass is only noticed by the
# next one; repeat until a pass finds nothing. -depth would report the whole
# nest at once but disables -prune, which the protected paths depend on.
if ((apply == 1)); then
  for root in "${roots[@]}"; do
    while :; do
      pruned=0
      while IFS= read -r -d '' path; do
        [[ $path == "$root" ]] && continue
        rmdir "$path"
        printf '  %-60s %8s\n' "$path" 'empty'
        count=$((count + 1))
        pruned=1
      done < <(find "$root" "${protect[@]}" -o \
        -type d -empty -not -name logs -print0)
      ((pruned == 1)) || break
    done
  done
fi

if ((apply == 1)); then
  printf '\n%d paths removed, %s reclaimed\n' "$count" "$(human_size "$total_kb")"
else
  printf '\n%d paths, %s reclaimable\n' "$count" "$(human_size "$total_kb")"
fi
