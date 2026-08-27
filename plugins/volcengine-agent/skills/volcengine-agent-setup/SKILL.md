---
name: volcengine-agent-setup
description: Use when configuring or checking status for the Volcengine provider and its general, developer, and reviewer native Codex profiles.
---

# Configure Volcengine Provider

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

Collect the endpoint as a non-secret value; the model or deployment ID is
optional. When
`--endpoint` is omitted, use the official default
`https://ark.cn-beijing.volces.com/api/plan/v3`. If the user explicitly
requests a relay or another endpoint, pass that non-secret value with
`--endpoint`.
Do not accept, quote, retain, or reuse an API key pasted in chat. State that the
exposed value cannot be used and that a fresh key must be entered only through
the native hidden dialog. When the dialog cannot appear (a VM, SSH, or a
sandboxed agent shell without GUI access), the script falls back to a hidden
terminal prompt instead; if it reports that neither is available, give the
user the exact configure command to run themselves in an interactive
Terminal window.

After the key is entered, `scripts/configure.sh` requests `GET /models` from
the selected endpoint. On macOS it presents a native model chooser; in a VM,
SSH session, or other headless environment it uses terminal selection. If the
endpoint does not support model listing or returns an unusable response, it
falls back to manual model or deployment ID input. `--model MODEL` remains
available for that fallback and for automation. Before changing managed global
Codex files, show the endpoint and selected model.
Explain that one provider registration creates the `volcengine_general`,
`volcengine_developer`, and `volcengine_reviewer` profiles, which share the
same endpoint, model or deployment, and Keychain credential. The managed
lifecycle also updates the V1 catalog, workflow block, and provider state under
the Codex home. Obtain explicit approval, resolve this skill's plugin root, and
run `scripts/configure.sh` with an optional `--model ID` and add
`--endpoint URL` only when an explicit override is requested.

The user and Codex must not provide a key through a command, environment
variable, piped or redirected standard input, config, log, JSON, TOML, fixture,
or backup. A fresh
key enters only through the native hidden dialog or its hidden terminal fallback. The adapter's private pipe into
`/usr/bin/security` is the sole internal implementation detail; never
expose, imitate, or reuse it.

An existing Keychain item may be reused only when strict managed state binds
this provider to the same endpoint; changing only the model or deployment is allowed.
If the endpoint differs or the binding is absent or unknown, stop before global
changes. Tell the user to run this plugin's uninstall cleanup first, then
configure again and enter a fresh key through the hidden dialog.

The fixed Keychain service is `codex-custom-subagent/volcengine-agent` with
account `api-key`. Old state ID or exact managed markers owned by
`volcengine-reviewer` require identifier-only migration failure before hidden
dialog or managed mutation. The old package must perform its own cleanup;
credentials and managed-file ownership are not migrated in place. Do not
perform a live API request unless the user separately authorizes it.

## Scheduling And Verification

The automatic scheduling may select the general, developer, or reviewer role by
task fit. A direct user request for an explicit provider or role overrides
automatic scheduling. The reviewer remains read-only; the other profiles do
not receive reviewer-only sandbox or approval restrictions.

After success, require a full Codex restart and a fresh task. Verify JSONL
evidence that the selected `agent_role` or `agent_type` is
`volcengine_general`, `volcengine_developer`, or `volcengine_reviewer`, with
`model_provider` equal to `volcengine`, the selected model exact, and
`multi_agent_version` equal to `v1`; the delegated payload must be complete for
that role. Report only non-secret evidence.
