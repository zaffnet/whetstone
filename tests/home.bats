#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Assertions against an applied chezmoi tree. Run against the real home with `just test`,
# or against the throwaway CI home with `just test-home` (sets WHETSTONE_HOME). The macOS
# workflow applies into the runner's own HOME, so CI=1 also counts as a throwaway home.
#
# Four conditions skip a test. The rule, not a count, because a count goes stale the moment
# a case is added -- and a skip nobody knows about is what let the regression through on #10:
#
#   real home without CI  the cases named "(CI home only)", which write to or delete from
#                         the home, and `the secrets file is not managed`, which a
#                         hand-made ~/.zsh_secrets would fail
#   role is work          `git identity comes from chezmoi data`, the one role where
#                         .gitconfig is deliberately unmanaged
#   config predates       `a bare chezmoi command resolves this checkout`; a throwaway or
#   sourceDir             CI home is regenerated every time, so there it always runs
#   no ~/.zsh_secrets     `the secrets file, when present, is readable only by its owner`,
#                         which therefore never runs in CI -- only a real machine with
#                         secrets exercises it
#
# macos.yml asserts that exactly this set skips, so a new one cannot arrive unannounced.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  H="${WHETSTONE_HOME:-$HOME}"
  export REPO H
}

resolves_to() {
  local link=$1 expected=$2
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$expected" ]
}

chezmoi_role() {
  sed -nE 's/^ *role = "([a-z]+)"$/\1/p' "$H/.config/chezmoi/chezmoi.toml"
}

chezmoi_managed() {
  HOME="$H" chezmoi --source "$REPO" managed
}

@test "managed files exist" {
  for f in .zshrc .p10k.zsh .claude/settings.json .codex/config.toml \
    .agents/mcp.json .config/homebrew/Brewfile .cursor/cli-config.json; do
    [ -f "$H/$f" ]
  done
}

@test ".gitconfig is managed on personal machines only" {
  if [ "$(chezmoi_role)" = personal ]; then
    chezmoi_managed | grep -qxF '.gitconfig'
    [ -f "$H/.gitconfig" ]
  else
    run ! bash -c "HOME='$H' chezmoi --source '$REPO' managed | grep -qxF .gitconfig"
  fi
}

@test "every agent's skills directory points at ~/.agents/skills" {
  resolves_to "$H/.claude/skills" "$H/.agents/skills"
  resolves_to "$H/.cursor/skills" "$H/.agents/skills"
  resolves_to "$H/.kiro/skills" "$H/.agents/skills"
}

@test "each hand-written skill resolves into the repo and has a SKILL.md" {
  for dir in "$REPO"/skills/*/; do
    s="$(basename "$dir")"
    resolves_to "$H/.agents/skills/$s" "$REPO/skills/$s"
    [ -f "$H/.agents/skills/$s/SKILL.md" ]
  done
}

@test "every symlink_* under home/dot_local/bin resolves to an executable in bin/" {
  for tmpl in "$REPO"/home/dot_local/bin/symlink_*.tmpl; do
    s="$(basename "$tmpl" .tmpl)"
    s="${s#symlink_}"
    resolves_to "$H/.local/bin/$s" "$REPO/bin/$s"
    [ -x "$H/.local/bin/$s" ]
  done
  resolves_to "$H/.agents/bin/sync-mcp" "$REPO/bin/sync-mcp"
}

@test "agent instruction files resolve to the repo AGENTS.md and handbook" {
  resolves_to "$H/.codex/AGENTS.md" "$REPO/AGENTS.md"
  resolves_to "$H/.claude/CLAUDE.md" "$REPO/AGENTS.md"
  resolves_to "$H/.cursor/AGENTS.md" "$REPO/AGENTS.md"
  resolves_to "$H/.agents/handbook" "$REPO/docs/handbook"
}

# Asserts the declaration, not the files: the externals are CI-ignored, and a case that
# skipped in CI would have to be added to the set macos.yml pins. Both properties are the
# point of fetching at all -- a moving branch lets content change under a passing checksum,
# and no checksum lets it change silently.
@test "every external is pinned to a commit and checksummed" {
  ext="$REPO/home/.chezmoiexternal.toml"
  [ -f "$ext" ]
  run python3 -c '
import re, sys, tomllib, pathlib

externals = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert externals, "no externals declared"
for path, spec in externals.items():
    url = spec["url"]
    sha = spec.get("checksum", {}).get("sha256", "")
    assert re.search(r"/[0-9a-f]{40}/", url), f"{path}: url is not pinned to a commit: {url}"
    assert re.fullmatch(r"[0-9a-f]{64}", sha), f"{path}: missing or malformed sha256"
' "$ext"
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
}

@test "reviewer subagents are linked for Claude Code and Codex" {
  resolves_to "$H/.claude/agents" "$REPO/agents"
  resolves_to "$H/.codex/agents" "$REPO/codex/agents"
}

@test "statusline scripts arrive executable" {
  [ -x "$H/.claude/statusline-command.sh" ]
  [ -x "$H/.claude/subagent-statusline.sh" ]
}

# The terminal was the one thing every machine disagreed about -- cursor shape, font --
# because nothing managed it. A Dynamic Profile is iTerm2's own mechanism for a profile that
# comes from a file: it reads it live and never writes back, so it survives an apply and does
# not churn the way the preferences plist does.
@test "the iTerm2 profile is managed and is the default" {
  profile="$H/Library/Application Support/iTerm2/DynamicProfiles/whetstone.json"
  [ -f "$profile" ]

  # Parsed the way iTerm2 parses it, not with jq. jq accepts `Infinity`, which Python's
  # json.dumps emits and NSJSONSerialization rejects -- the profile was silently unreadable
  # while a jq-based assertion called it valid. `plutil -convert` is Foundation's parser.
  # (`plutil -lint` is not: it rejects even `{"a": 1}`.)
  plutil -convert xml1 -o /dev/null "$profile"
  run ! grep -qE '\b(Infinity|-Infinity|NaN)\b' "$profile"

  jq -e '.Profiles | length == 1' "$profile" >/dev/null

  # The Guid is what `Default Bookmark Guid` points at, so it has to be stable rather than
  # the machine-generated one the profile was captured from.
  [ "$(jq -r '.Profiles[0].Guid' "$profile")" = whetstone-default ]
  [ "$(jq -r '.Profiles[0].Name' "$profile")" = Whetstone ]

  # Key bindings travel with the profile. They used to live in the app-level GlobalKeyMap,
  # which is not part of a Dynamic Profile, so a second machine got the profile's look and
  # none of its keys -- no word-wise Option+Delete, Option+Left, Option+Right. A profile
  # keymap takes precedence over the global one, so moving them here carries them.
  [ "$(jq -r '.Profiles[0]["Keyboard Map"] | length' "$profile")" -ge 18 ]
  # Option+Delete sends ^W, which is what deletes a word backward.
  [ "$(jq -r '.Profiles[0]["Keyboard Map"]["0x7f-0x80000-0x33"].Text' "$profile")" = "0x17" ]
  # Option+d sends Esc-d, which is what deletes a word forward.
  [ "$(jq -r '.Profiles[0]["Keyboard Map"]["0x64-0x80000-0x2"].Text' "$profile")" = "0x1b 0x64" ]
  # Option+Left and Option+Right send the word-motion escapes.
  [ "$(jq -r '.Profiles[0]["Keyboard Map"]["0xf702-0x280000-0x7b"].Text' "$profile")" = b ]
  [ "$(jq -r '.Profiles[0]["Keyboard Map"]["0xf703-0x280000-0x7c"].Text' "$profile")" = f ]

  # The settings that differed between machines, pinned so a drifting one is a failure.
  [ "$(jq -r '.Profiles[0]["Cursor Type"]' "$profile")" = 1 ]
  [ "$(jq -r '.Profiles[0]["Blinking Cursor"]' "$profile")" = true ]
  [ "$(jq -r '.Profiles[0]["Normal Font"]' "$profile")" = "FiraCodeRoman-Medium 13" ]

  # The applied file carries this machine's home, and the source carries none: the working
  # directory is templated, so the profile is not pinned to whoever captured it.
  [ "$(jq -r '.Profiles[0]["Working Directory"]' "$profile")" = "$H" ]
  run ! grep -qE '"/Users/[a-z0-9]+"' \
    "$REPO/home/Library/Application Support/iTerm2/DynamicProfiles/whetstone.json.tmpl"
}

# Comparing the two Macs is what found these; reading one could not, because a value that
# is set looks identical to one that is defaulted. The script is the only record that they
# are deliberate, so the test pins that it still writes them rather than that the machine
# currently has them -- a real home may have been changed by hand since.
@test "the managed defaults are written, retired, and retried" {
  script="$BATS_TEST_TMPDIR/managed.sh"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/.chezmoiscripts/run_after_20-macos-managed-defaults.sh.tmpl" >"$script"
  bash -n "$script"
  # The system bash is 3.2 and this uses arrays under `set -u`; the newer bash on PATH
  # would not catch an unguarded empty expansion.
  /bin/bash -n "$script"

  stub="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$stub"
  # Matched exactly. A `*iTerm*` pattern answers for `application "iTermBogus" is running`
  # too, so a script that queried the wrong application would still look guarded.
  cat >"$stub/osascript" <<'STUB'
#!/usr/bin/env bash
if [ "$*" = '-e application "iTerm" is running' ]; then
  echo "$FAKE_ITERM_RUNNING"
  exit 0
fi
echo "unexpected-query: $*"
STUB
  # Distinguishes `defaults read <domain>` from `defaults read <domain> <key>`: a readable
  # domain says nothing about whether the key is still there.
  cat >"$stub/defaults" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$DEFAULTS_LOG"
case "$1" in
  write) [ "$3" != "${FAIL_ON_KEY:-}" ] || exit 1 ;;
  delete) [ -z "${DELETE_FAILS:-}" ] || exit 1 ;;
  read)
    if [ "$#" -ge 3 ]; then
      [ -n "${KEY_PRESENT:-}" ] || exit 1
    else
      [ -z "${DOMAIN_UNREADABLE:-}" ] || exit 1
    fi
    ;;
esac
exit 0
STUB
  printf '#!/usr/bin/env bash\nexit 0\n' >"$stub/killall"
  chmod +x "$stub/osascript" "$stub/defaults" "$stub/killall"

  home1="$BATS_TEST_TMPDIR/h1"
  mkdir -p "$home1"
  log="$BATS_TEST_TMPDIR/w-running.log"
  : >"$log"
  # iTerm2 up: Finder and Dock still apply, iTerm2 does not, and the apply carries on.
  run env PATH="$stub:$PATH" HOME="$home1" FAKE_ITERM_RUNNING=true DEFAULTS_LOG="$log" \
    bash "$script"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^write com.apple.finder' "$log")" -eq 5 ]
  [ "$(grep -c '^write com.apple.dock' "$log")" -eq 8 ]
  [ "$(grep -c '^write com.googlecode.iterm2' "$log")" -eq 0 ]

  # An osascript that fails must skip too, not fall through to the writes.
  log="$BATS_TEST_TMPDIR/w-broken.log"
  : >"$log"
  cat >"$stub/osascript" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$stub/osascript"
  run env PATH="$stub:$PATH" HOME="$home1" DEFAULTS_LOG="$log" bash "$script"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^write com.googlecode.iterm2' "$log")" -eq 0 ]
  cat >"$stub/osascript" <<'STUB'
#!/usr/bin/env bash
if [ "$*" = '-e application "iTerm" is running' ]; then
  echo "$FAKE_ITERM_RUNNING"
  exit 0
fi
echo "unexpected-query: $*"
STUB
  chmod +x "$stub/osascript"

  home2="$BATS_TEST_TMPDIR/h2"
  mkdir -p "$home2"
  log="$BATS_TEST_TMPDIR/w-quit.log"
  : >"$log"
  run env PATH="$stub:$PATH" HOME="$home2" FAKE_ITERM_RUNNING=false DEFAULTS_LOG="$log" \
    bash "$script"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^write com.googlecode.iterm2' "$log")" -eq 14 ]
  while IFS= read -r written; do
    [ -n "$written" ] || continue
    grep -qFx -- "$written" "$log" || {
      echo "not written: $written"
      return 1
    }
  done <<'WRITES'
write com.apple.finder FXDefaultSearchScope -string SCcf
write com.apple.finder NewWindowTarget -string PfAF
write com.apple.dock wvous-bl-corner -int 5
write com.apple.dock wvous-br-modifier -int 0
write com.googlecode.iterm2 FocusFollowsMouse -bool true
write com.googlecode.iterm2 SplitPaneDimmingAmount -float 0.2518520555218447
write com.googlecode.iterm2 Selection Respects Soft Boundaries -bool true
write com.googlecode.iterm2 Default Bookmark Guid -string whetstone-default
WRITES
  # A permission, not a look: iTerm2 ships it off and this repository does not turn it on.
  code="$BATS_TEST_TMPDIR/code.sh"
  grep -vE '^[[:space:]]*#' "$script" >"$code"
  run ! grep -q 'AllowClipboardAccess' "$code"

  # Retiring one declaration retires the key. Cutting every line that mentions it would
  # hide a second copy, and a second copy is what stopped retirement working before.
  retired="$BATS_TEST_TMPDIR/retired.sh"
  grep -v '"ShowFullScreenTabBar|-bool|false"' "$script" >"$retired"
  [ "$(grep -c 'ShowFullScreenTabBar' "$retired")" -eq 0 ]
  keys="$home2/.local/state/whetstone/macos-iterm2-managed-keys.txt"

  log="$BATS_TEST_TMPDIR/w-retire.log"
  : >"$log"
  run env PATH="$stub:$PATH" HOME="$home2" FAKE_ITERM_RUNNING=false DEFAULTS_LOG="$log" \
    bash "$retired"
  [ "$status" -eq 0 ]
  grep -qFx 'delete com.googlecode.iterm2 ShowFullScreenTabBar' "$log"
  [ "$(grep -c '^delete' "$log")" -eq 1 ]
  run ! grep -qFx 'ShowFullScreenTabBar' "$keys"

  # Delete fails and the key still reads: carried, whatever the domain says. Forgetting it
  # here would strand the value, because nothing later would know it had been managed.
  home3="$BATS_TEST_TMPDIR/h3"
  mkdir -p "$home3"
  keys3="$home3/.local/state/whetstone/macos-iterm2-managed-keys.txt"
  run env PATH="$stub:$PATH" HOME="$home3" FAKE_ITERM_RUNNING=false \
    DEFAULTS_LOG="$BATS_TEST_TMPDIR/w3a.log" bash "$script"
  [ "$status" -eq 0 ]
  run env PATH="$stub:$PATH" HOME="$home3" FAKE_ITERM_RUNNING=false \
    DEFAULTS_LOG="$BATS_TEST_TMPDIR/w3b.log" DELETE_FAILS=1 KEY_PRESENT=1 bash "$retired"
  [ "$status" -eq 0 ]
  grep -qFx 'ShowFullScreenTabBar' "$keys3"

  # Delete fails, the key does not read, and neither does the domain: the failure is about
  # the domain, so it is carried rather than assumed gone.
  home4="$BATS_TEST_TMPDIR/h4"
  mkdir -p "$home4"
  keys4="$home4/.local/state/whetstone/macos-iterm2-managed-keys.txt"
  run env PATH="$stub:$PATH" HOME="$home4" FAKE_ITERM_RUNNING=false \
    DEFAULTS_LOG="$BATS_TEST_TMPDIR/w4a.log" bash "$script"
  [ "$status" -eq 0 ]
  run env PATH="$stub:$PATH" HOME="$home4" FAKE_ITERM_RUNNING=false \
    DEFAULTS_LOG="$BATS_TEST_TMPDIR/w4b.log" DELETE_FAILS=1 DOMAIN_UNREADABLE=1 bash "$retired"
  [ "$status" -eq 0 ]
  grep -qFx 'ShowFullScreenTabBar' "$keys4"

  # Copilot on #39: a key is owned from the moment its own write lands. Recording the whole
  # batch at the end meant a later write failing left every earlier key unowned, so retiring
  # one of them afterwards would delete nothing. Pruning still waits for the batch, because
  # a key missing due to a failed write is not a retired key.
  partial="$BATS_TEST_TMPDIR/h6"
  mkdir -p "$partial"
  log="$BATS_TEST_TMPDIR/w-partial.log"
  : >"$log"
  run env PATH="$stub:$PATH" HOME="$partial" FAKE_ITERM_RUNNING=false DEFAULTS_LOG="$log" \
    FAIL_ON_KEY=tilesize bash "$script"
  [ "$status" -ne 0 ]

  dock_keys="$partial/.local/state/whetstone/macos-dock-managed-keys.txt"
  # The three written before the failure are owned; the one that failed is not.
  grep -qFx 'autohide' "$dock_keys"
  grep -qFx 'show-recents' "$dock_keys"
  grep -qFx 'expose-group-apps' "$dock_keys"
  run ! grep -qFx 'tilesize' "$dock_keys"
  # And nothing was pruned on the way out: an interrupted batch must not delete anything.
  run ! grep -q '^delete' "$log"

  # Copilot on #39: the key file is replaced, not truncated and rewritten. A rewrite that
  # dies halfway would forget the carried keys permanently, so a failing rename must leave
  # the previous list untouched rather than an empty or half-written file.
  atomic="$BATS_TEST_TMPDIR/h7"
  mkdir -p "$atomic"
  # Finder is the first domain, so its rewrite is the one the failing rename catches.
  keys7="$atomic/.local/state/whetstone/macos-finder-managed-keys.txt"
  run env PATH="$stub:$PATH" HOME="$atomic" FAKE_ITERM_RUNNING=false \
    DEFAULTS_LOG="$BATS_TEST_TMPDIR/w7a.log" bash "$script"
  [ "$status" -eq 0 ]
  before="$(cat "$keys7")"
  [ -n "$before" ]
  printf '#!/usr/bin/env bash\nexit 1\n' >"$stub/mv"
  chmod +x "$stub/mv"
  run env PATH="$stub:$PATH" HOME="$atomic" FAKE_ITERM_RUNNING=false \
    DEFAULTS_LOG="$BATS_TEST_TMPDIR/w7b.log" bash "$script"
  [ "$status" -ne 0 ]
  [ "$(cat "$keys7")" = "$before" ]
  # And no half-written temporary file is left behind for the next apply to trip over.
  [ "$(find "$(dirname "$keys7")" -name 'macos-finder-managed-keys.txt.*' | wc -l)" -eq 0 ]
  rm -f "$stub/mv"

  # Retiring the last setting of a domain must not abort: an empty array under `set -u` is
  # an unbound variable on bash 3.2, which would take the whole apply down.
  empty="$BATS_TEST_TMPDIR/empty.sh"
  python3 - "$script" "$empty" <<'PYEOF'
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
text = re.sub(r'managed_dock_settings=\(\n(?:.*?\n)*?\)\n', 'managed_dock_settings=()\n', text)
open(dst, 'w').write(text)
PYEOF
  log="$BATS_TEST_TMPDIR/w-empty.log"
  : >"$log"
  run env PATH="$stub:$PATH" HOME="$BATS_TEST_TMPDIR/h5" FAKE_ITERM_RUNNING=false \
    DEFAULTS_LOG="$log" /bin/bash "$empty"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^write com.apple.dock' "$log")" -eq 0 ]
}

@test "Claude settings carry no env block" {
  jq -e 'has("env") | not' "$H/.claude/settings.json"
}

# The `cursor` CLI lives inside the app bundle and nothing else puts it on PATH, so a login
# shell without this has no `cursor` -- which ~/.codex/config.toml names as file_opener. It
# used to be a hand-added line in ~/.zprofile, so an apply deleted it.
@test ".zprofile puts Cursor on PATH when it is installed, and is quiet when it is not" {
  installed="$BATS_TEST_TMPDIR/installed"
  mkdir -p "$installed/Applications/Cursor.app/Contents/Resources/app/bin"
  : >"$installed/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
  chmod +x "$installed/Applications/Cursor.app/Contents/Resources/app/bin/cursor"

  run env -i HOME="$installed" PATH=/usr/bin:/bin \
    /bin/zsh -c ". '$H/.zprofile'; command -v cursor"
  [ "$status" -eq 0 ]
  [ "$output" = "$installed/Applications/Cursor.app/Contents/Resources/app/bin/cursor" ]

  # Copilot on #32: a bundle left half-deleted keeps an empty bin/, which must not be picked
  # and must not stop the search -- the launcher is what makes a directory worth adding.
  hollow="$BATS_TEST_TMPDIR/hollow"
  mkdir -p "$hollow/Applications/Cursor.app/Contents/Resources/app/bin"
  run env -i HOME="$hollow" PATH=/usr/bin:/bin \
    /bin/zsh -c ". '$H/.zprofile'; printf %s \"\$PATH\""
  [ "$status" -eq 0 ]
  [[ "$output" != *"$hollow"*Cursor.app* ]]

  # Copilot on #32, second round: an inherited variable must come out untouched. Unsetting
  # the iterator destroyed it just as surely as overwriting it did, so there is no iterator
  # now -- but the assertion is about what the caller sees, not about how it is spelled.
  run env -i HOME="$installed" PATH=/usr/bin:/bin cursor_bin=mine dir=mine \
    /bin/zsh -c ". '$H/.zprofile'; printf '%s %s' \"\${cursor_bin-<unset>}\" \"\${dir-<unset>}\""
  [ "$status" -eq 0 ]
  [ "$output" = "mine mine" ]

  # A machine with no Cursor sources the same file without error and without the entry.
  # Skipped when Cursor is installed in /Applications, which the loop finds whatever HOME is.
  if [ ! -d /Applications/Cursor.app ]; then
    run env -i HOME="$BATS_TEST_TMPDIR/bare" PATH=/usr/bin:/bin \
      /bin/zsh -c ". '$H/.zprofile'; printf %s \"\$PATH\""
    [ "$status" -eq 0 ]
    [[ "$output" != *Cursor.app* ]]
  fi
}

@test ".zshrc exports no CA bundle" {
  run ! grep -Eq '(SSL_CERT_FILE|REQUESTS_CA_BUNDLE|NODE_EXTRA_CA_CERTS|CURL_CA_BUNDLE)=' "$H/.zshrc"
}

@test "git identity comes from chezmoi data (CI home only)" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "real home uses the machine's own identity"; fi
  if [ "$(chezmoi_role)" = work ]; then skip ".gitconfig is unmanaged when role is work"; fi
  [ "$(git config -f "$H/.gitconfig" user.name)" = T ]
  [ "$(git config -f "$H/.gitconfig" user.email)" = t@example.com ]
}

# Issue #25: the modify_ scripts render to bash that runs on every apply, and nothing
# checked the result parses. While writing #19 the Cursor one did not -- a rendered body
# with an unbalanced apostrophe broke a heredoc inside $( ) under bash 3.2, the system bash
# on macOS. It surfaced only because the script was being run by hand at the time; an apply
# would have failed on a real machine.
@test "every modify_ script renders to bash that parses" {
  found=0
  while IFS= read -r -d "" tmpl; do
    found=$((found + 1))
    script="$BATS_TEST_TMPDIR/rendered-$found.sh"
    HOME="$H" chezmoi --source "$REPO" execute-template <"$tmpl" >"$script"
    # /bin/bash is 3.2 on macOS and is what an apply runs the script under. A newer bash
    # earlier on PATH accepts what 3.2 rejects, so parse under both rather than either.
    for shell in bash /bin/bash; do
      command -v "$shell" >/dev/null || continue
      run "$shell" -n "$script"
      if [ "$status" -ne 0 ]; then
        echo "$tmpl does not parse under $("$shell" --version | head -1)"
        echo "$output"
        return 1
      fi
    done
  done < <(find "$REPO/home" -name "modify_*.tmpl" -print0)

  # Data-driven, so a new modify script is covered without touching this test. The floor is
  # a vacuity guard: a rename that stops matching the glob would otherwise pass silently.
  [ "$found" -ge 3 ]
}

# Copilot on #10: nothing fed live state through the modify script, which is where two
# keys were being dropped. Seed a bare key and three tables the template does not declare,
# one of them nested under a table it does declare.
@test "the Codex modify script keeps undeclared state and is idempotent" {
  script="$BATS_TEST_TMPDIR/modify.sh"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/dot_codex/modify_private_config.toml.tmpl" >"$script"

  # notify spans lines and holds a blank and a comment line, which are valid inside a
  # multiline value: capturing has to run to the next key, not stop at the first blank.
  seeded="$BATS_TEST_TMPDIR/seeded.toml"
  {
    printf 'notify = [\n  # the client\n  "/opt/notifier",\n\n  "turn-ended",\n]\n\n'
    printf '[plugins."browser@openai-bundled"] # trailing comment\nenabled = true\n\n'
    # [tui] is declared, [tui.model_availability_nux] is not: it is Codex's own state, and
    # the KEEP allowlist this script replaced named it for exactly that reason. The
    # status_line_use_colors line below it must still lose to the template.
    printf '[tui]\nstatus_line_use_colors = false\n\n'
    printf '[tui.model_availability_nux]\nseen = true\n\n'
    printf '[mcp_servers.private]\ncommand = "x"\n'
  } >"$seeded"

  first="$BATS_TEST_TMPDIR/first.toml"
  bash "$script" <"$seeded" >"$first"
  grep -qF '"/opt/notifier",' "$first"
  grep -qF '"turn-ended",' "$first"
  grep -qF '[plugins."browser@openai-bundled"]' "$first"
  grep -qF '[tui.model_availability_nux]' "$first"
  grep -qF '[mcp_servers.private]' "$first"
  # A declared table is still rewritten whole, so the template's value wins.
  grep -qF 'status_line_use_colors = true' "$first"
  run grep -qF 'status_line_use_colors = false' "$first"
  [ "$status" -ne 0 ]
  # tomllib needs 3.11+; the system python3 on macOS is 3.9.
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$first"

  second="$BATS_TEST_TMPDIR/second.toml"
  bash "$script" <"$first" >"$second"
  diff "$first" "$second"

  # Copilot on #30: a header-looking line inside a preserved multiline value is content,
  # not a header. Reading it as one dropped the managed [tui] block out of the middle of
  # the string and left the value unterminated, so the apply wrote a config that does not
  # parse -- and nothing downstream would have caught that.
  multiline="$BATS_TEST_TMPDIR/multiline.toml"
  {
    printf '[projects."/srv/p"]\ntrust_level = "trusted"\n'
    printf 'note = """\n[tui]\nstatus_line_use_colors = false\n"""\n'
  } | bash "$script" >"$multiline"
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$multiline"
  grep -qF 'trust_level = "trusted"' "$multiline"
  # The managed table keeps the template's value; the string keeps its own copy of the name.
  grep -qF 'status_line_use_colors = true' "$multiline"
  grep -qF 'status_line_use_colors = false' "$multiline"

  # Copilot on #35: `\"""` is how TOML spells a literal `"""` inside a multiline basic
  # string -- an escaped quote and two plain ones. Read as the closing delimiter, it
  # reopened the same data loss from the next line on.
  escaped="$BATS_TEST_TMPDIR/escaped-multiline.toml"
  {
    printf '[projects."/srv/q"]\n'
    printf 'note = """\nliteral three quotes: \\"""\n[tui]\nstill inside\n"""\n'
    printf 'trust_level = "trusted"\n'
  } | bash "$script" >"$escaped"
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$escaped"
  grep -qF 'trust_level = "trusted"' "$escaped"
  grep -qF 'still inside' "$escaped"

  # Copilot on #35: a header is only a header at the lexical top level, which means outside
  # an array as well as outside a string. `["tui"]` as an array element on its own line read
  # as the managed table, so the block was dropped and `custom = [` was left orphaned.
  nested="$BATS_TEST_TMPDIR/nested-array.toml"
  printf 'custom = [\n["tui"]\n]\n' | bash "$script" >"$nested"
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; assert tomllib.load(open(sys.argv[1], "rb"))["custom"] == [["tui"]]' \
    "$nested"

  # And a key is only a key at the top level too: `model = "inside"` within a preserved
  # multiline value is that value's text, not the managed key. Reading it as the key dropped
  # the line and the closing delimiter, leaving `custom = """` unterminated.
  inner="$BATS_TEST_TMPDIR/inner-key.toml"
  printf 'custom = """\nmodel = "inside"\n"""\n' | bash "$script" >"$inner"
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; d = tomllib.load(open(sys.argv[1], "rb")); assert d["custom"] == chr(109) + chr(111) + chr(100) + chr(101) + chr(108) + " = \"inside\"\n", d["custom"]' \
    "$inner"
  # The managed `model` key is still the template's, not the one from inside the string.
  grep -qF 'model = "gpt-5.6-sol"' "$inner"

  # Copilot on #35: the marker line was stripped even when it appeared as content inside a
  # preserved multiline string. A project note containing the exact marker text lost that
  # line silently on apply.
  marker_in_str="$BATS_TEST_TMPDIR/marker-in-string.toml"
  marker='# --- preserved sections (owned by Codex and bin/sync-mcp; chezmoi keeps them as-is) ---'
  {
    printf '[projects."/srv/p"]\n'
    printf 'note = """\n%s\n"""\n' "$marker"
    printf 'trust_level = "trusted"\n'
  } | bash "$script" >"$marker_in_str"
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$marker_in_str"
  grep -qF "$marker" "$marker_in_str"
  grep -qF 'trust_level = "trusted"' "$marker_in_str"
}

# Copilot on #32: table names were compared as captured text, so ["tui"] and [tui] read as
# two tables. The live one was preserved and the template emitted its own, declaring [tui]
# twice -- a config.toml Codex cannot parse. Every spelling seeded here is a name the
# template already declares, written the way TOML also allows.
@test "the Codex modify script reads equivalent table spellings as one table" {
  script="$BATS_TEST_TMPDIR/modify.sh"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/dot_codex/modify_private_config.toml.tmpl" >"$script"

  seeded="$BATS_TEST_TMPDIR/seeded.toml"
  {
    # A managed preamble key and a managed table, each spelled with an escape: decoding
    # them is what makes the duplicate visible. \u006c is l, \u0069 is i.
    printf '"mode\\u006c" = "gpt-4"\n\n'
    printf '["tu\\u0069"]\nstatus_line_use_colors = false\n\n'
    printf "[ 'plugins' . \"github@claude-plugins-official\" ]\nenabled = false\n\n"
    # Undeclared, and differing from the declared [tui] only in quoting: still preserved.
    printf '[ "tui" . model_availability_nux ]\nseen = true\n'
  } >"$seeded"

  out="$BATS_TEST_TMPDIR/out.toml"
  bash "$script" <"$seeded" >"$out"

  # tomllib rejects a table declared twice, so parsing is the duplicate check; the values
  # say the template won and the undeclared table came through.
  uv run --no-project --python 3.12 python - "$out" <<'PYEOF'
import sys, tomllib

config = tomllib.load(open(sys.argv[1], "rb"))
assert config["model"] == "gpt-5.6-sol", config["model"]
assert config["tui"]["status_line_use_colors"] is True, config["tui"]
assert config["plugins"]["github@claude-plugins-official"]["enabled"] is True
assert config["tui"]["model_availability_nux"] == {"seen": True}
PYEOF

  second="$BATS_TEST_TMPDIR/second.toml"
  bash "$script" <"$out" >"$second"
  diff "$out" "$second"
}

# The Cursor settings were a plain template, so every apply wrote the file whole and
# deleted whatever Cursor and its extensions had written into it. Seed keys the template
# does not declare, including a multi-line value holding a blank and a comment line, a
# string holding `//`, and a string holding an escaped quote and a brace -- the input that
# makes a line-oriented or regex-stripping merge produce a plausible but wrong file.
@test "the Cursor modify script keeps undeclared settings and is idempotent" {
  script="$BATS_TEST_TMPDIR/modify.sh"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/Library/Application Support/Cursor/User/modify_settings.json.tmpl" >"$script"

  seeded="$BATS_TEST_TMPDIR/seeded.json"
  cat >"$seeded" <<'JSON'
{
	// a stray { and } in a comment must not move the depth
	"editor.formatOnSave": false,
	"[python]": {
		"editor.defaultFormatter": "someone.else"
	},
	"python.defaultInterpreterPath": "/opt/py/bin/python3.14",
	"sonarlint.rules": {
		// a comment and a blank line inside a value: capture must not stop here

		"python:S1234": { "level": "off" }
	},
	"myext.docsUrl": "https://example.com//docs",
	"myext.quote": "say \"hi\" }",
	"snyk.yesWelcomeNotification": false,
}
JSON

  first="$BATS_TEST_TMPDIR/first.json"
  bash "$script" <"$seeded" >"$first"

  # Undeclared keys survive, whole values and all, under the marker.
  grep -qF '"python.defaultInterpreterPath": "/opt/py/bin/python3.14"' "$first"
  grep -qF '"snyk.yesWelcomeNotification": false' "$first"
  grep -qF '"python:S1234"' "$first"
  grep -qF 'https://example.com//docs' "$first"
  grep -qF 'say \"hi\" }' "$first"
  grep -qF '// --- preserved' "$first"

  # A declared key still loses to the template, and is written once.
  grep -qF '"editor.formatOnSave": true' "$first"
  run grep -qF '"editor.formatOnSave": false' "$first"
  [ "$status" -ne 0 ]
  run grep -qF 'someone.else' "$first"
  [ "$status" -ne 0 ]
  # Anchored to one tab: the template also sets this key inside a per-language block, so
  # a plain count would be 2 for a correct file.
  [ "$(grep -cE '^\t"editor\.formatOnSave":' "$first")" -eq 1 ]

  # The template's own comments are documentation and survive verbatim.
  grep -qF 'SC2121' "$first"
  grep -qF 'FiraCode-VF.ttf' "$first"

  # Valid JSONC: the seeded trailing comma is gone and it parses once out-of-string //
  # comments do. This stripper tracks strings but not keys or depth, so it is independent
  # of the code under test.
  python3 "$REPO/tests/strip-jsonc-comments.py" "$first" | python3 -c 'import json,sys; json.load(sys.stdin)'

  second="$BATS_TEST_TMPDIR/second.json"
  bash "$script" <"$first" >"$second"
  diff "$first" "$second"

  # First apply on a new machine: no live file, so no marker and no block, and the output
  # is the rendered template byte for byte. A truncated file Cursor could not read either
  # falls back the same way rather than emitting half a value.
  plain="$BATS_TEST_TMPDIR/plain.json"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/.chezmoitemplates/cursor-settings.json.tmpl" >"$plain"
  bash "$script" </dev/null | diff "$plain" -
  printf '{\n\t"a": [1,\n' | bash "$script" | diff "$plain" -

  # Copilot on #19: depth alone let a malformed file through. `[1}` reaches depth zero, so
  # the slice was preserved and the emitted file would not parse at all -- worse than the
  # deletions this script exists to stop. A closer now has to match its opener.
  printf '{\n\t"extension.value": [1}\n}\n' | bash "$script" | diff "$plain" -
  # And nothing but whitespace or a comment may follow the root object, so a second one
  # cannot have a winner silently picked for it.
  printf '{\n\t"a.b": 1\n}\n{\n\t"c.d": 2\n}\n' | bash "$script" | diff "$plain" -
  printf '{\n\t"a.b": 1\n}\ngarbage\n' | bash "$script" | diff "$plain" -

  # Copilot on #19: a key name is compared decoded. Spelled with an escape it is still the
  # declared key, so it loses to the template rather than being appended after it and
  # winning as a duplicate once Cursor parses the result.
  escaped="$BATS_TEST_TMPDIR/escaped.json"
  printf '{\n\t"editor\\u002eformatOnSave": false\n}\n' | bash "$script" >"$escaped"
  diff "$plain" "$escaped"

  # A trailing comma is legal in settings.json, so a file carrying one still merges.
  printf '{\n\t"snyk.yesWelcomeNotification": false,\n}\n' | bash "$script" \
    | grep -qF '"snyk.yesWelcomeNotification": false'
}

# Copilot on #28: the model and proxy lookup had no test. Both defects it named were real —
# a relative invocation resolved the library to bin/bin/, and the awk lookup kept a trailing
# comment and the quotes of a TOML literal string. The header check that followed guessed
# per line and lost the value to a nested array and to a multiline string opened with
# content beside it, so the lookup now tracks where a value ends.
@test "the Codex config lookup reads every TOML spelling, and only top-level keys" {
  home="$BATS_TEST_TMPDIR/codex"
  mkdir -p "$home"

  value() {
    printf '%s\n' "$1" >"$home/config.toml"
    CODEX_HOME="$home" bash -c "source '$REPO/bin/_codex-config.sh'; codex_config_value model"
  }

  [ "$(value 'model = "plain"')" = plain ]
  [ "$(value 'model = "with-comment" # note')" = with-comment ]
  [ "$(value "model = 'literal'")" = literal ]
  [ "$(value 'model="no-spaces"')" = no-spaces ]
  [ "$(value '  model = "indented"')" = indented ]
  [ "$(value 'model = bare # note')" = bare ]
  # Copilot on #28, second round: a quoted key is the same key.
  [ "$(value '"model" = "quoted-key"')" = quoted-key ]
  [ "$(value "'model' = \"literal-key\"")" = literal-key ]
  # A tab separator, a trailing CR, and a commented-out line above the real one.
  [ "$(value "$(printf 'model\t=\t"tabs"')")" = tabs ]
  [ "$(value "$(printf 'model = "crlf"\r')")" = crlf ]
  [ "$(value "$(printf '# model = "commented"\nmodel = "real"')")" = real ]
  # A value above `model` that runs onto later lines must not look like the first table
  # header. An array runs until its brackets balance, wherever its elements sit and whether
  # or not the last one has a trailing comma; a multiline string runs until its delimiter
  # repeats, whether or not it opened with content beside it.
  [ "$(value "$(printf 'notify = [\n  [\"turn-ended\"],\n]\nmodel = \"after-array\"')")" = after-array ]
  [ "$(value "$(printf 'notify = [\n  [\"a\", \"b\"]\n]\nmodel = \"after-nested\"')")" = after-nested ]
  [ "$(value "$(printf 'notify = [\n  \"a]b\",\n]\nmodel = \"after-bracket\"')")" = after-bracket ]
  [ "$(value "$(printf 'note = \"\"\"\n[line]\n\"\"\"\nmodel = \"after-string\"')")" = after-string ]
  [ "$(value "$(printf 'note = \"\"\"open\n[line]\nclose\"\"\"\nmodel = \"after-open-string\"')")" = after-open-string ]
  [ "$(value "$(printf 'note = \047\047\047\n[line]\n\047\047\047\nmodel = \"after-literal\"')")" = after-literal ]
  # A bracket that only sits inside a value is not a header either.
  [ "$(value "$(printf 'note = \"[tui]\"\nmodel = \"after-quoted\"')")" = after-quoted ]
  [ "$(value "$(printf '# [tui]\nmodel = \"after-comment\"')")" = after-comment ]
  [ "$(value "$(printf 'tui = { model = \"inline\" }\nmodel = \"after-inline\"')")" = after-inline ]
  # A key that merely starts with the name must not match.
  [ "$(value "$(printf 'model_reasoning_effort = "high"\nmodel = "after"')")" = after ]
  [ -z "$(value 'notmodel = "x"')" ]
  [ -z "$(value '"notmodel" = "x"')" ]

  # `model` appears inside tables too, so only a key above the first header counts.
  [ -z "$(value "$(printf '[tui]\nmodel = "in-table"')")" ]
  [ -z "$(value "$(printf '  [tui]\n  model = "in-table"')")" ]

  # Missing file and missing key are both empty, not an error: a machine with no Codex
  # config still has to run the script.
  [ -z "$(CODEX_HOME=/nonexistent bash -c "source '$REPO/bin/_codex-config.sh'; codex_config_value model")" ]
  [ -z "$(value 'other = "x"')" ]

  # Precedence: environment beats the config, config beats the literal fallback.
  printf 'model = "from-config"\n' >"$home/config.toml"
  [ "$(CODEX_HOME="$home" bash -c "source '$REPO/bin/_codex-config.sh'; codex_model")" = from-config ]
  [ "$(CODEX_HOME="$home" CODEX_MODEL=from-env bash -c "source '$REPO/bin/_codex-config.sh'; codex_model")" = from-env ]
  [ "$(CODEX_HOME=/nonexistent bash -c "source '$REPO/bin/_codex-config.sh'; codex_model fallback-model")" = fallback-model ]
}

# Copilot on #28: `bin/commit.sh` sourced bin/bin/_codex-config.sh and died. The library is
# now symlinked into ~/.local/bin beside its callers, so `${BASH_SOURCE[0]%/*}` finds it by
# whichever path the script was reached -- which is the contract this pins. The assertion is
# the absence of that specific failure, not the exit status: only two of the three have a
# --help fast path and the third goes straight to Codex.
@test "the Codex scripts find their library however they are invoked" {
  # The applied tree has to put the library beside the scripts, or every one of them breaks.
  resolves_to "$H/.local/bin/_codex-config.sh" "$REPO/bin/_codex-config.sh"

  link_dir="$BATS_TEST_TMPDIR/localbin"
  stub_dir="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$link_dir" "$stub_dir"
  ln -sf "$REPO/bin/_codex-config.sh" "$link_dir/_codex-config.sh"

  # A codex that fails at once, so a script that gets past its source line stops there
  # instead of reaching the network.
  printf '#!/usr/bin/env bash\nexit 1\n' >"$stub_dir/codex"
  chmod +x "$stub_dir/codex"

  for script in commit.sh update-pr-title-and-body.sh suggest-branch-name.sh; do
    ln -sf "$REPO/bin/$script" "$link_dir/$script"

    for invocation in \
      "cd '$REPO' && bin/$script" \
      "cd '$REPO' && ./bin/$script" \
      "cd / && bash '$REPO/bin/$script'" \
      "cd / && bash '$link_dir/$script'" \
      "cd / && $script"; do
      run env PATH="$stub_dir:$link_dir:$PATH" bash -c "$invocation --help"
      [[ $output != *_codex-config.sh* ]] || {
        echo "library not found for: $invocation" >&2
        echo "$output" >&2
        return 1
      }
    done
  done
}

# Issue #20: this was the only one of the three modify scripts with no coverage, and the
# only one still on a named allowlist -- model, enabledPlugins and extraKnownMarketplaces
# won unconditionally, so editing them in the template was a no-op on any machine that
# already had them. Ownership is per key now, with `model` the one deliberate exception.
@test "the Claude modify script owns declared keys and keeps the model picker's choice" {
  script="$BATS_TEST_TMPDIR/claude-modify.sh"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/dot_claude/modify_settings.json.tmpl" >"$script"

  seeded="$BATS_TEST_TMPDIR/seeded-claude.json"
  cat >"$seeded" <<'JSON'
{
  "model": "opusplan",
  "enabledPlugins": {"never-declared@somewhere": true},
  "extraKnownMarketplaces": {"never-declared": {"source": {"source": "github", "repo": "x/y"}}},
  "outputStyle": "Explanatory",
  "someSettingClaudeCodeAdded": 123
}
JSON

  first="$BATS_TEST_TMPDIR/first-claude.json"
  bash "$script" <"$seeded" >"$first"

  # Declared keys come from the repo. This is the assertion #20 was about: the fabricated
  # plugin and marketplace lose, so desired.yaml and the template can change a machine.
  run ! jq -e '.enabledPlugins | has("never-declared@somewhere")' "$first"
  run ! jq -e '.extraKnownMarketplaces | has("never-declared")' "$first"
  jq -e '.enabledPlugins["github@claude-plugins-official"] == true' "$first"
  jq -e '.outputStyle == "Concise"' "$first"

  # `model` is the one exception: it is chosen per machine in the model picker.
  jq -e '.model == "opusplan"' "$first"

  # An undeclared key is Claude Code's and is carried over. It used to be dropped outright,
  # while this script's header claimed otherwise.
  jq -e '.someSettingClaudeCodeAdded == 123' "$first"
  # And it is named on stderr, so an apply says what it carried: JSON has no comment to
  # label a block with, which is what the Cursor script uses its marker for.
  bash "$script" <"$seeded" 2>&1 >/dev/null | grep -qF someSettingClaudeCodeAdded

  second="$BATS_TEST_TMPDIR/second-claude.json"
  bash "$script" <"$first" >"$second"
  diff "$first" "$second"

  # First apply on a new machine, and a file Claude Code could not parse either: both fall
  # back to the rendered template rather than emitting half a value.
  plain="$BATS_TEST_TMPDIR/plain-claude.json"
  HOME="$H" chezmoi --source "$REPO" execute-template \
    <"$REPO/home/.chezmoitemplates/claude-settings.json" >"$plain"
  printf '' | bash "$script" | diff <(jq -S . "$plain") <(jq -S . -)
  printf '{not json' | bash "$script" 2>/dev/null | diff <(jq -S . "$plain") <(jq -S . -)

  # The live file has to survive its own script unchanged, or an apply rewrites it forever.
  live="$BATS_TEST_TMPDIR/live-claude.json"
  jq -S . "$H/.claude/settings.json" >"$live"
  bash "$script" <"$H/.claude/settings.json" | jq -S . | diff "$live" -
}

# Copilot on #11: chezmoi replaces a real directory with the managed symlink by deleting it
# recursively and without a prompt, so an apply could take Cursor-only skills with it.
@test "an apply refuses while a skills directory is real (CI home only)" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "would disturb the real home"; fi
  rm -rf "$H/.cursor/skills"
  mkdir -p "$H/.cursor/skills/only-here"

  run env HOME="$H" CI=1 chezmoi apply --source "$REPO"
  survived=no
  [ -d "$H/.cursor/skills/only-here" ] && survived=yes

  # Put the home back before asserting, so a failure here does not affect later tests.
  rm -rf "$H/.cursor/skills"
  env HOME="$H" CI=1 chezmoi apply --force --source "$REPO"

  [ "$status" -ne 0 ]
  [ "$survived" = yes ]
  resolves_to "$H/.cursor/skills" "$H/.agents/skills"
}

# Copilot on #10: nothing exercised the .chezmoiremove entries, so a typo in one would
# leave the live file in place while the suite passed.
@test ".chezmoiremove deletes the paths it lists (CI home only)" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "would delete files from the real home"; fi
  mkdir -p "$H/.codex" "$H/.agents/plugins"
  echo seeded >"$H/.codex/hooks.json"
  echo seeded >"$H/.agents/plugins/marketplace.json"

  HOME="$H" CI=1 chezmoi apply --source "$REPO"

  [ ! -e "$H/.codex/hooks.json" ]
  [ ! -e "$H/.agents/plugins/marketplace.json" ]
}

# Copilot on #10: every other invocation passes --source, so none of them exercises the
# sourceDir that .chezmoi.toml.tmpl now emits.
@test "a bare chezmoi command resolves this checkout" {
  # A real home's config may predate sourceDir and needs one chezmoi init. A throwaway or CI
  # home is generated from the template every time, so there the key has to be there.
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ] \
    && ! grep -q '^sourceDir' "$H/.config/chezmoi/chezmoi.toml"; then
    skip "this home's config predates sourceDir; run chezmoi init to regenerate it"
  fi
  [ "$(HOME="$H" chezmoi source-path)" = "$REPO/home" ]
}

@test "the Codex config is readable only by its owner" {
  [ "$(stat -f '%Lp' "$H/.codex/config.toml")" = 600 ]
}

@test "Codex config parses as TOML" {
  # tomllib needs 3.11+; the system python3 on macOS is 3.9.
  uv run --no-project --python 3.12 python -c \
    'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$H/.codex/config.toml"
}

@test "shared MCP config parses as JSON with a non-empty server map" {
  jq -e '.mcpServers | type == "object" and length > 0' "$H/.agents/mcp.json"
}

@test "the secrets file is not managed" {
  if [ "$H" = "$HOME" ] && [ -z "${CI:-}" ]; then skip "the real home may hold a hand-made ~/.zsh_secrets"; fi
  [ ! -e "$H/.zsh_secrets" ]
}

# dot_zsh_secrets.example:1 and docs/new-machine.md:31 both say chmod 600, and nothing
# else checks that the instruction was followed.
@test "the secrets file, when present, is readable only by its owner" {
  [ -e "$H/.zsh_secrets" ] || skip "no ~/.zsh_secrets on this machine"
  [ "$(stat -f '%Lp' "$H/.zsh_secrets")" = 600 ]
}
