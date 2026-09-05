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

## Formatting on every file change

`hooks/ruff_format.sh` runs ruff over a changed Python file as soon as the tool call that
changed it returns. Its matcher is `Edit|Write|NotebookEdit|Bash|PowerShell`: the shell
tools are there because a matcher naming only the editing tools misses every file a shell
command writes, and auto mode steers an agent toward Bash for exactly that.

The two halves work from different evidence. An editing tool names the file in the payload.
A shell tool does not, so the working tree is what says which files changed -- which means
the hook has to decide what counts as this tool's work. It keeps files modified within the
last 30 seconds, because the working-tree diff also holds whatever the author had in
progress before the turn, and a read-only command like `ls` reaches that branch too.
Formatting everything uncommitted would rewrite a half-written file nothing in the session
touched.

The window has one gap: a command that writes a file early and then runs longer than 30
seconds leaves that file to pre-commit. Widening it trades that gap for the risk above.

Lint that ruff cannot fix itself reaches Claude through `systemMessage`. A clean pass says
nothing, so the report only appears when there is something to answer.

## Stop hooks

Three hooks check the work when a turn ends. None of them delays it: each is configured
with `"asyncRewake": true`, so the harness starts the hook, stops waiting, and ends the
turn. The checks run on their own and their findings arrive at the start of the next turn.

That timing is the reason each report says which turn it describes and that its line
numbers may have moved. The hook reads the diff when the turn ends, so an edit made in
between leaves a finding pointing at a line that has since shifted.

Two exit codes carry the whole protocol. Exit 2 delivers what the hook wrote to stderr;
it is the only code that reaches Claude at all. Exit 0 delivers nothing, which is what
every failure path uses: a checker that could not run says so on stderr, where it reaches
the debug log, and does not read as a clean audit. `hook_emit_rewake` in
`hooks/_common.sh` is the one place that writes stderr and exits 2.

Exit 2 from a hook the harness *is* waiting for means "refuse to let the turn end", so
these scripts and the `asyncRewake` field belong together. Dropping the field from a
settings file without changing the scripts turns their reports into blocked turns. The
field is declared in four places -- the chezmoi template for this machine, `hooks.json`
for plugin users, the project template for generated projects, and each generated
project's own checked-in copy -- and a project that has not run `uvx copier update` since
this landed is the case to watch.

- `hooks/typecheck.sh` runs the repository's own `./run-typecheck.sh` where there is one,
  which is what a generated project has, and `bin/run-typecheck.sh` otherwise. Whatever
  fails, the code or a missing virtualenv or `uvx`, is reported without blocking, since
  the same checkers run in pre-commit and CI. It skips repositories whose environment has
  neither mypy nor basedpyright, which would fail on the missing executables rather than
  on their code.
- `hooks/code_prose_honesty.sh` pipes the turn's code diff to a headless `claude -p`
  carrying `agents/code-honesty-auditor.md`, and reports comment text that a later reader
  cannot use, plus every checker suppression the diff adds. Its `HONESTY_GLOBS` names the
  languages it covers; a language absent from that list is audited by neither hook.
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
of the subprocess and cuts the cost roughly threefold.

Both ends of the size range are skipped. Diffs over 4000 lines go to a person instead.
Diffs adding fewer than five lines are not worth a model call, so a typo fix or a
reflowed sentence passes without one; deleted lines are not counted, because deleting
prose is what an audit asks for.

A `claude` that is absent, fails, or answers in prose is named on stderr with exit 0,
which reaches the debug log rather than Claude, and does not block: a checker that cannot
run must not hold a turn hostage, and must not pass as a clean audit either.

Shrink a docstring rather than deleting it: pre-commit fails on a public interface without
one.

## Generated projects and managed files

`AGENTS.md` carries the rule. The detail it leaves out: a project records its template
version in `.copier-answers.yml`, and you never edit, stage, or commit inside someone
else's project to deliver a template fix.
