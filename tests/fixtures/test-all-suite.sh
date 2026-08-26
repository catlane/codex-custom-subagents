#!/bin/sh
set -eu
[ -n "${TEST_ALL_SUITE_ROOT-}" ]
[ "$HOME" = "$TEST_ALL_SUITE_ROOT/home" ]
[ "$CODEX_HOME" = "$TEST_ALL_SUITE_ROOT/codex-home" ]
[ "$CUSTOM_SUBAGENT_HOME" = "$TEST_ALL_SUITE_ROOT/custom-subagent-home" ]
[ "$TMPDIR" = "$TEST_ALL_SUITE_ROOT/tmp" ]
printf '%s|%s\n' '__SUITE_LABEL__' "$TEST_ALL_SUITE_ROOT"
exit __SUITE_STATUS__
