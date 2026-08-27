# Uses

- Machine: MacBook Pro (Apple silicon), macOS.
- Terminal: iTerm2, zsh, Oh My Zsh, Powerlevel10k in the Pure style with an added segment for
  the branch's open PR number. Terminal font: Fira Code Medium. The profile is managed, as an
  iTerm2 Dynamic Profile in `home/Library/Application Support/iTerm2/DynamicProfiles/` --
  iTerm2 reads that file and never writes back, so it survives an apply. The preferences
  plist is not managed: most of its keys are window frames and session state that the app
  rewrites on every quit.
- Editor: Cursor. Editor font:
  Fira Code; terminal font inside the editor: JetBrainsMono Nerd Font. Theme: Quiet Light.
- Python: uv, ruff, mypy, basedpyright, pyrefly, pytest.
- Git: `git-delta` for diffs, `gh` with the `gh-stack` extension for stacked PRs, commitlint
  for message format, `zdiff3` conflict style, `rerere` on.
- Agents: Claude Code (statusline and theme in `home/dot_claude`), Codex CLI and desktop,
  Cursor agent. Skills and MCP servers shared through `~/.agents`.
- Utilities: fzf, ripgrep, jq, tmux, htop, tree, Caffeine, Maccy.
- Data: Beekeeper Studio, DBeaver.
