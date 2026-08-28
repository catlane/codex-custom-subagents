---
name: deepseek-agent-setup
description: Use when configuring or checking status for the DeepSeek provider and its general, developer, and reviewer native Codex profiles.
---

# Configure DeepSeek Provider

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

Report only this provider's ID, provider name, endpoint, model, three profile
names, and whether a full Codex restart plus fresh task is still required.
Do not call Keychain, configure, or uninstall. Do not print raw state, catalog
paths, original settings, backup locations, AGENTS shapes, or other restoration
metadata. If this provider is not registered, say so without starting setup.

## Configuration

Collect the non-secret endpoint in conversation; the model is optional. When
`--endpoint` is omitted, use the official default `https://api.deepseek.com`.
If the user explicitly requests a relay or another endpoint, pass that
non-secret value with `--endpoint`. Do not accept, quote, retain, or reuse an
API key pasted in chat. State that the exposed value cannot be used and that a
fresh key must be entered only through the native hidden dialog. Elevated
(unsandboxed) execution with an interactive terminal attached is mandatory for
`scripts/configure.sh`: request the user's approval for that elevation and run
the script only with it, because a sandboxed agent shell cannot present the
native hidden dialog or the native model chooser, and without an interactive
terminal even the hidden fallback prompts cannot be answered. If the user
declines elevation, stop: do not configure, do not attempt any fallback, and
never substitute hand-written agent files, environment variables, or launcher
scripts for this managed flow. The only remaining path is to give the user the
exact configure command to run themselves in an interactive Terminal window.

After the key is entered, `scripts/configure.sh` requests `GET /models` from
the selected endpoint. On macOS it presents a native model chooser when the
script runs with GUI access, which is why agent-driven configuration requires
elevated execution; in a VM, SSH session, or other headless environment it
uses terminal selection. If the
endpoint does not support model listing or returns an unusable response, it
falls back to manual model input. `--model MODEL` remains available for that
fallback and for automation. Before changing managed global Codex files, show
the intended endpoint and selected model. Explain that one provider
registration creates the `deepseek_general`,
`deepseek_developer`, and `deepseek_reviewer` profiles, which share the same
endpoint, model, and Keychain credential. The managed lifecycle also updates
the V1 catalog, workflow block, and provider state under the Codex home. Obtain
explicit approval, resolve this skill's plugin root, and run its
`scripts/configure.sh` with an optional `--model` and, when needed,
`--endpoint`.

Never put a key in a command, environment variable, piped or redirected standard
input, configuration file, log, JSON, TOML, fixture, or backup. A fresh key enters
only through the native hidden dialog or its hidden terminal fallback. The adapter's private pipe into
`/usr/bin/security` is the sole internal implementation detail;
never expose, imitate, or reuse it.

An existing Keychain item may be reused only when strict managed state binds
this provider to the same endpoint; changing only the model is allowed. If the
endpoint differs or the binding is absent or unknown, stop before global
changes. Tell the user to run this plugin's uninstall cleanup first, then
configure again and enter a fresh key through the hidden dialog.

The fixed Keychain service is `codex-custom-subagent/deepseek-agent` with
account `api-key`. Old state ID or exact managed markers owned by
`deepseek-developer` require identifier-only migration failure before hidden
dialog or managed mutation. The old package must perform its own cleanup;
credentials and managed-file ownership are not migrated in place.

## Scheduling And Verification

The automatic scheduling may select the general, developer, or reviewer role by
task fit. A direct user request for an explicit provider or role overrides
automatic scheduling. The reviewer remains read-only; the other profiles do
not receive reviewer-only sandbox or approval restrictions.

After success, instruct the user to restart Codex and create a fresh task. Do
not treat a display label as success. In fresh-task JSONL evidence, verify the
selected `agent_role` or `agent_type` is `deepseek_general`,
`deepseek_developer`, or `deepseek_reviewer`, `model_provider` is
`deepseek`, the model is exact, `multi_agent_version` is `v1`, and the
delegated payload is complete for that role. Do not expose authentication data
while reporting.
