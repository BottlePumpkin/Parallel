# Parallel

Lightweight macOS app for managing git worktrees with per-worktree PTY shells. Conductor-style sidebar + terminal panel — built so I could keep tens of feature worktrees organized without losing track in stacked iTerm windows.

> **Why** Conductor doesn't work on git enterprise. Pane and other open-source alternatives need notarization workarounds for company-managed Macs. This is small, native, and easy to inspect.

![Parallel screenshot](docs/screenshot.png) <!-- TODO: add a real screenshot -->

## Features

- **Sidebar** with repo groups, drag-reorder, dirty / clean status dots, changed-file badges
- **Per-worktree PTY**, login shell so `.zshrc` / `.zprofile` are loaded
- **Multiple tabs per worktree**, each independent shell — rename with right-click
- **`+ New Worktree`** with branch dropdown (Recent · Local · Remotes), path preview, optional setup commands auto-typed (`fvm flutter pub get` …)
- **`+ Import Existing`** with searchable picker for repos that already have worktrees
- **Status polling** via `git status --porcelain` every 5s (paused when window inactive)
- **Right-click menu**: Rename, Open in Finder / Cursor / VS Code / Android Studio / IntelliJ / Xcode, Remove from Parallel, Delete Worktree (with optional `git branch -D`)
- **Notifications** when a shell exits (so you know background `claude` is done)
- **Nerd Font auto-detection** — MesloLGS, JetBrains Mono, Hack, FiraCode, D2Coding, Menlo fallback chain
- All git work goes through `git` CLI — **works with git enterprise / GHE / Bitbucket / etc.**

## Install

### Easiest: download the .app

1. Grab the latest `Parallel-X.Y.Z-mac.zip` from [Releases](https://github.com/BottlePumpkin/Parallel/releases).
2. Unzip → drag `Parallel.app` to `/Applications`.
3. First launch: macOS will say "unidentified developer" — right-click `Parallel.app` → **Open** → Open. (Builds aren't notarized; one-time bypass.)

Requires **macOS 14+** (Sonoma).

### Build from source

Requires Xcode 16+ / Swift 5.10+, macOS 14+.

```bash
git clone https://github.com/BottlePumpkin/Parallel.git
cd Parallel
swift run Parallel
```

Or open `Package.swift` in Xcode and ⌘R.

To package your own `.app`:

```bash
./scripts/build-app.sh 0.1.0
# → build/Parallel.app  and  build/Parallel-0.1.0-mac.zip
```

### Optional: Install a Nerd Font

For nice prompts (powerlevel10k, starship) install a Nerd Font once; Parallel will pick it up automatically.

```bash
brew install --cask font-meslo-lg-nerd-font
```

The font fallback chain is in `Sources/Parallel/Services/SessionManager.swift`.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New worktree |
| `⌘⇧O` | Add repository |
| `⌘1`–`⌘9` | Switch to worktree N |
| `⌘W` | Close current session (worktree preserved) |
| `⌘⌫` | Delete current worktree (confirmation) |

Right-click on a sidebar worktree row for the rest.

## How "Resume after restart" works

Parallel doesn't try to keep PTYs alive across app restarts. Instead:

1. Worktree list, recent-base list, and display names persist in `workspace.json`.
2. When you click a worktree after restart, a fresh shell is forked at that path.
3. If you were running Claude Code in a session, `claude --resume` (or `/resume` inside Claude) brings the previous conversation back.

In-flight processes (`flutter run`, `npm dev`, scrollback) are not preserved.

## Storage

- Workspace: `~/Library/Application Support/Parallel/workspace.json`
- Corrupt file on load is moved aside (`workspace.json.corrupted-<timestamp>`) and the app starts empty.

## Logs

```bash
log stream --predicate 'subsystem == "com.byeonghopark.parallel"' --level debug
```

Debug builds also mirror stderr / stdout to `~/Library/Logs/Parallel/parallel-<timestamp>.log`.

## Tests

```bash
swift test
```

34 unit tests cover the pure-logic surface: `PathSanitizer`, `WorkspaceStore` (Codable round-trip, dedupe migration, corruption quarantine), `GitCLI` (large-output pipe drain), `WorktreeService` (porcelain parser, add / remove / status / branches), `PTY` (fork + read + terminate smoke test against `/bin/sh`).

Views and `SessionManager` are verified manually.

## Intentional limits

- Terminal sessions don't persist across app restart — `forkpty` re-runs at launch.
- No AI integration; you run whatever you want inside the PTY (Claude Code, Codex, plain shell).
- No PR / diff UI.
- Setup commands rely on a fixed 500ms delay after PTY fork; very slow shells may miss them.
- Exit code of a dead session is not captured (PTY EOF doesn't carry `WEXITSTATUS`).

## Design notes

- Design spec: [`docs/superpowers/specs/2026-05-27-parallel-design.md`](docs/superpowers/specs/2026-05-27-parallel-design.md)
- Implementation plan: [`docs/superpowers/plans/2026-05-27-parallel.md`](docs/superpowers/plans/2026-05-27-parallel.md)

## License

MIT — see [LICENSE](LICENSE).
