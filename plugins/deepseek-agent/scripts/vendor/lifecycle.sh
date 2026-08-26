#!/bin/sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE_JS="$SCRIPT_DIR/state.js"
OPERATION_LOCK_SH="$SCRIPT_DIR/operation-lock.sh"
. "$OPERATION_LOCK_SH"
BEGIN_MARKER='<!-- BEGIN custom-subagents managed workflow -->'
END_MARKER='<!-- END custom-subagents managed workflow -->'
WRITE_COUNT=0
COMMITTED=0
BACKUP_LIST=
LOCK_OWNED=0
LOCK_BORROWED=0
LOCK_ACQUIRING=0
LOCK_PENDING_SIGNAL=0
die() { printf '%s\n' "custom-subagents: $1" >&2; exit 1; }
require_home() {
  SUBAGENT_HOME=${CUSTOM_SUBAGENT_HOME:-}
  [ -n "$SUBAGENT_HOME" ] || die "CUSTOM_SUBAGENT_HOME must be set"
  case "$SUBAGENT_HOME" in /*) ;; *) die "CUSTOM_SUBAGENT_HOME must be an absolute path" ;; esac
  [ -d "$SUBAGENT_HOME" ] || die "CUSTOM_SUBAGENT_HOME must be an existing directory"
  CANONICAL_HOME=$(cd -P "$SUBAGENT_HOME" && pwd)
  [ "$CANONICAL_HOME" = "$SUBAGENT_HOME" ] || die "CUSTOM_SUBAGENT_HOME must not contain symlinks"
  if [ "${CUSTOM_SUBAGENT_PRODUCTION_MODE:-}" = 1 ]; then
    [ "${CUSTOM_SUBAGENT_TEST_MODE+x}" != x ] &&
    [ "${CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE+x}" != x ] &&
    [ "${CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL+x}" != x ] &&
    [ "${CUSTOM_SUBAGENT_ALLOW_HTTP+x}" != x ] ||
      die "test hooks are forbidden in production mode"
  fi
  case "$SUBAGENT_HOME" in
    "${HOME:-}/.codex")
      [ "${CUSTOM_SUBAGENT_PRODUCTION_MODE:-}" = 1 ] &&
      [ "${CUSTOM_SUBAGENT_PRODUCTION_APPROVAL:-}" = custom-subagents-live-home ] ||
        die "live Codex home requires explicit production approval"
      ;;
  esac
  PLUGIN_ROOT=${CUSTOM_SUBAGENT_PLUGIN_ROOT:-}
  [ -d "$PLUGIN_ROOT" ] || die "CUSTOM_SUBAGENT_PLUGIN_ROOT must be an existing directory"
  [ -f "$PLUGIN_ROOT/.codex-plugin/plugin.json" ] || die "plugin ownership manifest is missing"
  AGENT_SPEC=${CUSTOM_SUBAGENT_AGENT_SPEC:-}
  [ -n "$AGENT_SPEC" ] && [ -f "$AGENT_SPEC" ] && [ ! -L "$AGENT_SPEC" ] ||
    die "CUSTOM_SUBAGENT_AGENT_SPEC must be a regular file"
  CANONICAL_PLUGIN_ROOT=$(cd -P "$PLUGIN_ROOT" && pwd)
  CANONICAL_AGENT_SPEC=$(cd -P "$(dirname "$AGENT_SPEC")" && pwd)/$(basename "$AGENT_SPEC")
  case "$CANONICAL_AGENT_SPEC" in "$CANONICAL_PLUGIN_ROOT"/*) ;; *) die "agent spec must be inside plugin root" ;; esac
  [ -f "$STATE_JS" ] || die "state helper is missing"
  [ -f "$OPERATION_LOCK_SH" ] || die "operation lock helper is missing"
  TEST_CATALOG_SOURCE=
  TEST_PRIMARY_MODEL=
  if [ "${CUSTOM_SUBAGENT_TEST_MODE:-}" = 1 ]; then
    TEST_CATALOG_SOURCE=${CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE:-}
    TEST_PRIMARY_MODEL=${CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL:-}
  else
    [ -z "${CUSTOM_SUBAGENT_TEST_CATALOG_SOURCE:-}" ] || die "test catalog override requires CUSTOM_SUBAGENT_TEST_MODE=1"
    [ -z "${CUSTOM_SUBAGENT_TEST_PRIMARY_MODEL:-}" ] || die "test primary model override requires CUSTOM_SUBAGENT_TEST_MODE=1"
  fi
}
jxa() { /usr/bin/osascript -l JavaScript "$STATE_JS" "$@"; }
assert_safe_target() {
  checked_path=$1
  case "$checked_path" in "$SUBAGENT_HOME"/*) ;; *) die "refusing a path outside CUSTOM_SUBAGENT_HOME" ;; esac
  [ ! -L "$checked_path" ] || die "refusing symlinked managed target"
  checked_parent=$(dirname "$checked_path")
  while [ ! -e "$checked_parent" ]; do checked_parent=$(dirname "$checked_parent"); done
  [ ! -L "$checked_parent" ] || die "refusing symlinked managed parent"
  checked_physical_parent=$(cd -P "$checked_parent" && pwd)
  case "$checked_physical_parent" in "$SUBAGENT_HOME"|"$SUBAGENT_HOME"/*) ;; *) die "managed path escapes CUSTOM_SUBAGENT_HOME" ;; esac
}
safe_mkdir() {
  directory=$1
  assert_safe_target "$directory/.custom-subagents-guard"
  mkdir -p "$directory"
  assert_safe_target "$directory/.custom-subagents-guard"
}
release_lock() {
  if [ "$LOCK_OWNED" = 1 ]; then
    custom_subagent_lock_release "$SUBAGENT_HOME" || return $?
    LOCK_OWNED=0
  elif [ "$LOCK_ACQUIRING" = 1 ]; then
    if [ "${CUSTOM_SUBAGENT_LOCK_TOKEN+x}" = x ]; then
      custom_subagent_lock_release "$SUBAGENT_HOME" || return $?
    else
      custom_subagent_lock_abort_acquire "$SUBAGENT_HOME" || return $?
    fi
    LOCK_ACQUIRING=0
  fi
}
release_lock_on_exit() {
  status=$?
  trap - EXIT HUP INT TERM
  if ! release_lock && [ "$status" = 0 ]; then status=1; fi
  exit "$status"
}
release_lock_on_signal() {
  status=$1
  trap - EXIT HUP INT TERM
  release_lock || true
  exit "$status"
}
acquire_lock() {
  LOCK_PENDING_SIGNAL=0
  trap release_lock_on_exit EXIT
  trap 'LOCK_PENDING_SIGNAL=129' HUP
  trap 'LOCK_PENDING_SIGNAL=130' INT
  trap 'LOCK_PENDING_SIGNAL=143' TERM
  if [ "${CUSTOM_SUBAGENT_LOCK_TOKEN+x}" = x ]; then
    LOCK_BORROWED=1
    if custom_subagent_lock_validate_owner "$SUBAGENT_HOME"; then
      lock_acquire_status=0
    else
      lock_acquire_status=$?
    fi
  else
    LOCK_ACQUIRING=1
    if custom_subagent_lock_acquire "$SUBAGENT_HOME" >/dev/null; then
      lock_acquire_status=0
      LOCK_OWNED=1
    else
      lock_acquire_status=$?
    fi
    LOCK_ACQUIRING=0
  fi
  trap 'release_lock_on_signal 129' HUP
  trap 'release_lock_on_signal 130' INT
  trap 'release_lock_on_signal 143' TERM
  [ "$LOCK_PENDING_SIGNAL" = 0 ] || release_lock_on_signal "$LOCK_PENDING_SIGNAL"
  [ "$lock_acquire_status" = 0 ] || exit "$lock_acquire_status"
}
relative_target() {
  assert_safe_target "$1"
  printf '%s\n' "${1#"$SUBAGENT_HOME"/}"
}
backup_target() {
  target=$1; relative=$(relative_target "$target"); backup="$BACKUP_DIR/$relative"
  { [ -e "$backup" ] || [ -e "$backup.absent" ]; } && return 0
  mkdir -p "$(dirname "$backup")"
  if [ -e "$target" ]; then cp -p "$target" "$backup"; else : >"$backup.absent"; fi
  BACKUP_LIST="${BACKUP_LIST}${relative}
"
}
restore_backups() {
  [ -n "${BACKUP_DIR:-}" ] || return 0
  printf '%s' "$BACKUP_LIST" | while IFS= read -r relative; do
    [ -n "$relative" ] || continue
    target="$SUBAGENT_HOME/$relative"; backup="$BACKUP_DIR/$relative"
    if [ -e "$backup.absent" ]; then rm -f "$target"
    elif [ -e "$backup" ]; then mkdir -p "$(dirname "$target")"; cp -p "$backup" "$target"; fi
  done
}
rollback() {
  status=$1
  [ "$COMMITTED" = 1 ] || restore_backups
  trap - EXIT HUP INT TERM
  if ! release_lock && [ "$status" = 0 ]; then status=1; fi
  exit "$status"
}
cleanup_and_rollback() { status=${1:-$?}; rm -rf "$temp_dir"; rollback "$status"; }
atomic_write() {
  target=$1; source=$2; assert_safe_target "$target"; backup_target "$target"; target_dir=$(dirname "$target"); safe_mkdir "$target_dir"
  temporary=$(mktemp "$target_dir/.custom-subagents.XXXXXX"); cp "$source" "$temporary"; mv -f "$temporary" "$target"
  WRITE_COUNT=$((WRITE_COUNT + 1))
  [ "${CUSTOM_SUBAGENT_FAIL_AFTER_WRITE:-}" != "$WRITE_COUNT" ] || die "injected failure after write boundary $WRITE_COUNT"
}
remove_target() {
  target=$1; assert_safe_target "$target"; backup_target "$target"; rm -f "$target"
  WRITE_COUNT=$((WRITE_COUNT + 1))
  [ "${CUSTOM_SUBAGENT_FAIL_AFTER_WRITE:-}" != "$WRITE_COUNT" ] || die "injected failure after write boundary $WRITE_COUNT"
}
count_marker() {
  file=$1; marker=$2
  [ -f "$file" ] || { printf '0\n'; return; }
  grep -F -c -- "$marker" "$file" || true
}
agents_shape() {
  [ -e "$1" ] || { printf '%s\n' absent; return; }
  [ -s "$1" ] || { printf '%s\n' empty; return; }
  last_byte=$(tail -c 1 "$1" | od -An -t x1 | tr -d '[:space:]')
  [ "$last_byte" = 0a ] && printf '%s\n' ends-newline || printf '%s\n' no-final-newline
}
validate_markers() {
  begins=$(count_marker "$1" "$BEGIN_MARKER"); ends=$(count_marker "$1" "$END_MARKER")
  [ "$begins" -le 1 ] && [ "$ends" -le 1 ] && [ "$begins" = "$ends" ] || die "duplicate or malformed managed workflow markers; restore from a backup"
}
validate_agent_file() {
  [ -e "$1" ] || return 0
  begin="# BEGIN custom-subagents managed agent provider=$2 role=$3 plugin=$4"
  end="# END custom-subagents managed agent provider=$2 role=$3 plugin=$4"
  [ "$(grep -F -c -- "$begin" "$1" || true)" = 1 ] &&
  [ "$(grep -F -c -- "$end" "$1" || true)" = 1 ] ||
    die "refusing unmanaged target agent file: $1"
  [ "$(sed -n '1p' "$1")" = "$begin" ] && [ "$(tail -n 1 "$1")" = "$end" ] ||
    die "refusing malformed managed target agent file: $1"
  if [ -f "$5" ]; then
    expected_agent=$(jxa render-agent-spec-state "$CANONICAL_AGENT_SPEC" "$5" "$2" "$3" "$6" "codex-custom-subagent/$2")
    actual_agent=$(cat "$1")
    expected_enveloped=$(printf '%s\n%s\n%s' "$begin" "$expected_agent" "$end")
    [ "$actual_agent" = "$expected_enveloped" ] ||
      die "managed native agent TOML does not match deterministic spec rendering"
  fi
}
validate_endpoint() {
  jxa validate-endpoint "$1" >/dev/null
}
config_catalog_line() {
  [ -f "$1" ] || return 0
  grep -E '^[[:space:]]*model_catalog_json[[:space:]]*=' "$1" || true
}
has_managed_residue() {
  generated_catalog=$1; base_catalog=$2; workflow=$3; config=$4
  { [ -e "$generated_catalog" ] || [ -L "$generated_catalog" ]; } && return 0
  { [ -e "$base_catalog" ] || [ -L "$base_catalog" ]; } && return 0
  [ "$(count_marker "$workflow" "$BEGIN_MARKER")" -gt 0 ] && return 0
  [ "$(count_marker "$workflow" "$END_MARKER")" -gt 0 ] && return 0
  config_catalog_line "$config" | grep -F -- "$generated_catalog" >/dev/null 2>&1 && return 0
  if [ -d "$SUBAGENT_HOME/agents" ]; then
    for managed_candidate in "$SUBAGENT_HOME"/agents/*.toml; do
      [ -f "$managed_candidate" ] || continue
      grep -F '# BEGIN custom-subagents managed agent ' "$managed_candidate" >/dev/null 2>&1 && return 0
    done
  fi
  return 1
}
provider_profile_path() {
  provider_name=$(printf '%s' "$1" | tr '-' '_')
  printf '%s\n' "$SUBAGENT_HOME/agents/${provider_name}_$2.toml"
}
provider_marker_residue() {
  provider_id=$1
  [ -d "$SUBAGENT_HOME/agents" ] || return 1
  for managed_candidate in "$SUBAGENT_HOME"/agents/*.toml; do
    [ -e "$managed_candidate" ] || [ -L "$managed_candidate" ] || continue
    [ -f "$managed_candidate" ] || return 0
    grep -F "# BEGIN custom-subagents managed agent provider=$provider_id " "$managed_candidate" >/dev/null 2>&1 && return 0
  done
  return 1
}
provider_residue_for_id() {
  provider_id=$1
  provider_guess=${provider_id%-agent}
  [ "$provider_guess" != "$provider_id" ] || provider_guess=$provider_id
  for profile_role in general developer reviewer; do
    guessed_profile=$(provider_profile_path "$provider_guess" "$profile_role")
    { [ -e "$guessed_profile" ] || [ -L "$guessed_profile" ]; } && return 0
  done
  provider_marker_residue "$provider_id"
}
validate_backup_history() {
  backup_root=$1
  [ -d "$backup_root" ] || die "managed backup history is missing"
  for backup_record in "$backup_root"/*; do
    [ -d "$backup_record" ] && [ ! -L "$backup_record" ] || continue
    [ -n "$(find "$backup_record" -type f -print -quit)" ] && return 0
  done
  die "managed backup history is missing"
}
validate_with_recovery() {
  if validation_error=$("$@" 2>&1); then
    return 0
  fi
  [ -z "$validation_error" ] || printf '%s\n' "$validation_error" >&2
  die "restore from backup or reconfigure custom subagents"
}
render_workflow_file() {
  workflow_file=$1; rendered=$2; output=$3; begins=$(count_marker "$workflow_file" "$BEGIN_MARKER")
  if [ "$begins" = 0 ]; then
    if [ -f "$workflow_file" ]; then cat "$workflow_file" >"$output"; [ ! -s "$workflow_file" ] || printf '\n' >>"$output"; else : >"$output"; fi
    cat "$rendered" >>"$output"; return
  fi
  extract_workflow_parts "$workflow_file" "$output.prefix" "$output.suffix"
  cat "$output.prefix" >"$output"
  cat "$rendered" >>"$output"
  cat "$output.suffix" >>"$output"
}
extract_workflow_parts() {
  workflow_file=$1; prefix=$2; suffix=$3
  begin_offset=$(LC_ALL=C awk -v marker="$BEGIN_MARKER" '
    BEGIN { bytes = 0 }
    $0 == marker { print bytes; found = 1; exit }
    { bytes += length($0) + 1 }
    END { if (!found) exit 1 }
  ' "$workflow_file")
  end_offset=$(LC_ALL=C awk -v marker="$END_MARKER" '
    BEGIN { bytes = 0 }
    { bytes += length($0) + 1 }
    $0 == marker { print bytes; found = 1; exit }
    END { if (!found) exit 1 }
  ' "$workflow_file")
  dd if="$workflow_file" of="$prefix" bs=1 count="$begin_offset" 2>/dev/null
  dd if="$workflow_file" of="$suffix" bs=1 skip="$end_offset" 2>/dev/null
}
remove_workflow_file() {
  workflow_file=$1; output=$2; shape=$3
  extract_workflow_parts "$workflow_file" "$output.prefix" "$output.suffix"
  if [ "$shape" = ends-newline ] || [ "$shape" = no-final-newline ]; then
    prefix_size=$(wc -c <"$output.prefix" | tr -d ' ')
    [ "$prefix_size" -gt 0 ] || die "managed workflow separator is missing"
    last_prefix_byte=$(tail -c 1 "$output.prefix" | od -An -t x1 | tr -d '[:space:]')
    [ "$last_prefix_byte" = 0a ] || die "managed workflow separator is malformed"
    dd if="$output.prefix" of="$output.trim" bs=1 count=$((prefix_size - 1)) 2>/dev/null
    mv "$output.trim" "$output.prefix"
  fi
  cat "$output.prefix" >"$output"
  cat "$output.suffix" >>"$output"
}
validate_workflow_matches_state() {
  workflow_file=$1
  state_file=$2
  [ "$(count_marker "$workflow_file" "$BEGIN_MARKER")" = 1 ] ||
    die "managed workflow block is missing"
  workflow_begin=$(grep -n -F -- "$BEGIN_MARKER" "$workflow_file" | cut -d: -f1)
  workflow_end=$(grep -n -F -- "$END_MARKER" "$workflow_file" | cut -d: -f1)
  workflow_actual=$(sed -n "$workflow_begin,$((workflow_end))p" "$workflow_file")
  workflow_expected=$(jxa workflow "$state_file")
  [ "$workflow_actual" = "$workflow_expected" ] ||
    die "managed workflow block does not match state"
}
install() {
  [ "$#" = 4 ] || die "install requires provider ID, provider name, endpoint, and model"
  provider_id=$1; provider=$2; endpoint=$3; model=$4
  jxa validate-provider-input "$provider_id" "$provider" "$endpoint" "$model" >/dev/null
  case "$endpoint" in http://*) [ "${CUSTOM_SUBAGENT_ALLOW_HTTP:-}" = 1 ] || die "localhost HTTP requires CUSTOM_SUBAGENT_ALLOW_HTTP=1" ;; esac
  plugin_name=$(jxa manifest-name "$PLUGIN_ROOT/.codex-plugin/plugin.json")
  [ "$plugin_name" = "$provider_id" ] || die "provider ID does not match plugin ownership manifest"
  validate_endpoint "$endpoint"
  state_dir="$SUBAGENT_HOME/custom-subagents"; state_file="$state_dir/state.json"; catalog_file="$state_dir/models-v1.json"
  base_catalog_file="$state_dir/base-model-catalog.json"; config_file="$SUBAGENT_HOME/config.toml"
  workflow_file="$SUBAGENT_HOME/AGENTS.md"
  general_file=$(provider_profile_path "$provider" general)
  developer_file=$(provider_profile_path "$provider" developer)
  reviewer_file=$(provider_profile_path "$provider" reviewer)
  initial_agents_shape=$(agents_shape "$workflow_file")
  validate_markers "$workflow_file"
  assert_safe_target "$state_file"; assert_safe_target "$catalog_file"; assert_safe_target "$base_catalog_file"
  assert_safe_target "$config_file"; assert_safe_target "$workflow_file"
  assert_safe_target "$general_file"; assert_safe_target "$developer_file"; assert_safe_target "$reviewer_file"
  assert_safe_target "$state_dir/backups/.custom-subagents-preflight"
  validate_agent_file "$general_file" "$provider_id" general "$plugin_name" "$state_file" "$catalog_file"
  validate_agent_file "$developer_file" "$provider_id" developer "$plugin_name" "$state_file" "$catalog_file"
  validate_agent_file "$reviewer_file" "$provider_id" reviewer "$plugin_name" "$state_file" "$catalog_file"
  primary_model=$(jxa config-primary "$config_file" "$TEST_PRIMARY_MODEL")
  managed_artifact=0
  [ -e "$general_file" ] && managed_artifact=1
  [ -e "$developer_file" ] && managed_artifact=1
  [ -e "$reviewer_file" ] && managed_artifact=1
  [ -f "$catalog_file" ] && managed_artifact=1
  [ -f "$base_catalog_file" ] && managed_artifact=1
  [ "$(count_marker "$workflow_file" "$BEGIN_MARKER")" = 1 ] && managed_artifact=1
  config_catalog_line "$config_file" | grep -F -- "$catalog_file" >/dev/null 2>&1 && managed_artifact=1
  fresh_install=1
  if [ "$managed_artifact" = 1 ] || [ -f "$state_file" ]; then
    fresh_install=0
    [ -f "$state_file" ] || die "managed artifacts exist without lifecycle state; restore from a backup"
    target_registered=$(jxa provider-present "$state_file" "$provider_id")
    target_file_count=0
    [ -e "$general_file" ] && target_file_count=$((target_file_count + 1))
    [ -e "$developer_file" ] && target_file_count=$((target_file_count + 1))
    [ -e "$reviewer_file" ] && target_file_count=$((target_file_count + 1))
    if [ "$target_file_count" -gt 0 ] || [ "$target_registered" = 1 ]; then
      jxa validate-lifecycle-state "$state_file" "$catalog_file" "$base_catalog_file" "$provider_id" >/dev/null
      [ "$target_registered" = 1 ] && [ "$target_file_count" = 3 ] ||
        die "target provider profiles and lifecycle state disagree; restore from backup or reconfigure custom subagents"
    else
      jxa validate-lifecycle-state "$state_file" "$catalog_file" "$base_catalog_file" >/dev/null
    fi
    jxa validate-config-state "$state_file" "$config_file" >/dev/null
    primary_model=$(jxa primary-model "$state_file")
    base_catalog_source=$(jxa base-catalog-source "$state_file")
    base_catalog_source_kind=$(jxa base-catalog-source-kind "$state_file")
    jxa validate-base-catalog "$base_catalog_file" "$primary_model" >/dev/null
    jxa validate-catalog-matches-state "$state_file" "$base_catalog_file" "$catalog_file" >/dev/null
    validate_workflow_matches_state "$workflow_file" "$state_file"
    original_json=null
    initial_config_shape=$(jxa initial-config-shape "$state_file")
  else
    initial_config_shape=$(jxa config-shape "$config_file" "$TEST_PRIMARY_MODEL")
    original_json=$(jxa config-original-catalog-line-json "$config_file" "$TEST_PRIMARY_MODEL")
    base_catalog_source=$(jxa config-catalog-source "$config_file" "$SUBAGENT_HOME/models_cache.json" "$TEST_CATALOG_SOURCE" "$TEST_PRIMARY_MODEL")
    base_catalog_source_kind=$(jxa config-catalog-source-kind "$config_file" "$TEST_CATALOG_SOURCE" "$TEST_PRIMARY_MODEL")
    jxa validate-base-catalog "$base_catalog_source" "$primary_model" >/dev/null
  fi
  keychain_service="codex-custom-subagent/$provider_id"
  rendered_general=$(jxa render-agent-spec-args "$CANONICAL_AGENT_SPEC" "$provider_id" general "$provider" "$endpoint" "$model" "$catalog_file" "$keychain_service")
  rendered_developer=$(jxa render-agent-spec-args "$CANONICAL_AGENT_SPEC" "$provider_id" developer "$provider" "$endpoint" "$model" "$catalog_file" "$keychain_service")
  rendered_reviewer=$(jxa render-agent-spec-args "$CANONICAL_AGENT_SPEC" "$provider_id" reviewer "$provider" "$endpoint" "$model" "$catalog_file" "$keychain_service")
  safe_mkdir "$state_dir/backups"; safe_mkdir "$SUBAGENT_HOME/agents"; BACKUP_DIR="$state_dir/backups/$(date +%Y%m%d%H%M%S)-$$"; safe_mkdir "$BACKUP_DIR"
  trap 'status=$?; rollback "$status"' EXIT
  trap 'rollback 129' HUP
  trap 'rollback 130' INT
  trap 'rollback 143' TERM
  temp_dir=$(mktemp -d "$state_dir/.operation.XXXXXX"); trap cleanup_and_rollback EXIT
  trap 'cleanup_and_rollback 129' HUP
  trap 'cleanup_and_rollback 130' INT
  trap 'cleanup_and_rollback 143' TERM
  provider_json=$(printf '{"id":"%s","provider":"%s","endpoint":"%s","model":"%s"}' "$provider_id" "$provider" "$endpoint" "$model")
  { printf '%s\n' "# BEGIN custom-subagents managed agent provider=$provider_id role=general plugin=$plugin_name"; printf '%s\n' "$rendered_general"; printf '%s\n' "# END custom-subagents managed agent provider=$provider_id role=general plugin=$plugin_name"; } >"$temp_dir/general.toml"
  { printf '%s\n' "# BEGIN custom-subagents managed agent provider=$provider_id role=developer plugin=$plugin_name"; printf '%s\n' "$rendered_developer"; printf '%s\n' "# END custom-subagents managed agent provider=$provider_id role=developer plugin=$plugin_name"; } >"$temp_dir/developer.toml"
  { printf '%s\n' "# BEGIN custom-subagents managed agent provider=$provider_id role=reviewer plugin=$plugin_name"; printf '%s\n' "$rendered_reviewer"; printf '%s\n' "# END custom-subagents managed agent provider=$provider_id role=reviewer plugin=$plugin_name"; } >"$temp_dir/reviewer.toml"
  if [ "$fresh_install" = 1 ]; then atomic_write "$base_catalog_file" "$base_catalog_source"; fi
  atomic_write "$general_file" "$temp_dir/general.toml"
  atomic_write "$developer_file" "$temp_dir/developer.toml"
  atomic_write "$reviewer_file" "$temp_dir/reviewer.toml"
  jxa install-state "$state_file" "$provider_json" "$catalog_file" "$base_catalog_file" "$base_catalog_source" \
    "$base_catalog_source_kind" "$primary_model" "$original_json" "$initial_agents_shape" "$initial_config_shape" \
    >"$temp_dir/state.json"; atomic_write "$state_file" "$temp_dir/state.json"
  jxa catalog "$base_catalog_file" "$primary_model" >"$temp_dir/catalog.json"; atomic_write "$catalog_file" "$temp_dir/catalog.json"
  jxa render-config-to-file "$config_file" "$catalog_file" "$temp_dir/config.toml" "$TEST_PRIMARY_MODEL"
  atomic_write "$config_file" "$temp_dir/config.toml"
  jxa workflow "$state_file" >"$temp_dir/workflow.md"; render_workflow_file "$workflow_file" "$temp_dir/workflow.md" "$temp_dir/AGENTS.md"; atomic_write "$workflow_file" "$temp_dir/AGENTS.md"
  rm -rf "$temp_dir"; COMMITTED=1; trap - EXIT HUP INT TERM; release_lock
}
uninstall() {
  [ "$#" = 1 ] || die "uninstall requires a provider ID"
  provider_id=$1; jxa validate-provider-id "$provider_id" >/dev/null
  state_dir="$SUBAGENT_HOME/custom-subagents"; state_file="$state_dir/state.json"
  catalog_file="$state_dir/models-v1.json"; base_catalog_file="$state_dir/base-model-catalog.json"
  workflow_file="$SUBAGENT_HOME/AGENTS.md"
  plugin_name=$(jxa manifest-name "$PLUGIN_ROOT/.codex-plugin/plugin.json")
  [ "$plugin_name" = "$provider_id" ] || die "provider ID does not match plugin ownership manifest"
  assert_safe_target "$state_file"; assert_safe_target "$catalog_file"; assert_safe_target "$base_catalog_file"
  assert_safe_target "$workflow_file"
  assert_safe_target "$SUBAGENT_HOME/config.toml"; assert_safe_target "$state_dir/backups/.custom-subagents-preflight"
  if [ ! -f "$state_file" ]; then
    if ! has_managed_residue "$catalog_file" "$base_catalog_file" "$workflow_file" "$SUBAGENT_HOME/config.toml" &&
       ! provider_residue_for_id "$provider_id"; then
      return 0
    fi
    die "managed artifacts exist without lifecycle state; restore from backup or reconfigure custom subagents"
  fi
  validate_with_recovery validate_backup_history "$state_dir/backups"
  validate_with_recovery validate_markers "$workflow_file"
  validate_with_recovery jxa validate-lifecycle-state "$state_file" "$catalog_file" "$base_catalog_file"
  validate_with_recovery jxa validate-config-state "$state_file" "$SUBAGENT_HOME/config.toml"
  primary_model=$(jxa primary-model "$state_file")
  validate_with_recovery jxa validate-base-catalog "$base_catalog_file" "$primary_model"
  validate_with_recovery jxa validate-catalog-matches-state "$state_file" "$base_catalog_file" "$catalog_file"
  validate_with_recovery validate_workflow_matches_state "$workflow_file" "$state_file"
  target_registered=$(jxa provider-present "$state_file" "$provider_id")
  if [ "$target_registered" = 0 ]; then
    provider_residue_for_id "$provider_id" &&
      die "target provider profiles and lifecycle state disagree; restore from backup or reconfigure custom subagents"
    return 0
  fi
  provider=$(jxa provider-name "$state_file" "$provider_id")
  general_file=$(provider_profile_path "$provider" general)
  developer_file=$(provider_profile_path "$provider" developer)
  reviewer_file=$(provider_profile_path "$provider" reviewer)
  assert_safe_target "$general_file"; assert_safe_target "$developer_file"; assert_safe_target "$reviewer_file"
  [ -f "$general_file" ] && [ ! -L "$general_file" ] &&
  [ -f "$developer_file" ] && [ ! -L "$developer_file" ] &&
  [ -f "$reviewer_file" ] && [ ! -L "$reviewer_file" ] ||
    die "target provider profiles and lifecycle state disagree; restore from backup or reconfigure custom subagents"
  validate_with_recovery validate_agent_file "$general_file" "$provider_id" general "$plugin_name" "$state_file" "$catalog_file"
  validate_with_recovery validate_agent_file "$developer_file" "$provider_id" developer "$plugin_name" "$state_file" "$catalog_file"
  validate_with_recovery validate_agent_file "$reviewer_file" "$provider_id" reviewer "$plugin_name" "$state_file" "$catalog_file"
  original_agents_shape=$(jxa initial-agents-shape "$state_file")
  original_config_shape=$(jxa initial-config-shape "$state_file")
  safe_mkdir "$state_dir/backups"; BACKUP_DIR="$state_dir/backups/$(date +%Y%m%d%H%M%S)-$$"; safe_mkdir "$BACKUP_DIR"
  trap 'status=$?; rollback "$status"' EXIT
  trap 'rollback 129' HUP
  trap 'rollback 130' INT
  trap 'rollback 143' TERM
  temp_dir=$(mktemp -d "$state_dir/.operation.XXXXXX"); trap cleanup_and_rollback EXIT
  trap 'cleanup_and_rollback 129' HUP
  trap 'cleanup_and_rollback 130' INT
  trap 'cleanup_and_rollback 143' TERM
  jxa uninstall-state "$state_file" "$provider_id" >"$temp_dir/state.json"
  remaining_providers=$(jxa provider-count "$temp_dir/state.json")
  if [ "$remaining_providers" = 0 ]; then
    jxa restore-config-to-file "$SUBAGENT_HOME/config.toml" "$state_file" "$temp_dir/config.toml"
    remove_workflow_file "$workflow_file" "$temp_dir/AGENTS.md" "$original_agents_shape"
    remove_target "$general_file"
    remove_target "$developer_file"
    remove_target "$reviewer_file"
    if [ "$original_config_shape" = absent ]; then
      remove_target "$SUBAGENT_HOME/config.toml"
    else
      atomic_write "$SUBAGENT_HOME/config.toml" "$temp_dir/config.toml"
    fi
    if [ "$original_agents_shape" = absent ] && [ ! -s "$temp_dir/AGENTS.md" ]; then
      remove_target "$workflow_file"
    else
      atomic_write "$workflow_file" "$temp_dir/AGENTS.md"
    fi
    remove_target "$state_file"
    remove_target "$catalog_file"
    remove_target "$base_catalog_file"
  else
    jxa catalog "$base_catalog_file" "$primary_model" >"$temp_dir/catalog.json"
    jxa workflow "$temp_dir/state.json" >"$temp_dir/workflow.md"
    render_workflow_file "$workflow_file" "$temp_dir/workflow.md" "$temp_dir/AGENTS.md"
    remove_target "$general_file"
    remove_target "$developer_file"
    remove_target "$reviewer_file"
    atomic_write "$state_file" "$temp_dir/state.json"
    atomic_write "$catalog_file" "$temp_dir/catalog.json"
    atomic_write "$workflow_file" "$temp_dir/AGENTS.md"
  fi
  rm -rf "$temp_dir"; COMMITTED=1; trap - EXIT HUP INT TERM; release_lock
}
validate_registration() {
  [ "$#" = 1 ] || die "validate-registration requires a provider ID"
  provider_id=$1; jxa validate-provider-id "$provider_id" >/dev/null
  state_dir="$SUBAGENT_HOME/custom-subagents"; state_file="$state_dir/state.json"
  catalog_file="$state_dir/models-v1.json"; base_catalog_file="$state_dir/base-model-catalog.json"
  workflow_file="$SUBAGENT_HOME/AGENTS.md"; config_file="$SUBAGENT_HOME/config.toml"
  plugin_name=$(jxa manifest-name "$PLUGIN_ROOT/.codex-plugin/plugin.json")
  [ "$plugin_name" = "$provider_id" ] || die "provider ID does not match plugin ownership manifest"
  assert_safe_target "$state_file"; assert_safe_target "$catalog_file"; assert_safe_target "$base_catalog_file"
  assert_safe_target "$workflow_file"; assert_safe_target "$config_file"
  [ -f "$state_file" ] && [ ! -L "$state_file" ] || die "managed lifecycle state is missing or unsafe"
  validate_backup_history "$state_dir/backups"
  validate_markers "$workflow_file"
  jxa validate-lifecycle-state "$state_file" "$catalog_file" "$base_catalog_file" "$provider_id" >/dev/null
  jxa validate-config-state "$state_file" "$config_file" >/dev/null
  primary_model=$(jxa primary-model "$state_file")
  jxa validate-base-catalog "$base_catalog_file" "$primary_model" >/dev/null
  jxa validate-catalog-matches-state "$state_file" "$base_catalog_file" "$catalog_file" >/dev/null
  validate_workflow_matches_state "$workflow_file" "$state_file"
  provider=$(jxa provider-name "$state_file" "$provider_id")
  general_file=$(provider_profile_path "$provider" general)
  developer_file=$(provider_profile_path "$provider" developer)
  reviewer_file=$(provider_profile_path "$provider" reviewer)
  assert_safe_target "$general_file"; assert_safe_target "$developer_file"; assert_safe_target "$reviewer_file"
  [ -f "$general_file" ] && [ ! -L "$general_file" ] || die "managed general profile is missing or unsafe"
  [ -f "$developer_file" ] && [ ! -L "$developer_file" ] || die "managed developer profile is missing or unsafe"
  [ -f "$reviewer_file" ] && [ ! -L "$reviewer_file" ] || die "managed reviewer profile is missing or unsafe"
  validate_agent_file "$general_file" "$provider_id" general "$plugin_name" "$state_file" "$catalog_file"
  validate_agent_file "$developer_file" "$provider_id" developer "$plugin_name" "$state_file" "$catalog_file"
  validate_agent_file "$reviewer_file" "$provider_id" reviewer "$plugin_name" "$state_file" "$catalog_file"
}
status() { [ "$#" = 0 ] || die "status accepts no arguments"; jxa read "$SUBAGENT_HOME/custom-subagents/state.json"; }
require_home
command=${1:-}; shift || true
case "$command" in
  install) acquire_lock; install "$@" ;;
  uninstall) acquire_lock; uninstall "$@" ;;
  validate-registration) acquire_lock; validate_registration "$@" ;;
  status) status "$@" ;;
  *) die "expected install, uninstall, validate-registration, or status" ;;
esac
