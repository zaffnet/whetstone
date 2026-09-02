# Working with agents

These rules apply to Claude Code, Codex, Cursor, and any other coding agent that reads
`AGENTS.md`.

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

Three hooks check the work when a turn ends. Each reports through the `systemMessage`
field of its JSON output, which is the only channel Claude reads: stderr from a hook that
exits 0 reaches the debug log and nothing else. None of them blocks.

- `hooks/typecheck.sh` runs the repository's own `./run-typecheck.sh` where there is one,
  which is what a generated project has, and `bin/run-typecheck.sh` otherwise. Whatever
  fails, the code or a missing virtualenv or `uvx`, is reported without blocking, since
  the same checkers run in pre-commit and CI. It skips repositories whose environment has
  neither mypy nor basedpyright, which would fail on the missing executables rather than
  on their code.
- `hooks/code_prose_honesty.sh` pipes the turn's Python diff to a headless `claude -p`
  carrying `agents/code-honesty-auditor.md`, and reports comment text that a later reader
  cannot use, plus every checker suppression the diff adds.
- `hooks/prose_honesty.sh` does the same for markdown and text files, carrying
  `agents/prose-honesty-auditor.md`.

Both auditors report; neither rewrites, so the fix lands in the diff with the tests still
to run. `hooks/_honesty.sh` holds the body they share; each caller supplies the brief, the
pathspecs, and the wording of the report.

An audit judges every sentence and clause on its own, against a high bar: a comment holds
its space only by supplying what the code cannot express. A comment carrying one useful
clause and three of padding is reported for the padding. The aim is the largest honest
reduction in text, so expect the check to ask for deletions rather than rewordings.

The call is confined: `--max-turns 1`, no tools, and `--setting-sources ""` with
`--strict-mcp-config`, which keeps this machine's settings, MCP servers, and CLAUDE.md out
of the subprocess and cuts the cost roughly threefold. Diffs over 4000 lines are skipped. A
`claude` that is absent, fails, or answers in prose is reported on stderr and does not
block: a checker that cannot run must not hold a turn hostage, and must not pass as a clean
audit either.

Shrink a docstring rather than deleting it: pre-commit fails on a public interface without
one.

## Generated projects and managed files

`AGENTS.md` carries the rule. The detail it leaves out: a project records its template
version in `.copier-answers.yml`, and you never edit, stage, or commit inside someone
else's project to deliver a template fix.
