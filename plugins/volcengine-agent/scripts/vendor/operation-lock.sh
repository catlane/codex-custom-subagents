#!/bin/sh

unset custom_subagent_lock_pending_dir custom_subagent_lock_pending_home custom_subagent_lock_pending_owner_tmp

custom_subagent_lock_error() {
  printf '%s\n' "custom-subagents: $1" >&2
}

custom_subagent_lock_home_valid() {
  custom_subagent_lock_home=$1
  case "$custom_subagent_lock_home" in
    /*) ;;
    *) custom_subagent_lock_error 'lock home must be an absolute path'; return 76 ;;
  esac
  [ -d "$custom_subagent_lock_home" ] && [ ! -L "$custom_subagent_lock_home" ] || {
    custom_subagent_lock_error 'lock home must be a non-symlink directory'
    return 76
  }
  custom_subagent_lock_physical=$(cd -P "$custom_subagent_lock_home" 2>/dev/null && pwd) || {
    custom_subagent_lock_error 'lock home is unreadable'
    return 76
  }
  [ "$custom_subagent_lock_physical" = "$custom_subagent_lock_home" ] || {
    custom_subagent_lock_error 'lock home must not contain symlinks'
    return 76
  }
}

custom_subagent_lock_token_valid() {
  case ${1-} in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

custom_subagent_lock_validate_owner() {
  custom_subagent_lock_home_valid "$1" || return $?
  custom_subagent_lock_dir="$1/.custom-subagents-lifecycle.lock"
  custom_subagent_lock_owner="$custom_subagent_lock_dir/owner"
  [ -d "$custom_subagent_lock_dir" ] && [ ! -L "$custom_subagent_lock_dir" ] || {
    custom_subagent_lock_error 'lifecycle lock is missing or unsafe'
    return 76
  }
  [ -f "$custom_subagent_lock_owner" ] && [ ! -L "$custom_subagent_lock_owner" ] || {
    custom_subagent_lock_error 'lifecycle lock owner is missing or unsafe; confirm no lifecycle operation is running, then remove the lock directory'
    return 76
  }
  custom_subagent_lock_token=${CUSTOM_SUBAGENT_LOCK_TOKEN-}
  custom_subagent_lock_token_valid "$custom_subagent_lock_token" || {
    custom_subagent_lock_error 'lifecycle lock token is missing or invalid'
    return 76
  }
  custom_subagent_lock_owner_size=$(/usr/bin/wc -c <"$custom_subagent_lock_owner" | /usr/bin/tr -d '[:space:]')
  [ "$custom_subagent_lock_owner_size" = "${#custom_subagent_lock_token}" ] &&
    [ "$(/bin/cat "$custom_subagent_lock_owner")" = "$custom_subagent_lock_token" ] || {
      custom_subagent_lock_error 'lifecycle lock token does not match owner'
      return 76
    }
}

custom_subagent_lock_acquire() {
  [ "$#" = 1 ] || { custom_subagent_lock_error 'lock acquire requires HOME'; return 76; }
  unset CUSTOM_SUBAGENT_LOCK_TOKEN
  custom_subagent_lock_home_valid "$1" || return $?
  custom_subagent_lock_dir="$1/.custom-subagents-lifecycle.lock"
  if ! /bin/mkdir "$custom_subagent_lock_dir" 2>/dev/null; then
    custom_subagent_lock_error "another lifecycle operation is active; if this lock is stale, confirm no lifecycle operation is running, then remove $custom_subagent_lock_dir"
    return 75
  fi
  custom_subagent_lock_pending_dir=$custom_subagent_lock_dir
  custom_subagent_lock_pending_home=$1
  custom_subagent_lock_pending_owner_tmp=
  custom_subagent_lock_token=$(/usr/bin/uuidgen 2>/dev/null | /usr/bin/tr '[:upper:]' '[:lower:]') || {
    /bin/rmdir "$custom_subagent_lock_dir" 2>/dev/null || true
    unset custom_subagent_lock_pending_dir custom_subagent_lock_pending_home custom_subagent_lock_pending_owner_tmp
    custom_subagent_lock_error 'could not generate lifecycle lock token'
    return 76
  }
  custom_subagent_lock_token_valid "$custom_subagent_lock_token" || {
    /bin/rmdir "$custom_subagent_lock_dir" 2>/dev/null || true
    unset custom_subagent_lock_pending_dir custom_subagent_lock_pending_home custom_subagent_lock_pending_owner_tmp
    custom_subagent_lock_error 'generated lifecycle lock token is invalid'
    return 76
  }
  custom_subagent_lock_owner="$custom_subagent_lock_dir/owner"
  custom_subagent_lock_owner_tmp="$custom_subagent_lock_dir/.owner-$$"
  custom_subagent_lock_pending_owner_tmp=$custom_subagent_lock_owner_tmp
  if (umask 077 && printf '%s' "$custom_subagent_lock_token" >"$custom_subagent_lock_owner_tmp") &&
    /bin/mv "$custom_subagent_lock_owner_tmp" "$custom_subagent_lock_owner"; then
    CUSTOM_SUBAGENT_LOCK_TOKEN=$custom_subagent_lock_token
    export CUSTOM_SUBAGENT_LOCK_TOKEN
    unset custom_subagent_lock_pending_dir custom_subagent_lock_pending_home custom_subagent_lock_pending_owner_tmp
    printf '%s\n' "$CUSTOM_SUBAGENT_LOCK_TOKEN"
    return 0
  fi
  /bin/rm -f "$custom_subagent_lock_owner_tmp" 2>/dev/null || true
  /bin/rmdir "$custom_subagent_lock_dir" 2>/dev/null || true
  unset custom_subagent_lock_pending_dir custom_subagent_lock_pending_home custom_subagent_lock_pending_owner_tmp
  custom_subagent_lock_error 'could not write lifecycle lock owner'
  return 76
}

custom_subagent_lock_abort_acquire() {
  [ "$#" = 1 ] || { custom_subagent_lock_error 'lock abort requires HOME'; return 76; }
  custom_subagent_lock_expected_dir="$1/.custom-subagents-lifecycle.lock"
  [ "${custom_subagent_lock_pending_dir-}" = "$custom_subagent_lock_expected_dir" ] || return 0
  custom_subagent_lock_owner="$custom_subagent_lock_expected_dir/owner"
  custom_subagent_lock_owner_tmp=${custom_subagent_lock_pending_owner_tmp-}
  custom_subagent_lock_inprogress_token=${custom_subagent_lock_token-}

  if [ -e "$custom_subagent_lock_owner" ] || [ -L "$custom_subagent_lock_owner" ]; then
    if ! custom_subagent_lock_validate_owner "$1"; then
      [ "${CUSTOM_SUBAGENT_LOCK_TOKEN+x}" = x ] && return 76
      [ -n "$custom_subagent_lock_inprogress_token" ] || return 76
      custom_subagent_lock_inprogress_size=$(/usr/bin/wc -c <"$custom_subagent_lock_owner" | /usr/bin/tr -d '[:space:]')
      [ "$custom_subagent_lock_inprogress_size" = "${#custom_subagent_lock_inprogress_token}" ] || return 76
      [ "$(/bin/cat "$custom_subagent_lock_owner")" = "$custom_subagent_lock_inprogress_token" ] || return 76
    fi
    /bin/rm "$custom_subagent_lock_owner" || return 76
  elif [ -n "$custom_subagent_lock_owner_tmp" ]; then
    case "$custom_subagent_lock_owner_tmp" in "$custom_subagent_lock_expected_dir"/.owner-*) ;; *) return 76 ;; esac
    [ ! -L "$custom_subagent_lock_owner_tmp" ] || return 76
    /bin/rm -f "$custom_subagent_lock_owner_tmp" || return 76
  fi

  /bin/rmdir "$custom_subagent_lock_expected_dir" || return 76
  unset CUSTOM_SUBAGENT_LOCK_TOKEN custom_subagent_lock_pending_dir custom_subagent_lock_pending_home custom_subagent_lock_pending_owner_tmp
}

custom_subagent_lock_release() {
  [ "$#" = 1 ] || { custom_subagent_lock_error 'lock release requires HOME'; return 76; }
  custom_subagent_lock_validate_owner "$1" || return $?
  custom_subagent_lock_dir="$1/.custom-subagents-lifecycle.lock"
  custom_subagent_lock_release_dir="${custom_subagent_lock_dir}.releasing-$$-${CUSTOM_SUBAGENT_LOCK_TOKEN}"
  [ ! -e "$custom_subagent_lock_release_dir" ] && [ ! -L "$custom_subagent_lock_release_dir" ] || {
    custom_subagent_lock_error 'lifecycle lock release target already exists'
    return 76
  }
  if ! /bin/mv "$custom_subagent_lock_dir" "$custom_subagent_lock_release_dir"; then
    custom_subagent_lock_error "could not atomically release lifecycle lock; confirm no lifecycle operation is running, then remove $custom_subagent_lock_dir"
    return 76
  fi
  unset CUSTOM_SUBAGENT_LOCK_TOKEN
  if /bin/rm "$custom_subagent_lock_release_dir/owner" && /bin/rmdir "$custom_subagent_lock_release_dir"; then
    return 0
  fi
  custom_subagent_lock_error "lifecycle lock was released but cleanup failed; remove $custom_subagent_lock_release_dir"
  return 76
}

custom_subagent_lock_cli_defer_signal() { custom_subagent_lock_cli_pending_signal=$1; }
custom_subagent_lock_cli_release_on_signal() {
  custom_subagent_lock_cli_signal_status=$1
  trap '' HUP INT TERM
  custom_subagent_lock_release "$custom_subagent_lock_cli_home" >/dev/null 2>&1 || true
  exit "$custom_subagent_lock_cli_signal_status"
}

custom_subagent_lock_main() {
  custom_subagent_lock_command=${1-}
  shift || true
  case "$custom_subagent_lock_command" in
    acquire)
      custom_subagent_lock_cli_home=${1-}
      custom_subagent_lock_cli_pending_signal=0
      trap 'custom_subagent_lock_cli_defer_signal 129' HUP
      trap 'custom_subagent_lock_cli_defer_signal 130' INT
      trap 'custom_subagent_lock_cli_defer_signal 143' TERM
      if custom_subagent_lock_acquire "$@"; then
        custom_subagent_lock_cli_status=0
      else
        custom_subagent_lock_cli_status=$?
      fi
      if [ "$custom_subagent_lock_cli_status" = 0 ]; then
        trap 'custom_subagent_lock_cli_release_on_signal 129' HUP
        trap 'custom_subagent_lock_cli_release_on_signal 130' INT
        trap 'custom_subagent_lock_cli_release_on_signal 143' TERM
      else
        trap - HUP INT TERM
      fi
      if [ "$custom_subagent_lock_cli_pending_signal" != 0 ]; then
        if [ "$custom_subagent_lock_cli_status" = 0 ]; then
          custom_subagent_lock_cli_release_on_signal "$custom_subagent_lock_cli_pending_signal"
        fi
        return "$custom_subagent_lock_cli_pending_signal"
      fi
      return "$custom_subagent_lock_cli_status"
      ;;
    release)
      custom_subagent_lock_release "$@"
      custom_subagent_lock_cli_status=$?
      trap - HUP INT TERM
      return "$custom_subagent_lock_cli_status"
      ;;
    *) custom_subagent_lock_error 'expected acquire or release'; return 64 ;;
  esac
}

custom_subagent_lock_sourced=0
(return 0 2>/dev/null) && custom_subagent_lock_sourced=1
if [ "$custom_subagent_lock_sourced" = 0 ]; then
  custom_subagent_lock_main "$@"
  exit $?
fi
unset custom_subagent_lock_sourced
