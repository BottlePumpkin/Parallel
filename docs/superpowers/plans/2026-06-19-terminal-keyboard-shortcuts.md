# Terminal Keyboard Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add terminal-standard keyboard shortcuts (tab switching, clear, new tab, find) and fix the broken ⌘1–9 worktree mapping, resolving issue [#2](https://github.com/BottlePumpkin/Parallel/issues/2).

**Architecture:** Pure index/ordering helpers live in `SessionManager` and `WorkspaceStore` and are unit-tested. Thin action methods on `SessionManager` mutate active-tab state or feed escape sequences to the active `TerminalView`. `ContentActions` exposes callbacks; `ParallelCommands` binds them to menu items + shortcuts; `ContentView` wires them using the currently selected worktree. UI/menu wiring is verified by `swift build` + `swift test`; the pure cores carry the unit tests.

**Tech Stack:** SwiftUI `Commands`/`keyboardShortcut`, SwiftTerm 1.13 (`TerminalView.feed(byteArray:)`, `performTextFinderAction(_:)`), XCTest.

**Issue:** #2 (단축키 제안 — Ctrl+Tab tab switching). Scope expanded during triage by the maintainer.

---

## Design & rationale (serves as the spec)

### Problem found during triage
- No terminal-style shortcuts exist; `Commands.swift` only has worktree/app-level ones.
- **⌘1–9 is buggy:** it selects `store.worktrees[N-1]` (raw append-order array), but the
  sidebar shows worktrees **grouped by repo** (`store.repos` order × each repo's worktrees).
  With ≥2 repos, or after reordering repos/worktrees, the Nth visible row ≠ `worktrees[N-1]`,
  so ⌘N selects the wrong worktree. Confirmed in `SidebarView.swift:19-21` vs
  `ContentView.swift:143-147`.

### Decided keyboard scheme (maintainer-approved)

| Shortcut | Action | Note |
|---|---|---|
| **⌘1–9** | Switch to **tab N** in current worktree | new (was worktree) |
| **⌃Tab / ⌃⇧Tab** | Next / previous tab (wrap-around) | new — issue #2 |
| **⌘⌥1–9** | Switch to **worktree N** (sidebar-visible order) | moved + bug fixed |
| **⌘K** | Clear screen + scrollback (display-side) | new |
| **⌘T** | New tab in current worktree | new |
| **⌘F** | Show terminal find bar | new |

- Worktree moved to **⌘⌥**1–9 to avoid macOS conflicts (⌃-number = Mission Control spaces,
  ⌘⇧-number = screenshots).
- **⌘K** feeds `ESC[H ESC[2J ESC[3J` to the view only (verified SwiftTerm handles ED param 3 =
  scrollback erase in `Terminal.swift` `cmdEraseInDisplay`). The shell is not sent anything, so
  no running program is disturbed — matches Terminal.app ⌘K. The prompt redraws on next input.
- **⌘F** uses SwiftTerm's public `performTextFinderAction(_:)` with an `NSMenuItem` whose
  `tag = NSTextFinder.Action.showFindInterface.rawValue` (the `showFindBar` method itself is
  private; this is the supported entry point).

### Files
- Modify: `Sources/Parallel/Persistence/WorkspaceStore.swift` — add `orderedWorktrees`.
- Modify: `Sources/Parallel/Services/SessionManager.swift` — add `adjacentTabIndex` + 4 methods.
- Modify: `Sources/Parallel/Views/Commands.swift` — `ContentActions` fields + menus.
- Modify: `Sources/Parallel/Views/ContentView.swift` — wire `focusedActions`.
- Create: `Tests/ParallelTests/TerminalShortcutsTests.swift` — pure-core unit tests.

---

### Task 1: Pure helpers + unit tests (TDD)

**Files:**
- Create: `Tests/ParallelTests/TerminalShortcutsTests.swift`
- Modify: `Sources/Parallel/Services/SessionManager.swift`
- Modify: `Sources/Parallel/Persistence/WorkspaceStore.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ParallelTests/TerminalShortcutsTests.swift`:

```swift
import XCTest
@testable import Parallel

final class TerminalShortcutsTests: XCTestCase {

    // MARK: - adjacentTabIndex (tab cycling math)

    func test_adjacentTabIndex_forward_wraps_at_end() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 2, count: 3, forward: true), 0)
    }

    func test_adjacentTabIndex_forward_advances() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 3, forward: true), 1)
    }

    func test_adjacentTabIndex_backward_wraps_at_start() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 3, forward: false), 2)
    }

    func test_adjacentTabIndex_backward_retreats() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 2, count: 3, forward: false), 1)
    }

    func test_adjacentTabIndex_single_tab_stays() {
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 1, forward: true), 0)
        XCTAssertEqual(SessionManager.adjacentTabIndex(from: 0, count: 1, forward: false), 0)
    }

    func test_adjacentTabIndex_no_tabs_isNil() {
        XCTAssertNil(SessionManager.adjacentTabIndex(from: 0, count: 0, forward: true))
    }

    // MARK: - orderedWorktrees (sidebar-visible order = the ⌘⌥1–9 fix)

    func test_orderedWorktrees_groups_by_repo_in_sidebar_order() {
        let store = WorkspaceStore(directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        let repoA = Repo(root: URL(fileURLWithPath: "/tmp/a"), displayName: "A")
        let repoB = Repo(root: URL(fileURLWithPath: "/tmp/b"), displayName: "B")
        store.repos = [repoA, repoB]
        // Raw array interleaved across repos (the bug scenario): A1, B1, A2.
        let a1 = Worktree(repoId: repoA.id, path: URL(fileURLWithPath: "/tmp/a/1"), branch: "a1", displayName: "a1")
        let b1 = Worktree(repoId: repoB.id, path: URL(fileURLWithPath: "/tmp/b/1"), branch: "b1", displayName: "b1")
        let a2 = Worktree(repoId: repoA.id, path: URL(fileURLWithPath: "/tmp/a/2"), branch: "a2", displayName: "a2")
        store.worktrees = [a1, b1, a2]

        // Sidebar shows A:{a1,a2} then B:{b1} → visible order a1,a2,b1.
        XCTAssertEqual(store.orderedWorktrees.map(\.id), [a1.id, a2.id, b1.id])
        // Raw index 1 was b1 (the bug); visible index 1 is now a2.
        XCTAssertEqual(store.orderedWorktrees[1].id, a2.id)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TerminalShortcutsTests`
Expected: FAIL — `adjacentTabIndex` and `orderedWorktrees` don't exist yet (compile error).

- [ ] **Step 3: Add `adjacentTabIndex` to SessionManager**

In `Sources/Parallel/Services/SessionManager.swift`, add inside `final class SessionManager`, just after the `feedBytesPerHop` constant (around line 18):

```swift
    /// Index to activate when cycling `forward` (or backward) through `count`
    /// tabs from `current`, wrapping around. nil when there are no tabs. Pure
    /// math, unit-tested independently of any live PTY.
    static func adjacentTabIndex(from current: Int, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        let delta = forward ? 1 : -1
        return ((current + delta) % count + count) % count
    }
```

- [ ] **Step 4: Add `orderedWorktrees` to WorkspaceStore**

In `Sources/Parallel/Persistence/WorkspaceStore.swift`, add after the `worktree(id:)` method (around line 203):

```swift
    /// Worktrees in the order the sidebar displays them: grouped by repo (in
    /// `repos` order), each repo's worktrees in `worktrees` array order. ⌘⌥1–9
    /// selects by THIS visible order, not the raw `worktrees` index — the raw
    /// array is interleaved across repos and doesn't match what the user sees.
    var orderedWorktrees: [Worktree] {
        repos.flatMap { repo in worktrees.filter { $0.repoId == repo.id } }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter TerminalShortcutsTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Commit**

```bash
git add Tests/ParallelTests/TerminalShortcutsTests.swift Sources/Parallel/Services/SessionManager.swift Sources/Parallel/Persistence/WorkspaceStore.swift
git commit -m "feat(services): tab-cycle index math + sidebar-ordered worktrees"
```

---

### Task 2: SessionManager action methods

**Files:**
- Modify: `Sources/Parallel/Services/SessionManager.swift`

- [ ] **Step 1: Add the four action methods**

In `Sources/Parallel/Services/SessionManager.swift`, add to the `// MARK: - Mutations` section, after `setActive(sessionId:in:)` (around line 228):

```swift
    /// Cycle the active tab in a worktree's strip (⌃Tab / ⌃⇧Tab).
    func activateAdjacentTab(in worktreeId: UUID, forward: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let order = orderByWorktree[worktreeId], !order.isEmpty else { return }
        let currentIdx = activeByWorktree[worktreeId].flatMap { order.firstIndex(of: $0) } ?? 0
        guard let nextIdx = Self.adjacentTabIndex(from: currentIdx, count: order.count, forward: forward) else { return }
        activeByWorktree[worktreeId] = order[nextIdx]
    }

    /// Activate the tab at `index` (0-based) in a worktree's strip, if present (⌘1–9).
    func activateTab(in worktreeId: UUID, at index: Int) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let order = orderByWorktree[worktreeId], index >= 0, index < order.count else { return }
        activeByWorktree[worktreeId] = order[index]
    }

    /// Clear the active tab's screen + scrollback (⌘K). Display-side only: the
    /// shell is NOT sent anything, so a running program isn't disturbed. ESC[H
    /// home, ESC[2J erase screen, ESC[3J erase scrollback.
    func clearActiveTerminal(in worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let view = activeSession(for: worktreeId)?.terminalView else { return }
        let seq: [UInt8] = Array("\u{1b}[H\u{1b}[2J\u{1b}[3J".utf8)
        view.feed(byteArray: seq[...])
    }

    /// Show SwiftTerm's built-in find bar on the active tab (⌘F). Uses the
    /// public performTextFinderAction entry point; showFindBar is private.
    func showFind(in worktreeId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let view = activeSession(for: worktreeId)?.terminalView else { return }
        let item = NSMenuItem()
        item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        view.performTextFinderAction(item)
    }
```

(New-tab reuses the existing `startSession(for:setupCommands:)` — no new method needed.)

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds. (`AppKit` is already imported in this file, so `NSMenuItem` / `NSTextFinder` resolve.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Parallel/Services/SessionManager.swift
git commit -m "feat(services): tab switch/clear/find actions on SessionManager"
```

---

### Task 3: ContentActions fields + menu commands

**Files:**
- Modify: `Sources/Parallel/Views/Commands.swift`

- [ ] **Step 1: Rename `selectIndex` and add new action fields**

In `Sources/Parallel/Views/Commands.swift`, replace the `ContentActions` struct (lines 37-45) with:

```swift
struct ContentActions {
    var newWorktree: () -> Void = {}
    var addRepo: () -> Void = {}
    var selectWorktreeIndex: (Int) -> Void = { _ in }
    var selectTabIndex: (Int) -> Void = { _ in }
    var nextTab: () -> Void = {}
    var previousTab: () -> Void = {}
    var newTab: () -> Void = {}
    var clearTerminal: () -> Void = {}
    var findInTerminal: () -> Void = {}
    var closeCurrentSession: () -> Void = {}
    var deleteCurrentWorktree: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var reportIssue: () -> Void = {}
}
```

- [ ] **Step 2: Rework the Worktree menu and add a Terminal menu**

In the same file, replace the `CommandMenu("Worktree") { … }` block (lines 16-26) with:

```swift
        CommandMenu("Worktree") {
            ForEach(1...9, id: \.self) { idx in
                Button("Switch to Worktree \(idx)") { actions?.selectWorktreeIndex(idx - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx)")), modifiers: [.command, .option])
            }
            Divider()
            Button("Close Session") { actions?.closeCurrentSession() }
                .keyboardShortcut("w", modifiers: .command)
            Button("Delete Worktree…") { actions?.deleteCurrentWorktree() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        CommandMenu("Terminal") {
            Button("New Tab") { actions?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Clear") { actions?.clearTerminal() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Find…") { actions?.findInTerminal() }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Next Tab") { actions?.nextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Tab") { actions?.previousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Divider()
            ForEach(1...9, id: \.self) { idx in
                Button("Switch to Tab \(idx)") { actions?.selectTabIndex(idx - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(idx)")), modifiers: .command)
            }
        }
```

- [ ] **Step 2.5: Build (expected to FAIL until Task 4)**

Run: `swift build`
Expected: FAIL — `ContentView.swift` still constructs `ContentActions(selectIndex:…)`. This is fixed in Task 4. (Do not commit yet; Tasks 3 and 4 land together.)

---

### Task 4: Wire focusedActions in ContentView

**Files:**
- Modify: `Sources/Parallel/Views/ContentView.swift`

- [ ] **Step 1: Replace the `focusedActions` builder**

In `Sources/Parallel/Views/ContentView.swift`, replace the `focusedActions` computed property (lines 139-159) with:

```swift
    private var focusedActions: ContentActions {
        ContentActions(
            newWorktree: { newWorktreeTrigger = NewWorktreeTrigger(initialRepoId: nil) },
            addRepo:     { showAddRepo = true },
            selectWorktreeIndex: { idx in
                let ordered = store.orderedWorktrees
                if idx < ordered.count {
                    selectedWorktreeId = ordered[idx].id
                }
            },
            selectTabIndex: { idx in
                if let id = selectedWorktreeId {
                    sessionManager.activateTab(in: id, at: idx)
                }
            },
            nextTab: {
                if let id = selectedWorktreeId {
                    sessionManager.activateAdjacentTab(in: id, forward: true)
                }
            },
            previousTab: {
                if let id = selectedWorktreeId {
                    sessionManager.activateAdjacentTab(in: id, forward: false)
                }
            },
            newTab: {
                if let id = selectedWorktreeId, let wt = store.worktree(id: id) {
                    _ = sessionManager.startSession(for: wt, setupCommands: wt.setupCommands)
                }
            },
            clearTerminal: {
                if let id = selectedWorktreeId {
                    sessionManager.clearActiveTerminal(in: id)
                }
            },
            findInTerminal: {
                if let id = selectedWorktreeId {
                    sessionManager.showFind(in: id)
                }
            },
            closeCurrentSession: {
                if let id = selectedWorktreeId {
                    sessionManager.terminate(worktreeId: id)
                }
            },
            deleteCurrentWorktree: {
                pendingDeleteId = selectedWorktreeId
            },
            checkForUpdates: { Task { await runManualCheck() } },
            reportIssue: { showReportIssueSheet = true }
        )
    }
```

- [ ] **Step 2: Build + run the full test suite**

Run: `swift build && swift test`
Expected: Build succeeds; all tests pass (existing suite + 7 new in `TerminalShortcutsTests`).

- [ ] **Step 3: Commit Tasks 3+4 together**

```bash
git add Sources/Parallel/Views/Commands.swift Sources/Parallel/Views/ContentView.swift
git commit -m "feat(views): wire terminal/worktree keyboard shortcuts into menus"
```

---

### Task 5: Verify and prepare delivery (Gate 3)

**Files:** none (verification only)

- [ ] **Step 1: Confirm the full suite is green**

Run: `swift test 2>&1 | tail -5`
Expected: all tests pass, 0 failures.

- [ ] **Step 2: Record the manual-verification checklist for the PR body**

These need the GUI and cannot run headless — list them in the PR so the maintainer can verify:
- ⌘1–9 switches tabs within the current worktree; ⌃Tab / ⌃⇧Tab cycle with wrap-around.
- ⌘⌥1–9 selects the Nth worktree **as shown in the sidebar** (test with 2 repos).
- ⌘K clears screen + scrollback; ⌘T opens a new tab; ⌘F shows the find bar.

- [ ] **Step 3: Gate 3 — report diff summary + test results, get approval, then open the PR**

Per the issue workflow runbook, opening the PR is outward-facing and waits for approval:

```bash
gh pr create --title "fix: terminal keyboard shortcuts (tabs, clear, find) + ⌘1–9 fix" --body "$(cat <<'EOF'
<diff summary + manual-verification checklist>

Closes #2
EOF
)"
```

---

## Self-Review (plan author)

**Spec coverage:**
- ⌃Tab/⌃⇧Tab cycle → `activateAdjacentTab` + menu (Tasks 2,3). ✓
- ⌘1–9 tab N → `activateTab(at:)` + menu (Tasks 2,3). ✓
- ⌘⌥1–9 worktree + bug fix → `orderedWorktrees` + wiring (Tasks 1,3,4). ✓
- ⌘K clear → `clearActiveTerminal` (Task 2). ✓
- ⌘T new tab → reuse `startSession` (Task 4). ✓
- ⌘F find → `showFind` via `performTextFinderAction` (Task 2). ✓
- Tests for pure cores → Task 1 (7 tests). ✓

**Placeholder scan:** Only `<diff summary…>` inside the PR body, filled at Gate 3. No code placeholders. ✓

**Type/string consistency:** `selectWorktreeIndex`/`selectTabIndex`/`nextTab`/`previousTab`/`newTab`/`clearTerminal`/`findInTerminal` are identical across `ContentActions` (Task 3), the menu bindings (Task 3), and `focusedActions` (Task 4). `adjacentTabIndex`, `activateAdjacentTab`, `activateTab(in:at:)`, `clearActiveTerminal`, `showFind`, `orderedWorktrees` match between definition and call sites. ✓

**Build-order note:** Task 3 intentionally leaves the build red (ContentView still uses the old `selectIndex:` label); Task 4 makes it green. Tasks 3+4 commit together — no broken commit lands on its own except the explicitly-noted intermediate.
