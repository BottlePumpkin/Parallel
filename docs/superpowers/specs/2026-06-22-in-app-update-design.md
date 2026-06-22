# In-App One-Click Update — Design Spec

**Date:** 2026-06-22
**Status:** Approved (brainstorming)
**Issue:** #5 — 업데이트: 설치 명령 Copy 대신 인앱 '한 번에 업데이트'
**Target release:** 0.4.0

## Problem

When an update is available, `UpdateAvailableSheet` shows release notes plus an
install command (`curl … install.sh | bash`) the user must **Copy and paste into a
terminal**. We want a single **"Update Now"** button that downloads, installs, and
relaunches the app in place.

## Goals

- One click in the update sheet → download → unpack → swap → relaunch, no terminal.
- Update the **currently-running bundle wherever it lives** (not hardcoded to
  `/Applications`).
- Fail safe: if anything goes wrong, the running app is left intact and the user
  can fall back to the existing manual install command.

## Non-Goals

- No CI / no notarization requirement. (Notarization can be added later via the
  release automation from #15; this design does not depend on it.)
- No code-signature/notarization verification of the download (releases are ad-hoc
  today; verifying would block all updates). See "Security" below.
- No SHA-256 checksum verification in this iteration (possible later hardening that
  pairs with `release.sh`).
- No background/silent auto-update — the user always initiates from the sheet.

## Approach (chosen)

**Native in-app updater (Approach B).** A small native pipeline replaces the
"Copy install command" flow. `install.sh` is kept as-is for the `curl`-one-liner
bootstrap path (new installs target `/Applications`); the in-app updater targets
the running bundle's actual location, so the two paths are genuinely different and
not duplicative.

Approaches A (shell out to `install.sh`) and C (download & reveal) were rejected:
A hardcodes `/Applications` and surfaces progress/errors poorly; C doesn't meet
the "one click → relaunched" bar.

## Security / Trust model (chosen: HTTPS + version sanity)

The asset URL comes from the same TLS-protected GitHub API response we already
trust for the version check. We download over HTTPS and then verify the unpacked
bundle's `CFBundleShortVersionString` equals the expected latest version (guards
against a corrupt/wrong zip). This matches the trust model of the existing manual
`install.sh` path — it does not lower security. Stronger options (code-signature
check once notarized; SHA-256 checksum published by `release.sh`) are deferred.

## Architecture / Components

```
UpdateInfo / UpdateChecker   (modify) — parse the -mac.zip asset URL from release JSON
Updater                      (new)    — orchestrates download→unpack→verify→swap→relaunch
UpdateInstallTarget          (new)    — resolves running-bundle location + replaceability (pure)
UpdateAvailableSheet         (modify) — "Copy" block → "Update Now" + progress UI
```

### UpdateChecker / UpdateInfo (modify)

- `ReleasePayload` gains `assets: [Asset]` where `Asset` decodes
  `browser_download_url` and `name`.
- A pure helper selects the first asset whose name matches `*-mac.zip`.
- `UpdateInfo` gains `assetURL: URL?` (nil when no matching asset → "Update Now"
  disabled, manual fallback shown).

### Updater (new) — `@MainActor @Observable`

Observable phase drives the sheet UI:

```swift
enum UpdatePhase: Equatable {
    case idle
    case downloading(fraction: Double)
    case unpacking
    case verifying
    case installing
    case relaunching
    case failed(String)
}
```

`func update(from info: UpdateInfo, target: URL)` runs the pipeline:

1. **Download** `info.assetURL` to a temp file via `URLSession` download task;
   report progress → `.downloading(fraction)`; support cancel (task cancel →
   `.idle`).
2. **Unpack** `.unpacking`: `ditto -x -k <zip> <tempDir>` (Process). Locate
   `<tempDir>/Parallel.app`.
3. **Verify** `.verifying`: read `CFBundleShortVersionString` from the unpacked
   bundle; abort if it ≠ `info.latestVersion`. Strip quarantine
   (`xattr -dr com.apple.quarantine <app>`).
4. **Install** `.installing`: atomically replace the running bundle at `target`
   via `FileManager.replaceItemAt(target, withItemAt: unpackedApp, …)`. The
   running process keeps its mapped file handles, so replacing the live bundle is
   safe; nothing touches `target` until this step, so earlier failures leave the
   current app intact.
5. **Relaunch** `.relaunching`: spawn a detached helper, then `NSApp.terminate`:
   ```sh
   /bin/sh -c 'while kill -0 <PID> 2>/dev/null; do sleep 0.2; done; open "<bundle>"'
   ```
   When the current process exits, the helper opens the new bundle.

Auto-relaunch is acceptable: Parallel already does not persist PTY sessions across
restart (documented behavior), so nothing is lost.

### UpdateInstallTarget (new) — pure, the core unit-tested piece

`static func resolve(bundleURL: URL, isWritable: (URL) -> Bool) -> Result`
where

```swift
enum Result: Equatable {
    case replaceable(URL)        // the .app to replace in place
    case unsupported(String)     // human-readable reason
}
```

Rules:
- bundle path does not end in `.app` (e.g. `swift run` executable) →
  `.unsupported("dev build")`.
- path contains `AppTranslocation/` (Gatekeeper read-only randomized path) →
  `.unsupported("move to /Applications first")`.
- parent directory not writable → `.unsupported("can't write to <dir>")`.
- otherwise → `.replaceable(bundleURL)`.

### UpdateAvailableSheet (modify)

- Replace the "Install command" Copy block with a primary **Update Now** button
  (enabled only when `info.assetURL != nil` and the install target is
  `.replaceable`) plus progress/cancel UI bound to `Updater.phase`.
- Keep **Skip This Version**, **Later**, **Open Release Page**.
- On `.failed` or `.unsupported`, reveal the existing manual install command (the
  current Copy affordance) as a fallback, with the reason.

## Error Handling / Edge Cases

| Situation | Detection | Behavior |
|---|---|---|
| dev build (not a `.app`) | `UpdateInstallTarget.resolve` | Update Now hidden; manual command |
| App Translocation | path contains `AppTranslocation/` | unsupported + "move to /Applications" + Open Release Page |
| parent dir not writable | `isWritable(parent) == false` | unsupported + manual fallback |
| no `-mac.zip` asset | `assetURL == nil` | Update Now disabled; manual fallback |
| download/unpack/verify failure | pipeline throws | `.failed(msg)`; current app intact; show error + manual fallback |
| version mismatch | unpacked Info.plist ≠ latest | abort as corrupt/wrong zip |
| cancel during download | user action | task cancel → `.idle` |

`replaceItemAt` is atomic — no partial swap.

## Testing

**Unit-tested (pure logic):**
- `UpdateInstallTarget.resolve` — normal `/Applications/Parallel.app` →
  `.replaceable`; non-`.app` dev path → `.unsupported`; `AppTranslocation` path →
  `.unsupported`; non-writable parent → `.unsupported`.
- Bundle-version read helper — reads `CFBundleShortVersionString` from a fixture
  `Info.plist`; match / mismatch / missing.
- Asset-selection helper — pick `*-mac.zip` from an asset list: normal / none /
  multiple.
- `UpdateChecker` — extend the existing `URLProtocol`-stub tests: `assets[]`
  parsed → `UpdateInfo.assetURL` populated; absent → `nil`.

**Manual (side effects, not unit-tested, mirrors `SessionManager`/`build-app.sh`):**
- `Updater`'s real download → `ditto` → `replaceItemAt` → relaunch.
- Demo: run a deliberately lower-versioned build, click Update Now against the
  current latest release, confirm in-place update + relaunch.

`UpdateAvailableSheet` is a View — verified manually.

## Documentation Impact

- The README "Check for Updates" feature bullet can note one-click in-app update
  (minor; optional in this change).
```
