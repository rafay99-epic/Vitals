#!/usr/bin/env bash
#
# promote.sh — cut a Stable release by promoting nightly → main.
#
# Run this INSTEAD of clicking GitHub's "Squash & merge" on the weekly
# `nightly → main` PR. Here's why the button can't be used:
#
#   Every promotion adds a squash commit to `main` that never lands on `nightly`,
#   so the two branches don't share recent history — their merge-base is stuck far
#   back. GitHub's merge button (squash, merge, OR rebase — all three) then does a
#   3-way merge against that stale base and conflicts on every file both sides
#   touched, every single promotion.
#
# This sidesteps the 3-way merge entirely: it sets `main`'s tree to *exactly*
# `origin/nightly` as one new commit and pushes it normally. No merge, so no
# conflict; no rewind, so no force-push. `main` still gets exactly one commit per
# release, so the Stable version stays `0.<commit count on main>`. Pushing to
# `main` triggers ci.yml's release job (build + publish DMG).
#
# Feature branches still squash-merge into `nightly` through the normal PR button —
# that never conflicts. Only this final nightly → main step uses the script.
#
#   Usage:  .github/scripts/promote.sh        # promote, with a confirmation prompt
#           .github/scripts/promote.sh --yes  # skip the prompt (non-interactive)
#
# Requires: git (and gh, optionally, to auto-close the open promotion PR).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO="rafay99-epic/Vitals"

# In this repo "nightly" is both a branch AND a release tag, so a bare `nightly`
# ref is ambiguous. Use fully-qualified remote-tracking refs everywhere.
ORIGIN_MAIN="refs/remotes/origin/main"
ORIGIN_NIGHTLY="refs/remotes/origin/nightly"

assume_yes=false
case "${1:-}" in
  -y | --yes) assume_yes=true ;;
  "") ;;
  *) echo "Unknown argument: $1 (use --yes to skip the prompt)"; exit 2 ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not inside a git repository."; exit 1; }

# We move HEAD around, so refuse to run on a dirty tree.
if [ -n "$(git status --porcelain)" ]; then
  echo "Working tree isn't clean — commit or stash your changes first."
  exit 1
fi

# Remember where to return the user afterward (branch name, or sha if detached).
start_ref="$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)"

echo "Fetching latest main + nightly…"
git fetch --quiet origin \
  "+refs/heads/main:${ORIGIN_MAIN}" \
  "+refs/heads/nightly:${ORIGIN_NIGHTLY}"

# Direction is nightly → main: nothing to ship if the source (nightly) already
# matches the target (main). `--quiet` only reports presence, so operand order is
# cosmetic — nightly (source) is listed first to read in the promotion direction.
if git diff --quiet "${ORIGIN_NIGHTLY}" "${ORIGIN_MAIN}"; then
  echo "nightly is already identical to main — nothing to promote."
  exit 0
fi

# Stable version = 0.<commit count on main AFTER this promotion commit>.
version="0.$(( $(git rev-list --count "${ORIGIN_MAIN}") + 1 ))"

# Build the release notes NOW, before main moves. The changelog covers the
# nightly commits being promoted (since the last Stable cut); ci.yml's release
# job reads this commit's body as the Stable release notes. It must be computed
# here: after the promotion main == nightly, so the range can't be recovered.
changelog="$(bash "${SCRIPT_DIR}/changelog.sh" \
  "$(bash "${SCRIPT_DIR}/stable-base.sh" "${ORIGIN_MAIN}" "${ORIGIN_NIGHTLY}")" \
  "${ORIGIN_NIGHTLY}")"
commit_msg_file="$(mktemp)"
{
  echo "Promote nightly → main: Stable ${version}"
  echo
  echo "$changelog"
} > "$commit_msg_file"

echo
echo "About to cut Stable ${version}. Changes since the last Stable cut:"
git --no-pager log --oneline "${ORIGIN_MAIN}..${ORIGIN_NIGHTLY}" | sed 's/^/  /'
echo
echo "This sets main's contents to exactly origin/nightly, commits, and pushes to"
echo "main — which triggers the release build that publishes the DMG to Stable users."
if [ "$assume_yes" = false ]; then
  printf 'Proceed? [y/N] '
  read -r reply
  case "$reply" in
    y | Y | yes | YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

# Land on main at its current tip, then replace its tree with nightly's wholesale.
git checkout --quiet main
git reset --quiet --hard "${ORIGIN_MAIN}"
git read-tree -u --reset "${ORIGIN_NIGHTLY}"

# Safety net: the staged tree MUST equal nightly exactly. If not, back out cleanly
# before committing anything.
if ! git diff --quiet --cached "${ORIGIN_NIGHTLY}"; then
  echo "Aborting: staged tree doesn't match nightly (unexpected)."
  git reset --quiet --hard "${ORIGIN_MAIN}"
  git checkout --quiet "$start_ref"
  exit 1
fi

git commit --quiet -F "$commit_msg_file"
git push origin main

# Return the user to where they started.
git checkout --quiet "$start_ref"

# Best-effort: close the open promotion PR (promotion.yml opens a draft weekly).
# It can't be merged via the button anyway, and the promotion is now done.
if command -v gh >/dev/null 2>&1; then
  pr="$(gh pr list --base main --head nightly --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
  if [ -n "$pr" ]; then
    gh pr close "$pr" --comment "Promoted via \`.github/scripts/promote.sh\` (Stable ${version}). The merge button isn't usable here — main and nightly don't share recent history, so GitHub's 3-way merge conflicts. main now matches nightly exactly." >/dev/null 2>&1 \
      && echo "Closed promotion PR #${pr}." || true
  fi
fi

echo
echo "✅ Pushed Stable ${version}. Release build:"
echo "   https://github.com/${REPO}/actions/workflows/ci.yml"
