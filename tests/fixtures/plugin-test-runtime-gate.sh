#!/bin/sh

runtime_gate_die() {
  printf '%s\n' "custom-subagents: test harness gate: $1" >&2
  exit 1
}

custom_subagent_runtime_gate() {
  runtime_home=$1
  runtime_plugin_root=$2
  runtime_plugin_id=$3
  case "${CUSTOM_SUBAGENT_TEST_MODE:-}" in
    1)
      [ "${CUSTOM_SUBAGENT_TEST_APPROVAL:-}" = custom-subagents-isolated-test-harness ] ||
        runtime_gate_die 'explicit isolated-test approval is required'
      case "$runtime_home" in /private/tmp/*) ;; *) runtime_gate_die 'CODEX_HOME must be isolated under /private/tmp' ;; esac
      [ -d "$runtime_home" ] || runtime_gate_die 'CODEX_HOME must be an existing directory'
      runtime_physical_home=$(cd -P "$runtime_home" && pwd)
      [ "$runtime_physical_home" = "$runtime_home" ] || runtime_gate_die 'CODEX_HOME must not contain symlinks'

      runtime_security=${CUSTOM_SUBAGENT_SECURITY_BIN:-}
      runtime_osascript=${CUSTOM_SUBAGENT_OSASCRIPT_BIN:-}
      [ -n "$runtime_security" ] && [ -n "$runtime_osascript" ] ||
        runtime_gate_die 'security and osascript fake overrides must both be set'
      case "$runtime_security:$runtime_osascript" in /*:/*) ;; *) runtime_gate_die 'fake overrides must use absolute paths' ;; esac
      [ -f "$runtime_security" ] && [ ! -L "$runtime_security" ] || runtime_gate_die 'security fake must be a regular non-symlink file'
      [ -f "$runtime_osascript" ] && [ ! -L "$runtime_osascript" ] || runtime_gate_die 'osascript fake must be a regular non-symlink file'

      case "$runtime_plugin_root" in /*) ;; *) runtime_gate_die 'plugin root must be absolute' ;; esac
      [ -d "$runtime_plugin_root" ] && [ ! -L "$runtime_plugin_root" ] || runtime_gate_die 'plugin root must be a regular directory'
      runtime_plugin_physical=$(cd -P "$runtime_plugin_root" && pwd)
      [ "$runtime_plugin_physical" = "$runtime_plugin_root" ] || runtime_gate_die 'plugin root must not contain symlinks'
      runtime_marketplace_root=$(cd -P "$runtime_plugin_root/../.." && pwd)
      runtime_expected_plugin="$runtime_marketplace_root/plugins/$runtime_plugin_id"
      [ "$runtime_plugin_root" = "$runtime_expected_plugin" ] || runtime_gate_die 'plugin must use the source marketplace layout'

      runtime_checked_path=$runtime_marketplace_root
      while [ "$runtime_checked_path" != / ]; do
        [ ! -L "$runtime_checked_path" ] || runtime_gate_die 'marketplace root parents must not be symlinks'
        runtime_checked_path=$(dirname "$runtime_checked_path")
      done
      [ -d "$runtime_marketplace_root/plugins" ] && [ ! -L "$runtime_marketplace_root/plugins" ] &&
      [ -d "$runtime_marketplace_root/tests" ] && [ ! -L "$runtime_marketplace_root/tests" ] &&
      [ -d "$runtime_marketplace_root/tests/helpers" ] && [ ! -L "$runtime_marketplace_root/tests/helpers" ] ||
        runtime_gate_die 'source marketplace tests/helpers layout is unavailable'

      runtime_expected_security="$runtime_marketplace_root/tests/helpers/fake-security.sh"
      runtime_expected_osascript="$runtime_marketplace_root/tests/helpers/fake-osascript.sh"
      [ "$runtime_security" = "$runtime_expected_security" ] &&
      [ "$runtime_osascript" = "$runtime_expected_osascript" ] ||
        runtime_gate_die 'fake overrides must be the exact source marketplace helpers'
      RUNTIME_LIFECYCLE_PRODUCTION_MODE=
      RUNTIME_LIFECYCLE_PRODUCTION_APPROVAL=
      ;;
    '')
      [ -z "${CUSTOM_SUBAGENT_TEST_APPROVAL:-}" ] &&
      [ -z "${CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE:-}" ] &&
      [ -z "${CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL:-}" ] &&
      [ -z "${CUSTOM_SUBAGENT_FAIL_AFTER_WRITE:-}" ] &&
      [ -z "${CUSTOM_SUBAGENT_ALLOW_HTTP:-}" ] ||
        runtime_gate_die 'lifecycle test hooks require the approved isolated test harness'
      CUSTOM_SUBAGENT_SECURITY_BIN=/usr/bin/security
      CUSTOM_SUBAGENT_OSASCRIPT_BIN=/usr/bin/osascript
      export CUSTOM_SUBAGENT_SECURITY_BIN CUSTOM_SUBAGENT_OSASCRIPT_BIN
      unset CUSTOM_SUBAGENT_TEST_MODE CUSTOM_SUBAGENT_TEST_APPROVAL
      unset CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL
      unset CUSTOM_SUBAGENT_FAIL_AFTER_WRITE CUSTOM_SUBAGENT_ALLOW_HTTP
      RUNTIME_LIFECYCLE_PRODUCTION_MODE=1
      RUNTIME_LIFECYCLE_PRODUCTION_APPROVAL=custom-subagents-live-home
      ;;
    *) runtime_gate_die 'CUSTOM_SUBAGENT_TEST_MODE must be unset or exactly 1' ;;
  esac
}
