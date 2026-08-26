# Working conventions

Read once per session. Detail lives in `docs/handbook/` of the whetstone repo, which chezmoi
links to `~/.agents/handbook/`. This file is symlinked to `~/.claude/CLAUDE.md`,
`~/.codex/AGENTS.md`, and `~/.kiro/steering/AGENTS.md`, so it applies everywhere.

## Writing

Follow `~/.agents/handbook/writing.md`. Plain sentences that state
facts and decisions. Use a list when the material is a list. If the code, the doc, or the
user already named something, use that exact word.

## Code

Follow `~/.agents/handbook/code-style.md`. Python follows the Google
style guide for judgment calls; ruff owns formatting, naming, and imports. Test files are
`*_test.py` beside the module, never `test_*.py`. Fix the root cause; do not silence a
checker. Keep diffs surgical.

## Working with agents

Follow `~/.agents/handbook/working-with-agents.md`. Color
flags go on the command, never in the environment. Run independent reads in one turn. Ending
a turn is a stop, not a wait. Design docs are guidelines, and drift from code is expected.

## Git

Follow `~/.agents/handbook/git.md`. Small PRs, one logical change each.
Conventional commits, imperative mood, first line of 72 characters or fewer.
In whetstone, never push to `main` and never merge a pull request: push a branch, open the
PR, request a Copilot review and any other agent reviews, resolve every thread, and leave
the merge to zaffnet.

## Skills

Check `~/.agents/skills` at the start of a task and load the ones that match.

## Templates and dotfiles

Projects generated from whetstone and files managed by chezmoi are never patched in place.
A template fix goes into whetstone, ships with `just release vX.Y.Z`, and reaches a project
when its owner runs `uvx copier update` and commits. A dotfile fix goes into `home/` and
`just apply`. Published tags are never moved. Detail: `~/.agents/handbook/working-with-agents.md`.
