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

## Generated projects and managed files

- A project created with Copier records its template version in `.copier-answers.yml`. When a
  template bug shows up there, fix the template, release a new version, and let the project
  owner run `uvx copier update`. Do not edit, stage, or commit inside someone else's project
  to deliver a template fix.
- A file under `$HOME` that chezmoi manages is edited in `home/` and applied, or edited in
  place and pulled back with `just sync`. Patching it directly is overwritten by the next apply.
- A published `v*` tag is immutable. A bad release is followed by the next version.
