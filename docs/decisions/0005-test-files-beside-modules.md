# 0005: tests are `*_test.py` beside the module

## Context

pytest finds both `test_*.py` and `*_test.py` by default. The choice decides where a
reader looks for a module's tests and how files sort in a directory listing.

## Decision

`memory_store.py` has its tests in `memory_store_test.py` in the same directory. No
`tests/` tree mirroring the package. `python_files = "*_test.py"` is set explicitly in
`pyproject.toml` so the convention is recorded.

## Consequences

- The module and its tests sit next to each other in every listing and every editor.
- Coverage omits `**/*_test.py` and `**/_test_helpers.py`.
- Ruff `per-file-ignores` relaxes `S101`, `S105`, and `PLR2004` for `*_test.py` only.
- Contributors used to `tests/test_*.py` get a pre-commit failure with the file name rule.

## Alternatives considered

- `tests/test_*.py`: the more common layout; forces a parallel tree and import path games
  for packages that are not installed.
