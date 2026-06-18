# Release Automation — Design Spec

**Date:** 2026-06-18
**Status:** Approved (brainstorming)
**Topic:** Local all-in-one release pipeline (CHANGELOG + GitHub Release) via git-cliff

## Problem

Releases are manual. `scripts/build-app.sh` builds, notarizes, staples, and zips
`Parallel.app`, but the human then has to write release notes, create the GitHub
Release, and upload the zip by hand. The in-app `UpdateChecker` reads the GitHub
Release body to show update notes — so those notes being hand-written and
inconsistent directly degrades the user-facing update experience.

The repo already uses strict Conventional Commits (`feat(scope):`, `fix(scope):`,
`docs:`, `chore:`, `test:`, `refactor:`) and semver tags (`v0.1.0`…`v0.2.0`), so
changelog generation is essentially free if wired up.

## Goals

- One command turns a clean `master` into a tagged, notarized, published release.
- `CHANGELOG.md` is generated from commits, never hand-maintained.
- The GitHub Release body (what `UpdateChecker` surfaces in-app) is the generated
  notes for that version — automatic and consistent.
- Irreversible steps (push, public release) require an explicit confirmation.

## Non-Goals

- No CI/GitHub Actions. Notarization needs the local keychain, so the build —
  and therefore the release that uploads the notarized zip — stays local.
- No automatic version bumping. The human picks the version (minor vs. patch is a
  judgment call); git-cliff's suggested bump is printed for reference only.
- No changes to the app's Swift source. This is tooling only.

## Constraints (discovered)

- **Notarization is local.** `notarytool`/`stapler` use a keychain profile
  (`NOTARY_PROFILE`) — cannot run in cloud CI. Build must run on the dev machine.
- **`gh` auth host mismatch.** `gh` is currently authenticated to `github.jobis.co`
  (company GHE). The Parallel repo is on **github.com**
  (`https://github.com/BottlePumpkin/Parallel.git`). Release automation needs a
  separate github.com login — confirmed doable with the personal account
  `p4569zz@gmail.com` via `gh auth login --hostname github.com`. Both auths
  coexist (different hosts).

## Architecture

```
cliff.toml              # git-cliff config: commit → changelog mapping rules
CHANGELOG.md            # generated + accumulated (backfilled v0.1.0…v0.2.0)
scripts/release.sh      # NEW — release orchestrator
scripts/build-app.sh    # UNCHANGED — single responsibility: build/notarize/zip
```

**Separation of concerns:** `build-app.sh` keeps its single "build" responsibility
and remains directly callable for test builds. `release.sh` owns the "release"
responsibility (changelog, tag, push, GitHub Release) and calls `build-app.sh` for
the build step.

### `cliff.toml` rules

- `feat:` → **Features**, `fix:` → **Bug Fixes** — only these two sections appear.
- `docs`, `test`, `chore`, `refactor`, `build` → **skipped** (still in git history,
  not in the changelog / release notes).
- Scope rendered as a bold prefix: `**views:** hide ManualCheckSheet OK button…`.
- Each entry links its short commit hash; each version links a compare range
  (`v0.2.0...v0.3.0`).
- Grouped by tag.

### `release.sh <version>` flow

```
1. Preflight   — clean tree? on master? github.com gh auth present?
                 git-cliff + gh installed? tag not already present?
                 → fail fast with a clear message on any miss
2. Changelog   — git-cliff --tag v<version>  →  update CHANGELOG.md
3. Commit      — "docs: changelog for v<version>"
4. Tag         — git tag v<version>
5. Build       — build-app.sh <version>  (notarize / staple / zip)
6. Push        — git push origin master --follow-tags
7. Release     — gh release create v<version>
                   --repo github.com/BottlePumpkin/Parallel
                   --notes "<extracted section for this version>"
                   <notarized zip>
```

**Confirmation gate:** before the irreversible steps (6 push, 7 release), print a
`--dry-run` preview (the generated changelog section + version) and prompt for
confirmation. Default flow is still "one command," but nothing is pushed or
published until the human reviews and presses enter.

**Version:** a required manual argument (`release.sh 0.3.0`). git-cliff's
commit-derived bump suggestion is printed for reference but not applied.

## Error Handling / Edge Cases

- Dirty tree / not on master / no github.com auth / git-cliff or gh missing →
  abort in preflight (step 1).
- Tag already exists → abort (no overwrite).
- Notarize failure → abort before the release step. If the tag was already pushed,
  print rollback guidance.
- `NOTARY_PROFILE` / `SIGN_IDENTITY` unset → proceed with an ad-hoc build but warn
  loudly that the release is **unnotarized**.

## Testing / Validation

- `release.sh` is a shell orchestrator, not unit-tested. It ships a **`--dry-run`**
  mode that runs the whole flow without push/release and prints the changelog that
  would be generated — for manual verification.
- `cliff.toml` is validated by running it against the existing tag history
  (`v0.1.0`…`v0.2.0`) and eyeballing the output before first real use.

## One-Time Setup (manual, by user)

- `brew install git-cliff`
- `gh auth login --hostname github.com` (account `p4569zz@gmail.com`)

## Documentation Impact

- Update the README "Notarized release" section to describe the `release.sh`
  one-command flow.

## Out of Scope (future layers, not this spec)

- Layer 1: README "mechanical facts" generator (test count, keyboard shortcuts,
  font chain) + drift-detection CI gate.
- Layer 3: `/update-readme` Claude command that proposes Features-prose diffs from
  commits since the last README touch.
</content>
</invoke>
