# Bell Notifications + In-App List — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify the user (macOS banner + in-app list) when a worktree session finishes its turn and waits for input, detected via the terminal bell, and unify the existing session-ended notification into the same list.

**Architecture:** A pure `BellDebouncer` (owned per-session by `SessionTerminalDelegate`) gates raw bells; `SessionManager.handleBell` builds an `AppNotification`, appends it to an `@Observable NotificationStore`, and posts a banner unless the session is visible & the app active (`NotificationBanner.shouldBanner`). A toolbar bell icon opens a popover list; row taps and banner clicks both set `store.navigationTarget`, which `ContentView` applies. Decision logic lives in pure functions so it is unit-testable without a live terminal.

**Tech Stack:** Swift, SwiftUI, AppKit, SwiftTerm, UserNotifications, XCTest/XCUITest, SwiftPM + xcodegen.

## Global Constraints

- Match the surrounding file's style; prefer extending existing patterns over new abstractions.
- Conventional Commits: `feat(services):`, `feat(views):`, `test:`, `docs:`. Final delivery commit includes `Closes #12`.
- Notifications are no-ops when `Bundle.main.bundleIdentifier == nil` (SwiftPM bare-executable); reuse the existing `Notifications.isInBundle` guard.
- All `SessionManager` / store / delegate mutations run on the main thread/actor (existing `dispatchPrecondition(.onQueue(.main))` pattern).
- Bell debounce cooldown = 2.0 s, leading edge, monotonic clock (`ProcessInfo.processInfo.systemUptime`).
- History cap = 200 (drop oldest).
- Do NOT notify on user-initiated close (⌘W) or during app termination.
- Unit tests in `Tests/ParallelTests/` (`@testable import Parallel`); e2e in `Tests/ParallelUITests/`. Both suites must pass before the PR.

---

## File Structure

- `Sources/Parallel/Services/BellDebouncer.swift` (new) — pure leading-edge debounce gate.
- `Sources/Parallel/Models/AppNotification.swift` (new) — notification model + `NavigationTarget`.
- `Sources/Parallel/Services/NotificationStore.swift` (new) — `@Observable @MainActor` history + navigation target.
- `Sources/Parallel/Util/Notifications.swift` (modify) — `NotificationBanner.shouldBanner`, `sessionNeedsAttention`, id-carrying `sessionEnded`, `NotificationCenterDelegate`.
- `Sources/Parallel/Services/SessionManager.swift` (modify) — `SessionTerminalDelegate` bell wiring; `handleBell`, `activate`, `beginTermination`, suppression flags, `sessionEnded` reroute, `e2eEmitBellInBackground`.
- `Sources/Parallel/Views/ContentView.swift` (modify) — toolbar bell + popover, `visibleWorktreeId` sync, navigation application.
- `Sources/Parallel/Views/NotificationListView.swift` (new) — popover list UI.
- `Sources/Parallel/ParallelApp.swift` (modify) — create/inject `NotificationStore`, wire `UNUserNotificationCenter` delegate, `beginTermination` on quit.
- `Sources/Parallel/Views/E2EProbeView.swift` (modify) — unread-count probe + background-bell affordance button.
- Tests: `BellDebouncerTests`, `NotificationStoreTests`, `NotificationBannerTests` (unit); `BellNotificationTests` (e2e).

---

## Task 1: `BellDebouncer` (pure)

**Files:**
- Create: `Sources/Parallel/Services/BellDebouncer.swift`
- Test: `Tests/ParallelTests/BellDebouncerTests.swift`

**Interfaces:**
- Produces: `struct BellDebouncer { init(cooldown: TimeInterval = 2.0); mutating func shouldFire(now: TimeInterval) -> Bool }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ParallelTests/BellDebouncerTests.swift
import XCTest
@testable import Parallel

/// Issue #12: raw terminal bells are noisy (bursts). A per-session leading-edge
/// debouncer fires on the first bell, then suppresses further bells until the
/// cooldown elapses. Time is injected (monotonic seconds) for determinism.
final class BellDebouncerTests: XCTestCase {
    func test_firesOnFirstBell() {
        var d = BellDebouncer(cooldown: 2.0)
        XCTAssertTrue(d.shouldFire(now: 100.0))
    }

    func test_suppressesWithinCooldown() {
        var d = BellDebouncer(cooldown: 2.0)
        _ = d.shouldFire(now: 100.0)
        XCTAssertFalse(d.shouldFire(now: 101.9))
    }

    func test_firesAgainAfterCooldown() {
        var d = BellDebouncer(cooldown: 2.0)
        _ = d.shouldFire(now: 100.0)
        XCTAssertTrue(d.shouldFire(now: 102.0))
    }

    func test_burstCollapsesToOne() {
        var d = BellDebouncer(cooldown: 2.0)
        let results = [100.0, 100.1, 100.5, 101.0].map { d.shouldFire(now: $0) }
        XCTAssertEqual(results, [true, false, false, false])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BellDebouncerTests`
Expected: FAIL — `cannot find 'BellDebouncer' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Parallel/Services/BellDebouncer.swift
import Foundation

/// Leading-edge debounce gate for terminal bells (issue #12). Fires on the first
/// bell, then suppresses until `cooldown` seconds pass, collapsing a burst into a
/// single notification. Pure and value-typed; the caller injects a monotonic
/// timestamp (`ProcessInfo.processInfo.systemUptime`).
struct BellDebouncer {
    let cooldown: TimeInterval
    private var lastFire: TimeInterval?

    init(cooldown: TimeInterval = 2.0) {
        self.cooldown = cooldown
    }

    /// Returns true if this bell should raise a notification.
    mutating func shouldFire(now: TimeInterval) -> Bool {
        if let last = lastFire, now - last < cooldown { return false }
        lastFire = now
        return true
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BellDebouncerTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Services/BellDebouncer.swift Tests/ParallelTests/BellDebouncerTests.swift
git commit -m "feat(services): pure BellDebouncer for bell notifications (#12)"
```

---

## Task 2: `AppNotification` + `NotificationStore`

**Files:**
- Create: `Sources/Parallel/Models/AppNotification.swift`
- Create: `Sources/Parallel/Services/NotificationStore.swift`
- Test: `Tests/ParallelTests/NotificationStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct AppNotification: Identifiable, Equatable { enum Kind { case needsAttention, sessionEnded }; let id: UUID; let kind: Kind; let worktreeId: UUID; let sessionId: UUID; let worktreeName: String; let branch: String; let tabLabel: String; let date: Date; var isRead: Bool; init(kind:worktreeId:sessionId:worktreeName:branch:tabLabel:date:isRead:id:) }`
  - `struct NavigationTarget: Equatable { let worktreeId: UUID; let sessionId: UUID }`
  - `@Observable @MainActor final class NotificationStore { init(cap: Int = 200); private(set) var items: [AppNotification]; var navigationTarget: NavigationTarget?; var unreadCount: Int { get }; func add(_:); func markAllRead(); func clearAll() }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ParallelTests/NotificationStoreTests.swift
import XCTest
@testable import Parallel

/// Issue #12: in-memory notification history. Newest first, unread badge count,
/// mark-all-read on popover open, clear-all, and a bounded cap.
@MainActor
final class NotificationStoreTests: XCTestCase {
    private func note(_ name: String) -> AppNotification {
        AppNotification(kind: .needsAttention, worktreeId: UUID(), sessionId: UUID(),
                        worktreeName: name, branch: "main", tabLabel: "shell 1")
    }

    func test_addPrependsNewestFirst_andCountsUnread() {
        let s = NotificationStore()
        s.add(note("a"))
        s.add(note("b"))
        XCTAssertEqual(s.items.map(\.worktreeName), ["b", "a"])
        XCTAssertEqual(s.unreadCount, 2)
    }

    func test_markAllReadZeroesUnread() {
        let s = NotificationStore()
        s.add(note("a")); s.add(note("b"))
        s.markAllRead()
        XCTAssertEqual(s.unreadCount, 0)
        XCTAssertEqual(s.items.count, 2)
    }

    func test_clearAllEmpties() {
        let s = NotificationStore()
        s.add(note("a"))
        s.clearAll()
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertEqual(s.unreadCount, 0)
    }

    func test_capDropsOldest() {
        let s = NotificationStore(cap: 2)
        s.add(note("a")); s.add(note("b")); s.add(note("c"))
        XCTAssertEqual(s.items.map(\.worktreeName), ["c", "b"])
    }

    func test_addedAsReadDoesNotCountUnread() {
        let s = NotificationStore()
        var n = note("a"); n.isRead = true
        s.add(n)
        XCTAssertEqual(s.unreadCount, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationStoreTests`
Expected: FAIL — `cannot find 'AppNotification'` / `'NotificationStore'` in scope.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Parallel/Models/AppNotification.swift
import Foundation

/// One entry in the in-app notification list (issue #12).
struct AppNotification: Identifiable, Equatable {
    enum Kind: Equatable { case needsAttention, sessionEnded }

    let id: UUID
    let kind: Kind
    let worktreeId: UUID
    let sessionId: UUID
    let worktreeName: String
    let branch: String
    let tabLabel: String
    let date: Date
    var isRead: Bool

    init(kind: Kind, worktreeId: UUID, sessionId: UUID, worktreeName: String,
         branch: String, tabLabel: String, date: Date = Date(),
         isRead: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.worktreeId = worktreeId
        self.sessionId = sessionId
        self.worktreeName = worktreeName
        self.branch = branch
        self.tabLabel = tabLabel
        self.date = date
        self.isRead = isRead
    }
}

/// The worktree/tab a notification points at; consumed by the view layer to
/// navigate on row tap or banner click.
struct NavigationTarget: Equatable {
    let worktreeId: UUID
    let sessionId: UUID
}
```

```swift
// Sources/Parallel/Services/NotificationStore.swift
import Foundation
import Observation

/// In-memory notification history (issue #12). Cleared on restart (no disk
/// persistence in v1). Newest first; bounded to `cap` entries.
@Observable
@MainActor
final class NotificationStore {
    private(set) var items: [AppNotification] = []
    /// Set by a list-row tap or a banner click; ContentView observes and clears it.
    var navigationTarget: NavigationTarget?
    private let cap: Int

    init(cap: Int = 200) { self.cap = cap }

    var unreadCount: Int { items.lazy.filter { !$0.isRead }.count }

    func add(_ notification: AppNotification) {
        items.insert(notification, at: 0)
        if items.count > cap { items.removeLast(items.count - cap) }
    }

    func markAllRead() {
        for i in items.indices where !items[i].isRead { items[i].isRead = true }
    }

    func clearAll() { items.removeAll() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationStoreTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Models/AppNotification.swift Sources/Parallel/Services/NotificationStore.swift Tests/ParallelTests/NotificationStoreTests.swift
git commit -m "feat(services): AppNotification model + NotificationStore (#12)"
```

---

## Task 3: Banner policy + posting + click delegate

**Files:**
- Modify: `Sources/Parallel/Util/Notifications.swift`
- Test: `Tests/ParallelTests/NotificationBannerTests.swift`

**Interfaces:**
- Consumes: `NavigationTarget`, `NotificationStore` (Task 2).
- Produces:
  - `enum NotificationBanner { static func shouldBanner(appActive: Bool, sessionVisible: Bool) -> Bool }`
  - `Notifications.sessionNeedsAttention(worktreeId:sessionId:worktreeName:branch:tabLabel:)`
  - `Notifications.sessionEnded(worktreeId:sessionId:worktreeName:branch:tabLabel:)` (id-carrying; replaces the old 3-arg form)
  - `final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate { var store: NotificationStore? }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ParallelTests/NotificationBannerTests.swift
import XCTest
@testable import Parallel

/// Issue #12: suppress the macOS banner only when the belling session is the one
/// the user is already looking at (visible) AND the app is frontmost.
final class NotificationBannerTests: XCTestCase {
    func test_truthTable() {
        XCTAssertFalse(NotificationBanner.shouldBanner(appActive: true,  sessionVisible: true))
        XCTAssertTrue( NotificationBanner.shouldBanner(appActive: true,  sessionVisible: false))
        XCTAssertTrue( NotificationBanner.shouldBanner(appActive: false, sessionVisible: true))
        XCTAssertTrue( NotificationBanner.shouldBanner(appActive: false, sessionVisible: false))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationBannerTests`
Expected: FAIL — `cannot find 'NotificationBanner' in scope`.

- [ ] **Step 3: Write minimal implementation**

Replace the body of `Sources/Parallel/Util/Notifications.swift` with (keeps the existing `isInBundle` guard and `requestPermission`; upgrades `sessionEnded`; adds the rest):

```swift
import Foundation
import UserNotifications

/// Pure banner-suppression policy (issue #12), unit-testable without AppKit.
enum NotificationBanner {
    /// Show a banner unless the belling session is visible and the app is active.
    static func shouldBanner(appActive: Bool, sessionVisible: Bool) -> Bool {
        !(appActive && sessionVisible)
    }
}

enum Notifications {
    private static var isInBundle: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard isInBundle else {
            AppLogger.app.info("notifications disabled (no bundle — run from a .app to enable)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.app.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            AppLogger.app.info("notification permission granted=\(granted)")
        }
    }

    /// A session finished its turn and is waiting for input.
    static func sessionNeedsAttention(worktreeId: UUID, sessionId: UUID,
                                      worktreeName: String, branch: String, tabLabel: String) {
        post(title: "Waiting for you", worktreeId: worktreeId, sessionId: sessionId,
             worktreeName: worktreeName, branch: branch, tabLabel: tabLabel)
    }

    /// A shell session exited on its own.
    static func sessionEnded(worktreeId: UUID, sessionId: UUID,
                             worktreeName: String, branch: String, tabLabel: String) {
        post(title: "Session ended", worktreeId: worktreeId, sessionId: sessionId,
             worktreeName: worktreeName, branch: branch, tabLabel: tabLabel)
    }

    private static func post(title: String, worktreeId: UUID, sessionId: UUID,
                             worktreeName: String, branch: String, tabLabel: String) {
        guard isInBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = worktreeName
        content.body = "\(tabLabel) · \(branch)"
        content.sound = .default
        content.userInfo = ["worktreeId": worktreeId.uuidString, "sessionId": sessionId.uuidString]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error {
                AppLogger.app.error("notify post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Routes banner interactions back into the app (issue #12): shows banners even
/// while the app is frontmost (we already decided to post), and on click sets the
/// store's navigation target so ContentView jumps to that session.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var store: NotificationStore?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let w = info["worktreeId"] as? String, let wid = UUID(uuidString: w),
           let s = info["sessionId"] as? String, let sid = UUID(uuidString: s) {
            Task { @MainActor in
                self.store?.navigationTarget = NavigationTarget(worktreeId: wid, sessionId: sid)
            }
        }
        completionHandler()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationBannerTests`
Expected: PASS. Then `swift build` to confirm the `sessionEnded` signature change compiles here (the only caller is updated in Task 4).

Run: `swift build`
Expected: FAIL only at `SessionManager.markExited` (old `sessionEnded(worktreeName:branch:tabLabel:)` call) — fixed in Task 4. If any OTHER file fails, stop and reconcile.

- [ ] **Step 5: Commit**

```bash
git add Sources/Parallel/Util/Notifications.swift Tests/ParallelTests/NotificationBannerTests.swift
git commit -m "feat(services): banner policy, needs-attention post, click delegate (#12)"
```

---

## Task 4: SessionManager bell wiring + suppression + navigation helpers

**Files:**
- Modify: `Sources/Parallel/Services/SessionManager.swift`
- Test: `Tests/ParallelTests/NotificationStoreTests.swift` (extend — no new file)

**Interfaces:**
- Consumes: `BellDebouncer` (T1), `AppNotification`/`NavigationTarget` (T2), `NotificationBanner`/`Notifications` (T3).
- Produces (on `SessionManager`):
  - `var notificationStore: NotificationStore?`
  - `var visibleWorktreeId: UUID?`
  - `func handleBell(sessionId: UUID)`
  - `func activate(sessionId: UUID)`
  - `func beginTermination()`
  - `func e2eEmitBellInBackground()`
  - On `SessionTerminalDelegate`: `var onBell: () -> Void`

- [ ] **Step 1: Add the store/state properties and helpers to `SessionManager`**

Near the other stored properties on `SessionManager` (top of the class), add:

```swift
    /// In-app notification sink (issue #12). Injected by ParallelApp.
    var notificationStore: NotificationStore?
    /// The worktree currently shown in the detail pane (kept in sync by ContentView).
    /// Used to decide whether a belling session is "visible" (banner suppression).
    var visibleWorktreeId: UUID?
    /// Sessions the user is closing on purpose (⌘W) — their PTY EOF must not notify.
    private var userClosingSessions: Set<UUID> = []
    /// True while the app is tearing down; suppresses the session-ended cascade's notifications.
    private var isTerminating = false
```

- [ ] **Step 2: Add `activate`, `beginTermination`, `handleBell`, and the shared poster**

Add these methods to `SessionManager` (place near `terminate(sessionId:)`):

```swift
    /// Make `sessionId` the active tab of its worktree (issue #12 navigation).
    /// No-op if the session no longer exists.
    func activate(sessionId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let e = sessionsById[sessionId] else { return }
        activeByWorktree[e.session.worktreeId] = sessionId
    }

    /// Called before the app-quit teardown so the session-ended cascade stays silent.
    func beginTermination() {
        dispatchPrecondition(condition: .onQueue(.main))
        isTerminating = true
    }

    /// A debounced bell fired for `sessionId` — record + maybe banner.
    func handleBell(sessionId: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let e = sessionsById[sessionId] else { return }
        let idx = (orderByWorktree[e.session.worktreeId] ?? []).firstIndex(of: sessionId).map { $0 + 1 } ?? 1
        postNotification(entry: e, kind: .needsAttention, tabLabel: e.label ?? "shell \(idx)")
    }

    /// Build an AppNotification, append it, and post a banner unless the session
    /// is visible and the app active. Shared by bells and session-ended.
    private func postNotification(entry e: SessionEntry, kind: AppNotification.Kind, tabLabel: String) {
        let visibleSid = visibleWorktreeId.flatMap { activeSession(for: $0)?.session.id }
        let sessionVisible = (e.session.id == visibleSid)
        let appActive = NSApp.isActive
        let note = AppNotification(
            kind: kind,
            worktreeId: e.session.worktreeId,
            sessionId: e.session.id,
            worktreeName: e.worktreeDisplayName,
            branch: e.worktreeBranch,
            tabLabel: tabLabel,
            isRead: appActive && sessionVisible
        )
        notificationStore?.add(note)
        guard NotificationBanner.shouldBanner(appActive: appActive, sessionVisible: sessionVisible) else { return }
        switch kind {
        case .needsAttention:
            Notifications.sessionNeedsAttention(worktreeId: e.session.worktreeId, sessionId: e.session.id,
                                                worktreeName: e.worktreeDisplayName, branch: e.worktreeBranch, tabLabel: tabLabel)
        case .sessionEnded:
            Notifications.sessionEnded(worktreeId: e.session.worktreeId, sessionId: e.session.id,
                                       worktreeName: e.worktreeDisplayName, branch: e.worktreeBranch, tabLabel: tabLabel)
        }
    }

    /// E2E-only: feed a raw BEL to every running session that is NOT visible, so a
    /// UI test can exercise the real bell → delegate → store path deterministically.
    func e2eEmitBellInBackground() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard TestMode.isE2E() else { return }
        let visibleSid = visibleWorktreeId.flatMap { activeSession(for: $0)?.session.id }
        for entry in allRunningSessions where entry.session.id != visibleSid {
            entry.terminalView.feed(byteArray: ArraySlice([0x07]))
        }
    }
```

- [ ] **Step 3: Mark user-initiated closes and reroute `markExited`**

In `terminate(sessionId:)`, add at the very top (after the `dispatchPrecondition`):

```swift
        userClosingSessions.insert(sessionId)
```

Replace the `Notifications.sessionEnded(...)` block in `markExited(sessionId:)` (currently `SessionManager.swift:420-424`) with:

```swift
        let userClosed = userClosingSessions.remove(sessionId) != nil
        if isTerminating || userClosed { return }
        postNotification(entry: e, kind: .sessionEnded, tabLabel: "shell \(tabIndex)")
```

- [ ] **Step 4: Wire the bell into `SessionTerminalDelegate`**

On `SessionTerminalDelegate` (`SessionManager.swift:465`), add the closure + debouncer and implement `bell`:

```swift
    var onBell: () -> Void = {}
    private var bellDebouncer = BellDebouncer()
```

Replace `func bell(source: TerminalView) {}` with:

```swift
    func bell(source: TerminalView) {
        if bellDebouncer.shouldFire(now: ProcessInfo.processInfo.systemUptime) { onBell() }
    }
```

In `startSession(...)`, immediately after `let sessionId = session.id` (`SessionManager.swift:207`), add:

```swift
        delegate.onBell = { [weak self] in self?.handleBell(sessionId: sessionId) }
```

- [ ] **Step 5: Extend the unit test (activate + suppression are behavioural; cover what's pure)**

Append to `NotificationStoreTests.swift` a test that a session added while visible is read (mirrors `postNotification`'s `isRead` rule), keeping SessionManager's PTY-bound wiring for e2e:

```swift
    func test_isReadFlagMatchesBannerPolicy() {
        // postNotification sets isRead = appActive && sessionVisible; the store must
        // honour a pre-read entry (no unread badge for something you're looking at).
        let s = NotificationStore()
        var read = note("a"); read.isRead = true
        s.add(read)
        s.add(note("b"))
        XCTAssertEqual(s.unreadCount, 1)
    }
```

- [ ] **Step 6: Build + run unit suite**

Run: `swift build && swift test --filter NotificationStoreTests`
Expected: build succeeds (Task 3's `sessionEnded` caller is now fixed); tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Parallel/Services/SessionManager.swift Tests/ParallelTests/NotificationStoreTests.swift
git commit -m "feat(services): route bells + session-ended into NotificationStore (#12)"
```

---

## Task 5: Toolbar bell + popover list + navigation (views)

**Files:**
- Create: `Sources/Parallel/Views/NotificationListView.swift`
- Modify: `Sources/Parallel/Views/ContentView.swift`

**Interfaces:**
- Consumes: `NotificationStore`, `AppNotification`, `NavigationTarget` (T2); `SessionManager.activate/visibleWorktreeId` (T4).
- Produces: toolbar item id `toolbar.notifications`; list rows id `notificationRow`.

- [ ] **Step 1: Create the list view**

```swift
// Sources/Parallel/Views/NotificationListView.swift
import SwiftUI

/// Popover contents for the toolbar bell (issue #12). Newest first; a row tap
/// asks the store to navigate; "Clear all" empties history.
struct NotificationListView: View {
    @Environment(NotificationStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Notifications").font(.headline)
                Spacer()
                Button("Clear all") { store.clearAll() }
                    .disabled(store.items.isEmpty)
            }
            .padding(10)
            Divider()
            if store.items.isEmpty {
                Text("No notifications")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.items) { note in
                            Button {
                                store.navigationTarget = NavigationTarget(
                                    worktreeId: note.worktreeId, sessionId: note.sessionId)
                            } label: {
                                row(note)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("notificationRow")
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 320)
    }

    private func row(_ note: AppNotification) -> some View {
        HStack(spacing: 8) {
            Image(systemName: note.kind == .needsAttention ? "bell.fill" : "moon.zzz.fill")
                .foregroundStyle(note.isRead ? .secondary : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.worktreeName).font(.body)
                Text("\(note.tabLabel) · \(note.branch)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Add the toolbar bell + popover + sync + navigation to ContentView**

Add the environment + state near the top of `ContentView` (after line 17's environments / line 28's state):

```swift
    @Environment(NotificationStore.self) private var notificationStore
    @State private var showNotifications = false
```

Add a toolbar item inside `toolbarContent` (`ContentView.swift:95`), e.g. as a trailing item:

```swift
        ToolbarItem(placement: .primaryAction) {
            Button { showNotifications.toggle() } label: {
                Image(systemName: notificationStore.unreadCount > 0 ? "bell.badge.fill" : "bell")
            }
            .accessibilityIdentifier("toolbar.notifications")
            .popover(isPresented: $showNotifications, arrowEdge: .bottom) {
                NotificationListView()
            }
            .onChange(of: showNotifications) { _, shown in
                if shown { notificationStore.markAllRead() }
            }
        }
```

Add the visible-worktree sync and navigation application to the `body` view modifiers (near the existing `.focusedValue(...)` at `ContentView.swift:77`):

```swift
        .onChange(of: selectedWorktreeId) { _, new in
            sessionManager.visibleWorktreeId = new
        }
        .onChange(of: notificationStore.navigationTarget) { _, target in
            guard let target else { return }
            if store.worktree(id: target.worktreeId) != nil {
                selectedWorktreeId = target.worktreeId
                sessionManager.activate(sessionId: target.sessionId)
            }
            notificationStore.navigationTarget = nil
        }
```

Also set the initial sync in the existing `.onAppear` (`ContentView.swift:83`), adding:

```swift
            sessionManager.visibleWorktreeId = selectedWorktreeId
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: PASS. (ParallelApp still needs to inject the store — Task 6 — but the app target compiles because `@Environment(NotificationStore.self)` resolves at runtime.)

- [ ] **Step 4: Commit**

```bash
git add Sources/Parallel/Views/NotificationListView.swift Sources/Parallel/Views/ContentView.swift
git commit -m "feat(views): toolbar bell + notification popover + navigation (#12)"
```

---

## Task 6: App wiring — inject store, banner delegate, quit suppression

**Files:**
- Modify: `Sources/Parallel/ParallelApp.swift`

**Interfaces:**
- Consumes: `NotificationStore` (T2), `NotificationCenterDelegate` (T3), `SessionManager.notificationStore/beginTermination` (T4).

- [ ] **Step 1: Add the store, delegate wiring, and quit hook**

At the top of `ParallelApp.swift` add `import UserNotifications` (below `import AppKit`).

In the `AppDelegate` (added in #19), add:

```swift
    private let notificationCenterDelegate = NotificationCenterDelegate()

    /// Give the banner-click delegate the shared store and register it.
    func wireNotifications(store: NotificationStore) {
        notificationCenterDelegate.store = store
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = notificationCenterDelegate
        }
    }
```

In `ParallelApp`, add the state:

```swift
    @State private var notificationStore = NotificationStore()
```

Add `.environment(notificationStore)` to the `ContentView()` environment chain (next to the other `.environment(...)` calls).

In the `.onAppear` block (where `sessionManager.store = store` is set), add:

```swift
                    sessionManager.notificationStore = notificationStore
                    appDelegate.wireNotifications(store: notificationStore)
```

In the `willTerminate` `.onReceive` block, add `sessionManager.beginTermination()` as the FIRST line (before `sessionManager.store = nil`):

```swift
                    sessionManager.beginTermination()
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Manual smoke (documented, not a test)**

Run `./scripts/build-app.sh`, open the app, run `printf '\a'` in a background worktree's shell; confirm a banner + the toolbar bell badge. (Manual because the real macOS banner isn't XCUITest-assertable; the e2e in Task 7 covers the in-app path.)

- [ ] **Step 4: Commit**

```bash
git add Sources/Parallel/ParallelApp.swift
git commit -m "feat(app): inject NotificationStore, banner-click delegate, quit suppression (#12)"
```

---

## Task 7: E2E — real bell → badge → list → navigate

**Files:**
- Modify: `Sources/Parallel/Views/E2EProbeView.swift`
- Create: `Tests/ParallelUITests/BellNotificationTests.swift`

**Interfaces:**
- Consumes: `SessionManager.e2eEmitBellInBackground` (T4), `NotificationStore.unreadCount` (T2), toolbar id `toolbar.notifications`, row id `notificationRow` (T5).

- [ ] **Step 1: Add the unread probe + background-bell button to E2EProbeView**

Add the environment to `E2EProbeView`:

```swift
    @Environment(NotificationStore.self) private var notificationStore
```

Inside the probe `VStack` (next to the other `Text(...)` probes), add:

```swift
            Text("unread")
                .accessibilityIdentifier("e2e.unreadNotificationCount")
                .accessibilityValue("\(notificationStore.unreadCount)")
            Button("emitBell") { sessionManager.e2eEmitBellInBackground() }
                .accessibilityIdentifier("e2e.emitBackgroundBell")
```

(The button sits in the 1×1 hidden probe overlay; it is addressable by XCUITest but invisible to users. `allowsHitTesting(false)` is on the container — move the button OUTSIDE that modifier or drop `allowsHitTesting(false)`; simplest: wrap the button in its own `.allowsHitTesting(true)`.)

Concretely, ensure the button remains hittable:

```swift
            Button("emitBell") { sessionManager.e2eEmitBellInBackground() }
                .accessibilityIdentifier("e2e.emitBackgroundBell")
                .allowsHitTesting(true)
```

- [ ] **Step 2: Write the e2e test**

```swift
// Tests/ParallelUITests/BellNotificationTests.swift
import XCTest

/// Issue #12: a real terminal bell in a BACKGROUND session raises an unread
/// in-app notification; opening the popover marks it read; tapping the row
/// navigates to that worktree. Drives the full bell → delegate → store → UI path
/// (the BEL is fed to a non-visible SwiftTerm view via an e2e affordance).
final class BellNotificationTests: XCTestCase {
    func testBackgroundBellRaisesNotificationAndNavigates() throws {
        let fx = try E2EFixture.make()
        defer { fx.cleanup() }
        let repo = try fx.makeRepo(named: "demo")
        let alpha = try fx.addWorktree(repo: repo, branch: "alpha", dirName: "alpha")
        let beta  = try fx.addWorktree(repo: repo, branch: "beta",  dirName: "beta")
        try fx.writeSeed("""
        {"repos":[{"root":"\(repo.path)","displayName":"demo"}],
         "worktrees":[
           {"repoIndex":0,"path":"\(alpha.path)","branch":"alpha","displayName":"alpha"},
           {"repoIndex":0,"path":"\(beta.path)","branch":"beta","displayName":"beta"}
         ]}
        """)

        let app = XCUIApplication()
        app.launchE2E(fixture: fx)

        let alphaRow = app.staticTexts["alpha"]
        XCTAssertTrue(alphaRow.waitForExistence(timeout: 15))
        let count = app.staticTexts["e2e.runningSessionCount"]
        let awt = app.staticTexts["e2e.activeWorktreeId"]
        let unread = app.staticTexts["e2e.unreadNotificationCount"]
        XCTAssertTrue(unread.waitForExistence(timeout: 5))

        // Start alpha, then beta — alpha ends up backgrounded, beta visible.
        alphaRow.click()
        expectValue(count, toEqual: "1", timeout: 15)
        let alphaId = awt.value as? String
        app.staticTexts["beta"].click()
        expectValue(count, toEqual: "2", timeout: 15)

        // Feed a real BEL to the backgrounded alpha session.
        app.buttons["e2e.emitBackgroundBell"].click()
        expectValue(unread, toEqual: "1", timeout: 10)

        // Open the popover (marks read) and tap the row to navigate back to alpha.
        app.buttons["toolbar.notifications"].click()
        let row = app.buttons["notificationRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        expectValue(unread, toEqual: "0", timeout: 5)   // mark-all-read on open
        row.click()
        expectValue(awt, toEqual: alphaId ?? "", timeout: 10)   // navigated to alpha

        app.terminate()
    }
}
```

- [ ] **Step 3: Generate project + run the e2e**

Run:
```bash
xcodegen generate
xcodebuild test -project Parallel.xcodeproj -scheme Parallel \
  -destination 'platform=macOS' -only-testing:ParallelUITests/BellNotificationTests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```
Expected: PASS. (If the local XCUITest runner cannot foreground — a known environment limitation here — rely on CI, which runs both suites on the PR.)

- [ ] **Step 4: Commit**

```bash
git add Sources/Parallel/Views/E2EProbeView.swift Tests/ParallelUITests/BellNotificationTests.swift
git commit -m "test(e2e): background bell raises notification + navigates (#12)"
```

---

## Final: full suites + delivery

- [ ] **Step 1: Run both suites**

```bash
swift test
xcodegen generate && xcodebuild test -project Parallel.xcodeproj -scheme Parallel \
  -destination 'platform=macOS' -only-testing:ParallelUITests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```
Expected: both green (or e2e green on CI if the local runner can't foreground).

- [ ] **Step 2: Gate 3 — report diff + both suite results; get approval BEFORE the PR.**

- [ ] **Step 3: Open the PR (after approval)**

```bash
gh pr create --title "feat: bell-triggered notifications + in-app list (#12)" \
  --body "$(cat <<'EOF'
Implements bell-triggered notifications and an in-app list.

Closes #12
EOF
)"
```

---

## Self-Review

**Spec coverage:** bell hook (T4) ✓; per-session debounce (T1) ✓; focus suppression (T3 `shouldBanner` + T4 `postNotification`) ✓; `AppNotification` + `NotificationStore` (T2) ✓; `sessionNeedsAttention` (T3) ✓; toolbar bell + badge + popover, newest-first, row tap, Clear all, mark-all-read on open (T5) ✓; banner click navigation (T3 delegate + T5/T6 wiring) ✓; unify `sessionEnded` (T4) ✓; unit tests `BellDebouncer` + `NotificationStore` + `shouldBanner` (T1–T3) ✓; e2e (T7) ✓; D1–D7 all mapped (debounce T1; focus rule T3/T4; banner-click T3/T5/T6; per-turn T1/T4; cap T2; monotonic clock T4; no-notify on close/quit T4) ✓.

**Placeholder scan:** none — every step carries real code/commands.

**Type consistency:** `shouldFire(now:)`, `add(_:)`, `unreadCount`, `markAllRead()`, `clearAll()`, `navigationTarget`, `NavigationTarget(worktreeId:sessionId:)`, `handleBell(sessionId:)`, `activate(sessionId:)`, `beginTermination()`, `visibleWorktreeId`, `notificationStore`, `sessionNeedsAttention(worktreeId:sessionId:worktreeName:branch:tabLabel:)`, `sessionEnded(worktreeId:sessionId:worktreeName:branch:tabLabel:)`, ids `toolbar.notifications` / `notificationRow` / `e2e.unreadNotificationCount` / `e2e.emitBackgroundBell` — used consistently across tasks.
