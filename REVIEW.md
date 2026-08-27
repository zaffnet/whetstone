# Review instructions

Read with `CLAUDE.md`, which carries the conventions. This file is what to flag, at what
severity, and what to leave alone.

This repo is three things with three delivery paths, and the riskiest change touches two of
them: `home/` is a chezmoi tree applied to a machine; `template/project/` is a Copier
template rendered into new projects; `agents/`, `skills/` and `.claude-plugin/` are agent
config published as a plugin. Neither layer is ever patched in place downstream.

## What Important means here

This is configuration, not a service. Reserve Important for a change that silently destroys
user state or silently fails to apply:

- A chezmoi merge that drops a live key, table, or file an application wrote itself.
- A whole-file template over a config the application also writes.
- A check, test, or hook that cannot fail on the thing it names.
- A required-status-check context no job produces, or a matrix change that renames one.
- A generated project that fails its own lint, type, coverage, or container gates.
- A secret, private hostname, account id, employee id, or absolute `/Users/<name>/` path
  reaching the tree. This repo is public.

Style, naming, prose, and structure are Nit at most. A missing test is Important only when
it is the reason a defect in the same diff would ship.

## Cap the nits

At most five Nit comments. If there are more, give a count in the summary instead.
`markdownlint` skips `template/project/`, `skills/`, `agents/`, and `home/` entirely, so
prose nits here are unbounded and crowd out everything else.

## Do not report

Already enforced, so a finding here is noise:

- ruff, mypy, basedpyright, bandit, pip-audit findings inside `template/project/` — CI
  renders eight variants and runs the generated project's own hooks against them.
- shellcheck or shfmt on paths `.pre-commit-config.yaml` excludes, including the zsh files,
  which are not parseable as bash.
- Conventional-commit format. `bin/commitlint-msg` owns it.

Deliberate, with the reason in the file — do not re-raise:

- Whole-table ownership in the Codex merge drops undeclared keys *inside* a declared table
  by design. That is what makes deleting a setting from the template remove it from every
  machine. Per-key ownership cannot do that.
- Two gitleaks configs is not duplication. `.gitleaks.toml` is strict for history and
  pre-commit; `.gitleaks.dir.toml` extends it for `just validate` only.
- `run_before_06-skills-not-a-directory.sh` is *meant* to abort an apply.
- `home/.chezmoiremove` deliberately omits the yabai and VS Code files; it runs on every
  apply, so listing a path there deletes it repeatedly.
- `agents/*.md` deliberately differ from their `template/project/` copies: generic versus
  parameterised.
- Unpinned upstream installers in `run_once_before_05-oh-my-zsh.sh` are a documented
  exception.

Known and tracked. Do not re-report:

- `home/dot_claude/modify_settings.json.tmpl` — the `PRESERVE` allowlist makes the live
  value win, so the repo cannot change `model`, `enabledPlugins`, or
  `extraKnownMarketplaces` (#20).
- `bin/sync-mcp` has no behavioural test coverage (#21) and keeps one backup name that
  every run overwrites (#22).
- `tools/check-agents-sync.py` compares two fields, so `name` and effort drift between an
  agent's `.md` and `.toml` are invisible (#23).
- `macos.yml`'s `bootstrap (personal|work)` are matrix-named required contexts with no
  aggregator job (#24).
- No test renders the `modify_*` scripts and checks they parse (#25).
- `tests/home.bats`'s header undercounts its own skips (#26).

## Always check

Each of these has shipped as a bug here at least once.

- **Ownership.** For any file both a template and a live application write, the diff must
  answer two questions: what happens to a key the template never mentions, and what happens
  to a key removed from the template. If it answers neither, that is Important.
- **No hand-rolled parsing.** A regex or line loop over TOML, JSON, or JSONC needs the
  awkward inputs before it is trustworthy: a multiline value, a comment or blank line inside
  a value, `//` inside a string, an escaped quote followed by a brace, an escaped key
  spelling such as `.`, a trailing comma, a closer that does not match its opener, and
  content after the root object. Silent truncation and a key winning as a duplicate are the
  two failure modes to look for.
- **What edit makes this test fail?** If nothing, it is not a test. A bare `!` in a bats
  case does not fail it (SC2314) — require `run` plus a status check. A `skip` guard must
  not depend on the behaviour under test, or the suite goes green as the code breaks. Assert
  the resulting value, not that a key name appears.
- **Hook filters.** A pre-commit hook with a `files:` filter is skipped by a deletion-only
  commit, which is the commit that breaks a path reference. Reference-checking hooks need
  `always_run: true`, and the then-dead `files:` key deleted rather than left in place.
- **CI contexts.** Any matrix change renames every job in it. Matrix-named jobs are used as
  required status checks, so a rename blocks the branch with checks stuck at "Expected".
  Aggregate behind a stable name with `if: always()` — a skipped required check passes the
  ruleset. Verify against the live ruleset, not against a doc.
- **Coverage of what CI cannot see.** `template.yml` runs `SKIP=check-container-version,
  diff-cover`; the runner preinstalls `uv`, so fresh-machine PATH and interpreter problems
  are invisible; `bin/forbid-private-patterns` and `bin/commitlint-msg` no-op in CI by
  design. Never accept "CI checks this" for any of them.
- **Names that change behaviour with no error.** `modify_private_`, not `private_modify_` —
  the latter writes a file literally named `modify_config.toml` and unmanages the real one.
  A `symlink_` source needs `.tmpl`, or the target becomes a literal template string. A
  `run_onchange_` script's trigger comment is load-bearing, not documentation, and `include`
  returns raw source, so a hash over it misses data changes. `{{ if env "CI" }}` is true for
  `CI=0`.
- **Interpolated identifiers.** Anything putting `project_name`, `package_name`, or
  `description` into rendered Python must hold at the 40-character cap and
  `line_length = 88`, in every variant. A manual line wrap is undone by `ruff format`.
- **Two layers.** A fix for a generated project belongs in `template/project/` and ships
  with a release; a fix for a machine belongs in `home/` and ships with an apply. `just
  sync` cannot pull back a `.tmpl` or a `modify_*` file, so those are edited in the repo.

## Verification bar

A behaviour claim needs a `file:line` citation or a command whose output you quote. Do not
infer behaviour from a name, a comment, or a doc — several docs in this repo have described
behaviour the tree does not have. If you cannot verify a finding, say so in it rather than
dropping it or asserting it.

"The current state is X" is not evidence that X was chosen.

## Re-review convergence

After the first review on a pull request, report Important findings only. Do not raise new
nits on later pushes.

## Summary shape

Open with a one-line tally by severity. When there are no Important findings, say so in the
first sentence. Name anything you considered and rejected, with the reason.
