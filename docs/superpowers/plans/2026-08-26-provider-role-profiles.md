# Provider Role Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fixed-role provider plugins with independently installable DeepSeek and Volcengine provider plugins that each expose general, developer, and read-only reviewer native agent profiles.

**Architecture:** Keep one state record and one Keychain credential per provider plugin. During one transactional lifecycle operation, render three separately owned native agent TOML files from a role-aware provider spec; regenerate `AGENTS.md` so GPT selects provider and role dynamically while direct user routing overrides automatic selection.

**Tech Stack:** Codex plugin manifests and skills, POSIX shell, JavaScript for Automation, macOS Keychain, fixture-based shell tests.

## Global Constraints

- GPT remains the main task model.
- A custom-agent task uses V1 throughout and never mixes V1 and V2.
- One configured provider always exposes `general`, `developer`, and `reviewer` profiles.
- Reviewer TOML enforces `sandbox_mode = "read-only"` and `approval_policy = "never"`; other profiles do not.
- One provider's profiles share one endpoint, model, and Keychain item.
- API keys never enter chat, argv, environment variables, TOML, JSON, logs, backups, or fixtures.
- Preserve unrelated files and exact pre-install Codex configuration shapes.
- Do not modify the live `~/.codex`, call paid APIs, commit, push, or publish.

---

### Task 1: Provider Plugin Names And Static Contract

**Files:**
- Modify: `.agents/plugins/marketplace.json`
- Rename: `plugins/deepseek-developer/` to `plugins/deepseek-agent/`
- Rename: `plugins/volcengine-reviewer/` to `plugins/volcengine-agent/`
- Modify: both `.codex-plugin/plugin.json` files
- Modify: `tests/static-validation.sh`

**Interfaces:**
- Produces plugin selectors `deepseek-agent@custom-subagents` and `volcengine-agent@custom-subagents`.

- [ ] Change static tests first to require provider package names, provider-oriented descriptions, and setup/uninstall skill directories; run `sh tests/static-validation.sh` and verify it fails on the old names.
- [ ] Rename the plugin directories and manifests, remove fixed-role wording, and keep marketplace/plugin names identical.
- [ ] Run `sh tests/static-validation.sh`; expect PASS.

### Task 2: Role-Aware Provider Specs And Rendering

**Files:**
- Modify: `shared/state.js`
- Modify: `plugins/deepseek-agent/templates/agent-spec.json`
- Modify: `plugins/volcengine-agent/templates/agent-spec.json`
- Modify: `tests/agents-roundtrip.sh`
- Modify: `tests/lifecycle-state.sh`

**Interfaces:**
- A provider spec has exact keys `schema_version`, `provider_display_name`, `wire_api`, and `profiles`.
- `profiles` has exact keys `general`, `developer`, and `reviewer`; each profile has `description` and `developer_instructions`, with reviewer additionally requiring the fixed sandbox and approval values.
- `render-agent-spec-state SPEC STATE PROVIDER_ID ROLE CATALOG SERVICE` renders one deterministic native TOML profile named `${provider}_${role}`.

- [ ] Add failing round-trip tests for all three profiles, exact schema rejection, shared provider/model/auth values, and reviewer-only sandbox fields; verify RED.
- [ ] Update spec parsing and TOML rendering to accept only the role-aware schema and one of the three fixed role names.
- [ ] Replace provider templates with general, developer, and reviewer instructions; keep payload completeness and unrelated-change safeguards.
- [ ] Run `sh tests/agents-roundtrip.sh` and `sh tests/lifecycle-state.sh`; expect PASS.

### Task 3: Transactional Three-Profile Lifecycle

**Files:**
- Modify: `shared/lifecycle.sh`
- Modify: `tests/lifecycle-install.sh`
- Modify: `tests/lifecycle-rollback.sh`
- Modify: `tests/uninstall.sh`

**Interfaces:**
- `install PROVIDER_ID PROVIDER ENDPOINT MODEL` registers one provider record and atomically manages `${provider}_general.toml`, `${provider}_developer.toml`, and `${provider}_reviewer.toml`.
- `uninstall PROVIDER_ID` removes all three files before removing the provider record.

- [ ] Change lifecycle tests first to require three files per registration, complete rollback across every profile write boundary, and uninstall-all-three behavior; verify RED.
- [ ] Refactor lifecycle preflight to validate ownership and expected contents for every target profile before the first write.
- [ ] Render and atomically write all three profiles, then state/catalog/workflow, preserving the existing lock and rollback contract.
- [ ] Update residue detection and uninstall to treat the three files as one provider-owned unit and fail closed on partial or unmanaged ownership.
- [ ] Run the three focused lifecycle suites; expect PASS.

### Task 4: Automatic Routing And Explicit Overrides

**Files:**
- Modify: `shared/state.js`
- Modify: `tests/coexistence.sh`
- Modify: `tests/lifecycle-install.sh`

**Interfaces:**
- Managed `AGENTS.md` lists each installed provider's three exact agent types.
- Routing precedence is user/repository instructions, no-subagent request, official GPT request, explicit provider/role request, then automatic custom provider/role selection.

- [ ] Add failing workflow assertions for one-provider development plus review, two-provider cross-model routing, repeated use of one provider, and explicit user override precedence; verify RED.
- [ ] Render concise provider-neutral orchestration instructions with no default DeepSeek-development or Volcengine-review binding.
- [ ] Run `sh tests/coexistence.sh` and `sh tests/lifecycle-install.sh`; expect PASS.

### Task 5: Provider Entry Points, Keychain Ownership, And Migration Guard

**Files:**
- Modify: both plugin `scripts/configure.sh`, `scripts/uninstall.sh`, and skills
- Sync: both plugin `scripts/vendor/` directories from `shared/`
- Modify: `tests/deepseek-plugin.sh`
- Modify: `tests/volcengine-plugin.sh`
- Modify: `tests/keychain.sh`

**Interfaces:**
- Keychain services become `codex-custom-subagent/deepseek-agent` and `codex-custom-subagent/volcengine-agent`.
- Configure accepts endpoint/model only and calls the four-argument provider lifecycle install.
- Old fixed-role state or files cause an identifier-only migration error before Keychain or managed-file mutation.

- [ ] Change plugin tests first to require provider IDs, three profile files, shared credentials, reviewer-only restrictions, and rejection of old fixed-role registrations; verify RED.
- [ ] Update scripts and skills to describe one provider with automatic multi-role scheduling and task-level explicit overrides.
- [ ] Keep hidden-dialog, endpoint binding, lock, signal, and cleanup behavior unchanged except for provider IDs and the new lifecycle signature.
- [ ] Sync tested shared files into each plugin vendor directory and run both plugin suites plus `tests/keychain.sh`; expect PASS.

### Task 6: Documentation And Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/manual-acceptance.md`
- Modify: `docs/recovery.md`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Documents Chinese-first install/configure/use/uninstall for the two provider plugins and the fixed-role-name migration.

- [ ] Update docs to show automatic scheduling with one or multiple providers and examples of explicit provider/role selection.
- [ ] Document uninstalling old packages before installing renamed packages; do not claim automatic credential migration.
- [ ] Run `sh scripts/test-all.sh`; expect every discovered suite to pass with zero live-home or real-Keychain access.
- [ ] Run repository/plugin validators and inspect `git diff --check`, `git diff`, and `git status --short`.
- [ ] Run an independent findings-first review against the requirements and actual diff, repair actionable findings, and rerun affected tests plus the full suite.
