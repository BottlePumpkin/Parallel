#!/usr/bin/env bash
# Release orchestrator: changelog -> commit -> tag -> build -> push -> GitHub Release.
# Usage:  scripts/release.sh [--dry-run] <X.Y.Z>
# Build/notarize/zip is delegated to scripts/build-app.sh (unchanged).
set -euo pipefail

REPO="BottlePumpkin/Parallel"
GH_HOST="github.com"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "❌ $*" >&2; exit 1; }

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=true; shift; fi

VERSION="${1:-}"
[[ -n "$VERSION" ]] || die "Usage: release.sh [--dry-run] <X.Y.Z>   e.g. release.sh 0.3.0"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version must be X.Y.Z (got '$VERSION')"
TAG="v$VERSION"

# --- Preflight (fail fast) ---
command -v git-cliff >/dev/null || die "git-cliff not installed — brew install git-cliff"
command -v gh >/dev/null || die "gh not installed — brew install gh"
gh auth status --hostname "$GH_HOST" >/dev/null 2>&1 \
  || die "gh not authenticated to $GH_HOST — run: gh auth login --hostname $GH_HOST"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "master" ]] || die "Not on master"
git diff --quiet && git diff --cached --quiet || die "Working tree not clean — commit or stash first"
! git rev-parse "$TAG" >/dev/null 2>&1 || die "Tag $TAG already exists"

if [[ -z "${NOTARY_PROFILE:-}" || -z "${SIGN_IDENTITY:-}" ]]; then
  echo "⚠️  NOTARY_PROFILE/SIGN_IDENTITY unset — this release will be UNNOTARIZED."
fi

# --- Preview the release notes for this version ---
echo "==> git-cliff suggested next version: $(git-cliff --bumped-version 2>/dev/null || echo 'n/a')"
NOTES="$(git-cliff --unreleased --tag "$TAG" --strip header)"
echo "================ Release notes for $TAG ================"
echo "$NOTES"
echo "======================================================="

if $DRY_RUN; then
  echo "✅ dry-run complete — nothing committed, pushed, or published."
  exit 0
fi

read -r -p "Proceed to build, push, and publish $TAG? [y/N] " ans
[[ "$ans" == "y" || "$ans" == "Y" ]] || die "Aborted by user."

# --- Changelog + commit + tag (local, still reversible until push) ---
git-cliff --tag "$TAG" -o CHANGELOG.md
git add CHANGELOG.md
git commit -m "docs: changelog for $TAG"
git tag "$TAG"

# --- Build / notarize / zip ---
./scripts/build-app.sh "$VERSION"
ZIP="build/Parallel-$VERSION-mac.zip"
[[ -f "$ZIP" ]] || die "Expected $ZIP not found after build — aborting before push."

# --- Irreversible: push + publish ---
git push origin master --follow-tags
gh release create "$TAG" "$ZIP" \
  --repo "$REPO" \
  --title "$TAG" \
  --notes "$NOTES"

echo "✅ Released $TAG → https://github.com/$REPO/releases/tag/$TAG"
