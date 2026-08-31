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
  `bin/run-typecheck.sh` when the repository has none, and blocks while it fails. It also
  runs `tools/find-suppressions.py` over the lines the working-tree diff adds and blocks on
  any suppression among them: `# noqa`, `# type: ignore`, the file-level `# mypy:
  ignore-errors`, `# pyright: reportFoo=false`, and the pyrefly, pylint, and coverage
  equivalents. Every new suppression blocks, documented or not, because a suppression hides
  the finding rather than answering it. A missing virtualenv or `uvx` is reported on stderr
  without blocking; a suppression found alongside it still blocks.
- `hooks/audit_comments.sh` runs `tools/audit-comments.py` over the same lines and blocks on
  comments and docstrings that record the session rather than the code: section banners,
  changelog entries, docstrings that re-spell the function name, `Args:`/`Returns:` over a
  one-line body, end-of-block markers, category labels, vague TODOs, emoji, unverifiable
  praise, and prose several times longer than the code it documents. It reports; it never
  rewrites, so the fix lands in the diff with the tests still to run.

Both call the system `python3`, so neither tool uses syntax newer than 3.11, and both
hooks tell the three exit statuses apart: 0 is clean, 1 is findings, and anything else is
the tool failing to run, which is reported on stderr without blocking. Passing a failure
off as clean would retire the check the first time the interpreter could not run it.

Both read the added lines of the diff, not whole files, so editing one line of a file does
not put its committed comments on the session's account. A docstring counts as touched when
any line of it changed, since rewriting the middle of one makes the whole its author's.
Suppressions are read as comment tokens rather than as raw line text, so the same words
inside a string literal are not a suppression.

A comment containing a reason is never reported. `because`, `so that`, `otherwise`,
`workaround`, `assumes`, `breaks when`, `by design`, a bug number, a URL, and the rest of
`_WHY_MARKER` exempt a comment from every shape-based rule, and a lone finding in a long
file stays under a density gate. Shrink a docstring rather than deleting it: pre-commit
fails on a public interface without one.

## Generated projects and managed files

- A project created with Copier records its template version in `.copier-answers.yml`. When a
  template bug shows up there, fix the template, release a new version, and let the project
  owner run `uvx copier update`. Do not edit, stage, or commit inside someone else's project
  to deliver a template fix.
- A file under `$HOME` that chezmoi manages is edited in `home/` and applied, or edited in
  place and pulled back with `just sync`. Patching it directly is overwritten by the next apply.
- A published `v*` tag is immutable. A bad release is followed by the next version.
