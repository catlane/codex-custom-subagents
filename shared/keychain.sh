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

keychain_read() {
  set +x
  keychain_service_name=$(keychain_service "${1:-}") || return 1
  "$KEYCHAIN_SECURITY_BIN" find-generic-password -s "$keychain_service_name" -a "$KEYCHAIN_ACCOUNT" -w
  keychain_status=$?
  keychain_service_name=
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

# Hidden terminal fallback for environments where the native dialog cannot
# appear (VM consoles without GUI access for the agent shell, SSH sessions,
# sandboxed automation). The secret still never enters argv, the environment,
# files, or logs: echo is disabled on /dev/tty and the value is piped straight
# into the same private expect transport. Echo is restored even on signals.
keychain_prompt_store_tty() {
  set +x
  keychain_tty_service_name=${1:-}
  [ -n "$keychain_tty_service_name" ] || return 1
  [ -t 0 ] && [ -t 2 ] || return 1
  (
    set +x
    trap '/bin/stty echo 2>/dev/null' EXIT
    /bin/stty -echo 2>/dev/null || exit 1
    printf '%s' 'custom-subagents: native dialog unavailable; type the API key (input hidden) and press Return, or press Return alone to cancel: ' >&2
    IFS= read -r keychain_tty_secret || keychain_tty_secret=
    /bin/stty echo 2>/dev/null
    printf '\n' >&2
    if [ -z "$keychain_tty_secret" ]; then
      exit 2
    fi
    if [ "${#keychain_tty_secret}" -gt 12000 ]; then
      keychain_tty_secret=
      printf '%s\n' 'custom-subagents: API key is too long' >&2
      exit 1
    fi
    if printf '%s\n' "$keychain_tty_secret" | /usr/bin/expect "$KEYCHAIN_EXPECT_HELPER" "$keychain_tty_service_name" "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
      keychain_tty_secret=
      exit 0
    fi
    keychain_tty_secret=
    exit 1
  )
}

keychain_prompt_store() {
  set +x
  keychain_service_name=$(keychain_service "${1:-}") || return 1
  keychain_prompt_errfile=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/custom-subagents-prompt.XXXXXX") || return 1
  if keychain_prompt_response=$("$KEYCHAIN_OSASCRIPT_BIN" -l JavaScript "$KEYCHAIN_PROMPT_SECRET_SCRIPT" \
    "$KEYCHAIN_EXPECT_HELPER" "$keychain_service_name" "$KEYCHAIN_ACCOUNT" 2>"$keychain_prompt_errfile"); then
    /bin/rm -f "$keychain_prompt_errfile"
    :
  else
    # The native dialog could not run at all (for example a VM, SSH, or
    # sandboxed agent shell without GUI access). Surface the osascript
    # failure reason (it never contains the secret: failures happen before
    # input or inside the storage transport), then fall back to a hidden
    # terminal prompt when an interactive terminal is attached.
    keychain_prompt_reason=$(/usr/bin/awk 'NF { print; exit }' "$keychain_prompt_errfile")
    /bin/rm -f "$keychain_prompt_errfile"
    [ -n "$keychain_prompt_reason" ] &&
      printf '%s\n' "custom-subagents: native dialog failed: $keychain_prompt_reason" >&2
    keychain_prompt_response=
    keychain_secret=
    keychain_prompt_store_tty "$keychain_service_name" && keychain_tty_status=0 || keychain_tty_status=$?
    case "$keychain_tty_status" in
      0)
        keychain_service_name=
        return 0
        ;;
      2)
        keychain_service_name=
        return 2
        ;;
    esac
    printf '%s\n' "custom-subagents: native dialog and terminal prompt are both unavailable service=$keychain_service_name account=$KEYCHAIN_ACCOUNT; rerun this configure command with elevated (unsandboxed) execution so the native dialog can appear, or run it yourself in an interactive Terminal window" >&2
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
