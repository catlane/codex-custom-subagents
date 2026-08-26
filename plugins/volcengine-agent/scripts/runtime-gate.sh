#!/bin/sh

runtime_gate_die() {
  printf '%s\n' "custom-subagents: production runtime rejects test hooks or binary overrides: $1" >&2
  exit 1
}

custom_subagent_runtime_gate() {
  [ "${CUSTOM_SUBAGENT_SECURITY_BIN+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_OSASCRIPT_BIN+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_EXPECT_HELPER+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_PREPARED_CATALOG_DIR+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_TEST_MODE+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_TEST_APPROVAL+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_TEST_CODEX_BIN+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_FAIL_AFTER_WRITE+x}" != x ] &&
  [ "${CUSTOM_SUBAGENT_ALLOW_HTTP+x}" != x ] ||
    runtime_gate_die 'remove all inherited test-only variables and retry'

  CUSTOM_SUBAGENT_SECURITY_BIN=/usr/bin/security
  CUSTOM_SUBAGENT_OSASCRIPT_BIN=/usr/bin/osascript
  export CUSTOM_SUBAGENT_SECURITY_BIN CUSTOM_SUBAGENT_OSASCRIPT_BIN
  unset CUSTOM_SUBAGENT_LOCK_TOKEN
  RUNTIME_LIFECYCLE_PRODUCTION_MODE=1
  RUNTIME_LIFECYCLE_PRODUCTION_APPROVAL=custom-subagents-live-home
}
