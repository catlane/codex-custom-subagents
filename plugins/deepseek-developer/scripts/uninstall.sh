#!/bin/sh

set -eu
set +x
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLUGIN_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VENDOR_DIR="$SCRIPT_DIR/vendor"
CODEX_HOME=${CODEX_HOME:-"$HOME/.codex"}

[ -f "$SCRIPT_DIR/runtime-gate.sh" ] && [ ! -L "$SCRIPT_DIR/runtime-gate.sh" ] || {
  printf '%s\n' 'deepseek-developer: runtime gate is missing or unsafe' >&2
  exit 1
}
. "$SCRIPT_DIR/runtime-gate.sh"
custom_subagent_runtime_gate "$CODEX_HOME" "$PLUGIN_ROOT" deepseek-developer

die() {
  printf '%s\n' "deepseek-developer: $1" >&2
  exit 1
}

[ -d "$CODEX_HOME" ] || die "CODEX_HOME must be an existing directory"
[ -f "$VENDOR_DIR/lifecycle.sh" ] || die 'vendored lifecycle is missing'
[ -f "$VENDOR_DIR/operation-lock.sh" ] || die 'vendored operation lock is missing'
[ -f "$VENDOR_DIR/state.js" ] || die 'vendored state helper is missing'
[ -f "$VENDOR_DIR/keychain.sh" ] || die 'vendored Keychain adapter is missing'

CUSTOM_SUBAGENT_PROMPT_SECRET_SCRIPT="$VENDOR_DIR/prompt-secret.applescript"
. "$VENDOR_DIR/keychain.sh"
. "$VENDOR_DIR/operation-lock.sh"

OPERATION_LOCK_HELD=0
OPERATION_LOCK_ACQUIRING=0
OPERATION_PENDING_SIGNAL=0
release_operation_lock() {
  if [ "$OPERATION_LOCK_HELD" = 1 ]; then
    custom_subagent_lock_release "$CODEX_HOME" || return $?
    OPERATION_LOCK_HELD=0
  elif [ "$OPERATION_LOCK_ACQUIRING" = 1 ]; then
    if [ "${CUSTOM_SUBAGENT_LOCK_TOKEN+x}" = x ]; then
      custom_subagent_lock_release "$CODEX_HOME" || return $?
    else
      custom_subagent_lock_abort_acquire "$CODEX_HOME" || return $?
    fi
    OPERATION_LOCK_ACQUIRING=0
  fi
}
release_operation_lock_on_exit() {
  operation_status=$?
  trap - EXIT HUP INT TERM
  if ! release_operation_lock && [ "$operation_status" = 0 ]; then
    operation_status=1
  fi
  exit "$operation_status"
}
cleanup_removed_credential_on_signal() {
  signal_state="$CODEX_HOME/custom-subagents/state.json"
  if [ -f "$signal_state" ] && [ ! -L "$signal_state" ]; then
    set +e
    signal_registration=$(/usr/bin/osascript -l JavaScript "$VENDOR_DIR/state.js" \
      agent-present "$signal_state" deepseek-developer 2>/dev/null)
    signal_registration_status=$?
    set -e
    [ "$signal_registration_status" = 0 ] || return 0
    [ "$signal_registration" = 1 ] && return 0
  elif [ -e "$signal_state" ] || [ -L "$signal_state" ]; then
    return 0
  fi
  set +e
  keychain_exists deepseek-developer
  signal_keychain_status=$?
  set -e
  case "$signal_keychain_status" in
    0) keychain_delete deepseek-developer ;;
    44) return 0 ;;
    *)
      printf '%s\n' "deepseek-developer: interrupted uninstall could not inspect Keychain status=$signal_keychain_status service=codex-custom-subagent/deepseek-developer account=api-key; retry uninstall cleanup." >&2
      return "$signal_keychain_status"
      ;;
  esac
}
handle_operation_signal() {
  signal_status=$1
  trap - EXIT HUP INT TERM
  cleanup_removed_credential_on_signal || true
  release_operation_lock || true
  exit "$signal_status"
}
defer_operation_signal() { OPERATION_PENDING_SIGNAL=$1; }
trap release_operation_lock_on_exit EXIT
trap 'defer_operation_signal 129' HUP
trap 'defer_operation_signal 130' INT
trap 'defer_operation_signal 143' TERM
OPERATION_LOCK_ACQUIRING=1
if custom_subagent_lock_acquire "$CODEX_HOME" >/dev/null; then
  operation_acquire_status=0
  OPERATION_LOCK_HELD=1
else
  operation_acquire_status=$?
fi
OPERATION_LOCK_ACQUIRING=0
trap 'handle_operation_signal 129' HUP
trap 'handle_operation_signal 130' INT
trap 'handle_operation_signal 143' TERM
[ "$OPERATION_PENDING_SIGNAL" = 0 ] || handle_operation_signal "$OPERATION_PENDING_SIGNAL"
[ "$operation_acquire_status" = 0 ] || exit "$operation_acquire_status"

# Lifecycle cleanup must succeed before removing the exact Keychain item.
CUSTOM_SUBAGENT_HOME="$CODEX_HOME" \
CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/templates/agent-spec.json" \
CUSTOM_SUBAGENT_PRODUCTION_MODE="$RUNTIME_LIFECYCLE_PRODUCTION_MODE" \
CUSTOM_SUBAGENT_PRODUCTION_APPROVAL="$RUNTIME_LIFECYCLE_PRODUCTION_APPROVAL" \
/bin/sh "$VENDOR_DIR/lifecycle.sh" uninstall deepseek-developer

set +e
keychain_exists deepseek-developer
keychain_lookup_status=$?
set -e
case "$keychain_lookup_status" in
  0) keychain_delete deepseek-developer || die 'Keychain cleanup failed after lifecycle cleanup; retry uninstall after resolving Keychain access' ;;
  44) ;;
  *)
    printf '%s\n' "deepseek-developer: Keychain lookup failed status=$keychain_lookup_status service=codex-custom-subagent/deepseek-developer account=api-key; resolve Keychain access and retry uninstall." >&2
    exit "$keychain_lookup_status"
    ;;
esac
printf '%s\n' 'DeepSeek developer lifecycle and Keychain item removed.'
