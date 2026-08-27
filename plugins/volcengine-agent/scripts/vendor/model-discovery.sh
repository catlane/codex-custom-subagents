#!/bin/sh

set +x

MODEL_DISCOVERY_CURL_BIN=${CUSTOM_SUBAGENT_CURL_BIN:-/usr/bin/curl}

model_discovery_fetch() {
  [ "$#" = 2 ] || return 64
  model_discovery_endpoint=${1%/}/models
  model_discovery_agent_id=$2

  # Read the Keychain value through stdin so it is never part of curl argv or
  # the environment. The response contains only non-secret model metadata.
  keychain_read "$model_discovery_agent_id" |
    /usr/bin/awk 'NF { print "Authorization: Bearer " $0; found=1 } END { exit(found ? 0 : 1) }' |
    "$MODEL_DISCOVERY_CURL_BIN" -fsS --max-time 30 -H @- "$model_discovery_endpoint"
}

model_discovery_parse() {
  [ "$#" = 2 ] || return 64
  model_discovery_response=$1
  model_discovery_parser=$2
  [ -f "$model_discovery_parser" ] && [ ! -L "$model_discovery_parser" ] || return 1
  printf '%s' "$model_discovery_response" |
    /usr/bin/osascript -l JavaScript "$model_discovery_parser" list-json
}

model_discovery_lines() {
  [ "$#" = 2 ] || return 64
  model_discovery_json=$1
  model_discovery_parser=$2
  printf '%s' "$model_discovery_json" |
    /usr/bin/osascript -l JavaScript "$model_discovery_parser" list-lines
}

model_discovery_choose() {
  [ "$#" = 2 ] || return 64
  model_discovery_json=$1
  model_discovery_choice_script=$2
  [ -f "$model_discovery_choice_script" ] && [ ! -L "$model_discovery_choice_script" ] || return 1
  /usr/bin/osascript -l JavaScript "$model_discovery_choice_script" "$model_discovery_json"
}

model_discovery_prompt_tty() {
  [ -t 0 ] && [ -t 2 ] || return 78
  model_discovery_lines_text=$1
  model_discovery_number=1
  printf '%s\n' 'Available models:' >&2
  while IFS= read -r model_discovery_line; do
    [ -n "$model_discovery_line" ] || continue
    printf '%s) %s\n' "$model_discovery_number" "$model_discovery_line" >&2
    model_discovery_number=$((model_discovery_number + 1))
  done <<EOF
$model_discovery_lines_text
EOF
  printf '%s' 'Select a model number: ' >&2
  IFS= read -r model_discovery_selection </dev/tty || return 2
  case "$model_discovery_selection" in
    ''|*[!0-9]*) return 1 ;;
  esac
  model_discovery_selected=$(printf '%s\n' "$model_discovery_lines_text" |
    /usr/bin/awk -v selected="$model_discovery_selection" 'NR == selected { print; found=1 } END { exit(found ? 0 : 1) }') || return 1
  [ -n "$model_discovery_selected" ] || return 1
  printf '%s\n' "$model_discovery_selected"
}

model_discovery_prompt_manual() {
  [ -t 0 ] && [ -t 2 ] || return 78
  printf '%s' 'Model ID (manual fallback): ' >&2
  IFS= read -r model_discovery_manual </dev/tty || return 2
  [ -n "$model_discovery_manual" ] || return 1
  printf '%s\n' "$model_discovery_manual"
}

model_discovery_select() {
  [ "$#" = 3 ] || return 64
  model_discovery_selection_json=$1
  model_discovery_parser=$2
  model_discovery_choice_script=$3
  model_discovery_lines_text=$(model_discovery_lines "$model_discovery_selection_json" "$model_discovery_parser") || return 78
  if [ "${CUSTOM_SUBAGENT_TEST_MODE:-}" = 1 ] && [ -n "${CUSTOM_SUBAGENT_TEST_SELECTED_MODEL:-}" ]; then
    printf '%s\n' "$CUSTOM_SUBAGENT_TEST_SELECTED_MODEL"
    return 0
  fi
  if model_discovery_selected=$(model_discovery_choose "$model_discovery_selection_json" "$model_discovery_choice_script" 2>/dev/null); then
    case "$model_discovery_selected" in
      cancelled) return 2 ;;
      '') return 78 ;;
      *) printf '%s\n' "$model_discovery_selected"; return 0 ;;
    esac
  fi
  model_discovery_prompt_tty "$model_discovery_lines_text"
}

model_discovery_resolve() {
  [ "$#" = 4 ] || return 64
  model_discovery_endpoint=$1
  model_discovery_agent_id=$2
  model_discovery_parser=$3
  model_discovery_choice_script=$4
  model_discovery_response=$(model_discovery_fetch "$model_discovery_endpoint" "$model_discovery_agent_id" 2>/dev/null) || return 78
  model_discovery_models=$(model_discovery_parse "$model_discovery_response" "$model_discovery_parser" 2>/dev/null) || return 78
  model_discovery_select "$model_discovery_models" "$model_discovery_parser" "$model_discovery_choice_script"
}
