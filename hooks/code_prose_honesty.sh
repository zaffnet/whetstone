#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

HONESTY_NAME=code_prose_honesty
HONESTY_BRIEF=agents/code-honesty-auditor.md
HONESTY_GLOBS=(
  '*.py' '*.pyi' '*.sh' '*.bash' '*.zsh' '*.sql' '*.tf' '*.hcl'
  '*.js' '*.jsx' '*.mjs' '*.cjs' '*.ts' '*.tsx' '*.vue' '*.svelte'
  '*.java' '*.kt' '*.kts' '*.go' '*.rs' '*.rb' '*.php' '*.swift' '*.scala' '*.cs'
  '*.c' '*.h' '*.cc' '*.cpp' '*.hpp' '*.yaml' '*.yml' '*.toml'
  '*.jinja' '*.tmpl' '*.mk' 'justfile' 'Justfile' 'Makefile' 'Dockerfile'
  '*Brewfile' '*CODEOWNERS' '*ignore' '*.shellcheckrc' '*.worktreeinclude'
  '*.chezmoiremove' '*.env.example' '*dot_zprofile' '*dot_zshenv'
  '*dot_zsh_secrets.example'
)
HONESTY_SHEBANG_GLOBS=('bin/*' 'home/*')
HONESTY_LEAD="The turn that just ended changed some code. Cut the comment text a later
reader cannot use. Where a finding names one clause worth keeping, keep that clause and
delete the rest. Where it names none, delete the whole comment. For a suppression,
remove it and fix what the checker reported.

Where the language requires a doc comment on a public interface and a checker enforces
it, shrink that comment rather than deleting it.

The line numbers come from that turn and may have moved, so re-read the file before you
edit it."

# shellcheck source-path=SCRIPTDIR source=_honesty.sh
source "${BASH_SOURCE[0]%/*}/_honesty.sh"
