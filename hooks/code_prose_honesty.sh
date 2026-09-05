#!/usr/bin/env bash
# Stop hook, backgrounded through "asyncRewake": true. Asks a headless Claude whether
# the comments, docstrings, and checker suppressions in the ending turn's code diff are
# honest about the code, and reports what it finds at the start of the next turn without
# delaying this one. Markdown and text files are prose_honesty.sh's business.
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
  # Every template, whatever it renders to. Not '*.py.jinja' and siblings: the inner
  # extension is not a suffix to match on, because a name can carry a Jinja
  # conditional (`settings.py{% endif %}.jinja`) or a chezmoi attribute prefix
  # (`run_after_40-sync-mcp.sh.tmpl`). A '*.md.jinja' therefore lands here rather
  # than with prose_honesty.sh: a template is code once its name or body holds
  # template syntax.
  '*.jinja' '*.tmpl'
  # Extensionless config, which no suffix pattern reaches. Named individually
  # because these are identified by their name alone, unlike the scripts below.
  # Each carries a leading '*': a bare name is a pathspec anchored to the
  # repository root, so it would miss home/dot_zprofile and the rest.
  '*Brewfile' '*dot_zprofile' '*dot_zshenv'
  # Config whose whole name is its format, comment syntax included. The rendered
  # names as well as the templates: a generated project's CODEOWNERS and
  # .env.example carry no .jinja suffix once written.
  #
  # One '*ignore' rather than a name apiece: every ignore file this repository
  # writes takes '#' comments, and the set keeps growing -- .gitignore,
  # .cursorignore, .chezmoiignore, git's bare config/git/ignore -- so a per-name
  # list is a list that goes stale silently.
  '*ignore' '*.shellcheckrc' '*.worktreeinclude'
  '*.chezmoiremove' '*dot_zsh_secrets.example'
  '*CODEOWNERS' '*.env.example'
)

# Extensionless code, kept only when the file opens with a shebang: the whole of
# bin/ is scripts today, and a suffix cannot tell a future fixture from a script.
HONESTY_SHEBANG_GLOBS=('bin/*' 'home/*')
HONESTY_LEAD="Comment text that a later reader cannot use, in what the turn that just
ended changed. Cut it. Where a finding names one clause worth keeping, keep that clause
and delete the rest; where it names none, delete the whole comment. For a suppression,
remove it and fix what the checker reported.

Where the language requires a doc comment on a public interface and a checker
enforces it, shrink that comment rather than deleting it.

Line numbers are from that turn and may have shifted; re-read before editing."

# shellcheck source-path=SCRIPTDIR source=_honesty.sh
source "${BASH_SOURCE[0]%/*}/_honesty.sh"
