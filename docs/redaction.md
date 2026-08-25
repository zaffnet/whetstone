# Redaction and secrets

This repo is public and was built on a work laptop. These are the rules that keep employer
material and credentials out of it.

## What never enters the repo

- API keys, tokens, passwords, certificates, private keys, CA bundles.
- Employer hostnames, internal package indexes, proxy URLs, cloud account ids, IAM role
  names, asset or cost-center identifiers.
- Employee ids, colleague names and GitHub handles, internal team names.
- Absolute paths under `/Users/<name>/`; templates use `{{ .chezmoi.homeDir }}` and scripts
  use `$HOME`.
- Agent runtime state: histories, session logs, memories, plan files, OAuth caches.

## Where employer values go instead

| Value | Location |
| --- | --- |
| Proxy URL, AWS profile, private index, branch prefix | `[data.work]` in `~/.config/chezmoi/chezmoi.toml` |
| Shell exports specific to one machine | `~/.zshrc.local` |
| Commit signing program, certificate, CA bundle | `~/.gitconfig.local` |
| API keys | `~/.zsh_secrets` |

All four files are outside the repo. `.chezmoiignore` and `.gitignore` exclude them.

## Three scanning layers

1. Pre-commit. `gitleaks` with the default ruleset plus `.gitleaks.toml`, which adds
   generic rules for absolute home paths, employee-style ids, twelve-digit account numbers,
   internal-looking hostnames, and CA-bundle exports. `detect-private-key` and
   `detect-aws-credentials` from `pre-commit-hooks` run alongside.
2. A machine-local denylist. `bin/forbid-private-patterns` reads
   `~/.config/whetstone/private-patterns.txt` (or `$WHETSTONE_PRIVATE_PATTERNS`), one
   extended regex per line, `#` comments allowed, and fails the commit when any staged text
   file matches. The file holds the real employer strings, so it is never committed; without
   it the hook exits 0, which is what happens in CI and on a fresh clone.
3. Server side. GitHub secret scanning and push protection are on for public repos and
   block a push that contains a recognised credential. `secrets.yml` also runs `gitleaks git`
   over the full history on every push and weekly.

## Before publishing something new

- Render templates and read the output (`chezmoi execute-template < file.tmpl`).
- `just validate` runs `gitleaks dir .` and the plugin validator.
- If a private string ever lands in history, rewrite history before the next push rather
  than committing a removal on top: the repo is small enough that an orphan branch and a
  fresh initial commit is the honest fix.
