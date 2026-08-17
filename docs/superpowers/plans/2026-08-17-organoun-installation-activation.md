---
status: operator-approved
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
---

# Organoun Installation and Project Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the public checkout teach and enforce the approved separation between one-time installation and per-project Organoun activation.

**Architecture:** Preserve the runtime. Tighten the installed skill and operational runbook and add two human-facing guide artifacts. The final session handoff is context only and does not add a product command.

**Tech Stack:** Bash, Markdown, standalone HTML/CSS/JavaScript, Make.

## Global Constraints

- No pane, SSH connection, Claude process, or parallel event is created by this change.
- Installation never collects project routing data.
- Onboarding data stays project-local and Git-ignored.
- `organ onboard` and `organ init --json` remain mutually exclusive actions in one interaction.

---

### Task 1: Skill activation decision

**Files:**
- Modify: `tests/test_install_skill.sh`
- Modify: `skills/organoun/SKILL.md`
- Modify: `docs/operations.md`

**Interfaces:**
- Consumes: installed `organ`, current Git root, `TMUX`, `TMUX_PANE`, project deployment.
- Produces: a deterministic install/tmux/onboard/init decision and final operator handoff sentence.

- [ ] Add a failing contract check for install availability, tmux-first refusal,
      exclusive onboard/init selection, and the exact final sentence.
- [ ] Run `bash tests/test_install_skill.sh --assert-skill-contract skills/organoun/SKILL.md`
      and confirm the missing contract fails.
- [ ] Add the minimal positive recipe to the skill and align the runbook.
- [ ] Re-run the focused contract and installer test.

### Task 2: Human onboarding guide

**Files:**
- Create: `docs/README.onboarding.md`
- Create: `docs/onboarding.html`

**Interfaces:**
- Consumes: the approved installation and project-activation contract.
- Produces: a copyable Markdown candidate and an offline responsive HTML guide.

- [ ] Write the canonical human sequence in Markdown using placeholders only.
- [ ] Implement a semantic, responsive, printable HTML page with copy buttons and
      a Markdown download action.
- [ ] Verify both artifacts contain the same commands, decision branches, receipts,
      and stop points.

### Task 3: Verification and publication

**Files:**
- Verify all files above.

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: a reviewed commit synchronized to `origin/main`.

- [ ] Run focused skill/installer checks, Bash syntax, ShellCheck, HTML parsing when
      available, and `git diff --check`.
- [ ] Inspect the final diff for host/path/credential leakage.
- [ ] Commit intentionally and push `main` after the local commit is verified.
- [ ] Produce a contextual session handoff naming the public checkout, commit, guide
      paths, and exact next human test.
