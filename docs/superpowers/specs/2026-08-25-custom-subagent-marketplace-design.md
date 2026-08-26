# Custom Subagent Marketplace Design

## Goal

Build a GitHub-distributed Codex plugin marketplace for macOS Codex Desktop. GPT remains the main agent while installed custom agents handle fixed roles. The first release provides a DeepSeek developer and a Volcengine reviewer.

## Confirmed Behavior

- One fixed-role custom agent is one independently installable plugin.
- A task uses one multi-agent protocol only. Custom-agent tasks use V1 throughout.
- Normal non-trivial development prefers `deepseek-developer` and sends completed work to `volcengine-reviewer` when both are installed.
- An explicit request for official subagents uses Codex `default`, `worker`, or `explorer` agents in the same V1 task.
- An explicit request not to use subagents keeps all work in the GPT main task.
- The main GPT model remains the user's UI selection. The installer must not encode V1/V2 into renamed model choices.
- API keys are never accepted in chat, command arguments, configuration files, logs, or test fixtures.
- Installation and uninstallation preserve unrelated Codex configuration, agents, credentials, and `AGENTS.md` content.
- The repository is initialized locally but Codex does not commit, push, or publish it.

## Distribution

The repository is one Codex marketplace named `custom-subagents`. It contains two plugins:

```text
custom-subagents/
  .agents/plugins/marketplace.json
  plugins/deepseek-developer/
  plugins/volcengine-reviewer/
```

Users add the GitHub repository once and install either plugin independently:

```bash
codex plugin marketplace add OWNER/REPOSITORY --ref main
codex plugin add deepseek-developer@custom-subagents
codex plugin add volcengine-reviewer@custom-subagents
```

Installing a plugin exposes its setup and uninstall skills. Plugin installation itself does not silently rewrite global configuration. In conversation, the user asks Codex to configure the installed agent; the skill then runs the lifecycle script with explicit approval.

## Plugin Boundary

Each plugin owns:

- one `.codex-plugin/plugin.json` manifest;
- one setup skill and one uninstall skill;
- one strict `agent-spec.json` containing only fixed description, role instructions, provider display name, and wire API;
- one lifecycle script;
- tests using an isolated fake `CODEX_HOME` and fake Keychain command.

The DeepSeek plugin installs `~/.codex/agents/deepseek_developer.toml`. The Volcengine plugin installs `~/.codex/agents/volcengine_reviewer.toml`. Neither plugin edits the other file.

The shared lifecycle validates the exact JSON spec schema and generates the complete native Codex TOML itself. Plugins cannot inject extra TOML fields or override the Keychain command, service, account, or auth arguments.

## Shared Managed State

Both lifecycle scripts implement the same versioned state contract at:

```text
~/.codex/custom-subagents/state.json
```

The state file records installed agent IDs, non-secret endpoint/model settings, the selected GPT main model, stable base/generated catalog paths, and non-secret metadata needed to restore the exact pre-install configuration shape. It never stores API keys or full configuration contents.

Shared files use identifiable ownership markers:

```text
<!-- BEGIN custom-subagents managed workflow -->
...
<!-- END custom-subagents managed workflow -->
```

Install replaces only the marked block. Uninstall removes only the target agent entry. Shared V1 configuration and workflow blocks remain while at least one custom agent is registered. Removing the final custom agent restores the recorded pre-install model-catalog setting and removes the managed block.

## Configuration Flow

1. The setup skill checks macOS, Codex Desktop layout, and plugin files.
2. It asks for the API endpoint and model name as non-secret values.
3. It launches a native hidden-input macOS dialog for the API key.
4. The lifecycle script stores the key in Keychain under a plugin-specific service/account.
5. It writes the provider and fixed-role agent configuration.
6. It snapshots the complete active catalog, or `models_cache.json` fallback, and changes only the selected GPT main model's `multi_agent_version` to `v1` without changing other fields, models, IDs, display names, or ordering.
7. It switches `model_catalog_json` to that generated catalog while recording the previous setting and initial file shape.
8. It regenerates the shared `AGENTS.md` block from the state registry.
9. It reports that Codex must be fully restarted and a fresh task created.

The API-key dialog must not print its result. Shell tracing is disabled before reading the value, the value is piped to the Keychain command through stdin where supported, and the variable is unset immediately afterward.

## Routing Policy

The managed `AGENTS.md` block expresses precedence in this order:

1. Direct user instructions and repository-specific `AGENTS.md` rules.
2. Explicit `no subagents` request.
3. Explicit `official subagents` request using official GPT agent roles.
4. Installed fixed-role custom agents.

The block references only currently registered agents. Installing DeepSeek alone must not mention the Volcengine agent as available. Installing Volcengine alone permits review-only delegation without assuming a custom developer exists.

The generated Volcengine agent TOML must also enforce
`sandbox_mode = "read-only"` and `approval_policy = "never"`. These settings
are reviewer-specific; the DeepSeek developer agent must not inherit them.

## Failure Handling

- Preflight completes before any write.
- One owner-token lock serializes Keychain and managed-file changes across both plugins. A concurrent configure or uninstall fails before mutation.
- Every modified file gets a timestamped backup in `~/.codex/custom-subagents/backups/<operation-id>/`.
- Writes use temporary files followed by atomic rename.
- A failed operation restores files changed during that operation and leaves the prior state registry intact.
- Existing unmanaged agent files with the same name cause a hard stop rather than overwrite.
- Existing managed blocks with malformed or duplicate markers cause a hard stop with a recovery message.
- Keychain deletion targets only the exact plugin service/account and occurs only during that plugin's uninstall.
- Raw `codex plugin remove` cannot run lifecycle cleanup after the skill disappears, so documentation instructs users to request conversational uninstall first, then remove the plugin package.

## Verification

Automated tests run against temporary homes and cover fresh install, reinstall, two-plugin coexistence, uninstall-one, uninstall-last, rollback, malformed markers, and secret redaction. No test touches the real `~/.codex` directory or real Keychain.

Manual acceptance requires a full Codex restart and fresh tasks proving:

- DeepSeek development receives the delegated plaintext task and returns a result;
- Volcengine review receives the completed diff and returns findings;
- the generated Volcengine agent uses a read-only sandbox with approvals
  disabled, while the DeepSeek agent remains writable under the task policy;
- explicit official-agent routing uses a GPT `default`, `worker`, or `explorer` role;
- explicit no-agent routing creates no child;
- child JSONL records show the expected role, provider, model, and `multi_agent_version = v1`;
- uninstalling one plugin preserves the other;
- uninstalling the final plugin restores the recorded model-catalog configuration.

## First-Release Exclusions

- Windows and Linux support;
- a Codex composer dropdown;
- switching V1/V2 inside an existing task;
- arbitrary provider creation;
- automatic execution on `codex plugin add`;
- automatic GitHub publication or upgrades;
- accepting secrets through conversation text.
