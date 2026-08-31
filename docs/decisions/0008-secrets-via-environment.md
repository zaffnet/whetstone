# 0008: secrets come from the shell environment, never from tool config

## Context

Claude Code, Codex, and Cursor each accept API keys in their own settings file. Putting
keys there means the key lives in a file a dotfiles repo would naturally track, and the
same key ends up in three places.

## Decision

Keys are exported once in `~/.zsh_secrets` (created from `home/dot_zsh_secrets.example`,
never managed by chezmoi, never committed). Tool config files carry no `env` block with
secret values. Machine-specific non-secret overrides go in `*.local` files
(`~/.zshrc.local`, `~/.gitconfig.local`) or `[data.work]` in the chezmoi config.

## Consequences

- Nothing checks that a tool config file stays free of an `env` block. A Bats case asserted
  `jq 'has("env") | not' ~/.claude/settings.json` until the suite was removed; the rule now
  rests on review.
- Every process started from the shell inherits the keys; GUI-launched tools read them
  after a login shell has run once.
- Rotating a key is one edit in one file.
- gitleaks in pre-commit and CI plus GitHub push protection check that no key slips in
  (`docs/redaction.md`).

## Alternatives considered

- A password manager CLI in chezmoi templates (`onepasswordRead`): sound, and the natural
  next step if a second machine needs the same keys. Not adopted yet because the shell file
  already covers one machine with no new dependency.
- `settings.local.json` per tool: still three copies of the same key.
