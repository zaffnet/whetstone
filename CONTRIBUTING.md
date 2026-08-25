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

- Conventional commits: `type(scope): subject`, imperative mood, first line of 72 characters or fewer.
- One logical change per PR. `docs/handbook/git.md` has the rest.
- No private hostnames, account ids, names, absolute home paths, or secrets. Pre-commit
  checks this; `docs/redaction.md` explains what and why.
- A disabled rule, an unusual flag, or a pinned version carries a comment that says why.
- Design changes get a short note in `docs/decisions/` in the same PR.
