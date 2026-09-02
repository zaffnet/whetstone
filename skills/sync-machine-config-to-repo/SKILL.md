---
name: sync-machine-config-to-repo
description: >-
  Scan this macOS machine for dotfiles, configs, installed apps, and packages that
  whetstone does not manage yet, decide how each one should be managed, then add the
  worthwhile ones to the repo on a branch and open a PR. Use only when the user runs
  /sync-machine-config-to-repo.
disable-model-invocation: true
user-invocable: true
argument-hint: "[--report-only]"
tools: Read Edit Write Glob Grep Bash AskUserQuestion
effort: high
metadata:
  version: "1"
---

# sync-machine-config-to-repo

Walk this machine for anything whetstone does not manage, decide where each survivor
belongs, and land the worthwhile ones on a branch as a PR. The goal is that `just apply` on
a second machine reproduces more of this one.

`just sync` covers only the reverse direction: `chezmoi re-add` refreshes files chezmoi
already tracks and never surfaces a new one. This is the other half.

Terse operator mode. Report decisions and paths, do not teach.

With `--report-only` in $ARGUMENTS, run phases 1 through 8 and phase 12, skip phases 9
through 11: no branch, no edits, no deletions, no PR.

## 1. Preflight

Run `git fetch origin` first. Refuse and name the reason if any of these holds: the working
tree is dirty, HEAD is not `main`, HEAD does not equal `origin/main`, `chezmoi` is not
installed, `chezmoi source-path` is not `$(git rev-parse --show-toplevel)/home` (this repo
sets `.chezmoiroot` to `home`, so source-path is never the checkout root itself), or `just
diff` prints anything. Pending drift would be indistinguishable from this run's own change.

Record `chezmoi managed --include=files,symlinks` as the managed set. Every later question
is "is this path in the managed set". Bare `chezmoi managed` counts directories too and
overstates coverage; `--include=files` alone misses managed symlinks such as
`.claude/CLAUDE.md`, so either omission returns already-managed paths as apparent new
candidates. Pass `--source .` on every ad-hoc `chezmoi` call this skill makes outside
`just`, so it never reads a different `sourceDir` than this checkout.

Check `/Library/Managed Preferences`. If it is populated, this is an MDM machine: that path
and the preferences it overrides are read-only ground truth. Never scan it, never manage
it, never diff against it.

## 2. Scan

Issue the reads in one turn:

- `~` at depth 1: dotfiles and dot-directories.
- `~/.config` in full. It is small.
- `~` to depth 4 for `*.json`, `*.jsonc`, `*.toml`, `*.yaml`, `*.yml`, `*.ini`, `*.conf`.
- `~/Library/Application Support` at depth 2, allowlist only: `iTerm2`, `Code`, `Cursor`,
  `Claude`, `Kiro`, `zed`, `k9s`. The rest is app state.
- `~/Library/Preferences` plists whose domain does not start with `com.apple.`.
- `/Applications` and `~/Applications`, top level only.
- `brew leaves`, `brew list --cask`, `brew tap`, `uv tool list`, `npm ls -g --depth=0`,
  `ls ~/.nvm/versions/node`, `rbenv versions`.
- `chezmoi unmanaged`. A hint list, not a work queue: it returns hundreds of entries, most
  of them macOS internals. Filter it hard before reading anything.

## 3. Filter

Drop these outright, with no question asked and no report line:

`~/Downloads`, `~/Movies`, `~/Music`, `~/Pictures`, `~/Public`, `~/Screenshots`,
`~/.Trash`, anything under `~/Library` outside the phase 2 allowlist,
`/Library/Managed Preferences`, `node_modules`, `.venv`, `cdk.out`, `.git`, `__pycache__`,
any path segment containing `cache` or `logs`, `.DS_Store`, `*.zip`, `*.tar*`, `*.png`,
`*.pem`, `*_history`, `.viminfo`, `~/.config/chezmoi` (it holds `[data.work]` and is never
managed), generated receipts such as `~/.config/uv/uv-receipt.json`, and repo spill in `~`
(`main.py`, `pyproject.toml`, `uv.lock`).

`*.bak*`, `*backup*`, and `.zcompdump*` are not dropped here: they go to phase 8 as cruft,
so the user sees the path and size before it is deleted.

Then drop everything already in the managed set.

## 4. Classify

Put each survivor in exactly one bucket.

**Never manage.** Machine-generated state, written by a tool, so a blanked copy teaches a
new machine nothing: `~/.config/gh/hosts.yml`, `~/.docker/config.json`, `~/.claude.json`,
`~/.codex/auth.json`, and key material under `~/.ssh` (`id_*`, `known_hosts`,
`authorized_keys`). These are never-manage on the path alone; do not open them, since the
`~/.ssh` key files in particular hold private key material a read would expose for no
classification benefit. `~/.ssh/config` is not key material — it is hand-edited
configuration, so classify it normally. For a survivor not on this list, read the file
before deciding — a name is not evidence either way.

**Example plus ignore.** The default for a credential file a human edits by hand:
`~/.zsh_secrets`, `~/.aws/credentials`. The variable names are the useful part. Manage
those with every value empty, ignore the real path.
`dot_zsh_secrets.example` and its two `.chezmoiignore` lines are the model:

```sh
# export ANTHROPIC_API_KEY=
# export LANGFUSE_SECRET_KEY=
```

Diff the live file's names against the example and add every name found only in the live
file. A missing name is a key the next machine will not know it needs.

Strip everything right of `=`, and keep each line commented out so sourcing a half-filled
file exports nothing empty. A multiline value or a line continuation does not fit this
pattern; read the file, and if a key's value spans more than one line, take the key name
only and drop the value lines rather than copying any of them across.

Rewrite the comments as well. Notes beside a key accumulate an internal host, a private
URL, a workspace or asset id, a console link, a personal email, all of which
`docs/redaction.md` forbids and pre-commit catches. Say what the key is for in generic
terms, or drop the comment. Report any name you cannot describe without the private
detail.

**Manage.** Route it in phase 5.

**Cruft.** A backup or a stale copy. Nothing is deleted here; it goes to phase 8.

Auto-decide the clear cases. Auto-manage a hand-edited config for a tool already in the
Brewfile or already present in `home/`, when it holds no credential. Send a hand-edited
file whose contents show a credential to example plus ignore, and a tool-written one to
never manage. Auto-cruft names matching the backup patterns from phase 8. Auto-drop caches,
MRU lists, window frames, and session state. Ask only about what is left.

## 5. Route

| Route | When |
| --- | --- |
| Plain file in `home/` | Same bytes on every machine. |
| `.tmpl` | Any part varies by machine, user, or role. Default when unsure. |
| `symlink_` | The real content belongs in the repo working tree, as the agent config does. |
| `modify_` | An application also writes this file at runtime. A plain file or `.tmpl` would let the next apply discard keys the app wrote; `modify_settings.json.tmpl:2-12` for Cursor is the working example, owning per top-level key and carrying over anything else. |
| `.chezmoiscripts/` | The state is set by a command, not a file: `defaults write`, an installer. |
| `.chezmoiignore` | Paired with an `.example`, or a file corp tooling rewrites. |
| Brewfile | Software. See phase 6. |
| `template/project/` | Belongs to a Python project, not to this user. |

The split: a file lives in `home/` if a new machine needs it before any repo is cloned. It
lives in `template/project/` if only a generated project needs it. One project on this
machine is copier-managed, so the bar for `template/project/` is high, and a change there
reaches nothing until `just release vX.Y.Z` ships and the project owner runs
`uvx copier update`. Say that in the PR body.

Work-flavoured items default to a `.tmpl` guarded on `$work`, value kept out of the repo:

```
{{- $work := get . "work" | default (dict) -}}
{{ if hasKey $work "some_key" }}...{{ end }}
```

`home/.chezmoitemplates/codex-config.toml.tmpl` and `home/dot_config/uv/uv.toml.tmpl` are
the working examples. Fall back to a `.role`-guarded `.chezmoiignore` entry only when the
file cannot be managed at all, following the `.gitconfig` precedent already in that file.

Never edit `~/.config/chezmoi/chezmoi.toml`. Collect the `[data.work]` lines for the report
and let the user paste them.

Anything that would put a private hostname, internal URL, account id, or an absolute
`/Users/<name>/` path into the repo goes through a `$work` key or `{{ .chezmoi.homeDir }}`
instead. `docs/redaction.md` is the rule and pre-commit enforces it.

## 6. Software

`just sync` runs `chezmoi re-add`, then `bin/sync-claude-settings`, then a Brewfile dump and
diff. Only `chezmoi re-add` writes to the source tree. `bin/sync-claude-settings` is
read-only unless called with `--adopt`, which `just sync` does not pass: without it, a
declared key that differs is printed and left alone. HEAD is still `main` at this point, so
do not run `chezmoi re-add` yet, but the rest of `just sync` is safe to run directly:

- `python3 bin/sync-claude-settings`, read-only, reports drift in `~/.claude/settings.json`.
- Dump the live Brewfile with `brew bundle dump --force --file=/tmp/whetstone-brewfile`,
  then diff it against `home/dot_config/homebrew/Brewfile`, the same comparison `just sync`
  runs: filter both to lines starting `brew`, `cask`, `tap`, `uv`, `npm`, or `go`, strip
  trailing comments, sort, and diff.

Lines marked `>` are installed but absent from the Brewfile. For each, either add it under
the right comment heading or leave it out as a one-off, a dependency of something already
listed, or corp-installed.

The Brewfile carries non-standard `uv "..."` and `npm "..."` lines that the `just sync`
grep recognises. Preserve those line types; do not convert them to `brew` or `cask`.

Leave out fleet software: endpoint protection, network or web proxies, vulnerability
scanners, telemetry and asset inventory agents, and the MDM enrolment apps themselves. A
personal machine must not install those, and a work machine gets them from MDM. Anything
installed under `/Applications` that the user never chose is a candidate for this rule.

Under `--report-only`, this phase's reads already ran above; there is nothing further to
defer. Note in the report any `bin/sync-claude-settings` drift found.

Off `--report-only`, run `chezmoi re-add` only after phase 9 creates the branch, never
before. A change it makes is drift in an already-managed file, not a new candidate: report
it separately in phase 12 rather than folding it into this run.

## 7. Ask

Batch the genuine unknowns with `AskUserQuestion`, four at a time, grouped by theme: shell,
editors, agents, cloud, version managers, macOS defaults. Put the file path in the question
and the phase 5 routes in the options. Include "leave unmanaged" in every group.

There is no ledger, so a declined item is asked again on the next run. That is the accepted
cost.

## 8. Cruft

Find `*.bak*`, `*backup*`, and `.zcompdump*` matches from phase 3, and any other stale copy
noticed while scanning. Report every item with its exact path and size. Group by kind:
Claude config backups, shell-rc backups, whetstone pre-apply tarballs, zcompdumps, leftover
plists. Ask once per group.

Delete only approved groups, with `rm` on the exact paths the user saw. Never a glob they
did not see. Cruft deletion is a machine change, not a repo change: do it after the PR is
open, and skip the deletion step under `--report-only` — report the groups either way.

## 9. Apply

Create the branch before the first edit, so no change ever sits on `main`. Then run
`chezmoi re-add`, the mutating half of `just sync` deferred from phase 6 — now safe, since
any rewrite lands on the branch.

For every route except example plus ignore: onboard the file with `chezmoi add`. `re-add`
only touches already-managed files and does nothing at all for a new one. Pass `--template`
when phase 5 chose `.tmpl`. Then Read the added file under `home/` and Edit it: strip
machine specifics, add the `$work` guards, and add a comment where a setting's reason is
not obvious.

For the example plus ignore bucket, do not run `chezmoi add` on the live path at all —
`chezmoi add` copies live bytes verbatim, so the secret values would sit in the source tree,
reachable by `git add` and inside gitleaks' scan root, until the Edit that blanks them.
Instead: add the `.chezmoiignore` line for the live path first, then Write the `.example`
directly from the names read out of the live file in phase 4. No copy of the live file, or
its values, is ever created.

Two ways an apply destroys data. Handle both before running one:

- Adding a file whose live copy differs overwrites the live copy on the next apply. Always
  `just diff` and read the hunk first.
- Adding a managed directory where a real directory exists lets chezmoi delete the live one
  recursively, with no prompt. `run_before_06-skills-not-a-directory.sh.tmpl` guards the
  known cases. Prefer managing individual files, and if a new `symlink_` covers a path that
  is a real directory today, extend that script's loop in the same commit.

Files change with Edit and Write only. Never a shell redirect, `sed -i`, or a heredoc.
Reads and searches stay in Bash.

## 10. Verify

In order, stopping at the first failure:

1. `just diff`, reading every hunk. Expect only the added files. A hunk that deletes a
   file, replaces a directory with a symlink, or rewrites an untouched file is a stop:
   these files were just staged by `chezmoi add` in phase 9, so `git restore` either
   no-ops (untracked) or leaves the file in place (staged) instead of undoing it. Run
   `chezmoi forget` on the offending source path — the inverse of `chezmoi add` — or, if it
   is already staged, `git rm --cached` followed by `rm`. Report it instead of applying.
2. `just lint`. `check-skills-doc.py` fails here if `docs/skills.md` lacks the row for this
   skill; gitleaks and `forbid-private-patterns` fail here on a leaked string. Fix the
   cause, never suppress the checker.
3. `just validate`.
4. `just apply`.
5. `chezmoi verify`, then `just diff` again. Both silent. A non-empty second diff means an
   apply that does not converge.

If an apply breaks the machine, recovery is `git switch main && just apply`. `main` is the
last state known to apply cleanly. Say so in the report.

## 11. Commit, push, PR

One commit per logical group, not per file. Conventional commits, imperative mood, first
line 72 characters or fewer. Scope `dotfiles` for `home/`, `template` for
`template/project/`.

Push the branch, open the PR with `gh pr create`, and request a Copilot review. Never push
to `main`, never merge, never comment `@codex review`. If the PR touches
`template/project/`, say in the body that it reaches nothing until `just release vX.Y.Z`
and the project owner runs `uvx copier update`.

Load `writing-whip` before writing the PR body, and `prose-honesty` before writing any
comment into a managed file.

## 12. Report

In this order:

1. What was adopted: path, route, commit. Off `--report-only` only.
2. Every variable name added to an `.example`, and any name held back because its comment
   could not be rewritten without the private detail.
3. What was left unmanaged as tool-written state: exact path, one line on what it holds.
4. What was skipped by choice, and why.
5. The literal `[data.work]` lines to paste into `~/.config/chezmoi/chezmoi.toml`, stating
   that this run did not write that file.
6. The cruft list with paths and sizes, and which groups were deleted. Under
   `--report-only`, list the groups found instead of which were deleted.
7. Drift `bin/sync-claude-settings` and the Brewfile diff found in already-managed files.
8. Any item that stopped at verification. Off `--report-only` only.
