# New Python project

```bash
uvx copier copy gh:zaffnet/whetstone my-project
cd my-project
git init -b main
uv sync --all-groups
GIT_CONFIG_NOSYSTEM=1 uv run pre-commit install   # ignores a system core.hooksPath
```

Copier renders the latest tagged release of the template. Add `--vcs-ref HEAD` for the tip
of `main`.

## Questions

| Question | Effect |
| --- | --- |
| `project_name` | Distribution name in `pyproject.toml`, repo name in README and CI; kebab-case, 40 characters or fewer |
| `package_name` | Import name; defaults to `project_name` with hyphens turned into underscores; same 40-character limit |
| `description` | `pyproject.toml` description and README first line |
| `github_owner` | `CODEOWNERS`, clone URL in `docs/DEVELOPMENT.md`, container registry path |
| `python_version` | `requires-python`, `.python-version`, `target-version` for ruff, mypy, basedpyright |
| `line_length` | ruff and editor rulers |
| `use_docker` | Adds `Dockerfile`, `docker-compose.yaml`, `docker-compose.override.example.yaml`, `.dockerignore`, the image-version pre-commit hook, and the image build job in CI |
| `use_fastapi` | Adds FastAPI, uvicorn, pydantic-settings, and httpx2; a `/health` app with a test; the async-safety reviewer agent |
| `license` | `LICENSE` text (MIT or Apache-2.0) and the `license` field; `Proprietary` writes neither |
| `author` | Copyright holder named in `LICENSE`; asked only when a license text is written |

## What you get

- `pyproject.toml` with ruff `select = ["ALL"]` and a commented ignore list, mypy (with the
  Pydantic plugin when `use_fastapi`), basedpyright strict, pyrefly, bandit, pytest
  (`*_test.py`), coverage.
- `.pre-commit-config.yaml`: ruff fix and format, mypy, basedpyright, bandit, pip-audit,
  unit tests with coverage, `diff-cover --fail-under=80` against `origin/main`, and a
  pygrep hook that rejects section-separator comments.
- `.github/workflows/ci.yaml` with SHA-pinned actions, `permissions: {}` by default,
  pre-commit as the gate, and a diff-cover summary on the job page.
- `.github/dependabot.yml` for uv, GitHub Actions, pre-commit, and (with Docker) the
  Dockerfile and compose file.
- `.claude/` with hooks (ruff on every edit; `setup-working-tree.sh` ships unwired, for the
  project to call), rules, reviewer agents, and `.codex/` with the same agents in TOML.
- `.vscode/settings.json` pinned to the project's `.venv` ruff and basedpyright.
- `AGENTS.md` (and a `CLAUDE.md` that imports it), `docs/DEVELOPMENT.md`, `.env.example`.
- With Docker: a Compose stack that builds, starts, and answers `/health` (FastAPI) or runs
  the module once.

## Later: pulling template changes

```bash
uvx copier update                 # needs a clean working tree
git diff                          # review what the new template version changed
git commit -am "chore: update template to whetstone vX.Y.Z"
```

Copier reads `.copier-answers.yml`, fetches the version recorded there and the latest tag,
and three-way merges into the working tree. It changes files and stops; the commit is yours.
Conflicts appear as inline markers (`<<<<<<< before updating`); resolve them, `git add`, then
commit. Files listed in `_skip_if_exists` (`README.md`, `uv.lock`) are never touched by an
update.
