#!/usr/bin/env bash
# Runs a command with SENTRY_AUTH_TOKEN from the repo root's gitignored .env.local, unless the shell
# already has one. In a git worktree it falls back to the main checkout's .env.local, where the token lives.
#   scripts/with-sentry.sh <command> [args…]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  main="$(dirname "$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "$here/.git")")"
  for env in "$here/.env.local" "$main/.env.local"; do
    token="$(sed -n 's/^SENTRY_AUTH_TOKEN=//p' "$env" 2>/dev/null | tail -1 || true)"
    if [ -n "$token" ]; then
      export SENTRY_AUTH_TOKEN="$token"
      break
    fi
  done
fi
exec "$@"
