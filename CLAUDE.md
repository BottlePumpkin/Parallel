# Parallel — project guide for Claude

A macOS SwiftUI app for running parallel terminal sessions across git worktrees.

## Issue-driven work — follow the runbook

Any work that starts from a GitHub issue MUST follow the runbook:
[`docs/ISSUE_WORKFLOW.md`](docs/ISSUE_WORKFLOW.md). It is the source of truth for
phases and the three human-approval gates. Do not skip a gate.

- One worktree + branch per issue, named `issue-N`, branched off `origin/master`:
  `./scripts/new-issue-worktree.sh N` (also marks the issue in-progress + assigns it).
- Check `gh issue list --label in-progress` before picking up work so two sessions
  don't double-pick the same issue.

## Testing policy — not optional

Phase 3 is "Implement **& Test**". See the full
[Test policy](docs/ISSUE_WORKFLOW.md#test-policy-phase-3) in the runbook. In short:

- **Always** add/extend **unit tests** (`swift test`, `Tests/ParallelTests/`) for the
  logic you change.
- **Add e2e** (XCUITest, `Tests/ParallelUITests/`) whenever the change touches the
  view layer, menu commands / `ParallelCommands`, keyboard shortcuts, `SessionManager`,
  or the PTY/terminal flow. Where e2e genuinely can't reach SwiftTerm-internal state,
  say so in the PR and fall back to unit + a manual-check note.
- **Always run both suites green before the PR** and report both results as the Gate 3
  evidence — even when no new e2e test was added.

## Commands

```bash
# Unit tests
swift test

# e2e (XCUITest) — generate the project, then drive the real .app
xcodebuild -downloadComponent MetalToolchain || true   # one-time, no-op where unsupported
xcodegen generate
xcodebuild test -project Parallel.xcodeproj -scheme Parallel \
  -destination 'platform=macOS' -only-testing:ParallelUITests \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES

# Build the .app
./scripts/build-app.sh
```

CI (`.github/workflows/ci.yml`) runs both suites (`unit` + `e2e` jobs) on every PR.

## Conventions

- **Commits:** Conventional Commits matching the repo — `fix(views): …`,
  `feat(services): …`, `docs: …`, `test: …`. Include `Closes #N` so the issue
  auto-closes on merge.
- **Code:** match the style of the surrounding file; prefer extending existing
  patterns over introducing new abstractions.
