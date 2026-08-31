# Working with agents

These rules apply to Claude Code, Codex, Cursor, and any other coding agent that reads
`AGENTS.md`.

## Writing style

- Write for humans, not agents.
- If the code, the doc, or the user already named it, use that exact word. Do not paraphrase
  a technical term, and do not coin a near-synonym or near-homophone of one.

## Skills

Check `~/.agents/skills` at the beginning of a task and load the skills that match it.

## Terminal color

Color flags per command, never via env:

- screen output: `pytest --color=yes`, `ruff check --color always`,
  `git --no-pager diff --color=always`
- redirected or parsed output: no color (`NO_COLOR=1 GH_FORCE_TTY=0 gh api ...`)

Never strip ANSI with a regex after the fact.

## Parallel tool calls

When a request names several things to fetch, issue those calls in one turn. In long agent
loops the next independent reads are only implied by the task, and agents tend to issue them
one per turn. That costs round trips, not answer quality. Before each turn: list what you
need next, then request every item that does not depend on another's result in that one
response.

## Waiting on agents

Ending a turn is a stop, not a wait. After spawning background agents, hold the turn open
by blocking on each child, or run the fan-out through a workflow that collects results.
Never end a turn with "I'll wait for X".

## Stacked branches

`gh stack list` shows the stack. `gh stack` branches on whether stdout is a TTY: piped, most
commands error cleanly or print static text; under a PTY the same commands open a prompt or
a full-screen TUI and block. Pass explicit flags instead of relying on that detection.

## Stop hooks

Two hooks decide whether a turn may end. Both are silent when they find nothing, both
block by printing `{"decision": "block"}` with the findings, and both stand down when
`stop_hook_active` is set, so a problem the agent cannot fix costs one extra turn rather
than eight.

- `hooks/typecheck.sh` runs the repository's `./run-typecheck.sh`, or whetstone's
  `bin/run-typecheck.sh` when the repository has none, and blocks while the checkers fail.
  The fallback runs mypy and basedpyright from the target project's environment, so it is
  used only where both resolve: a repository that has neither would otherwise fail on the
  missing executables rather than on its code. A missing virtualenv or `uvx` is reported on
  stderr without blocking.
- `hooks/audit_comments.sh` pipes the diff to a headless `claude -p` carrying
  `agents/code-honesty-auditor.md`, and blocks on what it reports: comments and docstrings
  that record the session rather than the code, and every checker suppression the diff adds.
  It reports; it never rewrites, so the fix lands in the diff with the tests still to run.

The audit is a judgment, not a pattern match. An earlier version scored comments with a few
hundred lines of regexes -- a word list that decided whether a comment "stated a reason" --
which was brittle in both directions: it passed a changelog entry that happened to contain
"because" and flagged `# pyright: strict`, a directive that makes the checkers stricter. The
prompt in `agents/code-honesty-auditor.md` is now the whole of the rule, and its most
important line is to leave a comment alone when unsure, since a false positive is what gets
a check switched off.

The call is deliberately cheap and confined: `--max-turns 1`, no tools, and
`--setting-sources ""` with `--strict-mcp-config` so this machine's settings, MCP servers,
and CLAUDE.md stay out of the subprocess. None of them bear on the question, and loading
them tripled the measured cost. A diff over 4000 lines is left alone. A `claude` that is
absent, fails, or answers in prose is reported on stderr and does not block: a checker that
cannot run must not hold a turn hostage, and must not pass as a clean audit either.

Shrink a docstring rather than deleting it: pre-commit fails on a public interface without
one.

## Generated projects and managed files

- A project created with Copier records its template version in `.copier-answers.yml`. When a
  template bug shows up there, fix the template, release a new version, and let the project
  owner run `uvx copier update`. Do not edit, stage, or commit inside someone else's project
  to deliver a template fix.
- A file under `$HOME` that chezmoi manages is edited in `home/` and applied, or edited in
  place and pulled back with `just sync`. Patching it directly is overwritten by the next apply.
- A published `v*` tag is immutable. A bad release is followed by the next version.
