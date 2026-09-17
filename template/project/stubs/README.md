# Type stubs

Local `.pyi` stubs for dependencies that ship no types. All three checkers read this
directory (`mypy_path`, `stubPath`, and `search-path` in `pyproject.toml`). Prefer a
published `types-<package>` distribution when one exists; add a stub here only when it
does not.
