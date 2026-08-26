#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT/shared/prompt-secret.js"
COMPILED="${TEST_ALL_SUITE_ROOT:-/private/tmp}/prompt-secret.scpt"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[ -f "$SCRIPT" ] || fail 'missing shared/prompt-secret.js'
/usr/bin/osacompile -l JavaScript -o "$COMPILED" "$SCRIPT" >/dev/null 2>&1 ||
  fail 'prompt-secret.js does not compile as JavaScript for Automation'
grep -F 'hiddenAnswer: true' "$SCRIPT" >/dev/null 2>&1 ||
  fail 'prompt-secret.js does not request a hidden answer'

for plugin_name in deepseek-agent volcengine-agent; do
  vendor="$ROOT/plugins/$plugin_name/scripts/vendor/prompt-secret.js"
  [ -f "$vendor" ] || fail "missing vendored prompt-secret.js for $plugin_name"
  cmp -s "$SCRIPT" "$vendor" ||
    fail "vendored prompt-secret.js differs from shared source: $plugin_name"
done

printf '%s\n' 'prompt secret runtime tests passed'
