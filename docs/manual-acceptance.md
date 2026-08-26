# Manual Acceptance

This checklist covers behavior that isolated repository tests cannot prove. It
changes the live Codex home and macOS Keychain. Run it only on macOS Codex
Desktop after reviewing the repository and approving each setup or uninstall
operation. Never paste an API key into chat, a command, an environment
variable, or a file.

## Preconditions

- Run `sh scripts/test-all.sh` from the repository and require a zero exit.
- Install the marketplace and the two plugins sequentially. Do not run two
  `codex plugin add` commands concurrently.
- Have the exact DeepSeek model, Volcengine OpenAI-compatible endpoint, and
  Volcengine model or deployment ID available as non-secret values.
- Have fresh provider keys ready to enter only in the native hidden dialogs.
- Record whether `~/.codex/config.toml` and `~/.codex/AGENTS.md` exist. For each
  existing file, record its SHA-256 without displaying its contents. This is
  the pre-configuration restoration baseline.
- Fully quit Codex Desktop before beginning configuration.

## Configure DeepSeek Developer

1. Start Codex and ask it to use the `deepseek-developer-setup` skill with the
   selected non-secret model and either the accepted default endpoint
   `https://api.deepseek.com` or an explicit non-secret endpoint.
2. Confirm that Codex shows the endpoint and model and asks for approval before
   changing the native agent, V1 catalog, workflow block, or state registry.
3. Approve the managed-file change. Enter a fresh key only in the native hidden
   macOS dialog. Cancel once and confirm that cancellation leaves no partial
   configuration, then repeat and accept with a fresh key.
4. Confirm success is reported without displaying any credential value.
5. Fully quit and restart Codex Desktop. Create a new task; do not reuse the
   setup task.

## DeepSeek Development Route

In the fresh task, request a small, disposable development change and allow the
normal custom-agent route. Confirm the GPT model selected in the UI remains the
main agent and the delegated implementation is returned to that same task.

Inspect the task JSONL without printing authentication-bearing command data.
Require one child record with all of the following exact evidence:

- `agent_role` or `agent_type`: `deepseek_developer`
- `model_provider`: `deepseek`
- model: the exact configured DeepSeek model
- `multi_agent_version`: `v1`
- delegated payload: the complete bounded task plus explicit ownership

Reject the run if the JSONL shows V2, an incomplete payload, a different
provider/model, or a detached main task that cannot receive the child result.

## Configure And Exercise Volcengine Reviewer

1. In a separate setup conversation, ask Codex to use the
   `volcengine-reviewer-setup` skill with the exact non-secret OpenAI-compatible
   endpoint and model or deployment ID. No default may be guessed.
2. Confirm the proposed values and approve the managed-file change. Enter a
   fresh key only in the native hidden dialog.
3. Fully quit and restart Codex Desktop, then create a new task.
4. Before the task, inspect the generated `volcengine_reviewer.toml` and
   confirm it contains `sandbox_mode = "read-only"` and
   `approval_policy = "never"`. Confirm the DeepSeek agent TOML does not gain
   those reviewer-only settings.
5. Give the task original requirements and acceptance criteria, make a small
   testable change through the DeepSeek development route, and request an
   independent review of the actual diff and verification evidence.
6. Confirm review output is findings-first, includes severity and file/line
   evidence, checks correctness, security, data integrity, regressions and test
   gaps, and that the reviewer cannot edit files or request approval to escape
   the read-only sandbox.

Require the reviewer child JSONL to contain:

- `agent_role` or `agent_type`: `volcengine_reviewer`
- `model_provider`: `volcengine`
- model: the exact configured Volcengine model or deployment ID
- `multi_agent_version`: `v1`
- delegated payload: original requirements, acceptance criteria, actual diff,
  and verification evidence

## Routing Overrides

Use a new task for each routing case. A single task must never mix V1 and V2.

1. Ask explicitly for "official GPT agents" on a bounded task. Confirm the
   child uses an official `default`, `worker`, or `explorer` role in the same V1
   task, and that neither `deepseek_developer` nor `volcengine_reviewer` runs.
2. Ask explicitly for "no subagents" on a bounded task. Confirm the GPT main
   task performs the work and the JSONL has no child-agent dispatch.
3. Start one more task without an override. Confirm configured custom-agent
   routing resumes and still uses V1 throughout.

## Optional Live Provider Calls

Setup success, JSONL routing, and isolated tests do not prove provider API
access. A live DeepSeek or Volcengine request may incur cost and send task data
to an external provider. Perform each live API test only after separate,
explicit authorization that identifies the provider and payload. Record only
status, model/provider identifiers, and non-secret error details.

## Uninstall And Restoration

1. While both packages are still installed, ask Codex to use the
   `deepseek-developer-uninstall` skill. Approve deletion of only its managed
   files and Keychain item. Confirm the Volcengine agent, route, and Keychain
   item remain. Only after cleanup succeeds, remove
   `deepseek-developer@custom-subagents`.
2. Fully restart Codex and confirm Volcengine review routing still works in a
   fresh task.
3. Ask Codex to use the `volcengine-reviewer-uninstall` skill. Approve deletion
   of only its managed files and Keychain item. Only after cleanup succeeds,
   remove `volcengine-reviewer@custom-subagents`.
4. Confirm both exact Keychain services with account `api-key` are absent using
   identifier-only lookups; never use `security ... -w` or export Keychain
   data.
5. Confirm managed agent TOML files, `models-v1.json`, and `state.json` are
   absent. Confirm no managed workflow markers remain in `AGENTS.md`.
6. Compare `config.toml` and `AGENTS.md` existence and SHA-256 values with the
   pre-configuration baseline. The final uninstall must restore the exact
   original shape and bytes.
7. Fully quit and restart Codex. Create a fresh task and confirm official Codex
   behavior is available without either custom plugin.

If a package is removed before its uninstall skill runs, stop and follow
[`recovery.md`](recovery.md). Reinstall the same package, perform conversational
cleanup, and remove it again; do not delete managed residue manually.
