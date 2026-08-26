#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MARKETPLACE="$ROOT/.agents/plugins/marketplace.json"
PLUGIN_NAMES="deepseek-agent volcengine-agent"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: ${1#$ROOT/}"
}

assert_dir() {
  [ -d "$1" ] || fail "missing directory: ${1#$ROOT/}"
}

assert_json() {
  plutil -convert xml1 -o /dev/null -- "$1" >/dev/null 2>&1 ||
    fail "invalid JSON: ${1#$ROOT/}"
}

assert_contains() {
  file=$1
  pattern=$2
  message=$3
  grep -F "$pattern" "$file" >/dev/null 2>&1 || fail "$message"
}

assert_not_contains() {
  file=$1
  pattern=$2
  message=$3
  if grep -F "$pattern" "$file" >/dev/null 2>&1; then
    fail "$message"
  fi
}

assert_file "$MARKETPLACE"
assert_json "$MARKETPLACE"
assert_contains "$MARKETPLACE" '"name": "custom-subagents"' "wrong marketplace name"
assert_contains "$MARKETPLACE" '"installation": "AVAILABLE"' "missing installation policy"
assert_contains "$MARKETPLACE" '"authentication": "ON_INSTALL"' "missing authentication policy"
assert_contains "$MARKETPLACE" '"products": ["CODEX"]' "missing CODEX product policy"
assert_contains "$MARKETPLACE" '"category": "Developer Tools"' "wrong marketplace category"

for plugin_name in $PLUGIN_NAMES; do
  plugin_root="$ROOT/plugins/$plugin_name"
  manifest="$plugin_root/.codex-plugin/plugin.json"

  assert_file "$manifest"
  assert_json "$manifest"
  assert_contains "$MARKETPLACE" "\"name\": \"$plugin_name\"" "marketplace missing $plugin_name"
  assert_contains "$MARKETPLACE" "\"path\": \"./plugins/$plugin_name\"" "wrong marketplace path for $plugin_name"
  assert_contains "$manifest" "\"name\": \"$plugin_name\"" "manifest name mismatch for $plugin_name"
  grep -E '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+([+-][^"]+)?"' "$manifest" >/dev/null 2>&1 ||
    fail "manifest version is not semver: $plugin_name"
  assert_dir "$plugin_root/skills"
  assert_dir "$plugin_root/skills/${plugin_name}-setup"
  assert_dir "$plugin_root/skills/${plugin_name}-uninstall"
  assert_contains "$manifest" 'provider profiles' "manifest is not provider-oriented: $plugin_name"
  assert_not_contains "$manifest" 'fixed-role' "manifest retains fixed-role wording: $plugin_name"
  [ -x "$plugin_root/scripts/configure.sh" ] || fail "configure entrypoint is not executable: $plugin_name"
  [ -x "$plugin_root/scripts/uninstall.sh" ] || fail "uninstall entrypoint is not executable: $plugin_name"
  assert_file "$plugin_root/scripts/runtime-gate.sh"
  for shared_name in keychain.sh lifecycle.sh operation-lock.sh prompt-secret.js state.js; do
    assert_file "$plugin_root/scripts/vendor/$shared_name"
    cmp -s "$ROOT/shared/$shared_name" "$plugin_root/scripts/vendor/$shared_name" ||
      fail "vendored $shared_name differs from shared source: $plugin_name"
  done

  if find "$plugin_root" -type l -exec sh -c '
    root=$1
    shift
    for link do
      target=$(cd "$(dirname "$link")" && realpath "$link") || exit 2
      case "$target" in
        "$root"/*) ;;
        *) exit 1 ;;
      esac
    done
  ' sh "$plugin_root" {} +; then
    :
  else
    fail "symlink escapes plugin root: $plugin_name"
  fi
done

assert_file "$ROOT/scripts/validate-repository.sh"

printf 'PASS: static marketplace validation\n'
