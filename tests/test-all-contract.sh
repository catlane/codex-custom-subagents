#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SUBJECT="$ROOT/scripts/test-all.sh"
TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-test-all-contract.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "test-all-contract: $*" >&2
  exit 1
}

assert_contains() {
  file=$1
  text=$2
  grep -F -- "$text" "$file" >/dev/null 2>&1 ||
    fail "expected '$text' in $file"
}

[ -f "$SUBJECT" ] || fail "missing subject: $SUBJECT"

FIXTURE="$TEMP_ROOT/repository"
ARTIFACT_BASE="$TEMP_ROOT/artifacts"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/tests" "$ARTIFACT_BASE"
cp "$SUBJECT" "$FIXTURE/scripts/test-all.sh"

make_suite() {
  suite_path=$1
  suite_label=$2
  suite_status=$3
  sed \
    -e "s/__SUITE_LABEL__/$suite_label/g" \
    -e "s/__SUITE_STATUS__/$suite_status/g" \
    "$ROOT/tests/fixtures/test-all-suite.sh" >"$suite_path"
  chmod +x "$suite_path"
}

make_suite "$FIXTURE/tests/alpha.sh" alpha 0
make_suite "$FIXTURE/tests/beta.sh" beta 0

PASS_OUTPUT="$TEMP_ROOT/pass.out"
TEST_ALL_ARTIFACT_BASE="$ARTIFACT_BASE" sh "$FIXTURE/scripts/test-all.sh" >"$PASS_OUTPUT" 2>&1 ||
  fail 'all-passing fixture returned non-zero'
assert_contains "$PASS_OUTPUT" 'PASS  alpha.sh'
assert_contains "$PASS_OUTPUT" 'PASS  beta.sh'
assert_contains "$PASS_OUTPUT" 'Summary: 2 passed, 0 failed, 2 total'
[ -z "$(find "$ARTIFACT_BASE" -mindepth 1 -print -quit)" ] ||
  fail 'successful run retained artifacts'

make_suite "$FIXTURE/tests/gamma.sh" gamma 7
FAIL_OUTPUT="$TEMP_ROOT/fail.out"
if TEST_ALL_ARTIFACT_BASE="$ARTIFACT_BASE" sh "$FIXTURE/scripts/test-all.sh" >"$FAIL_OUTPUT" 2>&1; then
  fail 'failing fixture returned zero'
fi
assert_contains "$FAIL_OUTPUT" 'PASS  alpha.sh'
assert_contains "$FAIL_OUTPUT" 'PASS  beta.sh'
assert_contains "$FAIL_OUTPUT" 'FAIL  gamma.sh (exit 7)'
assert_contains "$FAIL_OUTPUT" 'Summary: 2 passed, 1 failed, 3 total'
assert_contains "$FAIL_OUTPUT" 'Artifacts preserved: '

PRESERVED=$(sed -n 's/^Artifacts preserved: //p' "$FAIL_OUTPUT" | tail -n 1)
[ -n "$PRESERVED" ] || fail 'missing preserved artifact path'
[ -d "$PRESERVED" ] || fail "preserved artifact path does not exist: $PRESERVED"
[ -f "$PRESERVED/gamma.sh/output.log" ] || fail 'missing failed-suite log'
assert_contains "$PRESERVED/gamma.sh/output.log" 'gamma|'

alpha_root=$(sed -n 's/^alpha|//p' "$PRESERVED/alpha.sh/output.log")
beta_root=$(sed -n 's/^beta|//p' "$PRESERVED/beta.sh/output.log")
[ -n "$alpha_root" ] && [ -n "$beta_root" ] || fail 'missing suite-root evidence'
[ "$alpha_root" != "$beta_root" ] || fail 'suites shared an isolation root'

printf '%s\n' 'test-all-contract: passed'
