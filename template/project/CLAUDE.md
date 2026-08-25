# Code style

Python follows the [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html) for judgment calls. Ruff (pre-commit) owns naming, formatting, and imports.

Google-style docstrings on public modules, classes, and functions. One-line helpers skip Args/Returns. Type hints on function signatures.

Make routine judgment calls. Check in only when different readings of the request would lead to materially different work. If you assume something, say what you assumed.

Write the minimum that solves the problem. Keep diffs surgical: every changed line traces to the request. Mention unrelated dead code; do not delete it unless asked. Remove names this change made unused.

Fix the root cause. Do not leave `# type: ignore`, bare `except: pass`, or unexplained `# noqa`.

Test files are `*_test.py`, never `test_*.py`. Correct: `memory_store_test.py`. Wrong: `test_memory_store.py`.

Do not add tests that only assert a constant or a fact ruff, mypy, or basedpyright already prove. No section-separator comments. No template docstrings that restate the function name.

Design docs use plain, direct sentences that state facts and decisions. Use a list when the material is a list. Drop corporate jargon, filler transitions, and repeated bold labels.
