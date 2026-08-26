#!/bin/sh

# This file is sourced by the plugin setup scripts. Stop inherited xtrace before
# a dialog response can enter a shell variable.
set +x

KEYCHAIN_SECURITY_BIN=${CUSTOM_SUBAGENT_SECURITY_BIN:-/usr/bin/security}
KEYCHAIN_OSASCRIPT_BIN=${CUSTOM_SUBAGENT_OSASCRIPT_BIN:-/usr/bin/osascript}
KEYCHAIN_PROMPT_SECRET_SCRIPT=${CUSTOM_SUBAGENT_PROMPT_SECRET_SCRIPT:-shared/prompt-secret.js}
KEYCHAIN_EXPECT_HELPER=${CUSTOM_SUBAGENT_EXPECT_HELPER:-shared/store-keychain.exp}
KEYCHAIN_ACCOUNT=api-key

keychain_service() {
  keychain_agent_id=${1:-}
  case "$keychain_agent_id" in
    ''|*[!A-Za-z0-9-]*) return 1 ;;
  esac
  printf '%s\n' "codex-custom-subagent/$keychain_agent_id"
}

keychain_exists() {
  set +x
  keychain_service_name=$(keychain_service "${1:-}") || return 1
  if "$KEYCHAIN_SECURITY_BIN" find-generic-password -s "$keychain_service_name" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
    keychain_status=0
  else
    keychain_status=$?
  fi
  keychain_service_name=
  # Stable contract: 0 exists, 44 is the macOS item-not-found result, and all
  # other security errors are returned unchanged for callers to handle.
  return "$keychain_status"
}

keychain_delete() {
  set +x
  keychain_service_name=$(keychain_service "${1:-}") || return 1
  if "$KEYCHAIN_SECURITY_BIN" delete-generic-password -s "$keychain_service_name" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
    keychain_service_name=
    return 0
  fi
  printf '%s\n' "custom-subagents: failed to delete Keychain item service=$keychain_service_name account=$KEYCHAIN_ACCOUNT" >&2
  keychain_service_name=
  return 1
}

keychain_prompt_store() {
  set +x
  keychain_service_name=$(keychain_service "${1:-}") || return 1
  if keychain_prompt_response=$("$KEYCHAIN_OSASCRIPT_BIN" -l JavaScript "$KEYCHAIN_PROMPT_SECRET_SCRIPT" \
    "$KEYCHAIN_EXPECT_HELPER" "$keychain_service_name" "$KEYCHAIN_ACCOUNT" 2>/dev/null); then
    :
  else
    keychain_prompt_response=
    keychain_secret=
    printf '%s\n' "custom-subagents: failed to collect Keychain item service=$keychain_service_name account=$KEYCHAIN_ACCOUNT" >&2
    keychain_service_name=
    return 1
  fi

  case "$keychain_prompt_response" in
    cancelled)
      keychain_prompt_response=
      keychain_service_name=
      return 2
      ;;
    stored)
      keychain_prompt_response=
      keychain_service_name=
      return 0
      ;;
    empty)
      keychain_prompt_response=
      printf '%s\n' "custom-subagents: empty Keychain item service=$keychain_service_name account=$KEYCHAIN_ACCOUNT" >&2
      keychain_service_name=
      return 1
      ;;
    *)
      printf '%s\n' "custom-subagents: invalid Keychain dialog response service=$keychain_service_name account=$KEYCHAIN_ACCOUNT" >&2
      keychain_prompt_response=
      keychain_service_name=
      return 1
      ;;
  esac
}
