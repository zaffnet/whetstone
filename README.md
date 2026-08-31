# whetstone

[![lint](https://github.com/zaffnet/whetstone/actions/workflows/lint.yml/badge.svg)](https://github.com/zaffnet/whetstone/actions/workflows/lint.yml)
[![template](https://github.com/zaffnet/whetstone/actions/workflows/template.yml/badge.svg)](https://github.com/zaffnet/whetstone/actions/workflows/template.yml)
[![macos](https://github.com/zaffnet/whetstone/actions/workflows/macos.yml/badge.svg)](https://github.com/zaffnet/whetstone/actions/workflows/macos.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

This is how I set up a machine and a Python project: my shell, git, and editor config as a
chezmoi source tree, a Copier template for new Python projects, and the skills, subagents,
and hooks I use with Claude Code, Codex, and Cursor.

I don't currently expect this to be useful to anyone but me. Maybe eventually it will be.

## Requirements

| What | Install |
| --- | --- |
| macOS on Apple silicon (the Brewfile, the `defaults write` script, and the paths assume it) | |
| Xcode Command Line Tools | `xcode-select --install` |
| Homebrew | [brew.sh](https://brew.sh); the bootstrap installs it if missing |
| chezmoi | `brew install chezmoi` |
| uv | `brew install uv` |
| just | `brew install just` |
| Node | `brew install node` |
| Claude Code CLI | [code.claude.com](https://code.claude.com) |

The template needs Python 3.12 or newer; uv downloads it.

## Install

### A whole machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply zaffnet/whetstone
```

Clones this repo, prompts for a role (`personal` or `work`) and a few other values, then
writes every file under `home/` into `$HOME`, installs the Brewfile, sets a few macOS
defaults, and links the skills. `docs/new-machine.md` has the long version and the steps
for a machine that already has a setup.

Do not run this on a machine you care about without reading `home/.chezmoiscripts/` and the
Brewfile first. Fork it, delete what you do not want, and run your fork.

### A Python project

```bash
uvx copier copy gh:zaffnet/whetstone my-project
```

Writes a project with uv, ruff, mypy, basedpyright, pre-commit, pytest, GitHub Actions,
Dependabot, and agent config. `docs/new-project.md` lists the questions. In an existing
project, `uvx copier update` applies newer template versions for you to review and commit.

### The skills only

```bash
npx skills add zaffnet/whetstone
```

Installs the skills in `skills/` into Claude Code, Codex, Cursor, or another agent that
reads `SKILL.md` files. `docs/skills.md` lists them and where each one comes from.

### Claude Code plugins

```bash
claude plugin marketplace add zaffnet/whetstone
# then inside Claude Code:
/plugin install whetstone-skills@whetstone
```

The repo root is a plugin marketplace with three plugins: the skills, the reviewer
subagents, and the hooks.

## What's inside

| Area | Tool | Why |
| --- | --- | --- |
| Shell | zsh + Oh My Zsh | Default on macOS; plugins cover completion and suggestions |
| Prompt | Powerlevel10k, Pure style | Instant prompt, async git status, and a segment that shows the branch's open PR number |
| Terminal | iTerm2 | Shell integration, split panes, the `it2` CLI |
| Editor | Cursor | Settings and keybindings are managed; ruff formats on save |
| Packages | Homebrew with a Brewfile | `brew bundle` installs what is missing and skips what is there |
| Python | uv, ruff, mypy, basedpyright, pyrefly | uv replaces pip, venv, and pyenv; ruff owns style |
| Task runner | just | A file of recipes, readable without knowing make |
| Agent config | `~/.agents` | One copy of skills, MCP servers, and instructions; every agent reads it or links to it. `bin/sync-mcp` copies the servers into `~/.claude.json` and `~/.codex/config.toml`, which each insist on a file of their own |
| Secrets | `~/.zsh_secrets` and `*.local` files | Exported by the shell, read by every tool, never written into a tool's own config |

`docs/uses.md` names the hardware, fonts, and themes behind these choices.

## How it's tested

- The template renders in eight combinations of `use_docker`, `use_fastapi`, and
  `line_length`, and each generated project runs its own pre-commit hooks, `pytest`, and
  `actionlint`. Homebrew installs are the one thing CI does not exercise.
- The Docker variants build, come up under Compose, and answer on `/health`.
- The `home/` tree applies to a clean macOS runner for both roles, and the rendered config
  is asserted with `jq -e` rather than eyeballed.
- One repo covers more than one machine. Machine-specific values sit in `[data.work]` of
  the local chezmoi config.
- Secrets stay in the environment, checked by gitleaks, a local denylist hook, and GitHub
  push protection (`docs/redaction.md`).

`AGENTS.md` is the handbook agents and humans both read, and `REVIEW.md` says what a
reviewer should flag here.

## Keeping it current

- `just sync` pulls edited files back from `$HOME` with `chezmoi re-add`, reports which
  `~/.claude/settings.json` keys drifted, and shows what Homebrew has that the Brewfile
  does not. It cannot pull back a template or a modify script, which is where the agent
  configs live; `docs/new-machine.md` covers what to do then.
- Dependabot bumps GitHub Actions, pre-commit hooks, and the tooling lockfile weekly.
- `macos.yml` and `secrets.yml` also run weekly, so a renamed cask or a leaked string is
  caught when nothing was pushed.

## License

[MIT](LICENSE).
