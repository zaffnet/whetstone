# Recipes for working on whetstone itself. `just` lists them.

set shell := ["bash", "-euo", "pipefail", "-c"]

ci_home := "/tmp/whetstone-home"

default:
    @just --list

# Tooling venv and git hooks.
install:
    uv sync -q --all-groups
    # Some Macs set a system-level core.hooksPath that chains to .git/hooks;
    # pre-commit refuses to install when it sees it, so hide the system gitconfig.
    GIT_CONFIG_NOSYSTEM=1 uv run pre-commit install

# Everything pre-commit runs, on every file.
lint:
    uv run pre-commit run --all-files --show-diff-on-failure

# Write the chezmoi tree into $HOME.
apply:
    chezmoi --source . apply

# Show what `apply` would change.
diff:
    chezmoi --source . --no-pager diff

# Answers the prompts and writes ~/.config/chezmoi/chezmoi.toml, applies nothing.
# Then `just diff` to review and `just apply` to write.
# First-time setup on this machine (asks name, email, role, src_dir).
init:
    chezmoi init --source .

# Fresh machine, no review: init and apply in one step.
bootstrap:
    chezmoi init --apply --source .

# re-add skips templates (.zshrc, .gitconfig, mcp.json, Cursor settings): edit those with
# `chezmoi edit` or in home/. The Brewfile diff drops the tracked file's trailing comments.
# Pull non-template edits made in $HOME back into home/; diff the Brewfile against brew.
sync:
    chezmoi --source . re-add
    brew bundle dump --force --file=/tmp/whetstone-brewfile
    @echo "lines with > are installed but not in the Brewfile; add them by hand:"
    -diff <(grep -E '^(brew|cask|tap|uv|npm|go) ' home/dot_config/homebrew/Brewfile | sed -E 's/[[:space:]]+#.*$//' | sort) <(grep -E '^(brew|cask|tap|uv|npm|go) ' /tmp/whetstone-brewfile | sort)
    git status --short

# bats suite against $HOME (or WHETSTONE_HOME).
test:
    bats tests/

# Apply into a throwaway HOME with CI=1 (no installs), then run the bats suite against it.
test-home:
    rm -rf {{ci_home}} && mkdir -p {{ci_home}}
    CI=1 HOME={{ci_home}} chezmoi --source . init --apply \
        --promptString name=T,email=t@example.com,src_dir=Desktop/src \
        --promptChoice role=personal
    WHETSTONE_HOME={{ci_home}} bats tests/

# Renders the committed tree (HEAD), so commit template edits first.
#
# copier writes the source to .copier-answers.yml verbatim. A relative one resolves to the
# generated project itself and breaks `uvx copier update` there, and this checkout's path
# resolves on this machine only, so rewrite it to the origin URL afterwards. An update then
# needs the ref pushed, which is right for a project someone keeps.
# Generate a Python project from template/ into DEST.
new DEST:
    uv run copier copy --vcs-ref HEAD "{{justfile_directory()}}" "{{DEST}}"
    sed -i '' "s|^_src_path: .*|_src_path: $(git remote get-url origin)|" \
        "{{DEST}}/.copier-answers.yml"

# Plugin and marketplace manifests, and a secret scan over tracked and untracked files.
validate:
    claude plugin validate .
    claude plugin validate .claude-plugin/plugin.json
    gitleaks dir --no-banner .

# Remove caches and the throwaway HOME.
clean:
    rm -rf {{ci_home}} .ruff_cache .pytest_cache

# Release the template from a clean, pushed main. One gh call creates the tag and the GitHub
# Release together, so a failure leaves nothing half-done. Tags are immutable on GitHub
# (ruleset "released-tags-are-immutable"); to fix a release, cut the next one.
# Downstream projects pick it up with `uvx copier update`.
release VERSION:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{VERSION}}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "use vMAJOR.MINOR.PATCH"; exit 2; }
    [[ -z "$(git status --porcelain)" ]] || { echo "working tree is dirty"; exit 1; }
    git fetch -q origin --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "push main first"; exit 1; }
    ! git rev-parse -q --verify "refs/tags/{{VERSION}}" >/dev/null || { echo "{{VERSION}} exists; pick the next version"; exit 1; }
    gh release create "{{VERSION}}" --target "$(git rev-parse HEAD)" --title "{{VERSION}}" --generate-notes
    git fetch -q origin --tags
    echo "released {{VERSION}}; projects update with: uvx copier update"
