#!/usr/bin/env bash
# Commit the staged changes with the message given as the single argument.
#
# `git commit` is not on the model's allowlist. Allow-list patterns match on a prefix, so
# `Bash(git commit -m:*)` would also admit `git commit -m x -F .git/config`, and `-F` reads a
# file into the commit message -- which the next push would publish. This takes a message and
# passes no other flag to git.
set -euo pipefail

[ "$#" -eq 1 ] && [ -n "$1" ] || {
  echo "usage: commit.sh <message>" >&2
  exit 2
}
git commit -m "$1"
