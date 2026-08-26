# Contributing

This is a personal configuration repo. The intended way to use it is to fork it and make
it yours. Pull requests for generic fixes (a broken script, a wrong path in a template, a
stale pin) are welcome.

## Setup

```bash
just install   # uv sync, pre-commit install
just lint      # everything pre-commit runs, on all files
just test-home # apply the chezmoi tree into a throwaway HOME and run the bats suite
```

## Rules

- `main` takes pull requests only. A ruleset with no bypass list enforces it, so it binds the
  owner too. Copilot reviews every PR automatically; ask other agents as well. CI is green
  before merge, and zaffnet merges (`docs/decisions/0011-main-is-pull-request-only.md`).
- Conventional commits: `type(scope): subject`, imperative mood, first line of 72 characters or fewer.
- One logical change per PR. `docs/handbook/git.md` has the rest.
- No private hostnames, account ids, names, absolute home paths, or secrets. Pre-commit
  checks this; `docs/redaction.md` explains what and why.
- A disabled rule, an unusual flag, or a pinned version carries a comment that says why.
- Design changes get a short note in `docs/decisions/` in the same PR.

## Releasing and updating projects

- Fix the template here, never in a generated project. A project takes the fix with
  `uvx copier update`.
- Ship with `just release vX.Y.Z`. It refuses a dirty tree, an unpushed `main`, or an existing
  tag, then creates the tag and a GitHub Release with generated notes in one call. Tags are
  immutable on GitHub; a bad release is followed by the next version, never re-pointed.
- Edit `$HOME` through `home/` and `just apply`, or edit the real file and `just sync`. Never
  hand-edit a managed file as a fix.
