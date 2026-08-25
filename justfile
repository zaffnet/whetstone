# Recipes for working on whetstone itself. `just` lists them.

set shell := ["bash", "-euo", "pipefail", "-c"]

ci_home := "/tmp/whetstone-home"

default:
    @just --list

# Tooling venv and git hooks.
install:
    uv sync -q --all-groups
    # Some managed Macs set a system-level core.hooksPath that chains to .git/hooks;
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

# First-time setup on this machine (asks name, email, role, src_dir).
# First run on a machine: answer the prompts, write ~/.config/chezmoi/chezmoi.toml, apply nothing.
# Then `just diff` to review and `just apply` to write.
init:
    chezmoi init --source .

# Fresh machine, no review: init and apply in one step.
bootstrap:
    chezmoi init --apply --source .

# Pull edits made directly in $HOME back into the repo and refresh the Brewfile.
sync:
    chezmoi --source . re-add
    brew bundle dump --describe --force --file=home/dot_config/homebrew/Brewfile
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

# Generate a Python project from template/ into DEST.
new DEST:
    uv run copier copy --trust . {{DEST}}

# Plugin manifest and secret scan.
validate:
    claude plugin validate .
    gitleaks dir --no-banner .

# Remove caches and the throwaway HOME.
clean:
    rm -rf {{ci_home}} .ruff_cache .pytest_cache
