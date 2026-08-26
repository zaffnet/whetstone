# Security

## Reporting

Email <zafar@zafarmahmood.com>. Do not open a public issue for a leaked credential or a
private hostname; email gets it removed and the key rotated first.

## What this repo promises

- No secrets in any commit. gitleaks runs in pre-commit and over the full history in CI
  (`.github/workflows/secrets.yml`); GitHub push protection is on.
- No private hostnames, account ids, or personal identifiers. A machine-local denylist
  hook enforces this at commit time (`docs/redaction.md`).
- Scripts under `bin/`, `hooks/`, and `home/.chezmoiscripts/` pass shellcheck and are reviewed
  before merge.
- GitHub Actions are pinned to commit SHAs and run with `contents: read`.

## Scope

The bootstrap installs software from Homebrew, GitHub, and npm. Read
`home/.chezmoiscripts/` and the Brewfile before running it on a machine you care about.
