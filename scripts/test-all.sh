#!/bin/sh

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TESTS_DIR="$ROOT/tests"
ARTIFACT_BASE=${TEST_ALL_ARTIFACT_BASE:-/private/tmp}

mkdir -p "$ARTIFACT_BASE" || {
  printf '%s\n' "test-all: cannot create artifact base: $ARTIFACT_BASE" >&2
  exit 1
}

RUN_ROOT=$(mktemp -d "$ARTIFACT_BASE/custom-subagents-test-all.XXXXXX") || {
  printf '%s\n' "test-all: cannot create isolated run root under $ARTIFACT_BASE" >&2
  exit 1
}

TEST_LIST="$RUN_ROOT/tests.list"
find "$TESTS_DIR" -type f -maxdepth 1 -name '*.sh' -print | LC_ALL=C sort >"$TEST_LIST"

total=$(wc -l <"$TEST_LIST" | tr -d ' ')
if [ "$total" -eq 0 ]; then
  printf '%s\n' "test-all: no test suites found in $TESTS_DIR" >&2
  rm -rf "$RUN_ROOT"
  exit 1
fi

passed=0
failed=0

while IFS= read -r suite; do
  suite_name=$(basename "$suite")
  suite_root="$RUN_ROOT/$suite_name"
  suite_log="$suite_root/output.log"
  mkdir -p \
    "$suite_root/home" \
    "$suite_root/codex-home" \
    "$suite_root/custom-subagent-home" \
    "$suite_root/tmp"

  if env \
    HOME="$suite_root/home" \
    CODEX_HOME="$suite_root/codex-home" \
    CUSTOM_SUBAGENT_HOME="$suite_root/custom-subagent-home" \
    TMPDIR="$suite_root/tmp" \
    TEST_ALL_SUITE_ROOT="$suite_root" \
    sh "$suite" >"$suite_log" 2>&1; then
    suite_status=0
  else
    suite_status=$?
  fi

  if [ "$suite_status" -eq 0 ]; then
    passed=$((passed + 1))
    printf '%s\n' "PASS  $suite_name"
  else
    failed=$((failed + 1))
    printf '%s\n' "FAIL  $suite_name (exit $suite_status)"
  fi
done <"$TEST_LIST"

printf '%s\n' "Summary: $passed passed, $failed failed, $total total"

if [ "$failed" -ne 0 ]; then
  printf '%s\n' "Artifacts preserved: $RUN_ROOT"
  exit 1
fi

rm -rf "$RUN_ROOT"
exit 0
