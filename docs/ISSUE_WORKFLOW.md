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
| **3. Implement & Test** | Work in the `issue-N` worktree; implement; **add/extend tests per the [Test policy](#test-policy-phase-3) below**; both `swift test` and the XCUITest suite must pass | — |
| **4. Deliver** | `Closes #N` commit → `gh pr create` → human review → issue auto-closes on merge | **Approval required before opening the PR** |

## Triage rubric (Phase 0)

Classify the issue so the correct Phase 2 branch (2a or 2b) is taken:

- **Trivial → fast-path (2a):** single or few files, behavior is unambiguous, no new
  abstraction or architectural change, low regression risk. Examples: add a keyboard
  shortcut, fix copy, small localized bug.
- **Complex → spec → plan (2b):** multiple modules, a new abstraction or piece of
  state, UX or data-flow decisions to make, or meaningful regression risk.
- **Tiebreak — when unsure, treat as complex** and confirm with the human in one line.

## Test policy (Phase 3)

Tests are not optional. Phase 3 is "Implement **& Test**" — a fix without tests is
not deliverable. Decide *which* layer the change needs, then **always run both
suites** as a regression check before delivery.

**Always — unit tests (`swift test`)**
- Add or extend a unit test for every piece of logic the change introduces or
  modifies (parsers, calculators, state transitions, clamps, formatters).
- Pure-logic issues stop here for *new* tests, but still run e2e for regression.

**Conditionally — e2e tests (XCUITest, `Tests/ParallelUITests/`)**
- **Required** when the change touches the view layer or live session flow:
  anything under `Sources/Parallel/Views/**`, menu commands / `ParallelCommands`,
  keyboard shortcuts, `SessionManager`, or the PTY/terminal interaction.
- Drive the real `.app` (click / type / assert) following the existing
  `Tests/ParallelUITests/` patterns; assert via accessibility identifiers and,
  for terminal/session state SwiftTerm hides from the AX tree, the
  `E2EProbeView` state probe or a sentinel-file round-trip.
- **Where e2e genuinely cannot reach** (e.g. SwiftTerm-internal state with no
  probe hook): state this in one line in the PR, expose a probe value if cheap,
  and fall back to unit coverage of the underlying logic + a manual-check note.

**Always — run both before the PR**
- `swift test` **and** the XCUITest suite must be green even when you added no new
  e2e test. Capture both results as the Gate 3 evidence (see below).

> See [`docs/superpowers/specs/2026-06-19-e2e-test-automation-design.md`](superpowers/specs/2026-06-19-e2e-test-automation-design.md)
> for the e2e architecture (test affordances, probe, fixtures).

## Gates (the 3 human-approval points)

1. **After Triage** — approve the classification (trivial/complex) and the one-line
   approach before any code is written.
2. **(complex only) Spec & Plan** — two approval steps: approve the spec first, then approve the plan.
3. **Before opening the PR** — Claude reports a diff summary **and the results of
   both test suites** (`swift test` *and* the XCUITest run — command + pass count,
   plus a one-line note for any e2e the change couldn't reach per the Test policy);
   the human approves, then `gh pr create` runs. Opening a PR is outward-facing, so it
   never happens without this approval.

## Appendix

### Command cheat sheet

```bash
# 0. Survey the board (the cross-session source of truth) and read the issue
gh issue list                       # all open
gh issue list --label in-progress   # already being worked on — don't double-pick
gh issue view N

# 3. Work in a per-issue worktree. Naming is FIXED: worktree + branch = issue-N
#    (so there's never a name to invent). The helper verifies the issue exists,
#    creates the worktree off the latest master, AND marks the issue
#    in-progress + assigns it to you so every other session/worktree sees it:
./scripts/new-issue-worktree.sh N
#    …equivalent to:
git worktree add .claude/worktrees/issue-N -b issue-N origin/master
gh issue edit N --add-label in-progress --add-assignee @me   # merging Closes #N clears it

# 3. Run BOTH suites before delivery (Test policy). Unit:
swift test
# e2e (XCUITest) — generate the project, then drive the real .app:
xcodebuild -downloadComponent MetalToolchain || true   # one-time, no-op where unsupported
xcodegen generate
xcodebuild test -project Parallel.xcodeproj -scheme Parallel \
  -destination 'platform=macOS' -only-testing:ParallelUITests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES

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
  (next-tab on Ctrl+Tab, previous-tab on Ctrl+Shift+Tab). Per the Test policy: a
  unit test covers the next/previous index math, and — because this touches menu
  commands / the view layer — an XCUITest drives the shortcut and asserts the tab
  change via the probe. Both `swift test` and the XCUITest suite pass.
- **Phase 4 — Deliver:** commit `fix(views): switch shell tabs with Ctrl+Tab`,
  PR body `Closes #2`, merge.

> This is illustrative. The real #2 fix is produced by running this runbook, not by
> reading this example.
