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
- **Status polling** via `git status --porcelain` every 5s (paused when window inactive), bounded by an `OperationQueue` so polling can't explode threads
- **Right-click menu**: Rename, Open in Finder / Cursor / VS Code / Android Studio / IntelliJ / Xcode, Remove from Parallel, Delete Worktree (with optional `git branch -D`)
- **Notifications** when a shell exits (so you know background `claude` is done)
- **Keep awake** toolbar toggle — prevents display dimming + idle sleep via native `IOPMAssertion` while a long background run finishes (released automatically on quit)
- **Check for Updates** — polls GitHub Releases, with Skip-this-version / Later / Open, release notes inline (`Parallel ▸ Check for Updates…`)
- **Report Issue** — opens a prefilled GitHub new-issue with app version, macOS, architecture, and log path baked in (`Parallel ▸ Report Issue…`)
- **10k-line scrollback** per terminal, preserved across worktree / tab switches
- **Backpressure-aware PTY** — output is coalesced to one main-thread feed per cycle with high/low-watermark pause/resume, so a noisy build can't freeze the UI
- **Nerd Font auto-detection** — MesloLGS, JetBrains Mono, Hack, FiraCode, D2Coding, Menlo fallback chain
- All git work goes through `git` CLI — **works with git enterprise / GHE / Bitbucket / etc.**

## Install

### Easiest: one line

```bash
curl -fsSL https://raw.githubusercontent.com/BottlePumpkin/Parallel/master/scripts/install.sh | bash
```

Downloads the latest release, strips the quarantine attribute, drops `Parallel.app` into `/Applications`. Double-click to launch — no Gatekeeper warning.

### Manual

1. Grab the latest `Parallel-X.Y.Z-mac.zip` from [Releases](https://github.com/BottlePumpkin/Parallel/releases).
2. Unzip → drag `Parallel.app` to `/Applications`.
3. First launch: right-click `Parallel.app` → **Open** → Open (builds aren't notarized; one-time bypass).

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

### Notarized release (Apple Developer required)

One-time setup:

1. Apple Developer Program membership ([$99/year](https://developer.apple.com/programs/)).
2. Create a **Developer ID Application** certificate via Xcode → Settings → Accounts → "Manage Certificates" → `+`.
3. Generate an **app-specific password** at [appleid.apple.com](https://appleid.apple.com) → "Sign-In and Security" → "App-Specific Passwords".
4. Store the credential once in your keychain:

   ```bash
   xcrun notarytool store-credentials parallel-notary \
       --apple-id you@example.com \
       --team-id YOUR_TEAM_ID \
       --password XXXX-XXXX-XXXX-XXXX
   ```

5. Export the build env in `~/.zshrc` (or invoke ad-hoc per build):

   ```bash
   export SIGN_IDENTITY="Developer ID Application: Your Name (YOUR_TEAM_ID)"
   export NOTARY_PROFILE="parallel-notary"
   ```

For a build-only `.app` (no publish), `./scripts/build-app.sh 0.2.0` signs with
hardened runtime, submits to Apple, waits for notarization (1-5 min), staples the
ticket onto the `.app`, and re-zips.

To cut and publish a full release in one command:

```bash
brew install git-cliff               # one-time
gh auth login --hostname github.com  # one-time (public repo lives on github.com)

./scripts/release.sh 0.3.0
```

`release.sh` regenerates `CHANGELOG.md` from Conventional Commits, previews the
release notes, and — after you confirm — commits the changelog, tags the version,
builds + notarizes via `build-app.sh`, pushes, and creates the GitHub Release with
the notarized zip attached. The generated notes become the release body that the
in-app **Check for Updates** shows. Use `./scripts/release.sh --dry-run 0.3.0` to
preview without pushing.

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

85 unit tests cover the pure-logic surface:

- `PathSanitizer`, `WorkspaceStore` (Codable round-trip, dedupe migration, corruption quarantine)
- `GitCLI` (large-output pipe drain), `WorktreeService` (porcelain parser, add / remove / status / branches)
- `PTY` (fork + read + terminate smoke test against `/bin/sh`), `PTYOutputCoalescer` + backpressure integration (watermark pause/resume)
- `SemanticVersion` (comparable tag parser), `AppVersion` / `IssueReporter` (issue-template signature + new-issue URL)
- `UpdateChecker` (GitHub Releases polling, cache + skip state) via a `URLProtocol` stub

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
