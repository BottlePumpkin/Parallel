# Issue Workflow Runbook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `docs/ISSUE_WORKFLOW.md`, a Claude-driven runbook that takes a GitHub issue from triage to a merged fix, with size-aware branching and explicit human gates.

**Architecture:** A single Markdown file is the source of truth. It is built up section by section (header → phase table → triage rubric → gates → appendix), then validated against a self-review checklist derived from the spec. No code, no automation infra — this is a documentation deliverable.

**Tech Stack:** Markdown. Validation by manual checklist (the spec's "Testing / validation" section). Reference repo facts: worktree layout (`issue-N` branch in `.claude/worktrees/`), `swift test`, `gh` CLI authed to github.com, Conventional Commits.

**Spec:** `docs/superpowers/specs/2026-06-18-issue-workflow-design.md`

---

### Task 1: Create the runbook with header + phase table

**Files:**
- Create: `docs/ISSUE_WORKFLOW.md`

- [ ] **Step 1: Create the file with the header and phase table**

Write `docs/ISSUE_WORKFLOW.md` with exactly this content:

````markdown
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
````

- [ ] **Step 2: Verify the file renders and the table is well-formed**

Run: `head -30 docs/ISSUE_WORKFLOW.md`
Expected: the header block and a 6-row phase table print with aligned `|` columns.

- [ ] **Step 3: Commit**

```bash
git add docs/ISSUE_WORKFLOW.md
git commit -m "docs: add issue workflow runbook (header + phases)"
```

---

### Task 2: Add the triage rubric and gates sections

**Files:**
- Modify: `docs/ISSUE_WORKFLOW.md` (append after the phase table)

- [ ] **Step 1: Append the triage rubric and gates**

Append exactly this content to `docs/ISSUE_WORKFLOW.md`:

````markdown

## Triage rubric (Phase 0)

Classify the issue so the correct Phase 2 branch (2a or 2b) is taken:

- **Trivial → fast-path (2a):** single or few files, behavior is unambiguous, no new
  abstraction or architectural change, low regression risk. Examples: add a keyboard
  shortcut, fix copy, small localized bug.
- **Complex → spec → plan (2b):** multiple modules, a new abstraction or piece of
  state, UX or data-flow decisions to make, or meaningful regression risk.
- **Tiebreak — when unsure, treat as complex** and confirm with the human in one line.

## Gates (the 3 human-approval points)

1. **After Triage** — approve the classification (trivial/complex) and the one-line
   approach before any code is written.
2. **(complex only) Spec & Plan** — two approval steps: approve the spec first, then approve the plan.
3. **Before opening the PR** — Claude reports a diff summary and `swift test` results;
   the human approves, then `gh pr create` runs. Opening a PR is outward-facing, so it
   never happens without this approval.
````

- [ ] **Step 2: Verify both sections were appended**

Run: `grep -n "^## " docs/ISSUE_WORKFLOW.md`
Expected: lines for `## Phases`, `## Triage rubric (Phase 0)`, and `## Gates (the 3 human-approval points)`.

- [ ] **Step 3: Commit**

```bash
git add docs/ISSUE_WORKFLOW.md
git commit -m "docs: add triage rubric and gates to issue workflow"
```

---

### Task 3: Add the appendix (cheat sheet, conventions, worked example)

**Files:**
- Modify: `docs/ISSUE_WORKFLOW.md` (append after the gates)

- [ ] **Step 1: Append the appendix**

Append exactly this content to `docs/ISSUE_WORKFLOW.md`:

````markdown

## Appendix

### Command cheat sheet

```bash
# 0. Read the issue
gh issue view N

# 3. Work in a per-issue worktree (branch issue-N under .claude/worktrees/)
git worktree add .claude/worktrees/issue-N -b issue-N
swift test                       # must pass before delivery

# 4. Open the PR (after the human approves)
gh pr create --title "fix: <summary>" --body "$(cat <<'EOF'
<what changed and why>

Closes #N
EOF
)"

# Optional: leave a status note on the issue
gh issue comment N --body "<note>"
```

> `gh` is authed to **github.com** for this repo (the company GHE auth is a separate
> host). If `gh` targets the wrong host, run `gh auth switch --hostname github.com`.

### Commit / PR conventions

- Conventional Commits, matching the repo: `fix(views): …`, `feat(services): …`,
  `docs: …`, `test: …`.
- The PR body (or a commit) includes `Closes #N` so the issue auto-closes on merge.

### Worked example — issue #2

Issue [#2 단축키 제안](https://github.com/BottlePumpkin/Parallel/issues/2): make
Ctrl+Tab switch shell tabs.

- **Phase 0 — Triage:** single concern, keyboard handling lives in
  `Sources/Parallel/Views/`, no new architecture → **trivial → fast-path**.
- **Phase 1 — Root-cause:** no Ctrl+Tab handler is wired to the tab strip.
- **Phase 2a — Fast-path:** nothing to design; skip straight to Phase 3.
- **Phase 3 — Implement & Test:** add the shortcut in `Sources/Parallel/Views/`
  (next-tab on Ctrl+Tab, previous-tab on Ctrl+Shift+Tab), with a test covering the
  next/previous index math; `swift test` passes.
- **Phase 4 — Deliver:** commit `fix(views): switch shell tabs with Ctrl+Tab`,
  PR body `Closes #2`, merge.

> This is illustrative. The real #2 fix is produced by running this runbook, not by
> reading this example.
````

- [ ] **Step 2: Verify the appendix sections exist**

Run: `grep -n "^### " docs/ISSUE_WORKFLOW.md`
Expected: lines for `### Command cheat sheet`, `### Commit / PR conventions`, and `### Worked example — issue #2`.

- [ ] **Step 3: Commit**

```bash
git add docs/ISSUE_WORKFLOW.md
git commit -m "docs: add appendix (cheat sheet, conventions, #2 example) to issue workflow"
```

---

### Task 4: Validate the runbook against the spec checklist

**Files:**
- Read: `docs/ISSUE_WORKFLOW.md`
- Read: `docs/superpowers/specs/2026-06-18-issue-workflow-design.md`

- [ ] **Step 1: Run the self-review checklist from the spec**

Read the full runbook and confirm each item from the spec's "Testing / validation"
section. Check, and fix inline if any fails:

1. Every phase has a clear owner action, and gated phases name their gate.
2. The trivial/complex rubric is decidable — the tiebreak rule ("when unsure, treat
   as complex") resolves ambiguity.
3. Every command in the cheat sheet is copy-pasteable and matches the real repo:
   worktree path `.claude/worktrees/issue-N`, `swift test`, `gh` on github.com,
   `Closes #N` convention.
4. The #2 worked example is consistent with the rubric (it is genuinely trivial).

- [ ] **Step 2: Confirm no placeholders remain**

Run: `grep -niE "TODO|TBD|FIXME|fill in" docs/ISSUE_WORKFLOW.md`
Expected: no output (exit status 1 / empty).

- [ ] **Step 3: Commit any fixes from validation**

Only if Step 1 required edits:

```bash
git add docs/ISSUE_WORKFLOW.md
git commit -m "docs: tighten issue workflow after self-review"
```

If no edits were needed, skip this commit — the runbook is complete.

---

## Self-Review (plan author)

**Spec coverage:**
- Executor & tone (Claude-driven, imperative) → Task 1 header. ✓
- 5-phase structure with size branch → Task 1 phase table. ✓
- Triage rubric (trivial/complex + tiebreak) → Task 2. ✓
- 3 gates → Task 2. ✓
- Appendix (cheat sheet, commit/PR conventions, #2 example) → Task 3. ✓
- Validation checklist → Task 4. ✓
- Non-goal "this spec does not fix #2" → enforced by Task 3's example disclaimer and
  the plan producing only `docs/ISSUE_WORKFLOW.md` (no Swift changes). ✓

**Placeholder scan:** No TODO/TBD; all section content is provided literally. ✓

**Type/string consistency:** Phase names (`2a Fast-path`, `2b Spec → Plan`), gate
count (3), worktree path (`.claude/worktrees/issue-N`), and `Closes #N` are identical
across Tasks 1–4. ✓
