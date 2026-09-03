#!/usr/bin/env bash
# Stop hook. Asks a headless Claude whether the comments, docstrings, and checker
# suppressions in this turn's code diff are honest about the code, reports what it
# finds, and lets the turn end. Markdown and text files are prose_honesty.sh's
# business.
# shellcheck source-path=SCRIPTDIR source=_common.sh
source "${BASH_SOURCE[0]%/*}/_common.sh"

HONESTY_NAME=code_prose_honesty
HONESTY_BRIEF=agents/code-honesty-auditor.md
# Every language whose comments this audits. A shell script's comments went
# unaudited while this listed Python alone: prose_honesty.sh takes only markdown and
# text, so anything absent here is checked by neither hook.
HONESTY_GLOBS=(
  '*.py' '*.pyi'
  '*.sh' '*.bash' '*.zsh'
  '*.js' '*.jsx' '*.mjs' '*.cjs' '*.ts' '*.tsx'
  '*.java' '*.kt' '*.kts'
  '*.go' '*.rs' '*.rb' '*.php' '*.swift' '*.scala' '*.cs'
  '*.c' '*.h' '*.cc' '*.cpp' '*.hpp'
  '*.sql' '*.vue' '*.svelte'
  '*.tf' '*.hcl'
  '*.yaml' '*.yml' '*.toml'
  'justfile' 'Justfile' 'Makefile' 'Dockerfile' '*.mk'
  # Every template, whatever it renders to. Not '*.py.jinja' and siblings: a
  # template's name can carry a Jinja conditional -- `settings.py{% endif %}.jinja`
  # -- so the inner extension is not a suffix to match on. A '*.md.jinja' lands
  # here rather than with prose_honesty.sh, which is the right side of the line: a
  # template is code the moment its name or body holds Jinja.
  '*.jinja'
)
HONESTY_LEAD="Comment text that a later reader cannot use. Cut it. Where a finding
names one clause worth keeping, keep that clause and delete the rest; where it
names none, delete the whole comment. For a suppression, remove it and fix what
the checker reported.

Where the language requires a doc comment on a public interface and a checker
enforces it, shrink that comment rather than deleting it."

# shellcheck source-path=SCRIPTDIR source=_honesty.sh
source "${BASH_SOURCE[0]%/*}/_honesty.sh"
