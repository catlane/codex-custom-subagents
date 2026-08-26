#!/bin/sh

set -eu

fail() {
  printf '%s\n' "FAIL: $1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

assert_not_file() {
  [ ! -e "$1" ] || fail "unexpected file: $1"
}

assert_contains() {
  grep -F -- "$2" "$1" >/dev/null 2>&1 || fail "missing '$2' in $1"
}

assert_equals() {
  [ "$1" = "$2" ] || fail "expected '$1', got '$2'"
}

assert_same_file() {
  cmp -s "$1" "$2" || fail "files differ: $1 $2"
}
