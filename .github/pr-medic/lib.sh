# shellcheck shell=bash
# Sourced by pick.sh and after.sh. Expects REPO and GH_TOKEN in the environment.

# How many review threads on a pull request are unresolved. Asks for totalCount as well as
# the page: past 100 threads the page reports *fewer* unresolved than there are, so report
# one unresolved and let the caller refuse rather than read an over-long list as clean.
unresolved_threads() {
  # shellcheck disable=SC2016  # $owner, $name and $pr are GraphQL variables.
  gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F pr="$1" -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) { totalCount nodes { isResolved } }
        }
      }
    }' --jq '.data.repository.pullRequest.reviewThreads
             | if .totalCount > 100 then 1
               else [.nodes[] | select(.isResolved == false)] | length
               end'
}

# Paths the Claude CLI reads from cwd at startup, mirroring SENSITIVE_PATHS in
# claude-code-action's restore-config.ts. trust-config.sh replaces them with the default
# branch's copies, which means the worktree legitimately differs from the PR head for any
# pull request that edits one -- so after.sh must not read that as an uncommitted fix.
# Re-check the list against upstream when bumping the pinned action SHA.
# shellcheck disable=SC2034  # read by trust-config.sh and after.sh, which source this.
TRUSTED_PATHS=(.claude .mcp.json .claude.json .gitmodules .ripgreprc CLAUDE.md CLAUDE.local.md .husky)

# Can this login push to the repository?
#
# Not authorAssociation. MEMBER only means membership in the owning organization, whose base
# role may be Read, and a collaborator can hold Read or Triage -- so associations do not
# establish write access. It does exclude Copilot, which reviews as NONE, but only by
# accident. Ask for the permission instead. A login the API cannot resolve, a bot included,
# does not have it.
has_push_access() {
  case "$(gh api "repos/$REPO/collaborators/$1/permission" --jq '.permission // ""' 2>/dev/null)" in
    admin | write) return 0 ;;
  esac
  return 1
}

# How many distinct APPROVED reviews come from someone who can actually push. Input: the
# `gh pr view --json latestReviews` object.
approval_count() {
  local login count=0
  while read -r login; do
    [ -n "$login" ] || continue
    ! has_push_access "$login" || count=$((count + 1))
  done < <(jq -r '[.latestReviews[]? | select(.state == "APPROVED") | .author.login] | unique | .[]')
  printf '%s\n' "$count"
}

# Not under pr-medic/, which the model reaches through --add-dir: only after.sh reads this,
# and a state file the model can rewrite would certify whatever it likes.
: "${TRUSTED_STATE_FILE:=${RUNNER_TEMP:-/tmp}/pr-medic-state/trusted-state}"

# A digest of the working-tree state of TRUSTED_PATHS. trust-config.sh records it right after
# the restore; after.sh compares. Excluding those paths from the clean-worktree check is not
# enough on its own -- it would also hide an edit Claude made to one of them and never
# committed, and the thread asking for that edit would then be resolved against a head the fix
# is missing from. Both the status and the diff, so an added file counts as well as a change.
trusted_state() {
  local p present=()
  for p in "${TRUSTED_PATHS[@]}"; do
    if [ -e "$p" ]; then present+=("$p"); fi
  done
  {
    git status --porcelain -- "${TRUSTED_PATHS[@]}"
    git diff HEAD -- "${TRUSTED_PATHS[@]}"
    # The contents too, not only git's view of them. A trusted path the pull request deletes is
    # restored as untracked, and there `git status` prints the same `?? CLAUDE.md` line whatever
    # the file holds while `git diff HEAD` sees nothing at all -- so an edit Claude made to it
    # would pass this check, and restore_pr_config's `git clean` would then delete the fix a
    # reply had already claimed. Sorted and path-prefixed, so neither traversal order nor a
    # rename can hide in the digest.
    if [ "${#present[@]}" -gt 0 ]; then
      while IFS= read -r -d "" p; do
        printf '%s %s\n' "$p" "$(shasum -a 256 <"$p" | cut -d' ' -f1)"
      done < <(find "${present[@]}" -type f -print0 | sort -z)
    fi
  } | shasum -a 256 | cut -d' ' -f1
}

# Put the PR's own versions of TRUSTED_PATHS back. trust-config.sh left them at the default
# branch's content so the CLI could not read the PR's hooks; once the gate has checked that
# state, the difference is only in the way -- `git rebase` refuses to run with unstaged
# changes even though the clean-worktree check excludes these paths. Per path, because
# `git checkout HEAD --` fails outright if any one of them is absent from HEAD.
restore_pr_config() {
  local p
  for p in "${TRUSTED_PATHS[@]}"; do
    git checkout HEAD -- "$p" 2>/dev/null || true
  done
  # Whatever the restore added that the pull request does not have.
  git clean -qfd -- "${TRUSTED_PATHS[@]}" 2>/dev/null || true
}
