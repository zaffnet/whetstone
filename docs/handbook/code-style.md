<!-- markdownlint-disable MD013 -->
# Code style

Python follows [PEP 8](https://peps.python.org/pep-0008/) for judgment calls. Ruff (pre-commit) owns naming, formatting, and imports.

Docstrings on public modules, classes, and functions: a one-line summary, then `Args:`, `Returns:`, and `Raises:` sections where they carry information. One-line helpers skip Args/Returns. Type hints on function signatures.

Make routine judgment calls. Check in only when different readings of the request would lead to materially different work. If you assume something, say what you assumed.

Write the minimum that solves the problem. Keep diffs surgical: every changed line traces to the request. Mention unrelated dead code; do not delete it unless asked. Remove names this change made unused.

Fix the root cause. Do not leave `# type: ignore`, bare `except: pass`, or unexplained `# noqa`. When a type error comes from a dependency, add real stubs -- `types-<pkg>` or a `stubs/` entry -- rather than annotating the call site as `Any`. Reserve `Any` for values that are genuinely dynamic.

Imports go at the top of the module, never inside a function body, a type annotation, or an interface field. A real circular dependency is the one exception; name it next to the import.

Test files are `*_test.py`, never `test_*.py`. Correct: `memory_store_test.py`. Wrong: `test_memory_store.py`.

Do not add tests that only assert a constant or a fact ruff, mypy, or basedpyright already prove. No section-separator comments. No template docstrings that restate the function name.

Asked to review names, list every weak identifier and wait. Renaming is a separate instruction.

Keep runner output out of context. One test file is `uv run pytest <file> -qq --tb=short --no-header`; sync is `uv sync -q --all-groups --all-extras`, which takes `--upgrade` only when the request is to upgrade, since it rewrites `uv.lock`. Use `-qq` rather than `-q` where a repo's `addopts` add verbosity of their own. Quieten anything else that prints at length: `ruff --quiet`, `git fetch -q`.

Design docs use plain, direct sentences that state facts and decisions. Use a list when the material is a list. Drop corporate jargon, filler transitions, and repeated bold labels.
