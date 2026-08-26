#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/tests/helpers/assert.sh"

TEMP_ROOT=$(mktemp -d /private/tmp/custom-subagents-keychain-tty.XXXXXX)
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM

SENTINEL='TTY_SECRET_SENTINEL_9C42'
AGENT='deepseek-agent'
HELPER_LOG="$TEMP_ROOT/helper-received.log"
export HELPER_LOG
TRANSCRIPT="$TEMP_ROOT/pty-transcript.log"
NO_TTY_ERR="$TEMP_ROOT/no-tty.err"

# The GUI path always fails in this suite, simulating a VM / SSH / sandboxed
# agent shell where the native dialog cannot be shown.
cat >"$TEMP_ROOT/failing-osascript" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$TEMP_ROOT/failing-osascript"

# Stand-in for the private expect transport: records what arrived on its
# private stdin pipe (the real helper forwards it into `security`).
cat >"$TEMP_ROOT/helper.exp" <<'EOF'
#!/usr/bin/expect -f
log_user 0
set timeout 10
if {[gets stdin secret] < 0 || $secret eq ""} { exit 65 }
set fh [open $env(HELPER_LOG) w]
puts -nonewline $fh $secret
close $fh
exit 0
EOF

# Drives the prompt under a real pty and answers it like a user would.
cat >"$TEMP_ROOT/driver.exp" <<'EOF'
#!/usr/bin/expect -f
log_user 0
set timeout 20
set keychain_sh [lindex $argv 0]
set fake_osascript [lindex $argv 1]
set helper [lindex $argv 2]
set agent [lindex $argv 3]
set input [lindex $argv 4]
set transcript [lindex $argv 5]
log_file -a $transcript
set env(CUSTOM_SUBAGENT_OSASCRIPT_BIN) $fake_osascript
set env(CUSTOM_SUBAGENT_EXPECT_HELPER) $helper
set env(CUSTOM_SUBAGENT_SECURITY_BIN) /usr/bin/true
spawn sh -c ". \"$keychain_sh\"; keychain_prompt_store \"$agent\""
expect {
  -ex {custom-subagents: native dialog unavailable; type the API key (input hidden) and press Return, or press Return alone to cancel: } {
    send -- "$input\r"
  }
  timeout { exit 124 }
  eof { exit 90 }
}
expect eof
set result [wait]
exit [lindex $result 3]
EOF

# 1. GUI unavailable + interactive terminal + typed key: stores via the helper.
/usr/bin/expect "$TEMP_ROOT/driver.exp" \
  "$ROOT/shared/keychain.sh" "$TEMP_ROOT/failing-osascript" "$TEMP_ROOT/helper.exp" \
  "$AGENT" "$SENTINEL" "$TRANSCRIPT" ||
  fail 'tty fallback did not store a typed key'
[ -f "$HELPER_LOG" ] || fail 'helper did not receive the typed key'
[ "$(cat "$HELPER_LOG")" = "$SENTINEL" ] ||
  fail 'helper received an unexpected value'
if grep -F "$SENTINEL" "$TRANSCRIPT" >/dev/null 2>&1; then
  fail 'typed key was echoed to the terminal transcript'
fi

# 2. GUI unavailable + interactive terminal + bare Return: treated as cancel.
rm -f "$HELPER_LOG"
if /usr/bin/expect "$TEMP_ROOT/driver.exp" \
  "$ROOT/shared/keychain.sh" "$TEMP_ROOT/failing-osascript" "$TEMP_ROOT/helper.exp" \
  "$AGENT" '' "$TRANSCRIPT"; then
  fail 'empty tty input should cancel the prompt'
else
  cancel_status=$?
fi
[ "$cancel_status" = 2 ] || fail "empty tty input returned $cancel_status, expected 2"
[ ! -f "$HELPER_LOG" ] || fail 'cancelled tty prompt still invoked the helper'

# 3. GUI unavailable + no terminal at all: clear guidance, exit 1.
if CUSTOM_SUBAGENT_OSASCRIPT_BIN="$TEMP_ROOT/failing-osascript" \
  CUSTOM_SUBAGENT_EXPECT_HELPER="$TEMP_ROOT/helper.exp" \
  CUSTOM_SUBAGENT_SECURITY_BIN=/usr/bin/true \
  sh -c '. "$1"; keychain_prompt_store "$2"' \
  sh "$ROOT/shared/keychain.sh" "$AGENT" </dev/null 2>"$NO_TTY_ERR"; then
  fail 'prompt should fail when neither dialog nor terminal is available'
else
  no_tty_status=$?
fi
[ "$no_tty_status" = 1 ] || fail "no-tty prompt returned $no_tty_status, expected 1"
grep -F 'interactive Terminal window' "$NO_TTY_ERR" >/dev/null 2>&1 ||
  fail 'no-tty failure did not tell the user to use an interactive Terminal'

printf '%s\n' 'keychain tty fallback tests passed'
