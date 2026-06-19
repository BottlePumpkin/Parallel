#!/usr/bin/env bash
# Create a worktree + branch for a GitHub issue, using the fixed `issue-<N>`
# naming convention — so you never have to invent a worktree name.
#
# Usage:
#   ./scripts/new-issue-worktree.sh <issue-number>
#
# What it does:
#   1. Verifies issue #N exists (gh) and prints its title.
#   2. Creates branch `issue-N` off the latest origin/master.
#   3. Adds a worktree at <main-repo>/.claude/worktrees/issue-N.
#   4. Prints the path + the runbook next step.
#
# Intended for the "issue management" session on master: survey issues with
# `gh issue list`, then spin off a per-issue worktree with one command. Works
# no matter which worktree it's invoked from — worktrees always land under the
# main repo root, never nested inside a linked worktree.
set -euo pipefail

N="${1:-}"
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
    echo "usage: $0 <issue-number>   (e.g. $0 7)" >&2
    exit 2
fi

cd "$(dirname "$0")/.."

# Resolve the MAIN worktree root (the primary checkout). Worktrees live under
# it, so creation must be anchored here — not at the current worktree, which
# may itself be a linked worktree. --git-common-dir points at the shared .git.
GIT_COMMON_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
MAIN_ROOT="$(dirname "$GIT_COMMON_DIR")"

# Derive owner/repo from origin so `gh` targets github.com even when another
# host (e.g. company GHE) is also authenticated.
ORIGIN_URL="$(git remote get-url origin)"
REPO_SLUG="$(printf '%s' "$ORIGIN_URL" | sed -E 's#.*github\.com[:/]##; s#\.git$##')"

BRANCH="issue-$N"
WT_PATH="$MAIN_ROOT/.claude/worktrees/issue-$N"

# Verify the issue exists (catches typos) and grab its title / state.
if ! ISSUE_JSON="$(gh issue view "$N" --repo "$REPO_SLUG" --json title,state 2>/dev/null)"; then
    echo "✗ Issue #$N not found in $REPO_SLUG (check the number)." >&2
    exit 1
fi
TITLE="$(printf '%s' "$ISSUE_JSON" | sed -E 's/.*"title":"([^"]*)".*/\1/')"
STATE="$(printf '%s' "$ISSUE_JSON" | sed -E 's/.*"state":"([^"]*)".*/\1/')"
if [ "$STATE" = "CLOSED" ]; then
    echo "⚠ Issue #$N is CLOSED — continuing anyway."
fi

# Guard against clobbering an existing branch or worktree.
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "✗ Branch '$BRANCH' already exists. cd into its worktree instead." >&2
    exit 1
fi
if [ -e "$WT_PATH" ]; then
    echo "✗ Worktree path already exists: $WT_PATH" >&2
    exit 1
fi

git fetch origin master --quiet
git worktree add "$WT_PATH" -b "$BRANCH" origin/master

# Mark the issue in-progress on GitHub so every other session/worktree sees it.
# (Local git branches are already shared across worktrees, but the GitHub board
# is the cross-session / cross-machine source of truth.) Merging the PR with
# `Closes #N` closes the issue, clearing it from the board automatically.
gh label create in-progress --repo "$REPO_SLUG" \
    --color FBCA04 --description "Being worked on in a worktree" >/dev/null 2>&1 || true
if gh issue edit "$N" --repo "$REPO_SLUG" \
        --add-label in-progress --add-assignee @me >/dev/null 2>&1; then
    MARKED="in-progress + assigned to you"
else
    MARKED="⚠ couldn't set in-progress label/assignee — set it manually"
fi

echo
echo "✓ Created worktree for issue #$N — $TITLE"
echo "    branch:   $BRANCH"
echo "    path:     $WT_PATH"
echo "    status:   $MARKED"
echo
echo "Next (per docs/ISSUE_WORKFLOW.md): work in that worktree, then deliver"
echo "with a 'Closes #$N' commit and 'gh pr create'."
