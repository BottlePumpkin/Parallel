# Issue Workflow

A runbook for taking a GitHub issue from filed to fixed-and-closed.

**Who runs this:** Claude drives each phase; the human approves at the gates marked
below. Claude executes top-to-bottom, pausing only at the three gates.

**When to use:** Any time work starts from a GitHub issue in this repo.

## Phases

| Phase | Claude does | Gate (human approval) |
|---|---|---|
| **0. Pickup & Triage** | `gh issue view N`; summarize the ask; judge labels/priority; **classify trivial vs. complex** (see rubric) | Report classification + one-line approach → **wait for approval** |
| **1. Reproduce & Root-cause** | Explore relevant code under `Sources/…`; write a 1–3 line reproduction / root-cause note | — (escalate to a gate only if genuinely ambiguous) |
| **2a. Fast-path** (trivial) | Skip straight to Phase 3 | none |
| **2b. Spec → Plan** (complex) | Run `superpowers` `brainstorming → writing-plans`; write spec + plan under `docs/superpowers/` | spec approved **and** plan approved |
| **3. Implement & Test** | Work in the `issue-N` worktree; implement; add/extend tests; `swift test` must pass | — |
| **4. Deliver** | `Closes #N` commit → `gh pr create` → human review → issue auto-closes on merge | **Approval required before opening the PR** |

## Triage rubric (Phase 0)

Classify the issue so Phase 2 takes the right path:

- **Trivial → fast-path (2a):** single or few files, behavior is unambiguous, no new
  abstraction or architectural change, low regression risk. Examples: add a keyboard
  shortcut, fix copy, small localized bug.
- **Complex → spec → plan (2b):** multiple modules, a new abstraction or piece of
  state, UX or data-flow decisions to make, or meaningful regression risk.
- **Tiebreak — when unsure, treat as complex** and confirm with the human in one line.

## Gates (the 3 human-approval points)

1. **After Triage** — approve the classification (trivial/complex) and the one-line
   approach before any code is written.
2. **(complex only) Spec & Plan** — approve the spec, then approve the plan.
3. **Before opening the PR** — Claude reports a diff summary and `swift test` results;
   the human approves, then `gh pr create` runs. Opening a PR is outward-facing, so it
   never happens without this approval.
