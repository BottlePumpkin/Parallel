# Issue Workflow Runbook — Design Spec

**Date:** 2026-06-18
**Status:** Approved (brainstorming)
**Topic:** Reusable, Claude-driven runbook for taking a GitHub issue from triage to a merged fix

## Problem

Incoming GitHub issues (e.g. [#2 단축키 제안](https://github.com/BottlePumpkin/Parallel/issues/2))
get handled ad hoc. There is no written, repeatable path from "an issue was filed"
to "a fix is merged and the issue is closed." The repo already has a strong
`superpowers` spec→plan→implement habit (`docs/superpowers/specs/` +
`docs/superpowers/plans/`), Conventional Commits, and a worktree-per-task layout —
but nothing ties issue intake into that machinery, so each issue is improvised.

## Goals

- One document Claude reads at the start of issue work, executes top-to-bottom, and
  pauses at explicit human gates.
- Size-aware: trivial issues take a fast path (implement + test directly); complex
  issues go through the full `superpowers` spec→plan flow. No over-process on small
  fixes, no under-process on risky ones.
- Delivery is standardized: a `issue-N` worktree/branch, a `Closes #N` commit, a PR
  via `gh`, and automatic issue close on merge.
- Irreversible / outward-facing steps (opening a PR) require explicit human approval.

## Non-Goals

- **No slash-command / automation infra** (no `.claude/commands/fix-issue.md`). The
  deliverable is a process document, not a tool. A thin pointer command may be added
  later once the runbook is stable, but it is out of scope here.
- **No CI bot / GitHub Action.** This describes how Claude + the human collaborate
  locally; it does not run unattended.
- **No change to existing superpowers skills.** The runbook *invokes*
  `brainstorming` and `writing-plans`; it does not modify them.
- **This spec does not fix issue #2.** Issue #2 (Ctrl+Tab tab switching) is used only
  as the worked example in the runbook's appendix; its actual implementation happens
  separately, by following this runbook.

## Executor & tone

Primary executor is **Claude (drives), with the human approving at gates.** The
document is therefore written in the imperative — "do X", "report Y to the human,
wait for approval" — and names concrete commands, tools, and gate points rather than
describing the process abstractly.

## Architecture

Single Markdown runbook at the repo root docs area:

```
docs/ISSUE_WORKFLOW.md
```

It is the single source of truth. Structure:

1. **Header** — purpose + who runs it (Claude-driven, human gates).
2. **Phase table** — the 5 phases below.
3. **Triage rubric** — trivial vs. complex decision criteria.
4. **Gates** — the 3 explicit human-approval points.
5. **Appendix** — command cheat sheet, commit/PR conventions, and the worked #2 example.

## Phases

| Phase | What Claude does | Gate (human approval) |
|---|---|---|
| **0. Pickup & Triage** | `gh issue view N`; summarize; judge labels/priority; **classify trivial vs. complex** | Report classification + approach → **wait for approval** |
| **1. Reproduce & Root-cause** | Explore relevant code (`Sources/…`); write a 1–3 line reproduction / root-cause note | — (escalate to a gate if genuinely ambiguous) |
| **2a. Fast-path** (trivial) | Proceed directly to Implement | none |
| **2b. Spec→Plan** (complex) | Run `superpowers` `brainstorming → writing-plans`; write spec + plan under `docs/superpowers/` | spec approved + plan approved |
| **3. Implement & Test** | Work in the `issue-N` worktree; implement; add/extend tests; `swift test` must pass | — |
| **4. Deliver** | `Closes #N` commit → `gh pr create` → review → issue auto-closes on merge | **Approval required before opening the PR** |

## Triage rubric (Phase 0)

- **Trivial → fast-path:** single or few files, behavior unambiguous, no new
  abstraction or architectural change, low regression risk. (e.g. add a keyboard
  shortcut, copy fix, small localized bug.)
- **Complex → spec→plan:** multiple modules, new abstraction/state, UX or data-flow
  decisions required, meaningful regression risk.
- **When unsure:** escalate to *complex*, and confirm with the human in one line.

## Gates (the 3 human-approval points)

1. **After Triage** — approve the classification (trivial/complex) and the one-line
   approach.
2. **(complex only) Spec & Plan** — approve each of the spec and the plan.
3. **Before opening the PR** — Claude reports a diff summary + test results; human
   approves, then `gh pr create` runs.

## Appendix content (to include in the runbook)

- **Command cheat sheet:** `gh issue view N`; create/enter the `issue-N` worktree;
  `swift test`; `gh pr create --body "… Closes #N"`; `gh issue comment`.
- **Commit / PR conventions:** existing Conventional Commit style (`fix(views): …`),
  body includes `Closes #N`.
- **Worked example — issue #2:** Ctrl+Tab tab switching → classified *trivial* →
  fast-path → implemented in `Sources/Parallel/Views/` with a test → PR `Closes #2`.
  (Illustrative; the real fix is done by running this runbook, not by this spec.)

## Testing / validation

This deliverable is a document, so "tests" are a self-review checklist applied after
writing `docs/ISSUE_WORKFLOW.md`:

- Every phase has a clear owner action and, where applicable, a named gate.
- The trivial/complex rubric is decidable (no "it depends" without a tiebreak rule).
- Commands in the cheat sheet are copy-pasteable and match the repo's real layout
  (worktree paths, `swift test`, `gh` usage, github.com remote).
- The #2 example is consistent with the rubric (it is genuinely trivial).
