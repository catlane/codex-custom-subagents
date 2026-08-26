---
name: deepseek-developer-setup
description: Use when configuring or checking status for the DeepSeek Developer fixed-role native Codex subagent.
---

# Configure DeepSeek Developer

## Status Requests

When the user asks only for status, resolve the plugin root and Codex home, then
run only the vendored lifecycle status command:

```sh
CUSTOM_SUBAGENT_HOME="$CODEX_HOME" \
CUSTOM_SUBAGENT_PLUGIN_ROOT="$PLUGIN_ROOT" \
CUSTOM_SUBAGENT_AGENT_SPEC="$PLUGIN_ROOT/templates/agent-spec.json" \
CUSTOM_SUBAGENT_PRODUCTION_MODE=1 \
CUSTOM_SUBAGENT_PRODUCTION_APPROVAL=custom-subagents-live-home \
/bin/sh "$PLUGIN_ROOT/scripts/vendor/lifecycle.sh" status
```

Report only this agent's ID, role, provider, endpoint, model, and whether a full
Codex restart plus fresh task is still required after configuration changes.
Do not call Keychain, configure, or uninstall. Do not print raw state, catalog
paths, original settings, backup locations, AGENTS shapes, or other restoration
metadata. If this agent is not registered, say so without starting setup.

## Configuration

Collect only the non-secret endpoint and model in conversation. Use
`https://api.deepseek.com` when the user accepts the default endpoint. Do not
accept, quote, retain, or reuse an API key pasted in chat. State that the
exposed value cannot be used and that a fresh key must be entered only through
the native hidden dialog.

Before changing managed global Codex files, show the intended endpoint and
model, identify that the lifecycle will manage the native agent, catalog,
workflow block, and state registry under the Codex home, and obtain explicit
approval. Resolve this skill's plugin root, then run its `scripts/configure.sh`
with `--model` and, when needed, `--endpoint`. Never put a key in a command,
environment variable, user/Codex-provided standard input, configuration file,
log, JSON, TOML, or backup. A fresh key enters only through the native hidden
dialog. The adapter's private pipe into `/usr/bin/security` is the sole internal
implementation detail; never expose, imitate, or reuse it.

An existing Keychain item may be reused only when strict managed state binds
this agent to the same endpoint; changing only the model is allowed. If the
endpoint differs or the binding is absent or unknown, stop before global
changes. Tell the user to run this plugin's uninstall cleanup first, then
configure again and enter a fresh key through the hidden dialog.

The script validates the endpoint and model before opening the hidden dialog.
It stores the fresh dialog value using the fixed Keychain service
`codex-custom-subagent/deepseek-developer` and account `api-key`; do not offer
an alternate storage path. Report only success or identifier-only failures.

After success, instruct the user to restart Codex and create a fresh task. Do
not treat a display label as success. In that fresh task, inspect JSONL
evidence for a child with `agent_role` or `agent_type` equal to
`deepseek_developer`, `model_provider` equal to `deepseek`, the exact selected
model, `multi_agent_version` equal to `v1`, and a complete delegated task
payload with ownership. Do not expose authentication data while reporting the
evidence.
