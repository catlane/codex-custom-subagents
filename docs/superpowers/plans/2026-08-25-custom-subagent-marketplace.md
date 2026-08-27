# Custom Subagent Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS Codex marketplace containing independently installable DeepSeek developer and Volcengine reviewer plugins with reversible V1 setup.

**Architecture:** Each plugin packages fixed-role skills, templates, and a lifecycle entrypoint. A shared, versioned registry coordinates only the V1 catalog and managed `AGENTS.md` block; plugin-specific agent files and Keychain items remain independently owned. Lifecycle behavior is tested against isolated temporary Codex homes before any real-machine acceptance test.

**Tech Stack:** Codex plugin manifests, Markdown skills, POSIX shell, macOS `security` and `osascript`, JavaScript for Automation for structured JSON, fixture-based shell tests.

## Global Constraints

- Target macOS Codex Desktop only.
- Keep GPT as the main task model selected in the Codex UI.
- Use one V1 multi-agent protocol for the complete custom-agent task.
- Never place API keys in chat, argv, TOML, JSON, logs, backups, or fixtures.
- Preserve unrelated user files and settings.
- Do not commit, push, publish, or modify the user's live `~/.codex` during automated tests.

---

### Task 1: Marketplace Skeleton And Static Validation

**Files:**
- Create: `.agents/plugins/marketplace.json`
- Create: `plugins/deepseek-developer/.codex-plugin/plugin.json`
- Create: `plugins/volcengine-reviewer/.codex-plugin/plugin.json`
- Create: `scripts/validate-repository.sh`
- Create: `tests/static-validation.sh`
- Create: `README.md`

**Interfaces:**
- Consumes: Codex marketplace local-plugin schema.
- Produces: plugin selectors `deepseek-developer@custom-subagents` and `volcengine-reviewer@custom-subagents`.

- [ ] Write `tests/static-validation.sh` to assert the marketplace name, both plugin paths, manifest names, semantic versions, required skill directories, and absence of symlinks escaping plugin roots.
- [ ] Run `sh tests/static-validation.sh`; expect failure because marketplace files do not exist.
- [ ] Add marketplace and plugin manifests with local sources `./plugins/deepseek-developer` and `./plugins/volcengine-reviewer`, product policy `CODEX`, and category `Developer Tools`.
- [ ] Add `scripts/validate-repository.sh` using `plutil -lint` plus explicit path/name checks; it must return nonzero with a concise filename-specific message.
- [ ] Run `sh tests/static-validation.sh`; expect all static assertions to pass.
- [ ] Document the verified two-command marketplace/install flow from local `codex plugin --help`.

### Task 2: Isolated Lifecycle Core

**Files:**
- Create: `shared/lifecycle.sh`
- Create: `shared/state.js`
- Create: `tests/helpers/assert.sh`
- Create: `tests/helpers/fake-security.sh`
- Create: `tests/fixtures/config-minimal.toml`
- Create: `tests/fixtures/config-existing-catalog.toml`
- Create: `tests/fixtures/models-cache.json`
- Create: `tests/lifecycle-install.sh`
- Create: `tests/lifecycle-rollback.sh`

**Interfaces:**
- Consumes: `CUSTOM_SUBAGENT_HOME`, `CUSTOM_SUBAGENT_PLUGIN_ROOT`, agent ID, role, provider ID, endpoint, and model.
- Produces: commands `install`, `uninstall`, and `status`; state schema version `1` in `$CUSTOM_SUBAGENT_HOME/custom-subagents/state.json`.

- [ ] Write failing install tests that create a temporary home and assert no access outside it, atomic state creation, backup creation, idempotent reinstall, and exact preservation of unrelated config text.
- [ ] Write failing rollback tests that inject failure after each write boundary and compare every pre-existing file byte-for-byte with its baseline.
- [ ] Implement `shared/state.js` commands for JSON registry reads/writes, catalog generation, model-entry V1 conversion, and deterministic workflow rendering. JSON output must be sorted and end with one newline.
- [ ] Implement `shared/lifecycle.sh` preflight, operation backups, temporary-file writes, rollback trap, plugin ownership checks, and dispatch to `state.js` through `/usr/bin/osascript -l JavaScript`.
- [ ] Ensure the lifecycle rejects empty endpoint/model, non-HTTPS endpoints unless `CUSTOM_SUBAGENT_ALLOW_HTTP=1` is set for localhost tests, duplicate managed markers, and unmanaged target agent files.
- [ ] Run `sh tests/lifecycle-install.sh` and `sh tests/lifecycle-rollback.sh`; expect all cases to pass.

### Task 3: Secure Keychain Adapter

**Files:**
- Create: `shared/keychain.sh`
- Create: `shared/prompt-secret.applescript`
- Create: `tests/keychain.sh`

**Interfaces:**
- Consumes: service `codex-custom-subagent/<agent-id>` and account `api-key`.
- Produces: `keychain_store`, `keychain_exists`, and `keychain_delete`; none return secret material.

- [ ] Write failing tests with `CUSTOM_SUBAGENT_SECURITY_BIN=tests/helpers/fake-security.sh` for create, replace, existence-only lookup, exact delete targeting, cancellation, and redacted stdout/stderr.
- [ ] Implement a hidden-answer native dialog that returns cancellation separately from an empty value and never logs the result.
- [ ] Implement the Keychain wrapper with tracing disabled, stdin-based secret transfer where accepted by `/usr/bin/security`, immediate variable cleanup, and messages containing only service/account identifiers.
- [ ] Add a regression test using sentinel `SECRET_MUST_NOT_APPEAR_7F31` and scan the complete captured output, state, configs, and backups for the sentinel.
- [ ] Run `sh tests/keychain.sh`; expect all cases to pass and zero sentinel matches.

### Task 4: DeepSeek Developer Plugin

**Files:**
- Create: `plugins/deepseek-developer/skills/deepseek-developer-setup/SKILL.md`
- Create: `plugins/deepseek-developer/skills/deepseek-developer-uninstall/SKILL.md`
- Create: `plugins/deepseek-developer/templates/agent-spec.json`
- Create: `plugins/deepseek-developer/scripts/configure.sh`
- Create: `plugins/deepseek-developer/scripts/uninstall.sh`
- Create: `tests/deepseek-plugin.sh`

**Interfaces:**
- Consumes: endpoint default `https://api.deepseek.com` unless an explicit endpoint override is supplied, the user-selected model, and Keychain service `codex-custom-subagent/deepseek-developer`.
- Produces: native agent type `deepseek_developer` with fixed development role.

- [ ] Write a failing plugin test that configures DeepSeek in a temporary home and asserts exact provider/agent IDs, endpoint/model substitution, development instructions, state registration, and workflow routing.
- [ ] Add a setup skill that asks only endpoint/model in conversation, explicitly refuses chat-provided keys, explains the native hidden dialog, runs `configure.sh`, and reports the restart/fresh-task requirement.
- [ ] Add an uninstall skill that runs lifecycle cleanup first and only then tells Codex to remove `deepseek-developer@custom-subagents`.
- [ ] Add the exact-schema agent spec with full task-payload requirement, scoped ownership, focused verification, unrelated-change preservation, and `MISSING_TASK_PAYLOAD` fallback; lifecycle code, not the plugin, renders native TOML and the fixed Keychain auth block.
- [ ] Wire plugin scripts to a vendored copy of the tested shared lifecycle version.
- [ ] Run `sh tests/deepseek-plugin.sh`; expect all assertions to pass.

### Task 5: Volcengine Reviewer Plugin

**Files:**
- Create: `plugins/volcengine-reviewer/skills/volcengine-reviewer-setup/SKILL.md`
- Create: `plugins/volcengine-reviewer/skills/volcengine-reviewer-uninstall/SKILL.md`
- Create: `plugins/volcengine-reviewer/templates/agent-spec.json`
- Create: `plugins/volcengine-reviewer/scripts/configure.sh`
- Create: `plugins/volcengine-reviewer/scripts/uninstall.sh`
- Create: `tests/volcengine-plugin.sh`

**Interfaces:**
- Consumes: endpoint default `https://ark.cn-beijing.volces.com/api/plan/v3` unless an explicit endpoint override is supplied, the user-selected model deployment ID, and Keychain service `codex-custom-subagent/volcengine-reviewer`.
- Produces: native agent type `volcengine_reviewer` with read-only review as its default responsibility.

- [ ] Write a failing plugin test asserting reviewer-only instructions, no implicit write authority, endpoint/deployment substitution, state registration, and coexistence with DeepSeek.
- [ ] Add setup/uninstall skills with the same security and cleanup contract as DeepSeek, including the official endpoint default and explicit override behavior.
- [ ] Add the exact-schema reviewer spec requiring findings-first output, severity, file/line evidence, regression/security/data-integrity checks, and explicit remaining test gaps; lifecycle code renders the native TOML.
- [ ] Regenerate the workflow from both registered roles and assert development routes to DeepSeek followed by independent Volcengine review.
- [ ] Run `sh tests/volcengine-plugin.sh`; expect all assertions to pass.

### Task 6: Coexistence, Uninstall, And Recovery

**Files:**
- Create: `tests/coexistence.sh`
- Create: `tests/uninstall.sh`
- Create: `docs/recovery.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: lifecycle and both plugin packages.
- Produces: verified two-plugin install/uninstall matrix and operator recovery instructions.

- [ ] Write the install matrix: DeepSeek only, Volcengine only, DeepSeek then Volcengine, Volcengine then DeepSeek, and repeated install.
- [ ] Write uninstall tests proving uninstall-one preserves the other agent, Keychain target, V1 catalog, workflow entry, and unrelated config.
- [ ] Write uninstall-last tests proving restoration of the exact original `model_catalog_json` line or exact removal when it was originally absent.
- [ ] Test malformed state, missing backups, duplicate markers, and raw plugin-removal residue; each case must fail closed with a recovery path and no unrelated mutation.
- [ ] Document conversational uninstall before `codex plugin remove`, backup locations, status inspection, and manual recovery without printing credentials.
- [ ] Run `sh tests/coexistence.sh` and `sh tests/uninstall.sh`; expect all matrix cases to pass.

### Task 7: Repository And Local Marketplace Verification

**Files:**
- Create: `scripts/test-all.sh`
- Create: `docs/manual-acceptance.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: complete repository.
- Produces: one non-destructive automated verification command and a separate live-machine acceptance checklist.

- [ ] Implement `scripts/test-all.sh` to run every test in a fresh temporary root, preserve failure artifacts, and print a concise pass/fail summary.
- [ ] Run `sh scripts/test-all.sh`; expect every static, lifecycle, security, plugin, coexistence, and uninstall suite to pass.
- [ ] Add the repository itself as a local marketplace and install both plugins using an isolated Codex config where supported; verify `codex plugin list` sees both plugin names.
- [ ] Inspect `git status --short` and verify no generated secrets, live-home files, test temporary directories, or plugin caches are tracked.
- [ ] Write manual acceptance steps for full Codex restart, fresh V1 task, DeepSeek development, Volcengine review, official GPT override, no-agent override, JSONL evidence, and final uninstall restoration.
- [ ] Leave all changes uncommitted for the user to review and publish.
