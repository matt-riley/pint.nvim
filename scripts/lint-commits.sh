#!/usr/bin/env bash
set -euo pipefail

range="${1:-}"
if [[ -z "$range" ]]; then
  if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
    git fetch origin "$GITHUB_BASE_REF" --depth=1
    range="origin/${GITHUB_BASE_REF}..HEAD"
  elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    range="origin/main..HEAD"
  else
    echo "lint-commits: no range provided and origin/main is unavailable" >&2
    exit 1
  fi
fi

if [[ -z "$(git rev-list "$range" 2>/dev/null || true)" ]]; then
  echo "lint-commits: no commits in range $range"
  exit 0
fi

types="build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test"
header_re="^(${types})(\\([^)]+\\))?(!)?: .+"

invalid=0
while IFS= read -r subject; do
  if [[ "$subject" =~ ^Merge ]]; then
    continue
  fi
  if [[ ! "$subject" =~ $header_re ]]; then
    echo "invalid conventional commit: $subject" >&2
    invalid=1
  fi
done < <(git log --format=%s "$range")

if [[ "$invalid" -ne 0 ]]; then
  echo "lint-commits: expected '<type>[optional scope]: <description>'" >&2
  exit 1
fi

echo "lint-commits: all commits in $range follow Conventional Commits"