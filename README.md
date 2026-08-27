# whetstone

[![lint](https://github.com/zaffnet/whetstone/actions/workflows/lint.yml/badge.svg)](https://github.com/zaffnet/whetstone/actions/workflows/lint.yml)
[![template](https://github.com/zaffnet/whetstone/actions/workflows/template.yml/badge.svg)](https://github.com/zaffnet/whetstone/actions/workflows/template.yml)
[![macos](https://github.com/zaffnet/whetstone/actions/workflows/macos.yml/badge.svg)](https://github.com/zaffnet/whetstone/actions/workflows/macos.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

This is how I set up a Mac and a Python project. The repo holds my shell, git, and editor
config as a chezmoi source tree, a Copier template for new Python projects, and the skills,
subagents, and hooks I use with Claude Code, Codex, and Cursor.

I don't currently expect this to be useful to anyone but me. Maybe eventually it will be.

## Requirements

| What | Why | Install |
| --- | --- | --- |
| macOS on Apple silicon | The Brewfile, the `defaults write` script, and the paths assume it | |
| Xcode Command Line Tools | git, which Homebrew and chezmoi need | `xcode-select --install` |
| Homebrew | Installs everything in `home/dot_config/homebrew/Brewfile` | [brew.sh](https://brew.sh); the bootstrap installs it if missing |
| chezmoi | Copies `home/` into `$HOME`, fills in templates, runs the install scripts | `brew install chezmoi` |
| uv | Python and project management; also runs Copier | `brew install uv` |
| just | Runs the recipes in `justfile` | `brew install just` |
| Node | `npx skills` installs the skills into an agent | `brew install node` |
| Claude Code CLI | `claude plugin` installs the plugins | [code.claude.com](https://code.claude.com) |

The template needs Python 3.12 or newer; uv downloads it.

## Install

### A whole Mac

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply zaffnet/whetstone
```

Clones this repo, asks for a name, an email, a role (`personal` or `work`), and where
repositories live, then writes every file under `home/` into `$HOME`, installs the
Brewfile, sets a few macOS defaults, and links the skills. `docs/new-machine.md` has the
long version and the steps for a machine that already has a setup.

Do not run this on a Mac you care about without reading `home/.chezmoiscripts/` and the
Brewfile first. Fork it, delete what you do not want, and run your fork.

### A Python project

```bash
uvx copier copy gh:zaffnet/whetstone my-project
```

Asks a few questions and writes a project with uv, ruff, mypy, basedpyright, pre-commit,
pytest, GitHub Actions, Dependabot, and agent config. `docs/new-project.md` lists the
questions. Later, `uvx copier update` inside the project applies newer template
versions to the working tree; you review the diff and commit it.

### The skills only

```bash
npx skills add zaffnet/whetstone
```

Installs the eleven skills in `skills/` into Claude Code, Codex, Cursor, or another agent
that reads `SKILL.md` files. `docs/skills.md` lists the skills this repo writes or
installs, and where each one comes from.

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
| Python | uv, ruff, mypy, basedpyright, pyrefly | uv replaces pip, venv, and pyenv; ruff owns style; `docs/decisions/0004` explains the three checkers |
| Task runner | just | A file of recipes, readable without knowing make |
| Agent config | `~/.agents` | One copy of skills, MCP servers, and instructions; every agent reads it or links to it |
| Secrets | `~/.zsh_secrets` and `*.local` files | Exported by the shell, read by every tool, never written into a tool's own config |

## How I keep it honest

- Agent configuration has one copy, in `~/.agents`. Claude Code, Cursor, and Kiro link
  their skills directories at it and Codex reads it in place; the instruction files are
  symlinks to this repo's `AGENTS.md`; `~/.cursor/mcp.json` is a symlink to the shared
  `mcp.json`, and `bin/sync-mcp` copies the servers into `~/.claude.json` and
  `~/.codex/config.toml`, which each insist on a file of their own.
- Secrets stay in the environment. No settings file in this repo holds a key, and gitleaks,
  a local denylist hook, and GitHub push protection check that (`docs/redaction.md`).
- Each disabled lint rule, unusual flag, or pinned version has a comment next to it that
  says why.
- Projects made from the template take later template versions with `uvx copier update`,
  then a normal commit.
- CI renders the template in all four `use_docker` and `use_fastapi` combinations and runs
  each result's own pre-commit hooks and tests, builds the Docker variants and hits
  `/health`, and applies the `home/` tree into a clean macOS runner for both roles and runs
  the bats assertions. Homebrew installs are not exercised in CI.
- One repo covers more than one Mac. Machine-specific values sit in `[data.work]` of the
  local chezmoi config.

## Layout

```text
home/                 chezmoi source state for $HOME (.chezmoiroot points here)
  .chezmoiscripts/    Oh My Zsh, Brewfile, macOS defaults, skill links, agent skills, MCP sync
  dot_agents/         ~/.agents: mcp.json, skills.txt, plugin inventory, handbook link
  dot_claude/         settings, statuslines, theme; skills and agents are symlinks
  dot_codex/          config.toml; MCP servers are written by bin/sync-mcp
  dot_config/         git, gh, uv, commitlint, homebrew/Brewfile
  Library/            Cursor user settings and keybindings
skills/               Agent Skills (SKILL.md), installable with npx skills (see docs/skills.md)
agents/               Claude Code reviewer subagents
codex/agents/         The same reviewers as Codex TOML (linked to ~/.codex/agents)
hooks/                Claude Code hooks: ruff on edit, worktree setup
bin/                  Scripts: AI commit messages, PR descriptions, PR merge gate, worktree cleanup, sync-mcp
template/             Copier template for a Python project (copier.yml is at the root)
docs/                 Handbook, decisions, runbooks (CI agent auth in ci-claude-auth.md)
tests/                bats assertions run against an applied home
.github/workflows/    lint, secrets, template, macos
```

## Keeping it current

- `just sync` pulls edited files back from `$HOME` with `chezmoi re-add` and shows what
  Homebrew has that the Brewfile does not.
- Dependabot bumps GitHub Actions, pre-commit hooks, and the tooling lockfile weekly.
- `macos.yml` and `secrets.yml` also run weekly, so a renamed cask or a leaked string is
  caught when nothing was pushed.

## Docs

- [New machine](docs/new-machine.md)
- [New project](docs/new-project.md)
- [Redaction and secrets](docs/redaction.md)
- [Review instructions](REVIEW.md): what a reviewer flags here, and what to leave alone
- [Handbook](AGENTS.md): the conventions agents and humans both read
- [Decisions](docs/decisions/)
- [Uses](docs/uses.md)

## License

[MIT](LICENSE).
