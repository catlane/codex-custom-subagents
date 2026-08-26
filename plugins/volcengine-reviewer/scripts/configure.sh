#!/bin/sh

set -eu
set +x
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PLUGIN_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VENDOR_DIR="$SCRIPT_DIR/vendor"
CODEX_HOME=${CODEX_HOME:-"$HOME/.codex"}
ENDPOINT=
MODEL=

[ -f "$SCRIPT_DIR/runtime-gate.sh" ] && [ ! -L "$SCRIPT_DIR/runtime-gate.sh" ] || {
  printf '%s\n' 'volcengine-reviewer: runtime gate is missing or unsafe' >&2
  exit 1
}
. "$SCRIPT_DIR/runtime-gate.sh"
custom_subagent_runtime_gate "$CODEX_HOME" "$PLUGIN_ROOT" volcengine-reviewer

die() {
  printf '%s\n' "volcengine-reviewer: $1" >&2
  exit 1
}

usage() {
  printf '%s\n' 'usage: configure.sh --endpoint URL --model MODEL_OR_DEPLOYMENT_ID' >&2
  exit 64
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --endpoint)
      [ "$#" -ge 2 ] || usage
      ENDPOINT=$2
      shift 2
      ;;
    --model)
      [ "$#" -ge 2 ] || usage
      MODEL=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

[ -n "$ENDPOINT" ] || usage
[ -n "$MODEL" ] || usage
[ -d "$CODEX_HOME" ] || die "CODEX_HOME must be an existing directory"
[ -f "$PLUGIN_ROOT/templates/agent-spec.json" ] || die 'agent spec is missing'
[ -f "$VENDOR_DIR/lifecycle.sh" ] || die 'vendored lifecycle is missing'
[ -f "$VENDOR_DIR/operation-lock.sh" ] || die 'vendored operation lock is missing'
[ -f "$VENDOR_DIR/state.js" ] || die 'vendored state helper is missing'
[ -f "$VENDOR_DIR/keychain.sh" ] || die 'vendored Keychain adapter is missing'
[ -f "$VENDOR_DIR/prompt-secret.applescript" ] || die 'vendored secret prompt is missing'

/usr/bin/osascript -l JavaScript "$VENDOR_DIR/state.js" validate-agent-input \
  volcengine-reviewer review volcengine "$ENDPOINT" "$MODEL" >/dev/null

# The key is never accepted through argv, environment, or a configuration file.
CUSTOM_SUBAGENT_PROMPT_SECRET_SCRIPT="$VENDOR_DIR/prompt-secret.applescript"
. "$VENDOR_DIR/keychain.sh"
. "$VENDOR_DIR/operation-lock.sh"

OPERATION_LOCK_HELD=0
OPERATION_LOCK_ACQUIRING=0
OPERATION_PENDING_SIGNAL=0
FRESH_CREDENTIAL_WAS_ABSENT=0
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
credential_binding_is_committed() {
  binding_state="$CODEX_HOME/custom-subagents/state.json"
  [ -f "$binding_state" ] && [ ! -L "$binding_state" ] || return 1
  set +e
  committed_binding=$(/usr/bin/osascript -l JavaScript "$VENDOR_DIR/state.js" \
    keychain-binding-status "$binding_state" volcengine-reviewer "$ENDPOINT" 2>/dev/null)
  committed_binding_status=$?
  set -e
  [ "$committed_binding_status" = 0 ] && [ "$committed_binding" = match ] || return 1
  set +e
  CUSTOM_SUBAGENT_HOME="$CODEX_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/templates/agent-spec.json" \
  CUSTOM_SUBAGENT_PRODUCTION_MODE="$RUNTIME_LIFECYCLE_PRODUCTION_MODE" \
  CUSTOM_SUBAGENT_PRODUCTION_APPROVAL="$RUNTIME_LIFECYCLE_PRODUCTION_APPROVAL" \
  /bin/sh "$VENDOR_DIR/lifecycle.sh" validate-registration volcengine-reviewer >/dev/null 2>&1
  committed_lifecycle_status=$?
  set -e
  [ "$committed_lifecycle_status" = 0 ]
}
cleanup_fresh_credential_on_signal() {
  [ "$FRESH_CREDENTIAL_WAS_ABSENT" = 1 ] || return 0
  credential_binding_is_committed && return 0
  set +e
  keychain_exists volcengine-reviewer
  signal_keychain_status=$?
  set -e
  case "$signal_keychain_status" in
    0) keychain_delete volcengine-reviewer ;;
    44) return 0 ;;
    *)
      printf '%s\n' "volcengine-reviewer: interrupted configuration could not inspect Keychain status=$signal_keychain_status service=codex-custom-subagent/volcengine-reviewer account=api-key; retry uninstall cleanup." >&2
      return "$signal_keychain_status"
      ;;
  esac
}
handle_operation_signal() {
  signal_status=$1
  trap - EXIT HUP INT TERM
  cleanup_fresh_credential_on_signal || true
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

run_lifecycle() {
  CUSTOM_SUBAGENT_HOME="$CODEX_HOME" \
  CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
  CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/templates/agent-spec.json" \
  CUSTOM_SUBAGENT_PRODUCTION_MODE="$RUNTIME_LIFECYCLE_PRODUCTION_MODE" \
  CUSTOM_SUBAGENT_PRODUCTION_APPROVAL="$RUNTIME_LIFECYCLE_PRODUCTION_APPROVAL" \
  /bin/sh "$VENDOR_DIR/lifecycle.sh" install volcengine-reviewer review volcengine "$ENDPOINT" "$MODEL"
}

credential_binding_status() {
  binding_state="$CODEX_HOME/custom-subagents/state.json"
  if [ ! -e "$binding_state" ] && [ ! -L "$binding_state" ]; then
    printf '%s\n' absent
    return 0
  fi
  [ ! -L "$binding_state" ] && [ -f "$binding_state" ] ||
    die 'credential binding state is not a regular managed file service=codex-custom-subagent/volcengine-reviewer account=api-key; restore lifecycle state before retrying'

  set +e
  binding_result=$(/usr/bin/osascript -l JavaScript "$VENDOR_DIR/state.js" \
    keychain-binding-status "$binding_state" volcengine-reviewer "$ENDPOINT")
  binding_result_status=$?
  set -e
  [ "$binding_result_status" = 0 ] ||
    die 'credential binding state validation failed service=codex-custom-subagent/volcengine-reviewer account=api-key; restore lifecycle state before retrying'
  case "$binding_result" in match|mismatch|absent) ;; *) die 'credential binding state returned an invalid status' ;; esac
  printf '%s\n' "$binding_result"
}

set +e
keychain_exists volcengine-reviewer
keychain_lookup_status=$?
set -e

case "$keychain_lookup_status" in
  0)
    binding_status=$(credential_binding_status)
    case "$binding_status" in
      match) run_lifecycle ;;
      mismatch|absent)
        die 'existing credential endpoint binding is mismatched or unknown service=codex-custom-subagent/volcengine-reviewer account=api-key; first run the volcengine-reviewer uninstall cleanup, then configure again and enter a fresh hidden-dialog key'
        ;;
    esac
    ;;
  44)
    FRESH_CREDENTIAL_WAS_ABSENT=1
    set +e
    keychain_prompt_store volcengine-reviewer
    prompt_status=$?
    set -e
    [ "$prompt_status" = 0 ] || {
      [ "$prompt_status" = 2 ] && exit 2
      die 'Keychain storage failed'
    }

    set +e
    run_lifecycle
    lifecycle_status=$?
    set -e
    if [ "$lifecycle_status" -ne 0 ]; then
      credential_binding_is_committed && exit "$lifecycle_status"
      if ! keychain_delete volcengine-reviewer; then
        printf '%s\n' 'volcengine-reviewer: lifecycle failed and Keychain cleanup incomplete service=codex-custom-subagent/volcengine-reviewer account=api-key; remove that exact item after resolving Keychain access, then rerun cleanup.' >&2
        exit 1
      fi
      exit "$lifecycle_status"
    fi
    ;;
  *)
    printf '%s\n' "volcengine-reviewer: Keychain lookup failed status=$keychain_lookup_status service=codex-custom-subagent/volcengine-reviewer account=api-key; resolve Keychain access and retry." >&2
    exit "$keychain_lookup_status"
    ;;
esac

printf '%s\n' 'Volcengine reviewer configured. Restart Codex and begin a fresh task.'
