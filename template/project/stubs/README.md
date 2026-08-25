# Type stubs

Local `.pyi` stubs for dependencies that ship no types. Both checkers read this
directory (`mypy_path` and `stubPath` in `pyproject.toml`). Prefer a published
`types-<package>` distribution when one exists; add a stub here only when it does not.
