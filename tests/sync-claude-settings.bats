#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# bin/sync-claude-settings reads ~/.claude/settings.json against
# home/.chezmoitemplates/claude-settings.json. `chezmoi re-add` skips modify-script targets,
# so this is the only path by which an in-product settings edit reaches the repo.
#
# Every case runs against a fake HOME and a copy of the template, so the repo's own template
# is never written -- a test that adopted into it would rewrite the file it asserts on.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  FAKE="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE/.claude"
  TPL="$REPO/home/.chezmoitemplates/claude-settings.json"
  export REPO FAKE TPL
}

# The script resolves the template from its own location, so a copy needs a copied bin/ too.
sandbox() {
  local root="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$root/bin" "$root/home/.chezmoitemplates"
  cp "$REPO/bin/sync-claude-settings" "$root/bin/"
  cp "$TPL" "$root/home/.chezmoitemplates/claude-settings.json"
  echo "$root"
}

live_from_template() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
exec(sys.argv[2])
json.dump(d, open(sys.argv[3], 'w'), indent=2)
" "$TPL" "$1" "$FAKE/.claude/settings.json"
}

@test "an unchanged live file reports no drift" {
  live_from_template "pass"
  run env HOME="$FAKE" python3 "$(sandbox)/bin/sync-claude-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no declared key differs"* ]]
}

@test "a changed declared key is reported but not written" {
  live_from_template "d['theme'] = 'probe-theme'"
  root="$(sandbox)"
  run env HOME="$FAKE" python3 "$root/bin/sync-claude-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"theme"* ]]
  [[ "$output" == *"nothing written"* ]]
  # The default has to be inert, or `just sync` commits a value nobody chose.
  run ! grep -q 'probe-theme' "$root/home/.chezmoitemplates/claude-settings.json"
}

@test "--adopt writes the changed key" {
  live_from_template "d['theme'] = 'probe-theme'"
  root="$(sandbox)"
  run env HOME="$FAKE" python3 "$root/bin/sync-claude-settings" --adopt
  [ "$status" -eq 0 ]
  grep -q 'probe-theme' "$root/home/.chezmoitemplates/claude-settings.json"
}

# The case that decided the default. pyright-lsp was false on one machine and true in the
# repo on purpose, and claude-md-management was absent there and enabled here; adopting live
# wholesale would have committed both. A nested key live lacks is kept, so `--adopt` can
# never turn one machine being behind into a deletion for every other.
@test "--adopt keeps a nested key the live file lacks" {
  live_from_template "d['enabledPlugins'].pop('claude-md-management@claude-plugins-official'); d['enabledPlugins']['pyright-lsp@claude-plugins-official'] = False"
  root="$(sandbox)"
  run env HOME="$FAKE" python3 "$root/bin/sync-claude-settings" --adopt
  [ "$status" -eq 0 ]
  python3 -c "
import json, sys
p = json.load(open(sys.argv[1]))['enabledPlugins']
assert p['claude-md-management@claude-plugins-official'] is True, 'nested key was deleted'
assert p['pyright-lsp@claude-plugins-official'] is False, 'changed value was not adopted'
" "$root/home/.chezmoitemplates/claude-settings.json"
}

# An absent nested key compares unequal forever, so testing live directly rather than the
# merge reported drift on every run and rewrote the file byte-identically.
@test "an absent nested key alone is not drift" {
  live_from_template "d['enabledPlugins'].pop('claude-md-management@claude-plugins-official')"
  run env HOME="$FAKE" python3 "$(sandbox)/bin/sync-claude-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no declared key differs"* ]]
}

@test "model is left to the machine's model picker" {
  live_from_template "d['model'] = 'machine-picked'"
  root="$(sandbox)"
  run env HOME="$FAKE" python3 "$root/bin/sync-claude-settings" --adopt
  [ "$status" -eq 0 ]
  run ! grep -q 'machine-picked' "$root/home/.chezmoitemplates/claude-settings.json"
}

# Two copies of one carve-out: the modify script hands these keys to the product on every
# apply, so a key this script pulled would be committed and then lose to the next apply.
@test "RUNTIME agrees with the modify script" {
  a="$(sed -nE 's/^RUNTIME = (.*)$/\1/p' "$REPO/bin/sync-claude-settings")"
  b="$(sed -nE 's/^RUNTIME = (.*)$/\1/p' "$REPO/home/dot_claude/modify_settings.json.tmpl")"
  [ -n "$a" ]
  [ "$a" = "$b" ]
}

@test "an unparseable live file fails instead of writing" {
  printf '{not json' >"$FAKE/.claude/settings.json"
  root="$(sandbox)"
  run env HOME="$FAKE" python3 "$root/bin/sync-claude-settings" --adopt
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not parse"* ]]
  diff "$TPL" "$root/home/.chezmoitemplates/claude-settings.json"
}

@test "a missing live file is a note, not a failure" {
  rm -f "$FAKE/.claude/settings.json"
  run env HOME="$FAKE" python3 "$(sandbox)/bin/sync-claude-settings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to report"* ]]
}
