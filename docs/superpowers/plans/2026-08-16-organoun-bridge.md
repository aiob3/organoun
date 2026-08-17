---
document_type: historical_implementation_plan
status: blocked
historical_operator_approved: true
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
policy_baseline: false
---

# Organoun Bridge Implementation Plan

> **NÃO EXECUTAR.** Este plano antecede a Constituição Organoun/RFC-0001 e contém decisões incompatíveis com ela. Permanece apenas como registro histórico.

> **Registro histórico:** a instrução original de execução por agentes foi revogada. As checkboxes abaixo não constituem fila ativa nem autorização.

**Goal:** Build the `organ` CLI and Codex skill that let the user observe, question, dispatch to, verify, and retrieve artifacts from Claude sessions locally or on `$ORGANOUN_REMOTE_HOST`, without manual delivery between chats.

**Architecture:** A Bash CLI reads an allowlisted target registry, routes each action through a local or Tailscale SSH transport, and delegates session mechanics to a pinned Outsourcerer adapter. State is private JSON on the host that owns the session; edit jobs record a base commit, worktree, allowed paths, and controller-owned verification command.

**Tech Stack:** Bash 4.4+, jq 1.7+, GNU coreutils, tmux 3.4+, OpenSSH/Tailscale SSH, Git, Outsourcerer v0.8.2 at `3a788b8e072b915622fd80c6f8ecec64de659bd5`, Claude Code native provider `cc`.

## Global Constraints

- The user is the pilot; Organoun observes and transports but does not choose new work autonomously.
- Human/project name is `Organoun`; executable name is `organ`; Codex skill name is `organoun`.
- Target hosts are allowlisted to exactly `local` and `$ORGANOUN_REMOTE_HOST`; never accept a host from prompt text.
- Managed Claude sessions use provider `cc`; omit model unless the target explicitly declares one.
- Question payloads are at most 16 KiB; read excerpts are at most 64 KiB.
- Never use `eval`; payloads enter `organ` on stdin and are forwarded with quoted argv or JSON stdin.
- Public JSON never contains claim tokens, credentials, full prompts, or full transcripts.
- `~/.local/state/organoun` is mode `0700`; claim, session-ownership, and job records are mode `0600`.
- Adopted sessions may be released but never stopped; only Organoun-created managed sessions may be stopped.
- A managed session name collision is never adopted implicitly; send/stop require a still-valid Organoun ownership receipt.
- No automatic retry after unknown delivery or failed verification.
- Never promote `tmux send-keys` success to confirmed delivery; without an independent receipt adapter, report `delivery=unknown` and observe with `read` only.
- `status` is observational and never executes an edit verification command.
- Job IDs are host-qualified as `<host>.job-<timestamp>-<nonce>`; `verify` routes only the allowlisted prefixes `local` and `$ORGANOUN_REMOTE_HOST`.
- `fetch` accepts only a validated job ID plus an opaque manifest artifact ID; it never accepts a filesystem path.
- Edit dispatch requires an absolute worktree, at least one relative `--allow`, and `--verify`; paths containing `..` are rejected.
- Agent-reported `done` is not acceptance; only `organ verify JOB_ID` can accept an edit job.
- Do not modify or vendor Outsourcerer source; install and invoke the exact pinned upstream commit.
- Keep the full anti-evasion state machine, AST scanning, mandatory mutation testing, and autonomous challenge loop out of this implementation.

## File Map

- `bin/organ` — argument parsing and command dispatch only.
- `lib/organ/common.sh` — limits, safe temp files, JSON envelopes, exit/error helpers.
- `lib/organ/config.sh` — registry loading, schema validation, target lookup, host/mode/provider constraints.
- `lib/organ/claims.sh` — private claim record creation, lookup, authorization, and deletion.
- `lib/organ/sessions.sh` — managed-session ownership receipts and live endpoint validation.
- `lib/organ/jobs.sh` — private job receipts and state transitions.
- `lib/organ/outsourcerer.sh` — the only code that invokes the upstream script or tmux fallback.
- `lib/organ/local.sh` — maps normalized actions to the local Outsourcerer adapter.
- `lib/organ/guard.sh` — worktree/base SHA capture, allowed-path diff audit, controller verification.
- `lib/organ/artifacts.sh` — artifact manifest lookup and containment-safe reads.
- `lib/organ/ssh.sh` — fixed-host SSH transport with JSON stdin and unreachable/delivery-unknown semantics.
- `remote/organ-remote` — remote request validator and local-action entrypoint on `$ORGANOUN_REMOTE_HOST`.
- `config/deployment.example.json` — valid, non-secret deployment example.
- `vendor/outsourcerer.lock.json` — upstream URL, tag, commit, and relative script path.
- `scripts/install-outsourcerer.sh` — idempotent pinned dependency installer.
- `scripts/install-organoun.sh` — opt-in local installation of CLI, library, example config, and skill.
- `probes/claude-composer-empty` — conservative, read-only Claude composer check for adopted-session mutation.
- `scripts/smoke-local.sh` — non-mutating local preflight and read test.
- `scripts/smoke-remote.sh` — non-mutating remote preflight and read test.
- `skills/organoun/SKILL.md` — natural-language routing and authority rules for Codex.
- `tests/helpers.sh` — assertions, isolated XDG directories, fixtures, and fake command path.
- `tests/run.sh` — deterministic shell test runner.
- `tests/fixtures/fake-outsourcerer.sh` — records exact adapter calls and emits controlled responses.
- `tests/fixtures/fake-tmux.sh` — simulates pane/session identity; hermetic tests never touch the user's tmux server.
- `tests/fixtures/fake-ssh.sh` — records the remote envelope and simulates success/failure/ambiguous delivery.
- `tests/fixtures/targets.json` — local adopted, local managed, and remote managed targets.
- `tests/test_config.sh` — registry and CLI contract.
- `tests/test_read.sh` — local list/status/read and bounded transcript behavior.
- `tests/test_dependency.sh` — lockfile, dry-run, exact-checkout, and idempotency behavior against a temporary fixture repository.
- `tests/test_claims.sh` — claim/ask/release security and delivery behavior.
- `tests/test_dispatch.sh` — managed read/edit dispatch, lifecycle, and provider selection.
- `tests/test_guard.sh` — scope audit, explicit verification, and no-auto-retry policy.
- `tests/test_artifacts.sh` — local/remote artifact containment and size metadata.
- `tests/test_ssh.sh` — request encoding, host allowlist, and failure semantics.
- `tests/test_install_skill.sh` — isolated installer and skill contract.
- `docs/operations.md` — setup, exact commands, local/VPS runbook, rollback, and acceptance checklist.

---

### Task 1: CLI, JSON Envelope, and Target Registry

**Files:**
- Create: `bin/organ`
- Create: `lib/organ/common.sh`
- Create: `lib/organ/config.sh`
- Create: `config/deployment.example.json`
- Create: `tests/helpers.sh`
- Create: `tests/run.sh`
- Create: `tests/fixtures/targets.json`
- Create: `tests/test_config.sh`

**Interfaces:**
- Produces: `organ_emit_ok ACTION TARGET HOST STATE DELIVERY DATA_JSON`
- Produces: `organ_emit_error ACTION TARGET HOST CODE MESSAGE`
- Produces: `organ_target_get CONFIG_PATH ALIAS` → one target JSON object on stdout.
- Produces: `organ_targets_list CONFIG_PATH` → configured target array on stdout.
- Produces: `ORGAN_CONFIG`, `ORGAN_STATE_HOME`, and `ORGAN_MAX_ASK_BYTES` environment overrides used by every later task.

- [ ] **Step 1: Write the failing registry tests**

Create `tests/fixtures/targets.json` with concrete targets:

```json
{
  "schema_version": "1",
  "targets": [
    {
      "alias": "claude-onp",
      "transport": "local",
      "host": "local",
      "cwd": "$ORGANOUN_PROJECT_ROOT",
      "mode": "adopted",
      "tmux_target": "tmux:1.3",
      "claude_session_id": null
    },
    {
      "alias": "claude-managed",
      "transport": "local",
      "host": "local",
      "cwd": "$ORGANOUN_PROJECT_ROOT",
      "mode": "managed",
      "provider": "cc",
      "session_name": "organoun-local",
      "model": null
    },
    {
      "alias": "remote-managed",
      "transport": "ssh",
      "host": "$ORGANOUN_REMOTE_HOST",
      "cwd": "/srv/organoun",
      "mode": "managed",
      "provider": "cc",
      "session_name": "organoun-remote",
      "model": null
    }
  ]
}
```

Create `tests/helpers.sh` with `new_test_env`, `assert_eq`, `assert_mode`, and `assert_jq` helpers. In `tests/test_config.sh`, assert:

```bash
new_test_env
export ORGAN_CONFIG="$REPO_ROOT/tests/fixtures/targets.json"

actual="$($REPO_ROOT/bin/organ list --json)"
assert_jq "$actual" '.ok == true'
assert_jq "$actual" '.data.targets | length == 3'
assert_jq "$actual" '.data.targets[0].alias == "claude-onp"'

set +e
actual="$($REPO_ROOT/bin/organ status missing --json 2>&1)"
rc=$?
set -e
assert_eq "64" "$rc"
assert_jq "$actual" '.error.code == "TARGET_NOT_FOUND"'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test_config.sh`

Expected: FAIL because `bin/organ` and the helper library do not exist.

- [ ] **Step 3: Implement the minimal JSON/config core**

Use `jq -cn` for every public envelope. The essential function bodies in `lib/organ/common.sh` are:

```bash
ORGAN_MAX_ASK_BYTES="${ORGAN_MAX_ASK_BYTES:-16384}"
ORGAN_MAX_READ_BYTES="${ORGAN_MAX_READ_BYTES:-65536}"

organ_emit_ok() {
  jq -cn --arg action "$1" --arg target "$2" --arg host "$3" \
    --arg state "$4" --arg delivery "$5" --argjson data "$6" \
    '{schema_version:"1",ok:true,action:$action,target:$target,host:$host,state:$state,delivery:$delivery,data:$data}'
}

organ_emit_error() {
  jq -cn --arg action "$1" --arg target "$2" --arg host "$3" \
    --arg code "$4" --arg message "$5" \
    '{schema_version:"1",ok:false,action:$action,target:$target,host:$host,state:"unknown",delivery:"not-applicable",error:{code:$code,message:$message}}'
}
```

`organ_target_get` must validate alias syntax, `schema_version == "1"`, absolute `cwd`, transport/host pairs, mode-specific fields, and `provider == "cc"` for managed targets. It must return exit 64 for invalid/missing configuration.

Default `ORGAN_CONFIG` to `${XDG_CONFIG_HOME:-$HOME/.config}/organoun/targets.json` and `ORGAN_STATE_HOME` to `${XDG_STATE_HOME:-$HOME/.local/state}/organoun`. `bin/organ` must resolve `${BASH_SOURCE[0]}` through `readlink -f`, locate its repository/share root without relying on `$PWD`, source the Task 1 libraries from that deterministic root, implement `list --json`, and emit `TARGET_NOT_FOUND` for commands that name an unknown alias. Later tasks add libraries and action handlers explicitly.

- [ ] **Step 4: Run config and syntax checks**

Run: `bash -n bin/organ lib/organ/common.sh lib/organ/config.sh tests/helpers.sh tests/test_config.sh`

Expected: exit 0.

Run: `bash tests/test_config.sh`

Expected: PASS with three targets and structured `TARGET_NOT_FOUND`.

- [ ] **Step 5: Add the deterministic runner**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for test_file in "$root"/tests/test_*.sh; do
  printf '==> %s\n' "${test_file##*/}"
  bash "$test_file"
done
```

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bin lib config tests
git commit -m "feat: add Organoun CLI and target registry"
```

---

### Task 2: Pinned Outsourcerer Dependency and Local Read Path

**Files:**
- Create: `vendor/outsourcerer.lock.json`
- Create: `scripts/install-outsourcerer.sh`
- Create: `lib/organ/outsourcerer.sh`
- Create: `lib/organ/local.sh`
- Create: `tests/fixtures/fake-outsourcerer.sh`
- Create: `tests/fixtures/fake-tmux.sh`
- Create: `tests/test_dependency.sh`
- Create: `tests/test_read.sh`
- Modify: `bin/organ`
- Modify: `tests/run.sh`

**Interfaces:**
- Consumes: `organ_target_get`, `organ_emit_ok`, `organ_emit_error` from Task 1.
- Produces: `organ_osrc ACTION TARGET_JSON PAYLOAD_FILE` → normalized adapter JSON.
- Produces: `organ_local ACTION TARGET_JSON PAYLOAD_FILE` → public response JSON.
- Produces: `organ_route ACTION TARGET_JSON PAYLOAD_FILE OPTIONS_JSON` → local transport in this task and the SSH branch added in Task 6.
- Produces: `ORGAN_OUTSOURCERER`, `ORGAN_OUTSOURCERER_LOCK`, and `ORGAN_TMUX` overrides for tests and nonstandard installations.

- [ ] **Step 1: Write failing list/status/read tests with a fake adapter**

The fake script must append NUL-safe quoted arguments to `$ORGAN_FAKE_LOG` and respond to exact command shapes:

```bash
case "$*" in
  "fleet ls --json") printf '%s\n' '{"items":[{"session_id":"cc-1","state":"working"}]}' ;;
  "fleet show cc-1 --json") printf '%s\n' '{"session_id":"cc-1","state":"idle","cwd":"$ORGANOUN_PROJECT_ROOT"}' ;;
  "session read --state") printf '%s\n' '{"state":"idle","evidence":"Claude ready"}' ;;
  *) printf 'unexpected fake call: %s\n' "$*" >&2; exit 70 ;;
esac
```

In `tests/test_read.sh`, set `ORGAN_OUTSOURCERER` and `ORGAN_TMUX` to the fakes and assert:

- adopted target with `claude_session_id` calls `fleet show`;
- an adopted target without a session ID uses only the exact configured `tmux_target` fallback;
- excerpts longer than 64 KiB are truncated and carry `data.truncated == true`;
- raw peer output appears only under `data.excerpt`.

In `tests/test_dependency.sh`, create a temporary local Git repository containing the expected relative script and a temporary lockfile selected through `ORGAN_OUTSOURCERER_LOCK`. Assert that dry run prints the exact destination and creates nothing; `--apply` installs the exact fixture commit; a second identical apply is idempotent; an existing destination with a different HEAD is refused. The hermetic suite never clones GitHub.

- [ ] **Step 2: Verify the read tests fail**

Run: `bash tests/test_dependency.sh && bash tests/test_read.sh`

Expected: FAIL because the lock installer, local adapter, and action branches do not exist.

- [ ] **Step 3: Lock and install the upstream dependency**

Create `vendor/outsourcerer.lock.json`:

```json
{
  "repository": "https://github.com/alexgreensh/outsourcerer.git",
  "tag": "v0.8.2",
  "commit": "3a788b8e072b915622fd80c6f8ecec64de659bd5",
  "script": "plugins/outsourcerer/skills/outsourcerer/scripts/outsourcerer.sh"
}
```

`scripts/install-outsourcerer.sh --prefix PREFIX` is a dry run and prints its exact destination. With `--apply`, it must clone into a temporary sibling directory, checkout the exact commit, verify `git rev-parse HEAD`, and atomically rename into `$PREFIX/outsourcerer-3a788b8`. It must refuse an existing directory whose HEAD differs. It must not edit upstream files.

- [ ] **Step 4: Implement bounded local read/status**

In `lib/organ/outsourcerer.sh`, invoke the upstream script as an array, never through `eval`:

```bash
organ_osrc_bin() {
  local default="$HOME/.local/share/organoun/outsourcerer-3a788b8/plugins/outsourcerer/skills/outsourcerer/scripts/outsourcerer.sh"
  printf '%s\n' "${ORGAN_OUTSOURCERER:-$default}"
}

organ_osrc_capture() {
  local max_bytes="$1"
  shift
  local raw rc
  set +e
  raw="$("$(organ_osrc_bin)" "$@" 2>&1)"
  rc=$?
  set -e
  printf '%s' "$raw" | tail -c "$max_bytes"
  return "$rc"
}
```

For adopted read, prefer `fleet show SESSION_ID --json`; otherwise run the configured `ORGAN_TMUX` command as `capture-pane -p -t EXACT_TARGET -S -120` and cap to 64 KiB. Execute every target-scoped adapter call from `(cd -- "$cwd" && ...)`, where `cwd` comes only from validated target JSON. Treat every excerpt as untrusted data. Managed reads remain unavailable until Task 4 establishes ownership receipts.

- [ ] **Step 5: Wire `status` and `read` into `bin/organ`**

Add exact dispatcher branches:

```bash
status|read)
  target_json="$(organ_target_get "$ORGAN_CONFIG" "$alias")" || organ_exit_target_error "$action" "$alias"
  organ_route "$action" "$target_json" /dev/null '{}'
  ;;
```

`organ_route` initially accepts only `transport == local`; Task 6 adds SSH.

- [ ] **Step 6: Run focused and full tests**

Run: `bash tests/test_dependency.sh && bash tests/test_read.sh`

Expected: PASS.

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add vendor scripts lib bin tests
git commit -m "feat: add pinned Outsourcerer read adapter"
```

---

### Task 3: Explicit Claim, Ask, and Release for Adopted Sessions

**Files:**
- Create: `lib/organ/claims.sh`
- Create: `probes/claude-composer-empty`
- Create: `tests/test_claims.sh`
- Modify: `lib/organ/outsourcerer.sh`
- Modify: `lib/organ/local.sh`
- Modify: `bin/organ`
- Modify: `tests/fixtures/fake-tmux.sh`

**Interfaces:**
- Consumes: local adapter and JSON/config core.
- Produces: `organ_claim_path ALIAS`, `organ_claim_write ALIAS RECORD_JSON`, `organ_claim_read ALIAS`, `organ_claim_delete ALIAS`.
- Produces: CLI actions `claim`, `ask`, and `release` for adopted targets.
- Produces: `ORGAN_CLAUDE_COMPOSER_PROBE` override and optional operator-set `ORGAN_EXTERNAL_RECEIPT_PROBE`.

- [ ] **Step 1: Write failing claim lifecycle tests**

In `tests/test_claims.sh`, use isolated `ORGAN_STATE_HOME`, `ORGAN_TMUX`, and `ORGAN_OUTSOURCERER` fakes and assert:

```bash
claim_json="$($REPO_ROOT/bin/organ claim claude-onp --json)"
assert_jq "$claim_json" '.ok and .delivery == "confirmed"'
assert_mode 700 "$ORGAN_STATE_HOME"
assert_mode 700 "$ORGAN_STATE_HOME/claims"
assert_mode 600 "$ORGAN_STATE_HOME/claims/claude-onp.json"
if printf '%s' "$claim_json" | grep -q 'secret-claim-token'; then
  fail "public claim response leaked token"
fi

reply_json="$(printf 'Qual commit você gerou?' | $REPO_ROOT/bin/organ ask claude-onp --stdin --json)"
assert_jq "$reply_json" '.delivery == "unknown"'

release_json="$($REPO_ROOT/bin/organ release claude-onp --json)"
assert_jq "$release_json" '.ok == true'
assert_not_exists "$ORGAN_STATE_HOME/claims/claude-onp.json"
```

Also assert: managed target rejects `claim`; `ask` without a claim fails; 16,385-byte input fails before the adapter runs; an unavailable/busy composer blocks before typing; a send without a receipt returns `delivery=unknown` and makes exactly one adapter call; an explicitly configured valid fake receipt maps to `delivery=confirmed`.

- [ ] **Step 2: Verify the tests fail**

Run: `bash tests/test_claims.sh`

Expected: FAIL because claim storage/actions do not exist.

- [ ] **Step 3: Implement private claim storage**

`lib/organ/claims.sh` must reject aliases outside `[A-Za-z0-9._-]+`, create directories with `umask 077`, write through a temporary file in the same directory, `chmod 600`, and rename atomically.

The stored JSON shape is exact:

```json
{
  "schema_version": "1",
  "alias": "claude-onp",
  "external_id": "claude-onp",
  "controller_id": "organ:claude-onp",
  "endpoint": "tmux:1.3",
  "token": "secret-claim-token"
}
```

- [ ] **Step 4: Implement adapter claim/ask/release**

For `claim`, set `OSRC_EXTERNAL_SEND=1` and `OSRC_CONTROLLER_ID=organ:ALIAS` only on the child process and call `session claim "$alias" "$tmux_target"`. Parse only the `claim token:` line, combine it with the configured endpoint and external ID, write the private record, and redact the token from output. The upstream generation remains in Outsourcerer's owner record; do not scrape or duplicate that internal field.

`probes/claude-composer-empty` accepts exactly one validated tmux pane. It invokes `${ORGAN_TMUX:-tmux}`, captures the pane without sending keys, and prints `empty` only when the final Claude prompt line is an empty `❯`, whitespace-only `❯`, or the known dimmed `❯ Try …` suggestion; every other state prints `unknown`. Set its absolute installed path as `OSRC_EXTERNAL_COMPOSER_PROBE` only on the `session reply` child. If `ORGAN_EXTERNAL_RECEIPT_PROBE` is explicitly set, require an executable absolute path and pass it as `OSRC_EXTERNAL_RECEIPT_PROBE`; otherwise leave that variable unset.

For `ask`, capture stdin to a private temp file, check `wc -c <= 16384`, load the claim, and call:

```bash
OSRC_EXTERNAL_SEND=1 \
OSRC_CONTROLLER_ID="$controller_id" \
OSRC_SESSION_CLAIM_TOKEN="$token" \
OSRC_EXTERNAL_COMPOSER_PROBE="$composer_probe" \
"$(organ_osrc_bin)" session reply "$alias" "$(<"$payload_file")"
```

Pass the message as one quoted argument. Map `receipt:` to `delivery=confirmed`, a composer refusal before typing to `delivery=blocked`, and upstream `delivery unknown` after typing to `delivery=unknown`. Never infer confirmation from `tmux send-keys`, and never call again; the next allowed action is observational `read`.

For `release`, call upstream with the same scoped environment and delete local claim state only after confirmed release.

- [ ] **Step 5: Run security and regression tests**

Run: `bash tests/test_claims.sh`

Expected: PASS, including mode and one-call assertions.

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bin lib/organ/claims.sh lib/organ/outsourcerer.sh lib/organ/local.sh probes/claude-composer-empty tests/test_claims.sh tests/fixtures/fake-outsourcerer.sh tests/fixtures/fake-tmux.sh
git commit -m "feat: add explicit adopted-session claims"
```

---

### Task 4: Managed Claude Session and Read-Mode Dispatch

**Files:**
- Create: `lib/organ/sessions.sh`
- Create: `lib/organ/jobs.sh`
- Create: `tests/test_dispatch.sh`
- Modify: `lib/organ/outsourcerer.sh`
- Modify: `lib/organ/local.sh`
- Modify: `bin/organ`
- Modify: `tests/fixtures/fake-tmux.sh`

**Interfaces:**
- Produces: `organ_job_create RECEIPT_JSON`, `organ_job_read JOB_ID`, `organ_job_update JOB_ID PATCH_JSON`.
- Produces: `organ_job_host JOB_ID` and `organ_job_route ACTION JOB_ID OPTIONS_JSON` with strict local/`$ORGANOUN_REMOTE_HOST` prefixes.
- Produces: `organ_session_write ALIAS RECORD_JSON`, `organ_session_read ALIAS`, `organ_session_assert_owned ALIAS`, and `organ_session_delete ALIAS`.
- Produces: `dispatch --mode read`, managed `status`, managed `read`, and managed `stop`.
- Produces: job IDs matching `(local|$ORGANOUN_REMOTE_HOST)\.job-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}`.

- [ ] **Step 1: Write failing managed-session tests**

In `tests/test_dispatch.sh`, force `ORGAN_TMUX` and `ORGAN_OUTSOURCERER` to the hermetic fakes—never the user's live tmux server—and assert that:

- `printf 'Mapeie a autenticação.' | organ dispatch claude-managed --mode read --stdin --json` starts provider `cc`, sets `OUTSOURCERER_TMUX=organoun-local`, and sends the prompt exactly once;
- target with explicit `model: "fable"` adds `-m fable`; target with `model: null` adds no model flag;
- provider other than `cc` is rejected before adapter execution;
- a newly created managed session gets a mode-`0600` ownership receipt; a valid receipt allows reuse and `stop`;
- a preexisting same-name tmux session without a valid receipt returns `MANAGED_SESSION_COLLISION` and receives neither send nor stop;
- a changed pane PID/start identity invalidates a stale receipt; `stop claude-onp` returns `ADOPTED_SESSION_CANNOT_STOP`;
- readiness polling is bounded and never sends while state is still starting/working;
- send without an independent receipt is returned as `delivery=unknown`, not `confirmed`, and is never retried;
- job receipt is mode `0600` and excludes the prompt;
- local dispatch returns a `local.job-*` receipt and rejects unqualified/unknown-host job IDs;
- `status` reads state but never invokes a verification command.

- [ ] **Step 2: Verify the tests fail**

Run: `bash tests/test_dispatch.sh`

Expected: FAIL because managed dispatch/jobs do not exist.

- [ ] **Step 3: Implement private job receipts**

Use `umask 077`, atomic rename, and schema validation. A read-mode receipt must contain:

```json
{
  "schema_version": "1",
  "job_id": "local.job-20260816T120000Z-a1b2c3d4",
  "target": "claude-managed",
  "host": "local",
  "mode": "read",
  "session_name": "organoun-local",
  "state": "working",
  "artifacts": []
}
```

- [ ] **Step 4: Implement native Claude managed dispatch**

Create managed-session records atomically under `$ORGAN_STATE_HOME/sessions`. The exact minimum shape is:

```json
{
  "schema_version": "1",
  "alias": "claude-managed",
  "host": "local",
  "session_name": "organoun-local",
  "cwd": "$ORGANOUN_PROJECT_ROOT",
  "pane_id": "%12",
  "pane_pid": 12345,
  "pid_start": "linux-proc-start-marker"
}
```

Serialize lifecycle operations with a private per-alias lock. The adapter sequence is:

1. If an ownership receipt exists, validate session name, cwd, pane ID, pane PID, and process start identity. Reuse only a valid owned session.
2. Without a receipt, require that the exact tmux session name does not exist, then run from the validated cwd with `OUTSOURCERER_TMUX="$session_name" "$(organ_osrc_bin)" --provider cc session start`; place `-m "$model"` before `session start` only when configured.
3. Treat the pinned upstream collision message as failure even if its exit code is zero. Record ownership only after the start output indicates a new launch and the new pane identity is readable.
4. Poll `session read --state` at most 20 times with a one-second interval. If readiness is not observed, return `SESSION_NOT_READY` without sending; keep the valid ownership receipt so a later dispatch can reuse it.
5. Create the private job receipt, then run `session send "$message"` exactly once.
6. Map an independently verified receipt to `delivery=confirmed`; map the upstream “keys delivered, not independently verified” outcome to `delivery=unknown`. Persist that delivery state and never retry.

Do not infer a model, provider, or ownership. Do not fall back to another provider. Every Outsourcerer call runs under `(cd -- "$cwd" && ...)`.

- [ ] **Step 5: Wire managed status/read/stop**

`status` and `read` call `session read --state` only after a managed ownership receipt validates. If neither receipt nor tmux session exists, `status` returns `stopped`; if the name exists without valid ownership, it returns a collision. `stop` calls `session stop` only for `mode == managed` and a still-valid receipt, then deletes that receipt after confirmed stop. A stale receipt or name collision fails closed. `status` may update observed state in a job receipt but must not execute `verify`.

- [ ] **Step 6: Run focused and full tests**

Run: `bash tests/test_dispatch.sh`

Expected: PASS.

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add bin lib tests
git commit -m "feat: add managed Claude dispatch lifecycle"
```

---

### Task 5: Guarded Edit Dispatch, Explicit Verify, and Artifacts

**Files:**
- Create: `lib/organ/guard.sh`
- Create: `lib/organ/artifacts.sh`
- Create: `tests/test_guard.sh`
- Create: `tests/test_artifacts.sh`
- Modify: `lib/organ/jobs.sh`
- Modify: `lib/organ/local.sh`
- Modify: `bin/organ`

**Interfaces:**
- Produces: `organ_guard_prepare WORKTREE ALLOW_JSON VERIFY_COMMAND` → base SHA and normalized scope JSON.
- Produces: `organ_guard_verify JOB_JSON` → `{accepted,changed_paths,verify_exit,verify_output}`.
- Produces: CLI actions `dispatch --mode edit`, `verify JOB_ID`, and `fetch JOB_ID ARTIFACT_ID`.

- [ ] **Step 1: Write failing guard-rail tests in a real temporary Git repository**

`tests/test_guard.sh` must initialize a fixture repo, commit `src/value.txt` and `tests/value_test.sh`, and create a separate worktree. Cover these cases:

```bash
printf 'change value' | "$REPO_ROOT/bin/organ" dispatch claude-managed \
  --mode edit \
  --worktree "$worktree" \
  --allow src \
  --verify 'bash tests/value_test.sh' \
  --stdin --json
```

Assertions:

- relative `--allow src` is accepted; absolute allow and `../src` are rejected;
- worktree must be absolute, clean, and belong to a Git repository;
- receipt captures base SHA, worktree, `allow:["src"]`, and verify command but not the prompt;
- a diff only under `src/` plus passing verification yields `accepted`;
- a diff under `tests/` without `--allow tests` yields `blocked-scope` and does not run verification;
- an untracked file outside the allowed paths also yields `blocked-scope`;
- a failing verification yields `blocked-verification`;
- calling `status` never creates the verification marker;
- calling `verify` twice returns the stored terminal result and does not rerun the command;
- no failure triggers a second dispatch.

- [ ] **Step 2: Verify guard tests fail**

Run: `bash tests/test_guard.sh`

Expected: FAIL because edit preparation and verify do not exist.

- [ ] **Step 3: Implement edit preflight and receipt**

Normalize every allowed path by rejecting empty, absolute, `.` and any component equal to `..`. Record `git -C WORKTREE rev-parse HEAD` before sending. Refuse a dirty worktree at dispatch time.

The edit receipt extends Task 4 with:

```json
{
  "mode": "edit",
  "base_sha": "40-hex-git-sha",
  "worktree": "/absolute/worktree",
  "allow": ["src"],
  "verify_command": "bash tests/value_test.sh",
  "verification": null
}
```

The worker prompt must include the absolute worktree and allowed relative paths, but Organoun must still enforce them after return.

- [ ] **Step 4: Implement explicit `organ verify JOB_ID`**

Verification order is fixed:

1. Load a private edit receipt in nonterminal state.
2. Build a NUL-delimited union of `git -C "$worktree" diff --name-only -z "$base_sha" --` and `git -C "$worktree" ls-files --others --exclude-standard -z`; do not lose untracked files or split unusual filenames on whitespace/newlines.
3. Reject any changed path not exactly equal to an allowed path or nested below the allowed path plus `/`; plain string-prefix matches are insufficient.
4. Only then execute `(cd -- "$worktree" && bash -lc "$verify_command")`; never interpolate either value into generated shell source.
5. Persist `accepted`, `blocked-scope`, or `blocked-verification`, captured exit code, and output capped to 64 KiB.
6. On a terminal receipt, return the stored result without executing again.

- [ ] **Step 5: Write failing artifact containment tests**

In `tests/test_artifacts.sh`, verify an accepted edit job that changed one regular file under the authorized worktree and assert:

- verification creates an opaque `artifact-*` ID that does not contain the relative path;
- `fetch JOB_ID ARTIFACT_ID --stdout` returns its exact bytes;
- JSON mode returns host, relative path, byte size, and commit when present;
- `../secret`, symlink escape, undeclared artifact ID, and file over the configured fetch cap are rejected;
- remote artifacts remain host-qualified; Task 6 supplies transport.

- [ ] **Step 6: Implement artifact manifests and fetch**

After an edit is accepted, generate manifest entries only for changed regular files under the allowed scope. Derive an opaque `artifact-<12hex>` ID from the job ID plus NUL-separated relative path, and store the mapping privately in the job receipt. For fetch, resolve with `realpath -e`, require the resolved path to start with `realpath -e AUTHORIZED_ROOT/`, reject symlinks whose target escapes, and read only artifact IDs present in that exact job receipt. Never accept a raw path directly from the CLI, and never expose artifacts from an unaccepted job.

- [ ] **Step 7: Run focused and full tests**

Run: `bash tests/test_guard.sh && bash tests/test_artifacts.sh`

Expected: PASS.

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add bin lib tests
git commit -m "feat: add guarded edit verification and artifacts"
```

---

### Task 6: Tailscale SSH Transport and Remote Helper

**Files:**
- Create: `lib/organ/ssh.sh`
- Create: `remote/organ-remote`
- Create: `tests/fixtures/fake-ssh.sh`
- Create: `tests/test_ssh.sh`
- Modify: `bin/organ`
- Modify: `lib/organ/artifacts.sh`

**Interfaces:**
- Consumes: normalized local action functions from Tasks 2–5.
- Produces: `organ_ssh ACTION ROUTE_JSON PAYLOAD_FILE OPTIONS_JSON` → the same public JSON contract as local transport; `ROUTE_JSON` is either a validated target or the fixed route produced from a validated job ID.
- Produces: remote helper request schema `{schema_version,action,alias?,options,payload}`; `verify`/`fetch` carry `options.job_id` and no target alias.
- Produces: fixed default remote command `~/.local/libexec/organoun/organ-remote`; `ORGAN_REMOTE_HELPER` may override it only for hermetic tests/operator configuration and is never read from a prompt.

- [ ] **Step 1: Write failing transport protocol tests**

`tests/test_ssh.sh` must use `ORGAN_SSH=$REPO_ROOT/tests/fixtures/fake-ssh.sh` and assert:

- only host `$ORGANOUN_REMOTE_HOST` is passed to SSH;
- payload containing quotes, newlines, `$()`, and backticks arrives as inert JSON text;
- remote request actions are allowlisted to `status`, `read`, `claim`, `ask`, `dispatch`, `verify`, `fetch`, `release`, and `stop`;
- local target never invokes SSH;
- a failed read-only request with no helper response returns `state=unreachable`;
- any mutating SSH request that lacks a complete valid helper response returns `delivery=unknown`, even if the connection appears to have failed early, and never retries;
- remote claim token is stored only on the remote fake state path and absent from local output/state;
- remote dispatch returns an `$ORGANOUN_REMOTE_HOST.job-*` ID; `verify $ORGANOUN_REMOTE_HOST.job-*` uses SSH exactly once, while `verify local.job-*` never uses SSH;
- unqualified job IDs, unknown host prefixes, and a job prefix that disagrees with the target host are rejected before adapter execution;
- remote `fetch $ORGANOUN_REMOTE_HOST.job-* ARTIFACT_ID` streams only the artifact declared by that exact accepted job.

- [ ] **Step 2: Verify the tests fail**

Run: `bash tests/test_ssh.sh`

Expected: FAIL because SSH transport/helper do not exist.

- [ ] **Step 3: Implement JSON stdin transport**

Capture payload bytes to a file and construct the envelope without shell interpolation:

```bash
jq -cn \
  --arg action "$action" \
  --arg alias "$alias" \
  --argjson options "$options_json" \
  --rawfile payload "$payload_file" \
  '({schema_version:"1",action:$action,options:$options,payload:$payload}
    + (if $alias == "" then {} else {alias:$alias} end))' \
  | "$ssh_bin" -T -o BatchMode=yes -o ConnectTimeout=10 -- $ORGANOUN_REMOTE_HOST "$remote_helper"
```

`remote_helper` is a fixed installation path selected by the operator, never supplied by a prompt or payload. SSH necessarily passes that one fixed path as its remote command; never append action, alias, options, or payload to the command string. All variable request data travels only in the JSON document on stdin.

Require one complete schema-valid JSON response from the helper. A transport failure without that response is `unreachable` only for observational actions; for every mutating action it is conservatively `delivery=unknown`, because the client cannot prove the helper did not execute it.

- [ ] **Step 4: Implement `remote/organ-remote`**

The helper reads one JSON document from stdin and applies action-dependent validation. Target actions require an allowlisted alias and are resolved again from the remote `targets.json`; `verify` and `fetch` require an `$ORGANOUN_REMOTE_HOST.job-*` value in `options.job_id`, and `fetch` additionally requires an opaque artifact ID. It writes payload to a private temp file and calls the same local action functions with `ORGAN_REMOTE_MODE=1`. It must reject nested SSH transport to prevent recursion.

Claims, session ownership receipts, and jobs remain under remote `~/.local/state/organoun`. For `verify/fetch`, worktree and artifacts are resolved on the remote host. `organ_job_route` parses the job host before transport selection; the helper independently requires `$ORGANOUN_REMOTE_HOST.job-*` for remote job actions and rejects any other host prefix.

- [ ] **Step 5: Run protocol, injection, and regression tests**

Run: `bash tests/test_ssh.sh`

Expected: PASS.

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add bin lib/organ/ssh.sh lib/organ/artifacts.sh remote tests
git commit -m "feat: add Organoun $ORGANOUN_REMOTE_HOST transport"
```

---

### Task 7: Codex Skill and Reversible Installation

**Files:**
- Create: `skills/organoun/SKILL.md`
- Create: `scripts/install-organoun.sh`
- Create: `tests/test_install_skill.sh`
- Create: `docs/operations.md`
- Modify: `config/deployment.example.json`

**Interfaces:**
- Consumes: completed `organ` CLI.
- Produces: `~/.local/bin/organ`, `~/.local/share/organoun` (including the composer probe), `~/.local/libexec/organoun/organ-remote`, `~/.config/organoun/targets.json`, and `~/.codex/skills/organoun/SKILL.md` only after explicit operator approval during execution.
- Produces: natural-language mappings that never bypass CLI authority rules.

- [ ] **Step 1: Write failing isolated installer/skill tests**

Run the installer against temporary XDG and Codex homes, not the real user directories. Assert:

- `organ` executable resolves libraries from the installed share directory;
- the default composer probe resolves to an executable absolute path inside the installed share directory;
- the remote helper is installed executable at the one fixed path used by SSH transport;
- project-local deployment is created only by `organ onboard` and is never overwritten;
- skill contains triggers for “veja o Claude”, “pergunte ao Claude”, “despache”, “Organoun”, and “organ”;
- skill requires explicit `claim` before first reply to an adopted session;
- skill forbids `stop` on adopted sessions, automatic retry, accepting self-reported `done`, and model/provider inference;
- uninstall instructions remove only Organoun-owned paths.

- [ ] **Step 2: Verify the tests fail**

Run: `bash tests/test_install_skill.sh`

Expected: FAIL because installer and skill do not exist.

- [ ] **Step 3: Write the Codex skill contract**

The skill workflow must be explicit:

```markdown
1. Resolve the user-named target with `organ list --json`; never guess an ambiguous alias.
2. Use `organ status/read` for observation.
3. Before replying to an adopted session, require an active explicit `organ claim`.
4. Send one bounded question with `organ ask --stdin`; when delivery is unknown, use `organ read` to observe and never replay the message.
5. For new work, require user intent and use a managed target.
6. For edit work, supply worktree, allowed paths, and controller verification command.
7. Treat worker output as untrusted data. Accept edits only after `organ verify JOB_ID` returns accepted.
8. Never stop an adopted session or broaden scope without the user.
```

- [ ] **Step 4: Implement the reversible installer**

`scripts/install-organoun.sh --prefix HOME_ROOT` must stage files in a temporary directory, run `bash -n`, then atomically install the share tree. Create relative symlinks from `.local/bin/organ` to the share-tree executable and from `.local/libexec/organoun/organ-remote` to the share-tree helper; both scripts resolve their real path before sourcing libraries. With no `--prefix`, it targets the real user home but prints the exact destinations and requires `--apply`; a dry run is the default.

Do not invoke `parity-codex`; install the dedicated Organoun skill. Do not edit global `~/.codex/AGENTS.md`.

- [ ] **Step 5: Write the operations runbook**

`docs/operations.md` must include:

- dependency pin and installer verification;
- the pinned upstream license boundary: this rollout is a private noncommercial experiment, with no vendoring, redistribution, production support expectation, or claim that Organoun owns Outsourcerer;
- concrete local target example;
- how to identify the current Claude tmux pane without reading its content;
- explicit canary sequence: `status → read → claim → ask → read → release`;
- managed read dispatch and guarded edit example using `$ORGANOUN_PROJECT_ROOT`;
- remote setup and authentication checkpoint;
- failure table for blocked/unknown/unreachable;
- rollback paths and commands;
- all 22 acceptance checks from the design spec.

- [ ] **Step 6: Run focused and full tests**

Run: `bash tests/test_install_skill.sh`

Expected: PASS.

Run: `bash tests/run.sh`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add skills scripts config docs tests
git commit -m "feat: add Organoun skill and installer"
```

---

### Task 8: Local and `$ORGANOUN_REMOTE_HOST` Smoke Tests

**Files:**
- Create: `scripts/smoke-local.sh`
- Create: `scripts/smoke-remote.sh`
- Modify: `docs/operations.md`
- Test: full `tests/run.sh` plus operator-observed smoke commands.

**Interfaces:**
- Consumes: completed CLI, skill, installers, pinned dependency, and remote helper.
- Produces: machine-readable smoke summaries `ORGAN_LOCAL_SMOKE_OK` and `ORGAN_ASVERAS_SMOKE_OK` without exposing session names, IDs, IPs, tokens, or transcript content.

- [ ] **Step 1: Write the local smoke script in non-mutating mode**

The default script checks commands and configuration only:

```bash
#!/usr/bin/env bash
set -euo pipefail
command -v jq >/dev/null
command -v tmux >/dev/null
command -v claude >/dev/null
command -v organ >/dev/null
organ list --json | jq -e '.ok == true' >/dev/null
organ status claude-onp --json | jq -e '.ok == true or .state == "unknown"' >/dev/null
printf 'ORGAN_LOCAL_SMOKE_OK\n'
```

Mutation requires `--canary`; that mode prints the exact target and waits for the operator before `claim/ask/release`.

- [ ] **Step 2: Run all hermetic tests before touching user state**

Run: `bash tests/run.sh`

Expected: every test PASS.

Run: `find bin lib probes remote scripts tests -type f \( -name '*.sh' -o -path 'bin/organ' -o -path 'probes/claude-composer-empty' -o -path 'remote/organ-remote' \) -print0 | xargs -0 -r bash -n`

Expected: exit 0.

- [ ] **Step 3: Install locally with explicit approval and run read-only smoke**

Run first: `scripts/install-organoun.sh`

Expected: dry-run list of destinations; no writes.

After operator approval, run: `scripts/install-organoun.sh --apply`

Then configure the exact current target and run: `scripts/smoke-local.sh`

Expected: `ORGAN_LOCAL_SMOKE_OK`.

- [ ] **Step 4: Run the operator-observed local canary**

Run: `scripts/smoke-local.sh --canary`

Expected sequence: exact target shown; one canary arrives; response is readable; `release` removes claim; a later `ask` is refused.

- [ ] **Step 5: Install Claude Code on `$ORGANOUN_REMOTE_HOST` with the operator present**

Use the current official Anthropic Linux installer documented at `https://code.claude.com/docs/en/quickstart`:

```bash
ssh -t $ORGANOUN_REMOTE_HOST 'curl -fsSL https://claude.ai/install.sh | bash -s stable'
ssh -t $ORGANOUN_REMOTE_HOST 'claude'
```

The second command is the user-controlled interactive login. Do not copy local Claude credentials to the VPS.

- [ ] **Step 6: Install pinned Outsourcerer, Organoun, and remote config on `$ORGANOUN_REMOTE_HOST`**

Package only committed Organoun files with `git archive`, name the archive with the current commit, compute its SHA-256, and copy that single archive to `$ORGANOUN_REMOTE_HOST:/tmp/` with `scp` after operator approval. On the VPS, verify the checksum, extract into a new commit-qualified directory under `~/.local/src/organoun/`, and refuse an existing directory with different contents. Do not sync the working tree or user state.

From that extracted directory, run both installers in dry-run mode, inspect destinations, then rerun with their explicit apply flags. Configure only alias, `host: $ORGANOUN_REMOTE_HOST`, remote absolute cwd, provider `cc`, and managed session name. Confirm the installed helper is exactly `~/.local/libexec/organoun/organ-remote`, the fixed command used by SSH transport. Keep claims, session receipts, and jobs on the VPS.

- [ ] **Step 7: Write and run remote read-only smoke**

`scripts/smoke-remote.sh` must call `organ status remote-managed --json`, require either a valid observed state or `unknown`, and print only:

```text
ORGAN_ASVERAS_SMOKE_OK
```

No session identifiers, IPs, tokens, or transcript data may be printed by the summary.

- [ ] **Step 8: Run the remote managed canary and failure checks**

With the operator present:

1. Dispatch one read-only prompt: “Responda exatamente ORGANOUN_REMOTE_OK”.
2. Read the exact response.
3. Simulate an unreachable SSH command and confirm `state=unreachable` with no local fallback.
4. Simulate an ambiguous send using the fake transport only; confirm no retry.
5. Stop only the Organoun-created remote session.

Expected: remote result arrives without manual copy/paste and no protected data appears in output.

- [ ] **Step 9: Run the complete acceptance audit**

Walk all 22 design-spec acceptance checks in `docs/operations.md`. Record each as PASS with the exact command/output evidence or leave the experiment incomplete. Do not infer completion from the hermetic suite alone.

- [ ] **Step 10: Commit smoke tooling and verified runbook updates**

```bash
git add scripts/smoke-local.sh scripts/smoke-remote.sh docs/operations.md
git commit -m "test: add Organoun local and $ORGANOUN_REMOTE_HOST smoke gates"
```

---

## Spec Coverage Matrix

| Design requirement | Implementation and evidence |
|---|---|
| Stable `organ` interface and allowlisted registry | Tasks 1–2; `test_config.sh`, `test_read.sh` |
| Explicit adopted-session claim, canary, and release | Task 3; `test_claims.sh`; Task 8 operator canary |
| Managed Claude `cc` session lifecycle | Task 4; `test_dispatch.sh`; Tasks 7–8 runbook and smoke |
| Guarded edit scope and controller-owned verification | Task 5; `test_guard.sh`; no automatic retry |
| Containment-safe artifact retrieval | Tasks 5–6; `test_artifacts.sh`, `test_ssh.sh` |
| Local/`$ORGANOUN_REMOTE_HOST` parity without public service | Task 6; fixed Tailscale SSH helper and stdin protocol |
| Private host-local state and secret-free public JSON | Tasks 1, 3–6; permission and redaction assertions |
| Reversible installation without upstream modification | Tasks 2 and 7; lockfile, isolated installer test, rollback runbook |
| Preliminary anti-evasion scope: independent proof and diff gate only | Task 5; full AST/mutation/challenge engine explicitly excluded |
| All 22 design acceptance checks | Tasks 7–8; documented command/output evidence per check |

---

## Final Verification

- [ ] Run `bash tests/run.sh`; expect every hermetic test to pass.
- [ ] Run `git diff --check`; expect no output.
- [ ] Run Bash syntax checks across `bin`, `lib`, `probes`, `remote`, `scripts`, and `tests`; expect exit 0.
- [ ] Confirm `git status --short` is empty after the final commit.
- [ ] Confirm the installed Outsourcerer HEAD equals `3a788b8e072b915622fd80c6f8ecec64de659bd5` on each used host.
- [ ] Confirm local and remote smoke summaries without exposing account/session data.
- [ ] Confirm every applicable design acceptance check has direct runtime evidence.
- [ ] Confirm rollback removes only Organoun-owned files and leaves Claude, Codex, tmux sessions, and the upstream repository intact.
