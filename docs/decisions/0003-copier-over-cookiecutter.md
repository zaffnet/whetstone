# 0003: Copier for the Python project template

## Context

New projects should start from the same `pyproject.toml`, pre-commit config, CI, Dockerfile,
and agent configuration. When the template improves, existing projects should be able to
pull the change.

## Decision

Copier, with the template in `template/` and answers recorded in `.copier-answers.yml` in
each generated project. `copier update` does a three-way merge against the template version
the project was created from.

## Consequences

- Downstream projects get template updates with conflict markers where they diverged.
- `_migrations` can script changes between template versions.
- The template is tested by rendering it in CI and running the generated project's own
  pre-commit and pytest.
- Copier must be installed (`uvx copier`), unlike a GitHub template repository.

## Alternatives considered

- Cookiecutter: one-way generation, no update path. Cruft adds a patch-based update with
  no merge strategy choice.
- GitHub "Use this template": one click, one-way copy, and no way to pull later changes.
- `uv init`: no templating at all.
