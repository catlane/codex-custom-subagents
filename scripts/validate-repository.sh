#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MARKETPLACE="$ROOT/.agents/plugins/marketplace.json"

fail() {
  printf 'validation error: %s\n' "$1" >&2
  exit 1
}

validate_json() {
  [ -f "$1" ] || fail "missing ${1#$ROOT/}"
  plutil -convert xml1 -o /dev/null -- "$1" >/dev/null 2>&1 ||
    fail "invalid JSON in ${1#$ROOT/}"
}

validate_json "$MARKETPLACE"

for plugin_name in deepseek-developer volcengine-reviewer; do
  plugin_root="$ROOT/plugins/$plugin_name"
  manifest="$plugin_root/.codex-plugin/plugin.json"

  validate_json "$manifest"
  grep -F "\"name\": \"$plugin_name\"" "$manifest" >/dev/null 2>&1 ||
    fail "manifest name mismatch for $plugin_name"
  grep -F "\"path\": \"./plugins/$plugin_name\"" "$MARKETPLACE" >/dev/null 2>&1 ||
    fail "marketplace path mismatch for $plugin_name"
  [ -d "$plugin_root/skills" ] || fail "missing skills directory for $plugin_name"
  [ -x "$plugin_root/scripts/configure.sh" ] || fail "configure entrypoint is not executable for $plugin_name"
  [ -x "$plugin_root/scripts/uninstall.sh" ] || fail "uninstall entrypoint is not executable for $plugin_name"
  [ -f "$plugin_root/scripts/runtime-gate.sh" ] || fail "missing production runtime gate for $plugin_name"
  for shared_name in keychain.sh lifecycle.sh operation-lock.sh prompt-secret.applescript state.js; do
    vendor_file="$plugin_root/scripts/vendor/$shared_name"
    [ -f "$vendor_file" ] || fail "missing vendored $shared_name for $plugin_name"
    cmp -s "$ROOT/shared/$shared_name" "$vendor_file" ||
      fail "vendored $shared_name differs from shared source for $plugin_name"
  done
done

if grep -R '\[TODO:' "$ROOT/plugins" >/dev/null 2>&1; then
  fail "plugin files contain scaffold placeholders"
fi

printf 'repository validation passed\n'
