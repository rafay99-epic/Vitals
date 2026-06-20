#!/usr/bin/env bash
#
# changelog.sh — print a clean Markdown changelog for a commit range, grouping
# squash-merged PRs by their `area:*` label (the same labels labeler.yml applies).
#
# ONE generator, reused everywhere so the changelogs never drift:
#   - promotion.sh  → the `nightly → main` promotion PR body
#   - promote.sh    → the Stable promotion commit body (→ Stable release notes)
#   - nightly.yml   → the rolling Nightly pre-release notes
#
#   Usage:  changelog.sh <base-ref> <head-ref>
#   e.g.    changelog.sh origin/main origin/nightly
#
# Emits Markdown to stdout (diagnostics go to stderr). Requires git, gh, jq, and
# a GH_TOKEN with **read** access to the repo's pull requests (the default
# GITHUB_TOKEN is enough). Assumes both refs are already fetched locally.
#
# Deliberately bash-3.2 compatible (no `mapfile`, no associative arrays): the
# Nightly publish job runs on a macOS runner whose /bin/bash is 3.2, and it's
# handy to run locally on a Mac too.

set -euo pipefail

BASE="${1:?usage: changelog.sh <base-ref> <head-ref>}"
HEAD_REF="${2:?usage: changelog.sh <base-ref> <head-ref>}"

# Fixed buckets mirror .github/labeler.yml. An unknown/absent area drops into
# uncategorized rather than being silently dropped.
b_desktop=""; b_website=""; b_backend=""; b_ci=""; b_docs=""; b_uncat=""
c_desktop=0;  c_website=0;  c_backend=0;  c_ci=0;  c_docs=0;  c_uncat=0
TOTAL=0

add_to_bucket() { # $1=area (may be empty) $2=line
  case "$1" in
    desktop) b_desktop="${b_desktop}$2"$'\n'; c_desktop=$((c_desktop + 1)) ;;
    website) b_website="${b_website}$2"$'\n'; c_website=$((c_website + 1)) ;;
    backend) b_backend="${b_backend}$2"$'\n'; c_backend=$((c_backend + 1)) ;;
    ci)      b_ci="${b_ci}$2"$'\n';           c_ci=$((c_ci + 1)) ;;
    docs)    b_docs="${b_docs}$2"$'\n';        c_docs=$((c_docs + 1)) ;;
    "")      b_uncat="${b_uncat}$2"$'\n';      c_uncat=$((c_uncat + 1)) ;;
    *)       b_uncat="${b_uncat}$2 _(area: $1)_"$'\n'; c_uncat=$((c_uncat + 1)) ;;
  esac
}

# Squash-merged PRs end every subject with `(#NN)`. `--reverse` so the oldest
# lands first, matching the order they were merged.
while IFS= read -r n; do
  [ -z "$n" ] && continue
  data=$(gh pr view "$n" --json title,author,labels 2>/dev/null) \
    || { echo "skip #$n (gh pr view failed)" >&2; continue; }
  title=$(jq -r '.title' <<< "$data")
  author=$(jq -r '.author.login // "ghost"' <<< "$data")
  areas=$(jq -r '.labels[].name' <<< "$data" | grep '^area:' | sed 's/^area://' || true)
  line="- #${n} ${title} — @${author}"

  if [ -z "$areas" ]; then
    add_to_bucket "" "$line"
  else
    while IFS= read -r area; do
      [ -z "$area" ] && continue
      add_to_bucket "$area" "$line"
    done <<< "$areas"
  fi
  TOTAL=$((TOTAL + 1))
done < <(git log --reverse --format='%s' "${BASE}..${HEAD_REF}" \
           | grep -oE '\(#[0-9]+\)$' | tr -d '()#' || true)

# Anything without a `(#NN)` suffix bypassed the PR flow — surfaced as a safety net.
DIRECT=""
DIRECT_N=0
while IFS= read -r d; do
  [ -z "$d" ] && continue
  DIRECT="${DIRECT}${d}"$'\n'
  DIRECT_N=$((DIRECT_N + 1))
done < <(git log --reverse --format='%h  %s' "${BASE}..${HEAD_REF}" \
           | grep -vE '\(#[0-9]+\)$' || true)

emit_section() { # $1=label $2=count $3=body
  [ "$2" -eq 0 ] && return
  echo "### $1 ($2)"
  echo
  printf '%s' "$3"
  echo
}

if [ "$TOTAL" -eq 0 ] && [ "$DIRECT_N" -eq 0 ]; then
  echo "_No changes in this range._"
  exit 0
fi

echo "**${TOTAL} pull request$([ "$TOTAL" -eq 1 ] || echo s)** in this release:"
echo

emit_section "Desktop"       "$c_desktop" "$b_desktop"
emit_section "Website"       "$c_website" "$b_website"
emit_section "Backend"       "$c_backend" "$b_backend"
emit_section "CI"            "$c_ci"      "$b_ci"
emit_section "Docs"          "$c_docs"    "$b_docs"
emit_section "Uncategorized" "$c_uncat"   "$b_uncat"

if [ "$DIRECT_N" -gt 0 ]; then
  echo "### Direct commits ($DIRECT_N)"
  echo
  echo "Bypassed the PR flow — CLAUDE.md says to avoid this; surfaced here as a safety net."
  echo
  echo '```'
  printf '%s' "$DIRECT"
  echo '```'
  echo
fi
