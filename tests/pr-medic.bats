#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# Gate and pick filters extracted from pr-medic.yml. These cases never skip:
# macos.yml pins the home.bats skip set, and a new skip here would fail it.

setup() {
  REPO="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  EXTRACT="$REPO/tools/extract_pr_medic.py"
  GATE_JQ="$BATS_TEST_TMPDIR/gate.jq"
  PICK_JQ="$BATS_TEST_TMPDIR/pick.jq"
  CHECKS_JQ="$BATS_TEST_TMPDIR/checks.jq"
  python3 "$EXTRACT" pr-medic-gate.jq >"$GATE_JQ"
  python3 "$EXTRACT" pr-medic-pick.jq >"$PICK_JQ"
  python3 "$EXTRACT" pr-medic-checks.jq >"$CHECKS_JQ"
}

# gh pr view --json statusCheckRollup returns two shapes. Getting this wrong is what made
# every commit status count as pending forever, and what let TIMED_OUT read as passing.
@test "check rollup buckets both CheckRun and StatusContext" {
  local got
  got=$(
    jq -c -f "$CHECKS_JQ" <<'JSON'
{"statusCheckRollup": [
  {"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS"},
  {"__typename": "CheckRun", "name": "slow", "status": "IN_PROGRESS"},
  {"__typename": "CheckRun", "name": "gone", "status": "COMPLETED", "conclusion": "TIMED_OUT"},
  {"__typename": "CheckRun", "name": "skip", "status": "COMPLETED", "conclusion": "SKIPPED"},
  {"__typename": "StatusContext", "context": "legacy", "state": "SUCCESS"},
  {"__typename": "StatusContext", "context": "waiting", "state": "PENDING"},
  {"__typename": "StatusContext", "context": "broke", "state": "ERROR"},
  {"__typename": "StatusContext", "context": "pr-medic", "state": "SUCCESS"}
]}
JSON
  )
  [ "$got" = '{"total":7,"failing":2,"pending":2}' ] || {
    echo "check rollup: got $got" >&2
    return 1
  }
}

@test "an empty rollup counts zero, so the gate can refuse it" {
  local got
  got=$(printf '%s' '{"statusCheckRollup": []}' | jq -c -f "$CHECKS_JQ")
  [ "$got" = '{"total":0,"failing":0,"pending":0}' ]
}

@test "pr-medic marker copies match, jq parses, and shellcheck passes" {
  python3 "$EXTRACT" --check
}

# The reason as well as the action: decide has four separate wait branches, so asserting
# only the action lets a case pass for the wrong reason.
@test "gate fixtures" {
  local n name expect expect_reason got got_reason decision
  n=$(jq 'length' "$REPO/tests/fixtures/pr-medic/gate.json")
  [ "$n" -gt 0 ]
  i=0
  while [ "$i" -lt "$n" ]; do
    name=$(jq -r --argjson i "$i" '.[$i].name' "$REPO/tests/fixtures/pr-medic/gate.json")
    expect=$(jq -r --argjson i "$i" '.[$i].expect' "$REPO/tests/fixtures/pr-medic/gate.json")
    expect_reason=$(jq -r --argjson i "$i" '.[$i].expect_reason' "$REPO/tests/fixtures/pr-medic/gate.json")
    [ "$expect_reason" != "null" ] || {
      echo "gate fixture '$name': no expect_reason" >&2
      return 1
    }
    decision=$(jq -c --argjson i "$i" '.[$i].input' "$REPO/tests/fixtures/pr-medic/gate.json" | jq -c -f "$GATE_JQ")
    got=$(printf '%s' "$decision" | jq -r .action)
    got_reason=$(printf '%s' "$decision" | jq -r .reason)
    [ "$got" = "$expect" ] && [ "$got_reason" = "$expect_reason" ] || {
      echo "gate fixture '$name': expected $expect ($expect_reason), got $got ($got_reason)" >&2
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
    got=$(jq -c --argjson i "$i" '.[$i].input' "$REPO/tests/fixtures/pr-medic/pick.json" | jq -c -f "$PICK_JQ") || {
      echo "pick fixture '$name': jq aborted" >&2
      return 1
    }
    [ "$got" = "$expect" ] || {
      echo "pick fixture '$name': expected $expect, got $got" >&2
      return 1
    }
    i=$((i + 1))
  done
}
