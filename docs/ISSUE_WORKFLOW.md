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
