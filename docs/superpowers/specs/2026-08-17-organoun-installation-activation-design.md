# Organoun Installation and Project Activation Design

**Status:** operator-approved on 2026-08-17

## Goal

Separate the one-time machine installation from project-local activation so a
human can install Organoun once and invoke it only inside repositories where it
must operate.

## Contract

### Machine installation

From a dedicated source checkout outside application repositories, the operator
runs `./scripts/install-organoun.sh --apply`. This publishes the CLI, runtime,
and Codex skill under the operator's home. It does not collect a host, remote
CWD, or project root and does not create `.organoun/` in the source checkout.

### Project activation

The operator enters the canonical Git root of an application, starts or enters
the local tmux session that will remain visible, and starts Codex there. The
request “inicialize o `$organoun` aqui” triggers this deterministic decision:

1. refuse if the `organ` CLI or Organoun skill is unavailable;
2. refuse and give restart instructions if this Codex process is not inside the
   visible tmux owner pane;
3. if `.organoun/deployment.json` is absent or invalid, execute only
   `organ onboard`, report `state=connected`, and stop;
4. if it is valid, execute only `organ init --json`;
5. after `state=initialized`, say exactly:
   `Organoun ativo nesta sessão. O que vamos criar hoje?`

`onboard` remains project-local and write-once. It stores the project root, SSH
alias, and remote CWD only in `<project>/.organoun/deployment.json`; project
state remains under `<project>/.organoun/state/`. Both paths are ignored by Git.

## Human guide

`docs/onboarding.html` is a standalone responsive and printable page. It has no
network assets or external dependencies. `docs/README.onboarding.md` contains
the same operational sequence and is the candidate root README, but this change
does not promote it to `README.md`.

## Non-goals

- no global deployment registry;
- no remote installation;
- no pane creation during installation, onboarding, guide validation, or
  handoff;
- no Makefile or product command for handoff; the session handoff is only a
  contextual record for the next Codex interaction;
- no change to claims, dispatch, verification, or transport behavior.
