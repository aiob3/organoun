# Organoun Project-Local Deployment Hygiene Implementation Plan

> **For agentic workers:** Execute inline in the visible owner session. Do not dispatch subagents or open panes. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one project-local `organ onboard` the only gateway that records deployment inputs, and make every later `organ init` and parallel effect load and match that deployment.

**Architecture:** A new deployment module owns strict input validation, project-root discovery, local SSH-route resolution, atomic `.gitignore` protection, write-once publication and sanitized receipt generation. Runtime target configuration and state are derived from the project-local deployment; `organ init` binds the owner to its digest, and all later effects reject missing or changed deployments.

**Tech Stack:** Bash 5+, jq 1.7+, Git, OpenSSH client, existing Organoun strict-JSON helpers.

## Global Constraints

- The only order is `onboard → input once → validate route → publish once → connected → init`.
- `organ onboard` never opens a pane, starts Claude, connects to SSH or dispatches work.
- Live remote access remains conditional on `organ init` plus an operator-visible subordinate pane.
- The real values exist only in `<project>/.organoun/deployment.json`, mode `0600`.
- `<project>/.organoun/state/` isolates owner, pane, claim, job and receipt state by project.
- Both local files are automatically ignored; no deployment value enters Git.
- Existing deployment files are never overwritten, replayed or merged.
- No new persistent automated test is created for the write procedure, by explicit operator decision.
- Verification consists of syntax/static inspection followed by one real onboarding execution.
- No real SSH session, remote mutation, hidden panel or parallel worker is allowed during implementation.

---

### Task 1: Implement the write-once deployment boundary

**Files:**
- Create: `lib/organ/deployment.sh`
- Create: `scripts/onboard-organoun.sh`
- Modify: `bin/organ`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: one strict JSON document on stdin.
- Produces: `organ_deployment_onboard INPUT_FILE`, `organ_deployment_path_resolve`, `organ_deployment_snapshot_create`, `organ_deployment_digest`, and the public `organ onboard` action.

- [ ] **Step 1: Add strict deployment validation**

Implement a schema predicate equivalent to:

```jq
type == "object" and
(keys_unsorted | sort) == ["local_project_root","remote_cwd","remote_host","schema_version"] and
.schema_version == "1" and
(.local_project_root | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not)) and
(.remote_host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$")) and
(.remote_cwd | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not))
```

Normalize the original bytes once with `organ_json_normalize_strict`; require the declared root to equal both `pwd -P` and `git rev-parse --show-toplevel`.

- [ ] **Step 2: Add local-only route resolution**

Run exactly one bounded `ssh -G "$remote_host"` resolution with stdout/stderr private. Accept only rc `0`, nonempty normalized hostname output and empty stderr. Do not open a socket and do not retry.

- [ ] **Step 3: Protect and publish the local files**

Update `.gitignore` atomically with exactly:

```gitignore
/.organoun/deployment.json
/.organoun/state/
```

Create `.organoun/` as `0700`, publish the strict normalized deployment by same-directory rename as `0600`, and refuse every pre-existing deployment path.

- [ ] **Step 4: Expose one backend and one assisted frontend**

`organ onboard --stdin --json` reads stdin once and calls the deployment module. `organ onboard` invokes `scripts/onboard-organoun.sh`, which collects the three values once, constructs one JSON object with jq and pipes it once to the backend.

The successful public envelope contains:

```json
{"schema_version":"1","ok":true,"action":"onboard","target":"","host":"","state":"connected","delivery":"not-applicable","data":{"message":"Organoun Connected","write_count":1,"submission_count":1,"config_path":".organoun/deployment.json","gitignored":true}}
```

- [ ] **Step 5: Perform syntax-only verification**

Run:

```bash
bash -n bin/organ lib/organ/deployment.sh scripts/onboard-organoun.sh
git diff --check
```

Expected: both commands exit `0`; no onboarding execution yet.

### Task 2: Make deployment the runtime source of truth

**Files:**
- Modify: `lib/organ/config.sh`
- Modify: `lib/organ/common.sh`
- Modify: `bin/organ`
- Modify: `lib/organ/control.sh`

**Interfaces:**
- Consumes: strict project-local deployment snapshot.
- Produces: in-memory `local-managed` and `remote-managed` targets, project-local state home, and owner `deployment_digest` binding.

- [ ] **Step 1: Remove implicit global configuration and state defaults**

Resolve the Git root once. Default to:

```bash
ORGAN_CONFIG="$project_root/.organoun/deployment.json"
ORGAN_STATE_HOME="$project_root/.organoun/state"
```

O CLI não aceita override de configuração ou estado. Não existe fallback XDG.

- [ ] **Step 2: Derive neutral runtime targets in memory**

Transform the deployment snapshot to:

```jq
{
  schema_version:"1",
  targets:[
    {alias:"local-managed",transport:"local",host:"local",cwd:.local_project_root,mode:"managed",provider:"cc",session_name:"organoun-local",model:null},
    {alias:"remote-managed",transport:"ssh",host:.remote_host,cwd:.remote_cwd,mode:"managed",provider:"cc",session_name:"organoun-remote",model:null}
  ]
}
```

Do not persist this derived registry.

- [ ] **Step 3: Gate `organ init` on a valid deployment**

Before `organ_control_init`, load one immutable deployment snapshot and calculate its SHA-256 digest. Missing, invalid or wrong-root deployment emits `ONBOARD_REQUIRED` and exits `64` before tmux effects.

- [ ] **Step 4: Bind owner and effects to the digest**

Add `deployment_digest` to the owner record. `organ_control_owner_live` compares it with the current immutable snapshot. Reserve, enter, status, read, claim, ask, release, dispatch, stop and close fail closed before effects when the digest is absent or changed.

- [ ] **Step 5: Perform syntax/static verification**

Run:

```bash
bash -n bin/organ lib/organ/common.sh lib/organ/config.sh lib/organ/control.sh
git diff --check
```

Expected: exit `0`; no pane or remote operation occurs.

### Task 3: Remove the laboratory host from routing authority

**Files:**
- Modify: `lib/organ/config.sh`
- Modify: `lib/organ/control.sh`
- Modify: `lib/organ/jobs.sh`
- Modify: `lib/organ/sessions.sh`
- Modify: `bin/organ`
- Modify: `config/deployment.example.json`
- Modify: `scripts/smoke-local.sh`
- Rename: legacy host-specific remote smoke filename to `scripts/smoke-remote.sh`

**Interfaces:**
- Consumes: configured `remote_host` only from the immutable deployment snapshot.
- Produces: neutral routing class `local|remote`; the real host remains a receipt field, never a protocol enum.

- [ ] **Step 1: Replace host enums**

Job IDs use `local.job-*` or `remote.job-*`. Routing branches use the class, while receipts retain the configured host as data. Any safe SSH alias is valid; no specific host string is accepted by code as authority.

- [ ] **Step 2: Quote the configured endpoint command safely**

Build the visible SSH pane command from the already validated host and CWD. Keep endpoint startup in the owned visible pane and preserve the no-remote-control-components rule.

- [ ] **Step 3: Neutralize installable examples and smoke names**

Use only `local-managed`, `remote-managed`, `/absolute/local/project/root`, `operator-selected-ssh-alias` and `/absolute/remote/project/root` in current examples. Historical invalid records remain non-authoritative.

- [ ] **Step 4: Run the hygiene scan once**

Run one repository scan over executable, installable and normative current artifacts. It must return no concrete laboratory host or deployment path outside explicitly invalid historical records.

### Task 4: Align installer, governance and operator documentation

**Files:**
- Modify: `scripts/install-organoun.sh`
- Modify: `docs/operations.md`
- Modify: `skills/organoun/SKILL.md`
- Modify: `.spec/constituicao.md`
- Modify: governed-document metadata carrying the constitutional digest

**Interfaces:**
- Consumes: the approved deployment state machine.
- Produces: runtime installation without real config, installed onboarding frontend, constitution binding to `deployment.local_project_root`, and neutral operational examples.

- [ ] **Step 1: Stop installing a global target registry**

The installer copies the runtime and assisted onboarding script but never writes `~/.config/organoun/targets.json`. Dry-run lists binaries only; configuration begins exclusively with `organ onboard` inside the project.

- [ ] **Step 2: Make the protocol the only documented entrypoint**

Current operational docs and skill begin with:

```text
deployment absent -> organ onboard
deployment valid -> organ init
init valid -> reserve/enter/observe/send/close/release
```

No parallel event is documented before `init`.

- [ ] **Step 3: Migrate the constitutional path binding**

Replace the concrete promotion worktree with the semantic deployment-root reference, increment the constitution version, calculate the canonical self-digest once, and update governed metadata mechanically without changing execution authority.

- [ ] **Step 4: Review the complete diff once**

Run `git diff --check`, shell syntax checks for every modified shell file, and inspect `git diff --stat` plus the full diff. Do not run the historical full test suite.

### Task 5: Await the operator decision about the private repository

**Files:**
- Create locally and ignored: `.organoun/deployment.json`
- Create locally and ignored: `.organoun/state/`
- Inspect locally: `.gitignore`

**Interfaces:**
- Consumes: the operator-provided local project root, remote SSH alias and remote CWD.
- Produces: one sanitized `Organoun Connected` receipt and a deployment ready for the next-window `organ init`.

- [ ] **Step 1: Stop after local hygiene and report the exact checkout state**

Do not onboard, commit, pull, push, change visibility or recreate the repository until the
operator states what will happen to the current private repository.

- [ ] **Step 2: After direction, confirm the deployment root and repository destination**

The chosen repository and checkout must be unambiguous before the one-time deployment input.

- [ ] **Step 3: Run `organ onboard` exactly once only when newly authorized**

Expected public result: rc `0`, `state=connected`, message `Organoun Connected`,
`write_count=1`, `submission_count=1`, and no pane/SSH session.

- [ ] **Step 4: Commit and push only to the repository selected by the operator**

Stage only reviewed source/docs changes, run `git diff --cached --check`, commit on `main`,
pull with `--ff-only` if required, push only to the operator-selected private repository,
and confirm local/remote refs match. Never add `.organoun/deployment.json` or
`.organoun/state/`.

- [ ] **Step 5: Handoff the next-window action**

Report that the next local interaction starts with `organ init --json`. If the deployment is missing for that path, the only allowed recovery is a newly authorized `organ onboard`; no pane or parallel event is created first.
