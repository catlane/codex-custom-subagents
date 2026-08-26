---
name: volcengine-reviewer-setup
description: Use when configuring or checking status for the Volcengine Reviewer fixed-role native Codex subagent.
---

# Configure Volcengine Reviewer

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

Collect the user's exact OpenAI-compatible endpoint and model or deployment ID
as non-secret values. Both are required; do not guess or offer defaults.
Do not accept, quote, retain, or reuse an API key pasted in chat. State that the
exposed value cannot be used and that a fresh key must be entered only through
the native hidden dialog.

Before changing managed global Codex files, show the endpoint and model, explain
that setup manages the native agent, V1 catalog, workflow block, and state
registry under the Codex home, and obtain explicit approval. Resolve this
skill's plugin root, then run `scripts/configure.sh --endpoint URL --model ID`.
The user and Codex must not provide a key through a command, environment
variable, standard input, config, log, JSON, TOML, fixture, or backup. A fresh
key enters only through the native hidden dialog. The adapter's private pipe
into `/usr/bin/security` is the sole internal implementation detail; never
expose, imitate, or reuse it.

An existing Keychain item may be reused only when strict managed state binds
this agent to the same endpoint; changing only the model or deployment is
allowed. If the endpoint differs or the binding is absent or unknown, stop
before global changes. Tell the user to run this plugin's uninstall cleanup first,
then configure again and enter a fresh key through the hidden dialog.

The script validates both values before the hidden dialog and stores the fresh
value only under Keychain service `codex-custom-subagent/volcengine-reviewer`
and account `api-key`. Do not perform a live API request unless the user
separately authorizes it.

After success, require a full Codex restart and a fresh task. Verify JSONL
evidence for `agent_role` or `agent_type` equal to `volcengine_reviewer`,
`model_provider` equal to `volcengine`, the exact selected model,
`multi_agent_version` equal to `v1`, and a complete delegated review payload
containing original requirements, acceptance criteria, actual diff, and
verification evidence. Report only non-secret evidence.
