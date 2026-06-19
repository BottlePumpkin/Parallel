# E2E Test Automation — Design Spec

**Date:** 2026-06-19
**Status:** Approved, ready for planning
**Topic:** UI-driven end-to-end test automation for the Parallel macOS app

## Problem

Parallel has 85 `swift test` unit tests covering the pure-logic surface, but the
README states plainly: *"Views and `SessionManager` are verified manually."* The
view layer, the wiring in `ParallelApp`/`ContentView`, and the live PTY/session
flow have no automated coverage. We want **real UI-driven e2e** — drive the
rendered app like a user (click "+ New Worktree", type a branch, assert the
terminal appears and is interactive) — and run it in CI.

## Constraints & Context

- The repo is **SwiftPM-only** (`Package.swift`, no `.xcodeproj`). XCUITest
  requires an Xcode project with a UI Test target.
- The app spawns **real PTYs** (`forkpty` via `PTY.swift`) and shells out to
  **real `git`** — true e2e touches the filesystem and git state.
- The terminal is **SwiftTerm** (an AppKit `TerminalView`); its rendered text is
  **not exposed in the Accessibility (AX) tree**, so terminal output can't be
  asserted by reading AX text.
- "Add Repo" uses a native **NSOpenPanel**, which XCUITest cannot easily drive.
- Must run on **GitHub Actions macOS runners** as a CI gate.

## Goals

1. Deterministic, repeatable UI e2e suite that gates PRs in CI (primary).
2. A shared foundation that a future exploratory agent layer can reuse.
3. Zero impact on production behavior — all test affordances gated behind an
   environment flag.

## Non-Goals (YAGNI)

- Pixel/screenshot comparison of rendered terminal text — sentinel files and
  state probes are sufficient.
- Automating the native NSOpenPanel — tests seed `workspace.json` instead.
- Running the exploratory agent layer (Layer B) in CI — it is non-deterministic.

## Architecture — Shared Foundation, Two Layers

```
   Layer A  │  XCUITest (deterministic)  ← primary, CI gate
            │  launches the real .app, clicks/types/asserts
   ─────────┼──────────────────────────────────────────────
   Layer B  │  Agent + macOS-automation MCP (exploratory)
  (later)   │  reuses the same AX ids + fixtures, human-invoked
   ─────────────────  Shared foundation (built now)  ─────────────────
   • AX identifiers (.accessibilityIdentifier)
   • Test run mode (PARALLEL_E2E=1 env gate)
   • Isolated fixtures (temp git repo + isolated support dir)
   • Terminal verification bypass (state probe + sentinel file)
```

The existing 85 `swift test` unit tests stay unchanged and run as a separate,
parallel CI job. E2E sits on top.

## Component 1 — App Test Affordances (`Sources/Parallel/`)

All affordances are gated behind the `PARALLEL_E2E=1` environment variable.
When unset, the app behaves exactly as it does in production.

### (a) Support-directory isolation — `ParallelApp.swift:17`

Replace the hardcoded `WorkspaceStore.defaultDirectory` with an env override:

```swift
let dir = ProcessInfo.processInfo.environment["PARALLEL_SUPPORT_DIR"]
    .map { URL(fileURLWithPath: $0) } ?? WorkspaceStore.defaultDirectory
let s = WorkspaceStore(directory: dir)
```

`WorkspaceStore` already takes `init(directory:)`, so this is a minimal change.
Tests pass a temp folder so the user's real `workspace.json` is never touched.

### (b) Accessibility identifiers

Attach `.accessibilityIdentifier(...)` to the controls the suite drives:

- Sidebar worktree rows: `wt.<uuid>`
- `+ New Worktree` button and `⌘N` target
- Sheet fields/buttons: e.g. `sheet.newWorktree.branch`, `sheet.newWorktree.create`,
  `sheet.deleteWorktree.confirm`
- Tab bar: tab items and the `+` add-tab control

These selectors serve both Layer A and Layer B.

### (c) Terminal verification bypass

Because SwiftTerm text is not in the AX tree, verify the terminal two ways:

- **State probe**: a hidden AX element, present only when `PARALLEL_E2E=1`, that
  exposes `SessionManager` state — `e2e.runningSessionCount` (value =
  `allRunningSessions.count`) and `e2e.activeWorktreeId`. Lets tests assert
  "adding a worktree created exactly one running session."
- **Sentinel file**: proves a true PTY round-trip. The test types
  `echo PARALLEL_READY > $PROBE_FILE\n` into the terminal and polls for the
  file. This confirms the shell is actually alive and accepting input
  end-to-end (PTY fork → write → shell exec → filesystem).

### (d) Determinism guards (gated by `PARALLEL_E2E=1`)

- Skip the GitHub Releases update-check network poll.
- Skip the notification permission prompt.
- Skip caffeinate / IOPMAssertion.
- The 500ms setup-command delay is irrelevant to tests (they use sentinel
  polling instead of relying on timing).

## Component 2 — Fixtures & Isolation

- **Temp git repo seeder**: each test creates a throwaway repo in a unique temp
  dir (`git init` + a dummy commit) so git operations have a real target.
- **NSOpenPanel avoidance**: instead of driving the native "Add Repo" panel, the
  test pre-writes a seeded `workspace.json` (pointing at the temp repo) into the
  isolated support dir, so the app launches already showing one registered repo.
- Per-test unique temp dirs make runs independent, parallel-safe, and repeatable.

## Component 3 — xcodegen Project Structure

- `project.yml` (committed) generates `Parallel.xcodeproj` (gitignored).
- Two targets:
  - **App target `Parallel`** — compiles `Sources/Parallel/**`, links SwiftTerm
    as an SPM dependency, produces the `.app` bundle.
  - **UI Test target `ParallelUITests`** — XCUITest cases in
    `Tests/ParallelUITests/**` (committed).
- The existing SwiftPM unit tests (`swift test`) are untouched. The Xcode
  project exists purely to build the `.app` and run UI tests.

## Component 4 — First XCUITest Suite

Implemented TDD-style: write S1 failing first, make it pass (validating the
affordances), then expand. **S1, S2, S5 are the first smoke set.**

| ID | Scenario | Assertions |
|----|----------|-----------|
| **S1** | Launch with seeded repo | Sidebar shows the repo group + worktree row |
| **S2** | `⌘N` → sheet → type branch → create | New worktree row appears; `runningSessionCount` +1; sentinel file proves the PTY is live |
| **S5** | `⌘⌫` → confirm sheet → delete | Row disappears; sessions terminated (count drops) |
| S3 | Tab add / rename / switch / close (`⌘W`) | Session count changes as expected |
| S4 | `⌘1` / `⌘2` worktree switch | `activeWorktreeId` probe updates |
| S6 | Open & dismiss Report Issue / Import sheets | Opens and closes with no external side effects |

## Component 5 — CI Workflow

`.github/workflows/e2e.yml` on `macos-14`:

```
brew install xcodegen
xcodegen generate
xcodebuild test -scheme ParallelUITests -destination 'platform=macOS'
```

- macOS runners provide the GUI session XCUITest needs; git and `forkpty` work;
  ad-hoc signing is sufficient.
- Runs as a **separate, parallel job** from the existing `swift test` unit job.
- One automatic retry to absorb UI-test flakiness.

## Component 6 — Layer B (Exploratory Agent) — Later

Once the AX identifiers and test mode exist, an agent driving a macOS-automation
MCP reuses the same selectors and fixtures for exploratory click-throughs. No
code is written now — only the seam is reserved. This requires installing a
separate MCP server and is **not** a CI gate (it is non-deterministic).

## Verification Strategy

The test infrastructure itself is validated incrementally: S1 is written to fail
first, then each affordance (support-dir isolation, AX identifiers, state probe,
sentinel file, seeded workspace) is implemented until S1 passes. S2 and S5 follow
the same loop. Green CI on `macos-14` is the acceptance signal.

## Open Risks

- **XCUITest flakiness on CI** — mitigated by sentinel polling (no fixed sleeps),
  unique per-test temp dirs, and a single retry.
- **Login-shell variability** — `startSession` uses the user's `$SHELL` and loads
  `.zshrc`; on CI the runner's shell is used. Sentinel verification only depends
  on `echo`/redirection, which is shell-agnostic.
- **xcodegen app target wiring** — linking SwiftTerm and compiling `Sources/**`
  through a generated app target must match the SwiftPM build; verified by the
  app launching cleanly under XCUITest.
