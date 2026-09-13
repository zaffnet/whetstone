#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--source REPO] [--new BRANCH] TARGET\n' "${0##*/}"
}

source_repo=""
new_branch=""
target=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      source_repo=$2
      shift 2
      ;;
    --new)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      new_branch=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      printf 'setup-working-tree: unknown option %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      [[ -z $target ]] || {
        usage >&2
        exit 2
      }
      target=$1
      shift
      ;;
  esac
done

[[ -n $target ]] || {
  usage >&2
  exit 2
}
[[ -n $source_repo ]] || source_repo="$(git rev-parse --show-toplevel)"
source_repo="$(cd "$source_repo" && pwd -P)"

if [[ -n $new_branch ]]; then
  if [[ -e $target ]]; then
    printf 'setup-working-tree: %s already exists\n' "$target" >&2
    exit 1
  fi
  git -C "$source_repo" worktree add -b "$new_branch" "$target" HEAD
fi

[[ -d $target ]] || {
  printf 'setup-working-tree: %s is not a directory\n' "$target" >&2
  exit 1
}
target="$(cd "$target" && pwd -P)"

include_list="$source_repo/.worktreeinclude"
if [[ -f $include_list ]]; then
  while IFS= read -r entry || [[ -n $entry ]]; do
    entry="${entry%%#*}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -n $entry ]] || continue
    case "/$entry/" in
      //* | /~* | */../*)
        printf 'setup-working-tree: skipping unsafe .worktreeinclude entry %s\n' "$entry" >&2
        continue
        ;;
    esac
    src="$source_repo/$entry"
    dst="$target/$entry"
    [[ -e $src || -L $src ]] || continue
    mkdir -p "$(dirname "$dst")"
    rm -rf -- "$dst"
    cp -Rp -- "$src" "$dst"
    printf 'copied %s\n' "$entry" >&2
  done <"$include_list"
fi

if [[ -f $target/pyproject.toml ]] && command -v uv >/dev/null 2>&1; then
  (cd "$target" && uv sync -q --all-groups) \
    || printf 'setup-working-tree: uv sync failed; run it by hand\n' >&2
  if [[ -f $target/.pre-commit-config.yaml ]]; then
    (cd "$target" && GIT_CONFIG_NOSYSTEM=1 uv run pre-commit install >/dev/null) \
      || printf 'setup-working-tree: pre-commit install failed; run it by hand\n' >&2
  fi
fi

printf 'ready: %s\n' "$target" >&2
