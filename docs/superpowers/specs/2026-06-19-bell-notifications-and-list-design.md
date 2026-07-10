# Bell-triggered notifications + in-app notification list — design

Issue: [#12](https://github.com/BottlePumpkin/Parallel/issues/12)

## Problem

Parallel runs one terminal session per worktree in parallel. Today the only
signal is `sessionEnded` (a macOS banner when a shell exits). There is no "this
session finished its turn and is waiting for you" signal, and no in-app record of
past notifications. When many sessions run at once, the user needs to know *which*
one needs attention.

CLIs like Claude Code emit the terminal **bell** (BEL, `\a`) when they finish a
turn and wait for input. We use that as the attention signal, surface it as a
macOS banner **and** an in-app list reachable from a toolbar bell icon, and unify
the existing `sessionEnded` into the same list.

## Why "any bell" is the right v1 trigger

BEL fires for several reasons: (1) a TUI finishing / waiting for input (the signal
we want), (2) shell readline beeps (tab-completion miss, backspace at an empty
prompt), (3) TUI error beeps (vim), (4) stray BELs in binary output. Cases 2–4
almost always occur in the session the user is **actively typing into** — which is
by definition the **focused** session. The focus-suppression rule below drops
those. What remains is bells from **background** sessions (nobody is typing there,
so a beep usually means "a program wants you") and bells while the **app is
inactive** (the user stepped away) — exactly the signals worth a notification.

Therefore v1 does **not** parse escape sequences or attempt semantic bell
classification (YAGNI). Focus suppression + per-session debounce is sufficient.

## Scope

In scope:
- Hook SwiftTerm's `SessionTerminalDelegate.bell(source:)` (currently empty).
- Per-session bell debounce (leading edge + ~2 s cooldown).
- Focus suppression: no macOS banner when that session is visible and the app is
  active; still record it in the list (as read).
- `AppNotification` model + in-memory `@Observable NotificationStore`.
- `Notifications.sessionNeedsAttention(...)` posting method (reuse the bundle guard).
- Toolbar bell icon with unread badge → popover `NotificationListView` (newest first).
- Row tap navigates to the worktree/tab that raised it; "Clear all"; mark-all-read
  on popover open.
- **macOS banner click navigates to the session** (pulled into v1 — see decision D3).
- Unify existing `sessionEnded` into the same list.
- Unit tests for `BellDebouncer` and `NotificationStore`; e2e for the toolbar/list/
  navigation path driven by a real bell.

Out of scope (v1 / YAGNI):
- Disk persistence of the list (cleared on restart).
- Bell triggers other than BEL + session-ended (e.g. output-idle detection).
- Semantic bell classification / escape-sequence parsing.

## Architecture

Small units, each with one purpose, with the decision logic factored into **pure
functions** so it is unit-testable without a live terminal or menu bar (the same
pattern used by issues #7/#24/#19).

### Components

| Unit | Kind | Responsibility |
|---|---|---|
| `BellDebouncer` | pure `struct` | Leading-edge + cooldown gate. `mutating func shouldFire(now: TimeInterval) -> Bool`. One instance per session, owned by the session's delegate. Cooldown = 2.0 s. |
| `AppNotification` | model `struct` (`Identifiable`, `Equatable`) | `id: UUID`, `kind: Kind`, `worktreeId: UUID`, `sessionId: UUID`, `worktreeName: String`, `branch: String`, `tabLabel: String`, `date: Date`, `isRead: Bool`. `enum Kind { case needsAttention, sessionEnded }`. |
| `NotificationStore` | `@Observable @MainActor` class | In-memory history. `private(set) var items: [AppNotification]` (newest first), `add(_:)` (prepend, cap 200 — drop oldest), `unreadCount: Int`, `markAllRead()`, `clearAll()`, and `var navigationTarget: NavigationTarget?` consumed by the view layer. |
| `NotificationBanner.shouldBanner(appActive:sessionVisible:)` | pure `static func` | Returns `!(appActive && sessionVisible)`. The banner-suppression truth table. |
| `Notifications.sessionNeedsAttention(...)` | extend existing `enum Notifications` | Post a macOS banner mirroring `sessionEnded`, with `userInfo` carrying `worktreeId`/`sessionId`. |
| `NotificationCenterDelegate` | `UNUserNotificationCenterDelegate` | On banner click (`didReceive`), read `userInfo` ids → set `store.navigationTarget`. |
| `NotificationListView` + toolbar bell | SwiftUI | Bell icon (`bell` / `bell.badge`) with unread badge → popover list (newest first). Row tap sets `navigationTarget`; "Clear all"; mark-all-read on open. |

### Bell routing

`SessionTerminalDelegate` currently holds only `pty`. It gains:
- an owned `BellDebouncer`, and
- an injected `onBell: () -> Void` closure (same "inject at creation" pattern as `pty`).

`bell(source:)` runs on the main thread (AppKit delegate). It calls
`debouncer.shouldFire(now:)` with a **monotonic** clock (`ProcessInfo.processInfo.systemUptime`,
robust against wall-clock changes); if it fires, it invokes `onBell()`.

`SessionManager` wires `onBell` to `handleBell(sessionId:)`, which:
1. builds an `AppNotification(kind: .needsAttention, …)` from the session/worktree,
2. `notificationStore.add(_:)`,
3. if `NotificationBanner.shouldBanner(appActive: NSApp.isActive, sessionVisible: <isVisible>)`,
   posts `Notifications.sessionNeedsAttention(...)`.

`<isVisible>` = `sessionId == activeSession(for: selectedWorktreeId)?.session.id`. The
selected worktree id lives in `ContentView` state, so `SessionManager` needs to know
the current selection: `ContentView` writes the selection into a lightweight field
(`sessionManager.visibleSessionId` / `visibleWorktreeId`) it already can compute, kept
in sync via `.onChange(of: selectedWorktreeId)`.

### Data flow

```
SwiftTerm bell(source:)  ──main──▶ SessionTerminalDelegate.onBell
   └▶ BellDebouncer.shouldFire(now)?  ──no──▶ drop
        └yes─▶ SessionManager.handleBell(sessionId)
               ├▶ AppNotification(.needsAttention) ─▶ NotificationStore.add
               └▶ shouldBanner(NSApp.isActive, sessionVisible)?
                     └yes─▶ Notifications.sessionNeedsAttention  (banner, userInfo=ids)
```

### Navigation

Both the list-row tap and the banner click converge on one entry point:
`NotificationStore.navigationTarget = NavigationTarget(worktreeId:sessionId:)`.

`ContentView` observes it (`.onChange(of: store.navigationTarget)`):
1. set `selectedWorktreeId = target.worktreeId` **iff** the worktree still exists,
2. `sessionManager.activate(sessionId:)` (new) if the session still exists; otherwise
   fall back to that worktree's current active tab,
3. if the worktree is gone, no-op (leave the row in history).
4. clear `navigationTarget` after applying.

`activate(sessionId:)` sets `activeByWorktree[worktreeId] = sessionId` (main-actor,
no-op if the session id is unknown).

The banner click originates in `NotificationCenterDelegate` (owned by the
`AppDelegate` added in #19). It needs the shared `NotificationStore`: the store is
created in `ParallelApp` and handed to the delegate on launch
(`appDelegate.notificationStore = store` in `.onAppear`, delegate holds it weakly).

### `sessionEnded` unification and suppression

`markExited` currently calls `Notifications.sessionEnded(...)` directly. It changes to
route through the store (`AppNotification(kind: .sessionEnded, …)` + the same banner
rule). Two suppressions are required so we don't spam on intentional teardown:

- **User-initiated close (⌘W, issue #19):** `terminate(sessionId:)` sets a
  `userClosing` marker for that session so the resulting PTY `onEOF` → `markExited`
  does **not** notify.
- **App termination:** `willTerminate` sets an `isTerminating` flag before the
  session-teardown cascade; `markExited` skips notifications while it is set.

Only a genuine process exit (the shell dying on its own) produces a `sessionEnded`
notification.

## Decisions (resolved during brainstorming)

- **D1 — trigger:** any bell is a candidate; per-session leading-edge debounce, 2 s
  cooldown; focus suppression removes the noisy cases. No semantic classification.
- **D2 — focus rule:** suppress the banner when `NSApp.isActive && sessionId ==
  activeSession(of: selectedWorktree)`. First-responder state is **not** used (the
  visible pane counts as focused even if the sidebar holds keyboard focus).
- **D3 — banner click navigation is in v1** (issue had it out of scope): reuses the
  list navigation; near-free and the core value when the app is backgrounded.
- **D4 — per-turn, not coalesced:** each debounced bell = one notification (Claude
  bells once per turn; collapsing per-session-unread would swallow legitimate turns).
- **D5 — history cap:** 200, drop oldest.
- **D6 — monotonic clock** for the debouncer.
- **D7 — do not notify** on user-initiated close or during app termination.

## Testing

Per the repo test policy (unit always; e2e when the view layer / SessionManager /
PTY flow is touched — all true here).

**Unit (`swift test`)**
- `BellDebouncer`: fires on first call; suppresses within the cooldown; fires again
  after the cooldown; independent per instance. Time injected.
- `NotificationStore`: `add` prepends and bumps `unreadCount`; cap drops oldest at
  200; `markAllRead` zeroes unread; `clearAll` empties; ordering newest-first.
- `NotificationBanner.shouldBanner`: full truth table (active×visible).

**e2e (XCUITest)**
- Seed a worktree whose `setupCommands` emit `printf '\a'` from a **background**
  session; assert the toolbar bell shows an unread badge and the popover lists a row.
- Open the popover, tap the row, assert `e2e.activeWorktreeId` switches to that
  worktree; assert the badge clears after mark-all-read.
- Add an `e2e.unreadNotificationCount` probe value to `E2EProbeView` for a stable,
  SwiftTerm-independent assertion of unread count.
- Where a real banner (system UNUserNotificationCenter) can't be asserted from
  XCUITest, cover the posting decision via the `shouldBanner` unit test and note it
  in the PR.

## Files (anticipated)

- `Sources/Parallel/Services/BellDebouncer.swift` (new, pure)
- `Sources/Parallel/Models/AppNotification.swift` (new)
- `Sources/Parallel/Services/NotificationStore.swift` (new, `@Observable`)
- `Sources/Parallel/Util/Notifications.swift` (extend: `sessionNeedsAttention`, delegate, `shouldBanner`)
- `Sources/Parallel/Services/SessionManager.swift` (bell wiring, `activate`, suppression flags, `sessionEnded` reroute)
- `Sources/Parallel/Views/SessionTerminalDelegate` bell → `onBell` (in `SessionManager.swift`)
- `Sources/Parallel/Views/NotificationListView.swift` (new) + toolbar bell in `ContentView.swift`
- `Sources/Parallel/ParallelApp.swift` (delegate ↔ store handoff)
- `Sources/Parallel/Views/E2EProbeView.swift` (unread-count probe)
- Tests: `BellDebouncerTests`, `NotificationStoreTests`, `NotificationBannerTests` (unit);
  `BellNotificationTests` (e2e)
