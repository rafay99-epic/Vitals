#!/usr/bin/env bash
#
# stable-base.sh — print the nightly commit that corresponds to the current
# Stable release, i.e. the point last promoted to main.
#
# Why this is needed: promotion never puts nightly's commits *onto* main — it
# writes a fresh squash commit whose *tree* equals nightly's tip (promote.sh
# verifies that equality exactly). So main and nightly share no recent history,
# and `main..nightly` would list the ENTIRE nightly history forever, not just the
# unreleased part. Instead we find the nightly commit whose tree matches the
# current Stable tree; everything after it on nightly is the real unreleased set.
#
#   Usage:  stable-base.sh [main-ref] [nightly-ref]
#           (defaults: refs/remotes/origin/main, refs/remotes/origin/nightly)
#
# Prints a commit SHA to stdout. Requires git; assumes both refs are fetched.
# bash-3.2 compatible (runs on the macOS Nightly runner too).

set -euo pipefail

MAIN_REF="${1:-refs/remotes/origin/main}"
NIGHTLY_REF="${2:-refs/remotes/origin/nightly}"

target_tree=$(git rev-parse "${MAIN_REF}^{tree}")

# One `git log` lists every nightly commit with its tree; take the newest whose
# tree matches Stable's. `%H %T` = commit hash + tree hash. We don't `exit` early
# from awk — that would SIGPIPE `git log` and trip `pipefail`; reading to the end
# is cheap and prints only the first (newest) match.
match=$(git log --format='%H %T' "${NIGHTLY_REF}" \
  | awk -v t="$target_tree" '$2 == t && !found { print $1; found = 1 }')

if [ -n "$match" ]; then
  echo "$match"
else
  # No nightly commit shares the Stable tree (the very first promotion, or a
  # hand-edited main). Fall back to the merge-base so callers get a bounded
  # range rather than the whole history or nothing.
  git merge-base "${MAIN_REF}" "${NIGHTLY_REF}"
fi
