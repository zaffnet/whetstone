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

## Design docs

Design docs are guidelines, not rules. During implementation, review, and testing, make the
decision that keeps the code readable, extensible, and simple. Design docs can change later.
Drift between code and design docs is normal and expected; do not justify code by a doc line
number, and do not propose syncing them as a task on its own.

## Tests

Every test that can run against a live backend runs against both a mock and the live backend.
Mock-only needs a written reason. Put backend differences in fixtures; the test body is the
action and the assertions, and does not branch on backend type.

Do not re-test validation constraints one at a time. One invalid input is enough. Type
checkers do not see JSON that arrives at runtime, so that one test earns its place.
