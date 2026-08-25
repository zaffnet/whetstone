# 0007: MIT license

## Context

The repo mixes shell config, a Python project template, skills, and scripts. A single
license is easier to state than one per directory.

## Decision

MIT for everything.

## Consequences

- Anyone can copy a `.zshrc` fragment or the template with attribution in their LICENSE.
- The template's generated projects default to MIT (configurable in `copier.yml`).
- Third-party skills are not vendored (see 0006), so no license mixing inside `skills/`.

## Alternatives considered

- 0BSD: MIT without the attribution requirement, which suits config files nobody wants to
  credit. Rejected for now because one widely recognised license reads simpler than two,
  and attribution for a dotfiles repo costs nothing. Revisit if the attribution clause
  causes friction for anyone.
- Unlicense / CC0: public-domain dedications are not valid in every jurisdiction.
