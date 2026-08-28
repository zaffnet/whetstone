#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Gate and pick filters extracted from pr-medic.yml. These cases never skip:
# macos.yml pins the home.bats skip set, and a new skip here would fail it.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  EXTRACT="$REPO/tools/extract_pr_medic.py"
  GATE_JQ="$BATS_TEST_TMPDIR/gate.jq"
  PICK_JQ="$BATS_TEST_TMPDIR/pick.jq"
  python3 "$EXTRACT" pr-medic-gate.jq >"$GATE_JQ"
  python3 "$EXTRACT" pr-medic-pick.jq >"$PICK_JQ"
}

@test "pr-medic marker copies match, jq parses, and shellcheck passes" {
  python3 "$EXTRACT" --check
}

@test "gate fixtures" {
  local n name expect got
  n=$(jq 'length' "$REPO/tests/fixtures/pr-medic/gate.json")
  [ "$n" -gt 0 ]
  i=0
  while [ "$i" -lt "$n" ]; do
    name=$(jq -r --argjson i "$i" '.[$i].name' "$REPO/tests/fixtures/pr-medic/gate.json")
    expect=$(jq -r --argjson i "$i" '.[$i].expect' "$REPO/tests/fixtures/pr-medic/gate.json")
    got=$(jq -c --argjson i "$i" '.[$i].input' "$REPO/tests/fixtures/pr-medic/gate.json" | jq -r -f "$GATE_JQ" | jq -r .action)
    [ "$got" = "$expect" ] || {
      echo "gate fixture '$name': expected $expect, got $got" >&2
      return 1
    }
    i=$((i + 1))
  done
}

@test "pick fixtures" {
  local n name expect got
  n=$(jq 'length' "$REPO/tests/fixtures/pr-medic/pick.json")
  [ "$n" -gt 0 ]
  i=0
  while [ "$i" -lt "$n" ]; do
    name=$(jq -r --argjson i "$i" '.[$i].name' "$REPO/tests/fixtures/pr-medic/pick.json")
    expect=$(jq -c --argjson i "$i" '.[$i].expect' "$REPO/tests/fixtures/pr-medic/pick.json")
    got=$(jq -c --argjson i "$i" '.[$i].input' "$REPO/tests/fixtures/pr-medic/pick.json" | jq -c -f "$PICK_JQ")
    [ "$got" = "$expect" ] || {
      echo "pick fixture '$name': expected $expect, got $got" >&2
      return 1
    }
    i=$((i + 1))
  done
}
