# 0001: chezmoi manages the home directory

## Context

The home directory holds shell config, editor settings, and configuration for three coding
agents. The same repo must work on a personal Mac and a work Mac, where the work machine
adds a proxy URL, an AWS profile, and a private package index that must never be published.

## Decision

chezmoi. The source state lives in `home/` (`.chezmoiroot`), files are templates where the
machine matters, and `run_once_` / `run_onchange_` scripts install Homebrew packages and
macOS defaults.

## Consequences

- One binary, one-line bootstrap, no symlink farm in `$HOME`: files are real files.
- Work-only values come from `[data.work]` in the local chezmoi config, so the repo stays
  clean and the work machine is a data difference, not a branch.
- Go template syntax in config files. Templates are kept small and rendered in CI.
- `chezmoi apply` rewrites managed files; tools that append to their own config (Codex)
  are re-prompted after an apply.

## Alternatives considered

- GNU Stow: symlinks only, no templating, no scripts. Work/personal would need two trees.
- Nix (nix-darwin + home-manager): declarative and idempotent, but a 90-minute first
  install and a language to learn before the first edit. Readability for strangers matters
  here.
- Plain `install.sh`: no templating, idempotency is hand-written, drift goes unnoticed.
