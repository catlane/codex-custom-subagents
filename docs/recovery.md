# Recovery And Uninstall

This guide applies to the macOS Codex Desktop plugins in this marketplace. It
never requires reading, printing, copying, or exporting an API key.

## Normal Uninstall

Always request conversational cleanup while the plugin is still installed:

1. Ask Codex to run the plugin's uninstall skill.
2. Approve removal of that plugin's managed agent files and its exact Keychain
   item.
3. Wait for lifecycle and Keychain cleanup to succeed.
4. Only then remove the package:

```bash
codex plugin remove deepseek-agent@custom-subagents
codex plugin remove volcengine-agent@custom-subagents
```

Run only the command for the plugin being removed. Removing one plugin must
leave the other plugin, native agent, shared V1 catalog, workflow route, and
Keychain item intact. Removing the last configured custom agent restores the
exact prior `config.toml` and `AGENTS.md` existence and byte shape.

## Safe Status Inspection

The shared registry is at:

```text
~/.codex/custom-subagents/state.json
```

Ask Codex to run the installed plugin lifecycle's `status` command and report
only provider ID, provider, endpoint, and model. A valid registry contains
only those non-secret settings plus catalog and restoration metadata. Do not
use `cat`, shell tracing, `security ... -w`, Keychain export, or any command
that retrieves a password while diagnosing a lifecycle problem.

The expected managed paths are:

```text
~/.codex/agents/deepseek_general.toml
~/.codex/agents/deepseek_developer.toml
~/.codex/agents/deepseek_reviewer.toml
~/.codex/agents/volcengine_general.toml
~/.codex/agents/volcengine_developer.toml
~/.codex/agents/volcengine_reviewer.toml
~/.codex/custom-subagents/base-model-catalog.json
~/.codex/custom-subagents/models-v1.json
~/.codex/custom-subagents/state.json
~/.codex/AGENTS.md
~/.codex/config.toml
```

Agent TOML files contain only a Keychain lookup command and item identifiers,
never the credential value.

## Upgrade From Fixed-Role Package Names

The earlier packages `deepseek-developer` and `volcengine-reviewer` used
different managed-file and Keychain ownership IDs. They are not migrated in
place. While each old package is still installed, run its conversational
uninstall workflow and verify cleanup before installing and configuring
`deepseek-agent` or `volcengine-agent`. Never keep an old fixed-role
registration and its renamed provider registration active together.

## Backups

Every lifecycle operation creates a timestamped directory under:

```text
~/.codex/custom-subagents/backups/<operation-id>/
```

Backups preserve only files touched by that operation. A sibling `.absent`
marker records that the target did not exist before the operation. API keys
are not present in lifecycle state, TOML, JSON, logs, or backups.

When an operation reports malformed state, duplicate managed markers, a
registry/file mismatch, or another fail-closed condition, stop. Do not delete
the state, catalog, agent TOML, workflow block, or configuration line merely to
make the check pass.

## Package Removed Too Early

Raw `codex plugin remove` removes the cleanup skill and its scripts before they
can unregister the native agent. The managed Codex home and plugin-specific
Keychain item therefore remain in place, and the removed package's cleanup
path is no longer callable. Do not delete that residue or alter lifecycle state
by hand. Recover in this order:

1. Reinstall the same package from the same marketplace.
2. Ask Codex to run that plugin's uninstall skill.
3. Verify that lifecycle and the exact plugin-specific Keychain item were
   cleaned up successfully.
4. Remove that package again.

Keep the other plugin installed throughout. Do not substitute another
plugin's lifecycle script or delete the other plugin's Keychain item.

## Fail-Closed Recovery

Before manual recovery, fully quit Codex and make a filesystem copy of
`~/.codex/custom-subagents`, `~/.codex/config.toml`, `~/.codex/AGENTS.md`, and
the managed agent TOML files that exist. Copy files without displaying
their contents.

For malformed state, duplicate markers, or a registry/file mismatch, restore
one internally consistent operation backup as a set. Preserve the current
files separately first. Do not combine state from one operation with catalog,
config, workflow, or agent files from another operation. Restart Codex and ask
for status inspection before retrying uninstall.

If lifecycle backups are missing, use a known external backup of the complete
Codex configuration or reconfigure the installed custom agents from their
known non-secret endpoint/model settings, then retry conversational uninstall.
If neither exists, automatic restoration cannot safely infer the original
`model_catalog_json` value or prior `AGENTS.md` bytes. Keep the artifacts
quarantined and obtain operator confirmation of those original values before
changing them.

Keychain recovery is separate from file recovery. The uninstall scripts target
only these identifiers with account `api-key`:

```text
codex-custom-subagent/deepseek-agent
codex-custom-subagent/volcengine-agent
```

Never inspect or report their stored password. If Keychain deletion fails,
leave the package installed, resolve Keychain access, and retry its uninstall
skill.
