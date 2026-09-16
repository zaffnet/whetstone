# Working conventions

Read once per session. This file is symlinked to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`,
and `~/.kiro/steering/AGENTS.md`, so it applies everywhere. The rules below cover Claude
Code, Codex, Cursor, and any other coding agent that reads `AGENTS.md`.

## Writing

Load the `writing-whip` skill before writing prose, and `prose-honesty` before writing
comments, docstrings, docs, or a PR body. `writing-whip` holds the catalog of AI writing
tells and ships to machines that do not have this repo. `prose-honesty` is the bar for
prose written as part of a change: does a reader who arrives next year, having never seen
the change, need this sentence?

Loading it before writing is not enough, since prose written to explain a change reads as
necessary to whoever just made it. A turn that added a comment, a docstring, or prose to a
markdown file does not end until `prose-honesty` has judged that text as written, whether
by re-reading the skill against the diff or by the `code-honesty-auditor` and
`prose-honesty-auditor` agents. Apply what it returns by cutting; a finding answered with a
rewording is not answered.

House style on top of them:

- Plain sentences that state facts and decisions.
- Use a list when the material is a list.
- If the code, the doc, or the user already named something, use that exact word. Do not
  paraphrase a technical term, and do not coin a near-synonym of one.
- Sentence case in headings.
- Straight quotes, no em dashes, no arrow glyphs.

## Code

Python follows [PEP 8](https://peps.python.org/pep-0008/) for judgment calls. Ruff
(pre-commit) owns naming, formatting, and imports.

Docstrings on public modules, classes, and functions: a one-line summary, then `Args:`,
`Returns:`, and `Raises:` sections where they carry information. One-line helpers skip
Args/Returns. Type hints on function signatures. Shrink a docstring rather than deleting
it: pre-commit fails on a public interface without one.

Make routine judgment calls. Check in only when different readings of the request would
lead to materially different work. If you assume something, say what you assumed.

Write the minimum that solves the problem. Keep diffs surgical: every changed line traces
to the request. Mention unrelated dead code; do not delete it unless asked. Remove names
this change made unused.

Fix the root cause. Do not leave `# type: ignore`, bare `except: pass`, or unexplained
`# noqa`. When a type error comes from a dependency, add real stubs -- `types-<pkg>` or a
`stubs/` entry -- rather than annotating the call site as `Any`. Reserve `Any` for values
that are genuinely dynamic.

Imports go at the top of the module, never inside a function body, a type annotation, or
an interface field. A real circular dependency is the one exception; name it next to the
import.

Test files are `*_test.py`, never `test_*.py`. Correct: `memory_store_test.py`. Wrong:
`test_memory_store.py`.

Do not add tests that only assert a constant or a fact ruff, mypy, or basedpyright already
prove. No section-separator comments. No template docstrings that restate the function
name.

Asked to review names, list every weak identifier and wait. Renaming is a separate
instruction.

Keep runner output out of context. One test file is
`uv run pytest <file> -qq --tb=short --no-header`; sync is
`uv sync -q --all-groups --all-extras`, which takes `--upgrade` only when the request is to
upgrade, since it rewrites `uv.lock`. Use `-qq` rather than `-q` where a repo's `addopts`
add verbosity of their own. Quieten anything else that prints at length: `ruff --quiet`,
`git fetch -q`.

## Working with agents

Color flags per command, never via env:

- screen output: `pytest --color=yes`, `ruff check --color always`,
  `git --no-pager diff --color=always`
- redirected or parsed output: no color (`NO_COLOR=1 GH_FORCE_TTY=0 gh api ...`)

Never strip ANSI with a regex after the fact.

When a request names several things to fetch, issue those calls in one turn. In long agent
loops the next independent reads are only implied by the task, and agents tend to issue
them one per turn. That costs round trips, not answer quality. Before each turn: list what
you need next, then request every item that does not depend on another's result in that one
response.

Ending a turn is a stop, not a wait. After spawning background agents, hold the turn open
by blocking on each child, or run the fan-out through a workflow that collects results.
Never end a turn with "I'll wait for X".

`gh stack list` shows the stack. `gh stack` branches on whether stdout is a TTY: piped,
most commands error cleanly or print static text; under a PTY the same commands open a
prompt or a full-screen TUI and block. Pass explicit flags instead of relying on that
detection.

## Stop hooks

Three hooks check the work when a turn ends. None of them delays it: each is configured
with `"asyncRewake": true`, so the harness starts the hook, stops waiting, and ends the
turn. Findings arrive at the start of the next turn, which is why each report says which
turn it describes and that its line numbers may have moved.

Exit 2 is the only code that reaches Claude; it delivers what the hook wrote to stderr.
Exit 0 delivers nothing, which is what every failure path uses: a checker that could not
run says so on stderr, where it reaches the debug log, and does not read as a clean audit.
Exit 2 from a hook the harness *is* waiting for means "refuse to let the turn end", so
these scripts and the `asyncRewake` field belong together -- dropping the field without
changing the scripts turns their reports into blocked turns.

- `hooks/typecheck.sh` runs the repository's own `./run-typecheck.sh` where there is one,
  and `bin/run-typecheck.sh` otherwise.
- `hooks/code_prose_honesty.sh` audits the turn's code diff for comment text a later reader
  cannot use, plus every checker suppression the diff adds. Its `HONESTY_GLOBS` names the
  languages it covers; a language absent from that list is audited by neither hook.
- `hooks/prose_honesty.sh` does the same for markdown and text files.

Both auditors report; neither rewrites. An audit judges every sentence and clause on its
own: a comment holds its space only by supplying what the code cannot express, so expect
deletions rather than rewordings.

## Git

Small PRs, one logical change each. Conventional commits, imperative mood, first line of
72 characters or fewer.

In whetstone, never push to `main` and never merge a pull request: push a branch, open the
PR, request a Copilot review, resolve every thread, and leave the merge to zaffnet.
Copilot is the only review bot to ask. Never comment `@codex review`.

## Skills

Check `~/.agents/skills` at the start of a task and load the ones that match.

## Templates and dotfiles

Projects generated from whetstone and files managed by chezmoi are never patched in place.
A template fix goes into whetstone, ships with `just release vX.Y.Z`, and reaches a project
when its owner runs `uvx copier update` and commits. A project records its template version
in `.copier-answers.yml`; never edit, stage, or commit inside someone else's project to
deliver a template fix. A dotfile fix goes into `home/` and `just apply`. Managed here, so
never edited in place: `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.codex/`,
`~/.cursor/`, `~/.agents/`. For anything else, `chezmoi source-path <file>` names the file
to edit instead, or fails if it is unmanaged. Published tags are never moved.
