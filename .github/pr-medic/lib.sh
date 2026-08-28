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

# How many distinct APPROVED reviews come from someone who can actually push. Input: the
# `gh pr view --json latestReviews` object.
#
# Not authorAssociation. MEMBER only means membership in the owning organization, whose base
# role may be Read, and a collaborator can hold Read or Triage -- so associations do not
# establish write access. It does exclude Copilot, which reviews as NONE, but only by
# accident. Ask for the permission instead. A login the API cannot resolve, a bot included,
# is not counted.
approval_count() {
  local login count=0
  while read -r login; do
    [ -n "$login" ] || continue
    case "$(gh api "repos/$REPO/collaborators/$login/permission" --jq '.permission // ""' 2>/dev/null)" in
      admin | write) count=$((count + 1)) ;;
    esac
  done < <(jq -r '[.latestReviews[]? | select(.state == "APPROVED") | .author.login] | unique | .[]')
  printf '%s\n' "$count"
}
