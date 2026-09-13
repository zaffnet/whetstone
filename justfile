
set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

install:
    uv sync -q --all-groups
    GIT_CONFIG_NOSYSTEM=1 uv run pre-commit install

lint:
    uv run pre-commit run --all-files --show-diff-on-failure

apply:
    chezmoi --source . apply

diff:
    chezmoi --source . --no-pager diff

init:
    chezmoi init --source .

bootstrap:
    chezmoi init --apply --source .

sync:
    chezmoi --source . re-add
    python3 bin/sync-claude-settings
    brew bundle dump --force --file=/tmp/whetstone-brewfile
    @echo "lines with > are installed but not in the Brewfile; add them by hand:"
    -diff <(grep -E '^(brew|cask|tap|uv|npm|go) ' home/dot_config/homebrew/Brewfile | sed -E 's/[[:space:]]+#.*$//' | sort) <(grep -E '^(brew|cask|tap|uv|npm|go) ' /tmp/whetstone-brewfile | sort)
    git status --short

new DEST:
    uv run copier copy --vcs-ref HEAD "{{justfile_directory()}}" "{{DEST}}"
    sed -i '' "s|^_src_path: .*|_src_path: $(git remote get-url origin)|" \
        "{{DEST}}/.copier-answers.yml"

validate:
    claude plugin validate .
    claude plugin validate .claude-plugin/plugin.json
    gitleaks dir --no-banner --config .gitleaks.dir.toml .

clean:
    rm -rf .ruff_cache

release VERSION:
    set -euo pipefail
    [[ "{{VERSION}}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "use vMAJOR.MINOR.PATCH"; exit 2; }
    [[ -z "$(git status --porcelain)" ]] || { echo "working tree is dirty"; exit 1; }
    git fetch -q origin --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "push main first"; exit 1; }
    ! git rev-parse -q --verify "refs/tags/{{VERSION}}" >/dev/null || { echo "{{VERSION}} exists; pick the next version"; exit 1; }
    gh release create "{{VERSION}}" --target "$(git rev-parse HEAD)" --title "{{VERSION}}" --generate-notes
    git fetch -q origin --tags
    echo "released {{VERSION}}; projects update with: uvx copier update"
