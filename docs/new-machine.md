# New machine

From a fresh macOS install to a working shell, editor, and agents.

## Steps

1. Install the Xcode command line tools: `xcode-select --install`. Homebrew needs git.
2. Run the bootstrap:

   ```bash
   sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply zaffnet/whetstone
   ```

   It clones the repo to `~/.local/share/chezmoi`, asks for `name`, `email`, `role`
   (`personal` or `work`), and `src_dir` (where repositories live, default `Desktop/src`),
   then applies. Scripts run in order: Oh My Zsh and Powerlevel10k, Homebrew and the
   Brewfile, macOS defaults, skill links, third-party agent skills, MCP sync.

   Non-interactive form, for CI or a script:

   ```bash
   chezmoi init --apply --source <repo> \
     --promptString name=...,email=...,src_dir=Desktop/src \
     --promptChoice role=personal
   ```

3. Create the secrets file and fill it in:

   ```bash
   cp ~/.local/share/chezmoi/home/dot_zsh_secrets.example ~/.zsh_secrets
   chmod 600 ~/.zsh_secrets
   ```

4. If this machine needs a proxy, a private package index, or a branch prefix, open
   `~/.config/chezmoi/chezmoi.toml` and fill the `[data.work]` table (`openai_base_url`,
   `aws_profile`, `pypi_index_url`, `pypi_publish_url`, `branch_prefix`), then
   `chezmoi apply`. Extra shell lines go in `~/.zshrc.local`; git signing and CA bundle
   settings go in `~/.gitconfig.local`.
5. Open a new terminal. Run `p10k configure` only if the prompt glyphs look wrong (the
   Nerd Font casks are in the Brewfile).
6. Install Cursor from [cursor.com](https://www.cursor.com/) if you want it. It is not in
   the Brewfile: it updates itself, so the cask never upgraded it, and adopting an app
   already in `/Applications` fails under macOS App Management and takes the app with it.
7. Sign in: `gh auth login`, `claude`, `codex`, Cursor.

## Day-to-day

| Task | Command |
| --- | --- |
| Edit a managed file | `chezmoi edit ~/.zshrc` then `chezmoi apply`, or edit in the repo and `just apply` |
| See what apply would change | `just diff` (run `just init` first on a new machine; it only writes the config) |
| Pull edits made directly in `$HOME` back into the repo | `just sync` (non-template files only; `chezmoi re-add` skips templates such as `.zshrc`, `.gitconfig`, and `mcp.json`, and modify scripts such as the Claude and Codex configs and the Cursor settings, so edit those with `chezmoi edit` or in `home/`). `just sync` does report which declared keys in `~/.claude/settings.json` differ from the template; `bin/sync-claude-settings --adopt` pulls them, and reporting is the default because the template's value is often the right one. The Codex and Cursor configs have no such pass yet. |
| Re-run the Brewfile after editing it | `just apply` (the script re-runs on Brewfile change) |
| Update the repo from GitHub and apply | `chezmoi update` |

## Cutting over a machine with an existing hand-rolled setup

1. Clone the repo somewhere permanent, for example `~/Desktop/src/whetstone`, and point
   chezmoi at it: `chezmoi init --source ~/Desktop/src/whetstone` (no `--apply` yet).
2. `chezmoi diff`. Read every hunk. Anything that should survive goes into `~/.zshrc.local`,
   `~/.gitconfig.local`, `~/.zsh_secrets`, or `[data.work]`.
3. Back up the files chezmoi will replace. `chezmoi archive` writes the *incoming* state, so
   tar the current files by the managed paths instead:

   ```bash
   chezmoi --source ~/Desktop/src/whetstone managed --include=files \
     | while IFS= read -r f; do [ -e ~/"$f" ] && printf '%s\n' "$f"; done \
     | tar -C ~ -cf ~/whetstone-pre-apply.tar -T -
   ```

4. `chezmoi apply`.
5. Codex rewrites its runtime sections (`[projects.*]`, `[marketplaces.*]`) on next launch
   and asks again to trust each project directory. The apply already ran `sync-mcp`, so the
   MCP server lists in `~/.codex/config.toml` and `~/.claude.json` match `~/.agents/mcp.json`.
6. Confirm the apply landed. `just diff` prints nothing, and every managed symlink resolves
   (scoping this to the managed set matters: Codex and Claude both keep churning broken
   links under `~/.codex/tmp/` and `~/.claude/debug/` that a bare `find` would flag):

   ```bash
   chezmoi --source ~/Desktop/src/whetstone managed --include=symlinks \
     | while IFS= read -r f; do [ -e ~/"$f" ] || printf 'broken: %s\n' "$f"; done
   ```

## CI mode

With `CI=1` set, `.chezmoiignore` skips the Oh My Zsh, Homebrew, macOS defaults, third-party
skill, and MCP sync scripts so the tree can be applied into a throwaway `HOME` in seconds.
`macos.yml` uses it to apply the tree on a clean runner for both roles.
