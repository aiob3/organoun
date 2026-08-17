#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: managed dispatch can infer a provider/model, adopt or stop a
# colliding tmux session, trust stale ownership, replay an uncertain send,
# persist prompts, poll forever, bypass host-qualified jobs, or run verify from
# a read-only status path.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
cwd="$TEST_TMP/target-cwd"
mkdir -p -- "$cwd"
config="$TEST_TMP/targets.json"
jq -cn --arg cwd "$cwd" '
  {schema_version:"1",targets:[
    {alias:"claude-onp",transport:"local",host:"local",cwd:$cwd,mode:"adopted",tmux_target:"tmux:1.3",claude_session_id:null},
    {alias:"claude-managed",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-local",model:null},
    {alias:"claude-fable",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-fable",model:"fable"},
    {alias:"claude-env",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-env",model:null},
    {alias:"claude-false-stop",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-false-stop",model:null},
    {alias:"claude-collision",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-collision",model:null},
    {alias:"claude-upstream-collision",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-upstream-collision",model:null},
    {alias:"claude-slow",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-slow",model:null},
    {alias:"claude-confirmed",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-confirmed",model:null},
    {alias:"claude-serial",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-serial",model:null},
    {alias:"claude-wrong-cwd",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-wrong-cwd",model:null},
    {alias:"claude-wrong-name",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-wrong-name",model:null},
    {alias:"claude-raced",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-raced",model:null},
    {alias:"claude-tmux-error",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-tmux-error",model:null},
    {alias:"claude-stop-error",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-stop-error",model:null},
    {alias:"claude-observe-error",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-observe-error",model:null},
    {alias:"claude-payload",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-payload",model:null},
    {alias:"claude-stopped",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-stopped",model:null}
  ]}' >"$config"

export ORGAN_CONFIG="$config"
export ORGAN_STATE_HOME="$TEST_TMP/private-state"
export ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
export ORGAN_PROC_ROOT="$TEST_TMP/proc"
export ORGAN_SESSION_POLL_INTERVAL=0
export ORGAN_FAKE_LOG="$TEST_TMP/outsourcerer-argv.log"
export ORGAN_FAKE_COMMAND_LOG="$TEST_TMP/outsourcerer-command.log"
export ORGAN_FAKE_ENV_LOG="$TEST_TMP/outsourcerer-env.log"
export ORGAN_FAKE_MANAGED_ENV_LOG="$TEST_TMP/outsourcerer-managed-env.log"
export ORGAN_FAKE_CWD_LOG="$TEST_TMP/outsourcerer-cwd.log"
export ORGAN_FAKE_SEND_LOG="$TEST_TMP/send.log"
export ORGAN_FAKE_TMUX_LOG="$TEST_TMP/tmux.log"
export ORGAN_FAKE_TMUX_STATE_FILE="$TEST_TMP/tmux-state.json"
export ORGAN_FAKE_PANE_ID='%12'
export ORGAN_FAKE_PANE_PID=4242
export ORGAN_FAKE_PID_START=777
mkdir -p -- "$ORGAN_PROC_ROOT"

clear_logs() {
  : >"$ORGAN_FAKE_LOG"
  : >"$ORGAN_FAKE_COMMAND_LOG"
  : >"$ORGAN_FAKE_ENV_LOG"
  : >"$ORGAN_FAKE_MANAGED_ENV_LOG"
  : >"$ORGAN_FAKE_CWD_LOG"
  : >"$ORGAN_FAKE_SEND_LOG"
  : >"$ORGAN_FAKE_TMUX_LOG"
}

write_proc_start() {
  local pid="$1"
  local marker="$2"
  mkdir -p -- "$ORGAN_PROC_ROOT/$pid"
  {
    printf '%s (fake-claude) S' "$pid"
    printf ' 0%.0s' {4..21}
    printf ' %s\n' "$marker"
  } >"$ORGAN_PROC_ROOT/$pid/stat"
}

set_tmux_session() {
  local session_name="$1"
  local session_cwd="$2"
  local pane_id="$3"
  local pane_pid="$4"
  local pid_start="$5"
  jq -cn --arg session_name "$session_name" --arg cwd "$session_cwd" \
    --arg pane_id "$pane_id" --argjson pane_pid "$pane_pid" \
    '{exists:true,session_name:$session_name,cwd:$cwd,pane_id:$pane_id,pane_pid:$pane_pid}' \
    >"$ORGAN_FAKE_TMUX_STATE_FILE"
  write_proc_start "$pane_pid" "$pid_start"
}

set_tmux_absent() {
  jq -cn '{exists:false}' >"$ORGAN_FAKE_TMUX_STATE_FILE"
}

command_count() {
  local command="$1"
  grep -Fxc -- "$command" "$ORGAN_FAKE_COMMAND_LOG" || true
}

clear_logs
set_tmux_absent
actual="$(printf 'Mapeie a autenticação.' | "$REPO_ROOT/bin/organ" dispatch claude-managed --mode read --stdin --json)"
assert_jq "$actual" '.ok == true and .action == "dispatch" and .target == "claude-managed" and .host == "local" and .state == "working" and .delivery == "unknown"'
job_id="$(jq -r '.data.job_id' <<<"$actual")"
[[ "$job_id" =~ ^local\.job-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]] || {
  printf 'invalid local job id: %s\n' "$job_id" >&2
  exit 1
}
assert_eq 1 "$(command_count '--provider cc session start')"
assert_eq 0 "$(command_count '--provider cc -m fable session start')"
assert_eq 1 "$(command_count 'session send Mapeie a autenticação.')"
managed_clean_env='send=<unset> controller=<unset> token=<unset> composer=<unset> receipt=<unset> osrc_provider=<unset> osrc_model=<unset> osrc_default_provider=<unset> osrc_default_model=<unset> provider=<unset> model=<unset> default_provider=<unset> default_model=<unset> claude_model=<unset> anthropic_model=<unset>'
assert_eq "tmux=<organoun-local> $managed_clean_env" "$(sort -u "$ORGAN_FAKE_MANAGED_ENV_LOG")"
assert_eq "$cwd" "$(sort -u "$ORGAN_FAKE_CWD_LOG")"

session_receipt="$ORGAN_STATE_HOME/sessions/claude-managed.json"
job_receipt="$ORGAN_STATE_HOME/jobs/$job_id.json"
assert_mode 700 "$ORGAN_STATE_HOME"
assert_mode 700 "$ORGAN_STATE_HOME/sessions"
assert_mode 700 "$ORGAN_STATE_HOME/jobs"
assert_mode 700 "$ORGAN_STATE_HOME/locks"
assert_mode 600 "$session_receipt"
assert_mode 600 "$job_receipt"
assert_mode 600 "$ORGAN_STATE_HOME/locks/session-claude-managed.lock"
jq -e --arg cwd "$cwd" '
  .schema_version == "1" and .alias == "claude-managed" and .host == "local" and
  .session_name == "organoun-local" and .cwd == $cwd and .pane_id == "%12" and
  .pane_pid == 4242 and .pid_start == "777"
' "$session_receipt" >/dev/null
jq -e --arg id "$job_id" '
  .schema_version == "1" and .job_id == $id and .target == "claude-managed" and
  .host == "local" and .mode == "read" and .session_name == "organoun-local" and
  .state == "working" and .delivery == "unknown" and .artifacts == []
' "$job_receipt" >/dev/null
if grep -Fq 'Mapeie a autenticação.' "$job_receipt"; then
  printf 'job receipt persisted the dispatch prompt\n' >&2
  exit 1
fi

# Reuse a still-owned session: no second start, exactly one new send.
clear_logs
actual="$(printf 'Segunda mensagem.' | "$REPO_ROOT/bin/organ" dispatch claude-managed --mode read --stdin --json)"
assert_jq "$actual" '.ok == true and .delivery == "unknown"'
assert_eq 0 "$(command_count '--provider cc session start')"
assert_eq 1 "$(command_count 'session send Segunda mensagem.')"

# Explicit models are positioned before the session verb; null never implies one.
clear_logs
set_tmux_absent
actual="$(printf 'Use o modelo explícito.' | "$REPO_ROOT/bin/organ" dispatch claude-fable --mode read --stdin --json)"
assert_jq "$actual" '.ok == true'
assert_eq 1 "$(command_count '--provider cc -m fable session start')"
assert_eq 1 "$(command_count 'session send Use o modelo explícito.')"

# A valid ownership receipt authorizes stop and is removed only after confirmation.
clear_logs
actual="$("$REPO_ROOT/bin/organ" stop claude-fable --json)"
assert_jq "$actual" '.ok == true and .state == "stopped"'
assert_eq 1 "$(command_count 'session stop')"
assert_not_exists "$ORGAN_STATE_HOME/sessions/claude-fable.json"

# Managed actions inherit no adopted-session authority or provider/model
# overrides. Start/read/send/stop receive only the explicit managed tmux value.
export OSRC_EXTERNAL_SEND='ambient-send'
export OSRC_CONTROLLER_ID='ambient-controller'
export OSRC_SESSION_CLAIM_TOKEN='ambient-token'
export OSRC_EXTERNAL_COMPOSER_PROBE='/bin/false'
export OSRC_EXTERNAL_RECEIPT_PROBE='/bin/false'
export OSRC_PROVIDER='ambient-provider'
export OSRC_MODEL='ambient-model'
export OSRC_DEFAULT_PROVIDER='ambient-default-provider'
export OSRC_DEFAULT_MODEL='ambient-default-model'
export OUTSOURCERER_PROVIDER='ambient-outsourcerer-provider'
export OUTSOURCERER_MODEL='ambient-outsourcerer-model'
export OUTSOURCERER_DEFAULT_PROVIDER='ambient-outsourcerer-default-provider'
export OUTSOURCERER_DEFAULT_MODEL='ambient-outsourcerer-default-model'
export CLAUDE_MODEL='ambient-claude-model'
export ANTHROPIC_MODEL='ambient-anthropic-model'
clear_logs
set_tmux_absent
printf 'Ambiente limpo.' | "$REPO_ROOT/bin/organ" dispatch claude-env --mode read --stdin --json >/dev/null
"$REPO_ROOT/bin/organ" stop claude-env --json >/dev/null
unset OSRC_EXTERNAL_SEND OSRC_CONTROLLER_ID OSRC_SESSION_CLAIM_TOKEN
unset OSRC_EXTERNAL_COMPOSER_PROBE OSRC_EXTERNAL_RECEIPT_PROBE
unset OSRC_PROVIDER OSRC_MODEL OSRC_DEFAULT_PROVIDER OSRC_DEFAULT_MODEL
unset OUTSOURCERER_PROVIDER OUTSOURCERER_MODEL OUTSOURCERER_DEFAULT_PROVIDER OUTSOURCERER_DEFAULT_MODEL
unset CLAUDE_MODEL ANTHROPIC_MODEL
assert_eq "tmux=<organoun-env> $managed_clean_env" "$(sort -u "$ORGAN_FAKE_MANAGED_ENV_LOG")"
assert_eq 1 "$(command_count '--provider cc session start')"
assert_eq 1 "$(command_count 'session read --state')"
assert_eq 1 "$(command_count 'session send Ambiente limpo.')"
assert_eq 1 "$(command_count 'session stop')"

# Text alone cannot confirm stop: a backend that acknowledges but leaves the
# exact tmux session live must fail closed and retain Organoun ownership.
clear_logs
set_tmux_absent
printf 'Prepare o falso stop.' | "$REPO_ROOT/bin/organ" dispatch claude-false-stop --mode read --stdin --json >/dev/null
clear_logs
export ORGAN_FAKE_STOP_KEEPS_SESSION=1
set +e
actual="$("$REPO_ROOT/bin/organ" stop claude-false-stop --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_STOP_KEEPS_SESSION
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "STOP_UNCONFIRMED"'
assert_eq 1 "$(command_count 'session stop')"
[[ -f "$ORGAN_STATE_HOME/sessions/claude-false-stop.json" ]] || {
  printf 'false stop confirmation deleted ownership\n' >&2
  exit 1
}
jq -e '.exists == true and .session_name == "organoun-false-stop"' "$ORGAN_FAKE_TMUX_STATE_FILE" >/dev/null

# Invalid providers fail configuration before any adapter process executes.
bad_config="$TEST_TMP/bad-provider.json"
jq -cn --arg cwd "$cwd" '{schema_version:"1",targets:[{alias:"bad",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"other",session_name:"organoun-bad",model:null}]}' >"$bad_config"
clear_logs
export ORGAN_CONFIG="$bad_config"
set +e
actual="$(printf 'Nunca envie.' | "$REPO_ROOT/bin/organ" dispatch bad --mode read --stdin --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CONFIG_INVALID"'
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"
export ORGAN_CONFIG="$config"

# Two lifecycles for one alias serialize around creation, so only one starts.
clear_logs
set_tmux_absent
serial_gate="$TEST_TMP/serial-gate"
mkdir -p -- "$serial_gate"
export ORGAN_FAKE_START_GATE="$serial_gate"
serial_one="$TEST_TMP/serial-one.json"
serial_two="$TEST_TMP/serial-two.json"
printf 'Primeira serializada.' | "$REPO_ROOT/bin/organ" dispatch claude-serial --mode read --stdin --json >"$serial_one" &
serial_one_pid=$!
for _ in {1..200}; do
  [[ -e "$serial_gate/entered" ]] && break
  sleep 0.01
done
[[ -e "$serial_gate/entered" ]] || {
  printf 'first serialized start did not reach gate\n' >&2
  [[ ! -s "$serial_one" ]] || sed -n '1,20p' "$serial_one" >&2
  [[ ! -s "$ORGAN_FAKE_COMMAND_LOG" ]] || sed -n '1,20p' "$ORGAN_FAKE_COMMAND_LOG" >&2
  exit 1
}
printf 'Segunda serializada.' | "$REPO_ROOT/bin/organ" dispatch claude-serial --mode read --stdin --json >"$serial_two" &
serial_two_pid=$!
for _ in {1..20}; do
  sleep 0.01
done
touch "$serial_gate/release"
wait "$serial_one_pid"
wait "$serial_two_pid"
unset ORGAN_FAKE_START_GATE
assert_jq "$(<"$serial_one")" '.ok == true'
assert_jq "$(<"$serial_two")" '.ok == true'
assert_eq 1 "$(command_count '--provider cc session start')"
assert_eq 1 "$(command_count 'session send Primeira serializada.')"
assert_eq 1 "$(command_count 'session send Segunda serializada.')"

# An existing name without Organoun ownership is a collision, never adoption.
clear_logs
set_tmux_session organoun-collision "$cwd" '%31' 5131 931
set +e
actual="$(printf 'Não adote.' | "$REPO_ROOT/bin/organ" dispatch claude-collision --mode read --stdin --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "MANAGED_SESSION_COLLISION"'
assert_eq 0 "$(command_count 'session send Não adote.')"
assert_eq 0 "$(command_count 'session stop')"
set +e
actual="$("$REPO_ROOT/bin/organ" stop claude-collision --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "MANAGED_SESSION_COLLISION"'
assert_eq 0 "$(command_count 'session stop')"

# The pinned upstream collision line is failure even when upstream exits zero.
clear_logs
set_tmux_absent
export ORGAN_FAKE_START_OUTPUT='Session already exists: organoun-upstream-collision'
export ORGAN_FAKE_START_CREATES_SESSION=0
set +e
actual="$(printf 'Não envie após colisão.' | "$REPO_ROOT/bin/organ" dispatch claude-upstream-collision --mode read --stdin --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_START_OUTPUT ORGAN_FAKE_START_CREATES_SESSION
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "MANAGED_SESSION_COLLISION"'
assert_eq 1 "$(command_count '--provider cc session start')"
assert_eq 0 "$(command_count 'session send Não envie após colisão.')"
assert_not_exists "$ORGAN_STATE_HOME/sessions/claude-upstream-collision.json"

# A launch acknowledgement is not ownership: the live session name and cwd
# must exactly match the configured target before any receipt, job, or send.
for bad_live_field in cwd session_name; do
  clear_logs
  set_tmux_absent
  if [[ "$bad_live_field" == cwd ]]; then
    bad_alias=claude-wrong-cwd
    export ORGAN_FAKE_LIVE_CWD="$TEST_TMP/wrong-live-cwd"
  else
    bad_alias=claude-wrong-name
    export ORGAN_FAKE_LIVE_SESSION_NAME='different-live-session'
  fi
  set +e
  actual="$(printf 'Não confie no start.' | "$REPO_ROOT/bin/organ" dispatch "$bad_alias" --mode read --stdin --json 2>&1)"
  rc=$?
  set -e
  unset ORGAN_FAKE_LIVE_CWD ORGAN_FAKE_LIVE_SESSION_NAME
  assert_eq 64 "$rc"
  assert_jq "$actual" '.error.code == "MANAGED_SESSION_COLLISION"'
  assert_not_exists "$ORGAN_STATE_HOME/sessions/$bad_alias.json"
  assert_eq 0 "$(command_count 'session send Não confie no start.')"
  if grep -RFlq -- "\"target\":\"$bad_alias\"" "$ORGAN_STATE_HOME/jobs"; then
    printf 'wrong live %s created a job receipt\n' "$bad_live_field" >&2
    exit 1
  fi
done

# Readiness is not ownership proof: a pane identity change caused by the read
# itself must be caught before job allocation and before the single send.
clear_logs
set_tmux_absent
export ORGAN_FAKE_MUTATE_AFTER_READ=1
export ORGAN_FAKE_MUTATE_PANE_PID=6262
export ORGAN_FAKE_MUTATE_PID_START=962
set +e
actual="$(printf 'Não envie após a corrida.' | "$REPO_ROOT/bin/organ" dispatch claude-raced --mode read --stdin --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_MUTATE_AFTER_READ ORGAN_FAKE_MUTATE_PANE_PID ORGAN_FAKE_MUTATE_PID_START
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "MANAGED_SESSION_COLLISION"'
assert_eq 1 "$(command_count 'session read --state')"
assert_eq 0 "$(command_count 'session send Não envie após a corrida.')"
if grep -RFlq -- '"target":"claude-raced"' "$ORGAN_STATE_HOME/jobs"; then
  printf 'identity change during readiness created a job receipt\n' >&2
  exit 1
fi

# Polling is capped, uses the zero test interval, and never sends while working.
clear_logs
set_tmux_absent
export ORGAN_FAKE_READ_STATE=working
set +e
actual="$(printf 'Espere ficar ocioso.' | "$REPO_ROOT/bin/organ" dispatch claude-slow --mode read --stdin --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_READ_STATE
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "SESSION_NOT_READY"'
assert_eq 20 "$(command_count 'session read --state')"
assert_eq 0 "$(command_count 'session send Espere ficar ocioso.')"
[[ -f "$ORGAN_STATE_HOME/sessions/claude-slow.json" ]] || {
  printf 'not-ready dispatch discarded valid ownership\n' >&2
  exit 1
}

# An adapter read failure is terminal for this dispatch attempt, not twenty
# synthetic not-ready observations. Preserve its exact normalized error.
clear_logs
set_tmux_absent
export ORGAN_FAKE_READ_RC=71
set +e
actual="$(printf 'Não masque o erro.' | "$REPO_ROOT/bin/organ" dispatch claude-observe-error --mode read --stdin --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_READ_RC
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "OUTSOURCERER_UNAVAILABLE"'
assert_eq 1 "$(command_count 'session read --state')"
assert_eq 0 "$(command_count 'session send Não masque o erro.')"
if grep -RFlq -- '"target":"claude-observe-error"' "$ORGAN_STATE_HOME/jobs"; then
  printf 'failed readiness observation created a job receipt\n' >&2
  exit 1
fi

# Only an independent receipt upgrades delivery, and every dispatch sends once.
clear_logs
set_tmux_absent
export ORGAN_FAKE_SEND_OUTPUT='receipt: managed-fake-receipt'
actual="$(printf 'Confirme independentemente.' | "$REPO_ROOT/bin/organ" dispatch claude-confirmed --mode read --stdin --json)"
unset ORGAN_FAKE_SEND_OUTPUT
assert_jq "$actual" '.ok == true and .delivery == "confirmed"'
assert_eq 1 "$(command_count 'session send Confirme independentemente.')"
confirmed_job="$(jq -r '.data.job_id' <<<"$actual")"
assert_jq "$(<"$ORGAN_STATE_HOME/jobs/$confirmed_job.json")" '.delivery == "confirmed"'

# Payload transport preserves one exact argv value, including empty input,
# embedded newlines, terminal newlines, and the inclusive 16-KiB boundary.
payload_empty="$TEST_TMP/payload-empty"
payload_multiline="$TEST_TMP/payload-multiline"
payload_terminal="$TEST_TMP/payload-terminal"
payload_boundary="$TEST_TMP/payload-boundary"
: >"$payload_empty"
printf 'linha um\nlinha dois' >"$payload_multiline"
printf 'termina aqui\n\n' >"$payload_terminal"
head -c 16382 /dev/zero | tr '\0' x >"$payload_boundary"
printf '\n\n' >>"$payload_boundary"
assert_eq 16384 "$(wc -c <"$payload_boundary")"
set_tmux_absent
for payload_input in "$payload_empty" "$payload_multiline" "$payload_terminal" "$payload_boundary"; do
  clear_logs
  payload_delivered="$TEST_TMP/delivered-${payload_input##*/}"
  export ORGAN_FAKE_PAYLOAD_FILE="$payload_delivered"
  set +e
  actual="$("$REPO_ROOT/bin/organ" dispatch claude-payload --mode read --stdin --json <"$payload_input" 2>&1)"
  rc=$?
  set -e
  unset ORGAN_FAKE_PAYLOAD_FILE
  assert_eq 0 "$rc"
  assert_jq "$actual" '.ok == true and .target == "claude-payload"'
  if ! cmp -s -- "$payload_input" "$payload_delivered"; then
    printf 'managed payload bytes changed for %s\n' "${payload_input##*/}" >&2
    printf 'expected bytes: %s; delivered bytes: %s\n' "$(wc -c <"$payload_input")" "$(wc -c <"$payload_delivered")" >&2
    od -An -tx1 "$payload_input" >&2
    od -An -tx1 "$payload_delivered" >&2
    exit 1
  fi
  payload_job_id="$(jq -r '.data.job_id' <<<"$actual")"
  if [[ -s "$payload_input" ]]; then
    if jq -e --rawfile prompt "$payload_input" 'tostring | contains($prompt)' >/dev/null <<<"$actual"; then
      printf 'public dispatch metadata persisted payload %s\n' "${payload_input##*/}" >&2
      exit 1
    fi
    if jq -e --rawfile prompt "$payload_input" 'tostring | contains($prompt)' "$ORGAN_STATE_HOME/jobs/$payload_job_id.json" >/dev/null; then
      printf 'job receipt persisted payload %s\n' "${payload_input##*/}" >&2
      exit 1
    fi
  fi
done

# Managed observation reads state only and never invokes a verifier.
clear_logs
set_tmux_session organoun-local "$cwd" '%12' 4242 777

# The route selected from the strict config snapshot remains authoritative for
# the whole command. Mutating the source after its first schema validation may
# not affect the later managed-ownership checks.
command_snapshot_config="$TEST_TMP/command-snapshot-targets.json"
command_replacement_config="$TEST_TMP/command-replacement-targets.json"
command_jq_shim="$TEST_TMP/command-jq-shim"
command_real_jq="$(command -v jq)"
cp -- "$config" "$command_snapshot_config"
printf '%s\n' '{"schema_version":"1","targets":[]}' >"$command_replacement_config"
mkdir -p -- "$command_jq_shim"
cat >"$command_jq_shim/jq" <<'SHIM'
#!/usr/bin/env bash
set -u

set +e
"${ORGAN_TEST_REAL_JQ:?}" "$@"
jq_rc=$?
set -e

for jq_arg in "$@"; do
  if [[ "$jq_arg" == *'def valid_target'* && ! -e "${ORGAN_TEST_MUTATION_MARKER:?}" ]]; then
    cp -- "${ORGAN_TEST_REPLACEMENT_CONFIG:?}" "${ORGAN_TEST_MUTATE_CONFIG:?}"
    : >"$ORGAN_TEST_MUTATION_MARKER"
    break
  fi
done
exit "$jq_rc"
SHIM
chmod 700 -- "$command_jq_shim/jq"
set +e
actual="$(
  PATH="$command_jq_shim:$PATH" \
    ORGAN_CONFIG="$command_snapshot_config" \
    ORGAN_TEST_REAL_JQ="$command_real_jq" \
    ORGAN_TEST_MUTATE_CONFIG="$command_snapshot_config" \
    ORGAN_TEST_REPLACEMENT_CONFIG="$command_replacement_config" \
    ORGAN_TEST_MUTATION_MARKER="$TEST_TMP/command-config-mutated" \
    "$REPO_ROOT/bin/organ" status claude-managed --json
)"
rc=$?
set -e
assert_eq 0 "$rc"
assert_jq "$actual" '.ok == true and .state == "idle" and .data == {}'
clear_logs

actual="$("$REPO_ROOT/bin/organ" status claude-managed --json)"
assert_jq "$actual" '.ok == true and .state == "idle" and .data == {}'
actual="$("$REPO_ROOT/bin/organ" read claude-managed --json)"
assert_jq "$actual" '.ok == true and .state == "idle" and .data.excerpt == "state: idle" and .data.truncated == false'
assert_eq 2 "$(command_count 'session read --state')"
assert_eq 0 "$(grep -c 'verify' "$ORGAN_FAKE_COMMAND_LOG" || true)"

# Every ownership component is authoritative: target session/cwd and live pane,
# PID, and process-start identities must all still match.
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/organ/common.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/organ/config.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/organ/outsourcerer.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/organ/sessions.sh"
owned_record="$(<"$session_receipt")"
for mutation in \
  '.session_name = "wrong-session"' \
  '.cwd = "/wrong/cwd"' \
  '.pane_id = "%99"' \
  '.pane_pid = 9999' \
  '.pid_start = "999"'; do
  jq "$mutation" <<<"$owned_record" >"$session_receipt"
  chmod 600 -- "$session_receipt"
  if organ_session_assert_owned claude-managed >/dev/null 2>&1; then
    printf 'ownership accepted mutated identity: %s\n' "$mutation" >&2
    exit 1
  fi
done
printf '%s\n' "$owned_record" >"$session_receipt"
chmod 600 -- "$session_receipt"
organ_session_assert_owned claude-managed >/dev/null

clear_logs
set_tmux_absent
actual="$("$REPO_ROOT/bin/organ" status claude-stopped --json)"
assert_jq "$actual" '.ok == true and .state == "stopped"'
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"

# A successful exact-name list positively distinguishes a live session from a
# missing name while a server is available.
clear_logs
set_tmux_absent
export ORGAN_FAKE_TMUX_REQUIRE_C_LOCALE=1
saved_lc_all="${LC_ALL-}"
saved_lc_all_set="${LC_ALL+x}"
unset LC_ALL
actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json)"
if [[ -n "$saved_lc_all_set" ]]; then
  export LC_ALL="$saved_lc_all"
fi
unset ORGAN_FAKE_TMUX_REQUIRE_C_LOCALE
assert_jq "$actual" '.ok == true and .state == "stopped"'
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"

clear_logs
set_tmux_session organoun-tmux-error "$cwd" '%31' 3131 931
set +e
actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "MANAGED_SESSION_COLLISION"'
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"

# Tmux's single-line no-server diagnostic is also positive absence evidence.
clear_logs
set_tmux_absent
export ORGAN_FAKE_TMUX_NO_SERVER=1
actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json)"
unset ORGAN_FAKE_TMUX_NO_SERVER
assert_jq "$actual" '.ok == true and .state == "stopped"'
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"

# Plausible version output cannot turn ambiguous rc1 query results into
# absence. Every case must fail status and dispatch before upstream start.
clear_logs
set_tmux_absent

# Embedded NUL bytes in any authoritative tmux stream must fail before Bash
# command substitution or read can erase them. Each case exercises the public
# absence/start lifecycle and proves no managed start was authorized.
tmux_version_nul="$TEST_TMP/tmux-version-nul"
tmux_listing_nul="$TEST_TMP/tmux-listing-nul"
tmux_diagnostic_nul="$TEST_TMP/tmux-diagnostic-nul"
printf 'tmux 3.4\0' >"$tmux_version_nul"
printf 'unrelated\0garbage\n' >"$tmux_listing_nul"
printf 'no server running on /tmp/tmux-test/default\0' >"$tmux_diagnostic_nul"

assert_public_tmux_stream_rejected() {
  local tmux_stream_case="$1"
  local tmux_stream_action
  local -a tmux_stream_actions=(status dispatch)
  local failed=0

  if [[ $# -eq 2 ]]; then
    tmux_stream_actions=("$2")
  fi
  for tmux_stream_action in "${tmux_stream_actions[@]}"; do
    rm -f -- "$ORGAN_STATE_HOME/sessions/claude-tmux-error.json"
    set_tmux_absent
    clear_logs
    set +e
    if [[ "$tmux_stream_action" == status ]]; then
      actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
    else
      actual="$(printf 'Não inicie após bytes tmux inválidos.' | "$REPO_ROOT/bin/organ" dispatch claude-tmux-error --mode read --stdin --json 2>&1)"
    fi
    rc=$?
    set -e
    if [[ "$rc" -ne 64 ]]; then
      printf '%s %s accepted invalid raw tmux stream with rc %s\n' \
        "$tmux_stream_case" "$tmux_stream_action" "$rc" >&2
      failed=1
    elif ! jq -e '.error.code == "TMUX_UNAVAILABLE"' >/dev/null <<<"$actual"; then
      printf '%s %s returned the wrong tmux error: %s\n' \
        "$tmux_stream_case" "$tmux_stream_action" "$actual" >&2
      failed=1
    fi
  done
  if [[ "$(command_count '--provider cc session start')" -ne 0 ]]; then
    printf '%s authorized managed start from invalid raw tmux output\n' \
      "$tmux_stream_case" >&2
    failed=1
  fi
  rm -f -- "$ORGAN_STATE_HOME/sessions/claude-tmux-error.json"
  set_tmux_absent
  return "$failed"
}

tmux_byte_regression_failed=0
export ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE="$tmux_version_nul"
if ! assert_public_tmux_stream_rejected version; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE

export ORGAN_FAKE_TMUX_QUERY_RC=0
export ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE="$tmux_listing_nul"
if ! assert_public_tmux_stream_rejected listing; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE

export ORGAN_FAKE_TMUX_QUERY_RC=1
export ORGAN_FAKE_TMUX_QUERY_STDERR_FILE="$tmux_diagnostic_nul"
if ! assert_public_tmux_stream_rejected diagnostic; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDERR_FILE

# The file helper independently preserves the accepted newline control while
# rejecting forbidden bytes and extra line structure. Removing raw-file
# validation makes the NUL fixture indistinguishable from that valid control.
tmux_line_valid="$TEST_TMP/tmux-line-valid"
tmux_line_nul="$TEST_TMP/tmux-line-nul"
tmux_line_control="$TEST_TMP/tmux-line-control"
tmux_line_extra="$TEST_TMP/tmux-line-extra"
printf 'tmux 3.4\n' >"$tmux_line_valid"
printf 'tmux 3.4\0' >"$tmux_line_nul"
printf 'tmux 3.4\001' >"$tmux_line_control"
printf 'tmux 3.4\nextra\n' >"$tmux_line_extra"
assert_eq 'tmux 3.4' "$(organ_tmux_single_printable_line "$tmux_line_valid")"
for invalid_tmux_line in "$tmux_line_nul" "$tmux_line_control" "$tmux_line_extra"; do
  if organ_tmux_single_printable_line "$invalid_tmux_line" >/dev/null 2>&1; then
    printf 'accepted invalid raw tmux line: %s\n' "${invalid_tmux_line##*/}" >&2
    tmux_byte_regression_failed=1
  fi
done

# Every authoritative tmux stream is strict ASCII. Actual high bytes at the
# beginning, middle, and end must fail before they can prove absence.
tmux_high_version_begin="$TEST_TMP/tmux-high-version-begin"
tmux_high_version_middle="$TEST_TMP/tmux-high-version-middle"
tmux_high_version_end="$TEST_TMP/tmux-high-version-end"
tmux_high_listing_begin="$TEST_TMP/tmux-high-listing-begin"
tmux_high_listing_middle="$TEST_TMP/tmux-high-listing-middle"
tmux_high_listing_end="$TEST_TMP/tmux-high-listing-end"
tmux_high_diagnostic_begin="$TEST_TMP/tmux-high-diagnostic-begin"
tmux_high_diagnostic_middle="$TEST_TMP/tmux-high-diagnostic-middle"
tmux_high_diagnostic_end="$TEST_TMP/tmux-high-diagnostic-end"
printf '\377tmux 3.4\n' >"$tmux_high_version_begin"
printf 'tmux \3773.4\n' >"$tmux_high_version_middle"
printf 'tmux 3.4\377\n' >"$tmux_high_version_end"
printf '\377other\n' >"$tmux_high_listing_begin"
printf 'oth\377er\n' >"$tmux_high_listing_middle"
printf 'other\377\n' >"$tmux_high_listing_end"
printf '\377no sessions\n' >"$tmux_high_diagnostic_begin"
printf 'no sess\377ions\n' >"$tmux_high_diagnostic_middle"
printf 'no sessions\377\n' >"$tmux_high_diagnostic_end"

for tmux_high_file in \
  "$tmux_high_version_begin" "$tmux_high_version_middle" "$tmux_high_version_end"; do
  export ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE="$tmux_high_file"
  if ! assert_public_tmux_stream_rejected "high-byte version ${tmux_high_file##*-}" status; then
    tmux_byte_regression_failed=1
  fi
  unset ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE
done
for tmux_high_file in "$tmux_high_listing_begin" "$tmux_high_listing_middle"; do
  export ORGAN_FAKE_TMUX_QUERY_RC=0
  export ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE="$tmux_high_file"
  if ! assert_public_tmux_stream_rejected "high-byte listing ${tmux_high_file##*-}" status; then
    tmux_byte_regression_failed=1
  fi
  unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE
done
export ORGAN_FAKE_TMUX_QUERY_RC=0
export ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE="$tmux_high_listing_end"
if ! assert_public_tmux_stream_rejected 'high-byte listing end'; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE
for tmux_high_file in \
  "$tmux_high_diagnostic_begin" "$tmux_high_diagnostic_middle" "$tmux_high_diagnostic_end"; do
  export ORGAN_FAKE_TMUX_QUERY_RC=1
  export ORGAN_FAKE_TMUX_QUERY_STDERR_FILE="$tmux_high_file"
  if ! assert_public_tmux_stream_rejected "high-byte diagnostic ${tmux_high_file##*-}" status; then
    tmux_byte_regression_failed=1
  fi
  unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDERR_FILE
done
for tmux_high_file in \
  "$tmux_high_version_begin" "$tmux_high_version_middle" "$tmux_high_version_end" \
  "$tmux_high_listing_begin" "$tmux_high_listing_middle" "$tmux_high_listing_end" \
  "$tmux_high_diagnostic_begin" "$tmux_high_diagnostic_middle" "$tmux_high_diagnostic_end"; do
  if organ_tmux_raw_file_valid "$tmux_high_file" >/dev/null 2>&1; then
    printf 'raw tmux scanner accepted a high-byte stream: %s\n' "${tmux_high_file##*/}" >&2
    tmux_byte_regression_failed=1
  fi
done

# Scanner failures are failures even when the caller has disabled pipefail.
# In particular, an unreadable regular file must not be accepted just because
# a downstream scanner stage observed no bytes.
tmux_scanner_unreadable="$TEST_TMP/tmux-scanner-unreadable"
printf 'tmux 3.4\n' >"$tmux_scanner_unreadable"
chmod 000 -- "$tmux_scanner_unreadable"
if (set +o pipefail; organ_tmux_raw_file_valid "$tmux_scanner_unreadable" >/dev/null 2>&1); then
  printf 'raw tmux scanner accepted an unreadable file without pipefail\n' >&2
  tmux_byte_regression_failed=1
fi
chmod 600 -- "$tmux_scanner_unreadable"
if (set +o pipefail; organ_tmux_raw_file_valid "$TEST_TMP/missing-tmux-scan" >/dev/null 2>&1); then
  printf 'raw tmux scanner accepted a missing file without pipefail\n' >&2
  tmux_byte_regression_failed=1
fi

# Authority capture has a fixed 64-KiB payload ceiling per stdout/stderr
# stream. A one-byte overflow sentinel is the largest private staged file.
tmux_oversize_payload="$TEST_TMP/tmux-oversize-payload"
tmux_version_oversize="$TEST_TMP/tmux-version-oversize"
tmux_version_stderr_oversize="$TEST_TMP/tmux-version-stderr-oversize"
tmux_listing_oversize="$TEST_TMP/tmux-listing-oversize"
tmux_diagnostic_oversize="$TEST_TMP/tmux-diagnostic-oversize"
dd if=/dev/zero bs=70000 count=1 status=none | LC_ALL=C tr '\0' a >"$tmux_oversize_payload"
{
  printf 'tmux '
  cat -- "$tmux_oversize_payload"
  printf '\n'
} >"$tmux_version_oversize"
cp -- "$tmux_oversize_payload" "$tmux_version_stderr_oversize"
{
  cat -- "$tmux_oversize_payload"
  printf '\n'
} >"$tmux_listing_oversize"
{
  printf 'no server running on /'
  cat -- "$tmux_oversize_payload"
  printf '\n'
} >"$tmux_diagnostic_oversize"

export ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE="$tmux_version_oversize"
if ! assert_public_tmux_stream_rejected 'oversized version stdout' dispatch; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE
export ORGAN_FAKE_TMUX_VERSION_STDERR_FILE="$tmux_version_stderr_oversize"
if ! assert_public_tmux_stream_rejected 'oversized version stderr' dispatch; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_VERSION_STDERR_FILE
export ORGAN_FAKE_TMUX_QUERY_RC=0
export ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE="$tmux_listing_oversize"
if ! assert_public_tmux_stream_rejected 'oversized listing stdout' dispatch; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE
export ORGAN_FAKE_TMUX_QUERY_RC=1
export ORGAN_FAKE_TMUX_QUERY_STDERR_FILE="$tmux_diagnostic_oversize"
if ! assert_public_tmux_stream_rejected 'oversized diagnostic stderr' dispatch; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDERR_FILE

# Exercise the bounded capture primitive directly so the test observes the
# actual private storage ceiling, not only the public rejection outcome.
tmux_capture_probe_dir="$TEST_TMP/tmux-capture-probe"
mkdir -p -- "$tmux_capture_probe_dir"
if ! declare -F organ_tmux_capture_bounded >/dev/null; then
  printf 'bounded tmux capture primitive is missing\n' >&2
  tmux_byte_regression_failed=1
else
  export ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE="$tmux_version_oversize"
  set +e
  organ_tmux_capture_bounded \
    "$tmux_capture_probe_dir/stdout" "$tmux_capture_probe_dir/stderr" \
    "$ORGAN_TMUX" -V
  capture_rc=$?
  set -e
  unset ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE
  if [[ "$capture_rc" -ne 64 ]]; then
    printf 'oversized bounded capture returned rc %s\n' "$capture_rc" >&2
    tmux_byte_regression_failed=1
  fi
  for capture_probe_file in "$tmux_capture_probe_dir/stdout" "$tmux_capture_probe_dir/stderr"; do
    if [[ ! -f "$capture_probe_file" ]] ||
      [[ "$(stat -c '%s' -- "$capture_probe_file")" -gt 65537 ]]; then
      printf 'bounded capture exceeded its private stream ceiling: %s\n' "$capture_probe_file" >&2
      tmux_byte_regression_failed=1
    fi
  done
  rm -f -- "$tmux_capture_probe_dir/stdout" "$tmux_capture_probe_dir/stderr"
  export ORGAN_FAKE_TMUX_VERSION_STDERR_FILE="$tmux_version_stderr_oversize"
  set +e
  organ_tmux_capture_bounded \
    "$tmux_capture_probe_dir/stdout" "$tmux_capture_probe_dir/stderr" \
    "$ORGAN_TMUX" -V
  capture_rc=$?
  set -e
  unset ORGAN_FAKE_TMUX_VERSION_STDERR_FILE
  if [[ "$capture_rc" -ne 64 ]]; then
    printf 'oversized stderr bounded capture returned rc %s\n' "$capture_rc" >&2
    tmux_byte_regression_failed=1
  fi
  for capture_probe_file in "$tmux_capture_probe_dir/stdout" "$tmux_capture_probe_dir/stderr"; do
    if [[ ! -f "$capture_probe_file" ]] ||
      [[ "$(stat -c '%s' -- "$capture_probe_file")" -gt 65537 ]]; then
      printf 'bounded stderr capture exceeded its private stream ceiling: %s\n' "$capture_probe_file" >&2
      tmux_byte_regression_failed=1
    fi
  done
  if find "$tmux_capture_probe_dir" -mindepth 1 -type p -print -quit | grep -q .; then
    printf 'bounded capture left a private fifo behind\n' >&2
    tmux_byte_regression_failed=1
  fi
fi

# Both version and listing peers have a fixed wall-time budget. The test-side
# timeout is only a deadlock guard; Organoun must return its own fail-closed
# error first and must clean every private query directory.
saved_tmpdir="${TMPDIR-}"
saved_tmpdir_set="${TMPDIR+x}"
tmux_private_tmp="$TEST_TMP/tmux-private-tmp"
mkdir -p -- "$tmux_private_tmp"
export TMPDIR="$tmux_private_tmp"

assert_timed_tmux_rejected() {
  local timed_case="$1"
  local timed_action="$2"
  local started_ns elapsed_ms timed_actual timed_rc
  local failed=0

  rm -f -- "$ORGAN_STATE_HOME/sessions/claude-tmux-error.json"
  set_tmux_absent
  clear_logs
  started_ns="$(date +%s%N)"
  set +e
  if [[ "$timed_action" == status ]]; then
    timed_actual="$(timeout 4 "$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
  else
    timed_actual="$(printf 'Não inicie após timeout tmux.' | timeout 4 "$REPO_ROOT/bin/organ" dispatch claude-tmux-error --mode read --stdin --json 2>&1)"
  fi
  timed_rc=$?
  set -e
  elapsed_ms=$(( ($(date +%s%N) - started_ns) / 1000000 ))
  if [[ "$timed_rc" -ne 64 ]]; then
    printf '%s did not fail closed before the guard timeout: rc=%s elapsed=%sms\n' \
      "$timed_case" "$timed_rc" "$elapsed_ms" >&2
    failed=1
  elif ! jq -e '.error.code == "TMUX_UNAVAILABLE"' >/dev/null <<<"$timed_actual"; then
    printf '%s returned the wrong timeout error: %s\n' "$timed_case" "$timed_actual" >&2
    failed=1
  fi
  if [[ "$elapsed_ms" -ge 2000 ]]; then
    printf '%s exceeded the bounded wall time: %sms\n' "$timed_case" "$elapsed_ms" >&2
    failed=1
  fi
  if [[ "$(command_count '--provider cc session start')" -ne 0 ]]; then
    printf '%s authorized managed start after timeout\n' "$timed_case" >&2
    failed=1
  fi
  if find "$tmux_private_tmp" -maxdepth 1 -name 'organoun-tmux-query.*' -print -quit | grep -q .; then
    printf '%s left private capture storage behind\n' "$timed_case" >&2
    failed=1
  fi
  rm -f -- "$ORGAN_STATE_HOME/sessions/claude-tmux-error.json"
  set_tmux_absent
  return "$failed"
}

export ORGAN_FAKE_TMUX_VERSION_HOLD_SECONDS=2.5
if ! assert_timed_tmux_rejected 'hung version peer' dispatch; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_VERSION_HOLD_SECONDS
printf 'other\n' >"$TEST_TMP/tmux-hung-listing"
export ORGAN_FAKE_TMUX_QUERY_RC=0
export ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE="$TEST_TMP/tmux-hung-listing"
export ORGAN_FAKE_TMUX_QUERY_HOLD_SECONDS=2.5
if ! assert_timed_tmux_rejected 'hung listing peer' dispatch; then
  tmux_byte_regression_failed=1
fi
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE ORGAN_FAKE_TMUX_QUERY_HOLD_SECONDS
if [[ -n "$saved_tmpdir_set" ]]; then
  export TMPDIR="$saved_tmpdir"
else
  unset TMPDIR
fi

clear_logs
saved_tmux="$ORGAN_TMUX"
export ORGAN_TMUX=/bin/false
for tmux_error_action in status dispatch; do
  set +e
  if [[ "$tmux_error_action" == status ]]; then
    actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
  else
    actual="$(printf 'Não inicie após rc 1 silencioso.' | "$REPO_ROOT/bin/organ" dispatch claude-tmux-error --mode read --stdin --json 2>&1)"
  fi
  rc=$?
  set -e
  assert_eq 64 "$rc"
  assert_jq "$actual" '.error.code == "TMUX_UNAVAILABLE"'
done
assert_eq 0 "$(command_count '--provider cc session start')"

# Missing executables and non-absence errors are likewise ambiguous.
export ORGAN_TMUX="$TEST_TMP/missing-tmux"
for tmux_error_action in status dispatch; do
  set +e
  if [[ "$tmux_error_action" == status ]]; then
    actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
  else
    actual="$(printf 'Não inicie sem tmux.' | "$REPO_ROOT/bin/organ" dispatch claude-tmux-error --mode read --stdin --json 2>&1)"
  fi
  rc=$?
  set -e
  assert_eq 64 "$rc"
  assert_jq "$actual" '.error.code == "TMUX_UNAVAILABLE"'
done
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"
export ORGAN_TMUX="$saved_tmux"

ambiguous_query_outputs=(
  ''
  'error connecting to /tmp/tmux-fake/default (Connection refused)'
  'permission denied'
  'unrelated tmux failure'
  $'no server running on /tmp/tmux-fake/default\nunrelated second line'
)
for ambiguous_query_output in "${ambiguous_query_outputs[@]}"; do
  clear_logs
  set_tmux_absent
  export ORGAN_FAKE_TMUX_QUERY_RC=1
  export ORGAN_FAKE_TMUX_QUERY_OUTPUT="$ambiguous_query_output"
  for tmux_error_action in status dispatch; do
    set +e
    if [[ "$tmux_error_action" == status ]]; then
      actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
    else
      actual="$(printf 'Não inicie após consulta ambígua.' | "$REPO_ROOT/bin/organ" dispatch claude-tmux-error --mode read --stdin --json 2>&1)"
    fi
    rc=$?
    set -e
    assert_eq 64 "$rc"
    assert_jq "$actual" '.error.code == "TMUX_UNAVAILABLE"'
  done
  unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_OUTPUT
  assert_eq 0 "$(command_count '--provider cc session start')"
done

clear_logs
set_tmux_absent
export ORGAN_FAKE_TMUX_QUERY_RC=70
export ORGAN_FAKE_TMUX_QUERY_OUTPUT='tmux query execution failed'
for tmux_error_action in status dispatch; do
  set +e
  if [[ "$tmux_error_action" == status ]]; then
    actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
  else
    actual="$(printf 'Não inicie após erro tmux.' | "$REPO_ROOT/bin/organ" dispatch claude-tmux-error --mode read --stdin --json 2>&1)"
  fi
  rc=$?
  set -e
  assert_eq 64 "$rc"
  assert_jq "$actual" '.error.code == "TMUX_UNAVAILABLE"'
done
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_OUTPUT
assert_eq 0 "$(command_count '--provider cc session start')"

# Version identification is exactly one line: literal "tmux ", followed by a
# nonempty printable token. Whitespace controls and extra lines fail closed.
invalid_tmux_versions=(
  $'tmux\t3.4'
  $'tmux\n3.4'
  $'tmux 3.4\nextra'
  $'tmux 3.4\n\n'
  $'tmux 3.4\001'
  'tmux '
  'not-tmux 3.4'
  ''
)
for invalid_tmux_version in "${invalid_tmux_versions[@]}"; do
  clear_logs
  set_tmux_absent
  export ORGAN_FAKE_TMUX_VERSION_OUTPUT="$invalid_tmux_version"
  set +e
  actual="$("$REPO_ROOT/bin/organ" status claude-tmux-error --json 2>&1)"
  rc=$?
  set -e
  unset ORGAN_FAKE_TMUX_VERSION_OUTPUT
  assert_eq 64 "$rc"
  assert_jq "$actual" '.error.code == "TMUX_UNAVAILABLE"'
done

clear_logs
set_tmux_absent
printf 'Prepare stop ambíguo.' | "$REPO_ROOT/bin/organ" dispatch claude-stop-error --mode read --stdin --json >/dev/null

assert_stop_listing_rejected() {
  local stop_case="$1"
  local stop_listing_file="$2"
  local stop_actual stop_rc

  clear_logs
  export ORGAN_FAKE_TMUX_QUERY_RC=0
  export ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE="$stop_listing_file"
  export ORGAN_FAKE_STOP_KEEPS_SESSION=1
  set +e
  stop_actual="$("$REPO_ROOT/bin/organ" stop claude-stop-error --json 2>&1)"
  stop_rc=$?
  set -e
  unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE ORGAN_FAKE_STOP_KEEPS_SESSION
  if [[ "$stop_rc" -ne 64 ]]; then
    printf '%s stop check accepted invalid tmux listing with rc %s\n' "$stop_case" "$stop_rc" >&2
    tmux_byte_regression_failed=1
  elif ! jq -e '.error.code == "STOP_UNCONFIRMED"' >/dev/null <<<"$stop_actual"; then
    printf '%s stop check returned the wrong error: %s\n' "$stop_case" "$stop_actual" >&2
    tmux_byte_regression_failed=1
  fi
  if [[ ! -f "$ORGAN_STATE_HOME/sessions/claude-stop-error.json" ]]; then
    printf '%s stop check deleted ownership\n' "$stop_case" >&2
    tmux_byte_regression_failed=1
    set_tmux_absent
    printf 'Recrie ownership para regressões seguintes.' | \
      "$REPO_ROOT/bin/organ" dispatch claude-stop-error --mode read --stdin --json >/dev/null
  fi
}

assert_stop_listing_rejected 'high-byte' "$tmux_high_listing_end"
assert_stop_listing_rejected 'oversized' "$tmux_listing_oversize"

clear_logs
export ORGAN_FAKE_TMUX_QUERY_RC=1
export ORGAN_FAKE_TMUX_QUERY_STDERR_FILE="$tmux_diagnostic_nul"
export ORGAN_FAKE_STOP_KEEPS_SESSION=1
set +e
actual="$("$REPO_ROOT/bin/organ" stop claude-stop-error --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_STDERR_FILE ORGAN_FAKE_STOP_KEEPS_SESSION
if [[ "$rc" -ne 64 ]]; then
  printf 'diagnostic stop accepted invalid raw tmux stream with rc %s\n' "$rc" >&2
  tmux_byte_regression_failed=1
elif ! jq -e '.error.code == "STOP_UNCONFIRMED"' >/dev/null <<<"$actual"; then
  printf 'diagnostic stop returned the wrong tmux error: %s\n' "$actual" >&2
  tmux_byte_regression_failed=1
fi
if [[ ! -f "$ORGAN_STATE_HOME/sessions/claude-stop-error.json" ]]; then
  printf 'NUL-bearing tmux stop check deleted ownership\n' >&2
  tmux_byte_regression_failed=1
fi
if [[ "$tmux_byte_regression_failed" -ne 0 ]]; then
  exit 1
fi

clear_logs
export ORGAN_FAKE_TMUX_QUERY_RC=1
export ORGAN_FAKE_TMUX_QUERY_OUTPUT=''
export ORGAN_FAKE_STOP_KEEPS_SESSION=1
set +e
actual="$("$REPO_ROOT/bin/organ" stop claude-stop-error --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_OUTPUT ORGAN_FAKE_STOP_KEEPS_SESSION
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "STOP_UNCONFIRMED"'
[[ -f "$ORGAN_STATE_HOME/sessions/claude-stop-error.json" ]] || {
  printf 'ambiguous tmux stop check deleted ownership\n' >&2
  exit 1
}

clear_logs
export ORGAN_FAKE_TMUX_QUERY_RC=70
export ORGAN_FAKE_TMUX_QUERY_OUTPUT='tmux query execution failed'
export ORGAN_FAKE_STOP_KEEPS_SESSION=1
set +e
actual="$("$REPO_ROOT/bin/organ" stop claude-stop-error --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_TMUX_QUERY_RC ORGAN_FAKE_TMUX_QUERY_OUTPUT ORGAN_FAKE_STOP_KEEPS_SESSION
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "STOP_UNCONFIRMED"'
[[ -f "$ORGAN_STATE_HOME/sessions/claude-stop-error.json" ]] || {
  printf 'tmux execution error deleted ownership\n' >&2
  exit 1
}

# PID and process-start reuse are part of ownership, not advisory metadata.
clear_logs
set_tmux_session organoun-local "$cwd" '%12' 4343 999
set +e
actual="$("$REPO_ROOT/bin/organ" stop claude-managed --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "MANAGED_SESSION_COLLISION"'
assert_eq 0 "$(command_count 'session stop')"
[[ -f "$session_receipt" ]] || { printf 'stale ownership receipt was deleted\n' >&2; exit 1; }

# Adopted sessions are never stopped through the managed lifecycle.
clear_logs
set +e
actual="$("$REPO_ROOT/bin/organ" stop claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "ADOPTED_SESSION_CANNOT_STOP"'
assert_eq 0 "$(command_count 'session stop')"

# State roots cannot redirect session or job writes through symlinks.
# This is validation-only: never invoke an initializer while testing `/`.
saved_state_home="$ORGAN_STATE_HOME"
for unsafe_state_home in / '' relative/state /tmp/../unsafe-state /tmp//unsafe-state /tmp/unsafe-state/; do
  export ORGAN_STATE_HOME="$unsafe_state_home"
  if organ_state_ancestors_safe; then
    printf 'accepted unsafe state root: <%s>\n' "$unsafe_state_home" >&2
    exit 1
  fi
done
export ORGAN_STATE_HOME="$saved_state_home"

outside_state="$TEST_TMP/outside-state"
state_link="$TEST_TMP/state-link"
mkdir -p -- "$outside_state"
ln -s -- "$outside_state" "$state_link"
export ORGAN_STATE_HOME="$state_link"
clear_logs
set_tmux_absent
set +e
actual="$(printf 'Não redirecione estado.' | "$REPO_ROOT/bin/organ" dispatch claude-stopped --mode read --stdin --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "SESSION_STORE_FAILED"'
assert_not_exists "$outside_state/sessions"
assert_not_exists "$outside_state/jobs"
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"
export ORGAN_STATE_HOME="$TEST_TMP/private-state"

for redirected_subdir in sessions jobs; do
  redirected_state="$TEST_TMP/redirected-$redirected_subdir-state"
  redirected_outside="$TEST_TMP/redirected-$redirected_subdir-outside"
  mkdir -p -- "$redirected_state" "$redirected_outside"
  ln -s -- "$redirected_outside" "$redirected_state/$redirected_subdir"
  export ORGAN_STATE_HOME="$redirected_state"
  clear_logs
  set_tmux_absent
  set +e
  actual="$(printf 'Não siga subdiretório.' | "$REPO_ROOT/bin/organ" dispatch claude-stopped --mode read --stdin --json 2>&1)"
  rc=$?
  set -e
  assert_eq 64 "$rc"
  assert_jq "$actual" '.error.code == "SESSION_STORE_FAILED"'
  assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"
  assert_not_exists "$redirected_outside/claude-stopped.json"
done
export ORGAN_STATE_HOME="$TEST_TMP/private-state"

# Job IDs are always host-qualified; unknown or absent hosts fail closed.
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/organ/jobs.sh"
assert_eq local "$(organ_job_route_class "$job_id")"
assert_eq remote "$(organ_job_route_class remote.job-20260816T120000Z-a1b2c3d4)"
for invalid_job_id in job-20260816T120000Z-a1b2c3d4 other.job-20260816T120000Z-a1b2c3d4 local.job-bad; do
  if organ_job_route_class "$invalid_job_id" >/dev/null 2>&1; then
    printf 'accepted invalid job id: %s\n' "$invalid_job_id" >&2
    exit 1
  fi
done

# The documented minimum schemas remain accepted independently of runtime
# delivery enrichment and use an opaque Linux process-start marker.
sample_session="$(jq -cn --arg cwd "$cwd" '
  {schema_version:"1",alias:"sample-owned",host:"local",session_name:"organoun-sample",cwd:$cwd,pane_id:"%77",pane_pid:7777,pid_start:"linux-proc-start-marker"}')"
organ_session_write sample-owned "$sample_session"
assert_mode 600 "$ORGAN_STATE_HOME/sessions/sample-owned.json"

sample_job_id='local.job-20260816T120000Z-a1b2c3d4'
sample_job="$(jq -cn --arg job_id "$sample_job_id" '
  {schema_version:"1",job_id:$job_id,target:"claude-managed",host:"local",mode:"read",session_name:"organoun-local",state:"working",artifacts:[]}')"
organ_job_create "$sample_job"
assert_jq "$(organ_job_read "$sample_job_id")" '.state == "working" and (has("delivery") | not)'

# Create is atomic no-clobber: a deterministic duplicate and concurrent
# creators can never replace the receipt that won the ID.
duplicate_job_id='local.job-20260816T120001Z-b1b2c3d4'
duplicate_original="$(jq -cn --arg job_id "$duplicate_job_id" '
  {schema_version:"1",job_id:$job_id,target:"claude-managed",host:"local",mode:"read",session_name:"organoun-local",state:"working",delivery:"unknown",artifacts:[]}')"
duplicate_conflict="$(jq -cn --arg job_id "$duplicate_job_id" '
  {schema_version:"1",job_id:$job_id,target:"claude-fable",host:"local",mode:"read",session_name:"organoun-fable",state:"done",delivery:"confirmed",artifacts:[]}')"
organ_job_create "$duplicate_original"
duplicate_before="$(organ_job_read "$duplicate_job_id")"
set +e
organ_job_create "$duplicate_conflict"
duplicate_rc=$?
set -e
assert_eq 73 "$duplicate_rc"
assert_eq "$duplicate_before" "$(organ_job_read "$duplicate_job_id")"

concurrent_job_id='local.job-20260816T120002Z-c1b2c3d4'
concurrent_a="$(jq -cn --arg job_id "$concurrent_job_id" '
  {schema_version:"1",job_id:$job_id,target:"claude-managed",host:"local",mode:"read",session_name:"organoun-local",state:"working",delivery:"unknown",artifacts:[]}')"
concurrent_b="$(jq -cn --arg job_id "$concurrent_job_id" '
  {schema_version:"1",job_id:$job_id,target:"claude-fable",host:"local",mode:"read",session_name:"organoun-fable",state:"done",delivery:"confirmed",artifacts:[]}')"
concurrent_rc_a="$TEST_TMP/concurrent-a.rc"
concurrent_rc_b="$TEST_TMP/concurrent-b.rc"
(
  set +e
  organ_job_create "$concurrent_a"
  printf '%s\n' "$?" >"$concurrent_rc_a"
) &
concurrent_pid_a=$!
(
  set +e
  organ_job_create "$concurrent_b"
  printf '%s\n' "$?" >"$concurrent_rc_b"
) &
concurrent_pid_b=$!
wait "$concurrent_pid_a"
wait "$concurrent_pid_b"
assert_eq $'0\n73' "$(sort -n "$concurrent_rc_a" "$concurrent_rc_b")"
concurrent_winner="$(organ_job_read "$concurrent_job_id")"
if [[ "$concurrent_winner" != "$concurrent_a" && "$concurrent_winner" != "$concurrent_b" ]]; then
  printf 'concurrent job allocation produced an unknown receipt\n' >&2
  exit 1
fi

# Allocation retries only EEXIST, preserving the existing job and atomically
# publishing the next fresh ID.
retry_collision_id='local.job-20260816T120003Z-d1b2c3d4'
retry_fresh_id='local.job-20260816T120004Z-e1b2c3d4'
retry_existing="$(jq -cn --arg job_id "$retry_collision_id" '
  {schema_version:"1",job_id:$job_id,target:"claude-fable",host:"local",mode:"read",session_name:"organoun-fable",state:"done",delivery:"confirmed",artifacts:[]}')"
organ_job_create "$retry_existing"
retry_calls="$TEST_TMP/retry-id-calls"
: >"$retry_calls"
organ_job_new_id() {
  local call_count
  printf 'call\n' >>"$retry_calls"
  call_count="$(wc -l <"$retry_calls")"
  if [[ "$call_count" -eq 1 ]]; then
    printf '%s\n' "$retry_collision_id"
  else
    printf '%s\n' "$retry_fresh_id"
  fi
}
allocated_job_id="$(organ_job_create_read claude-managed local organoun-local)"
assert_eq "$retry_fresh_id" "$allocated_job_id"
assert_eq 2 "$(wc -l <"$retry_calls")"
assert_eq "$retry_existing" "$(organ_job_read "$retry_collision_id")"
assert_jq "$(organ_job_read "$retry_fresh_id")" '.target == "claude-managed" and .delivery == "unknown"'
