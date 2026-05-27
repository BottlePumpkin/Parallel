# Parallel

A lightweight macOS app for managing git worktrees with per-worktree PTY sessions. Built because Conductor doesn't work on git enterprise — and as a personal Swift project.

## Status

MVP. Personal use.

## Run

Requires Xcode 16+ / Swift 5.10+, macOS 14+.

```bash
swift run Parallel
```

Or open `Package.swift` in Xcode and `⌘R`.

For best results, install a Nerd Font so popular shell prompts render correctly:

```bash
brew install --cask font-meslo-lg-nerd-font
```

The terminal font fallback chain is in `Sources/Parallel/Services/SessionManager.swift`.

## What it does

- **Sidebar** lists registered repos and their git worktrees.
- **Detail pane** hosts a SwiftTerm view backed by a `forkpty` shell session, one per worktree.
- **`+ New Worktree`** creates a `git worktree add` and auto-spawns a shell, with optional setup commands (e.g. `flutter pub get`) auto-typed on startup.
- **`+ Add Repository`** registers an existing repo and offers to import its existing worktrees.
- **Status** is polled every 5 seconds; sidebar shows dirty/clean and changed-file counts.

## Storage

`~/Library/Application Support/Parallel/workspace.json`

If the file is corrupt on load, it's moved aside (`workspace.json.corrupted-<timestamp>`) and the app starts empty.

## Logs

Subsystem `com.byeonghopark.parallel`. View in Console.app or:

```bash
log stream --predicate 'subsystem == "com.byeonghopark.parallel"' --level debug
```

Debug builds also create `~/Library/Logs/Parallel/`.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New worktree |
| `⌘⇧O` | Add repository |
| `⌘1`–`⌘9` | Switch to worktree N |
| `⌘W` | Close current session (worktree preserved) |
| `⌘⇧⌫` | Delete current worktree (confirmation) |

## Intentional limits

- Terminal sessions don't persist across app restart — `forkpty` re-runs at launch.
- No AI integration; you run whatever you want inside the PTY (Claude Code, Codex, plain shell).
- No PR/diff UI.
- Exit code of a dead session is not captured.
- Setup commands rely on a fixed 500ms delay after PTY fork; slow shells may miss them.

## Tests

```bash
swift test
```

33 tests covering PathSanitizer, WorkspaceStore, GitCLI, WorktreeService (list/parser/add/remove/status), and PTY (smoke).

## Design notes

- `docs/superpowers/specs/2026-05-27-parallel-design.md` — the design spec.
- `docs/superpowers/plans/2026-05-27-parallel.md` — the implementation plan (22 tasks).
