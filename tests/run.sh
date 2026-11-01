#!/bin/sh
# Regression tests for mise-me. Usage: sh tests/run.sh
# Runs tests/*.test.sh and bases/*/tests/*.test.sh against throwaway homes,
# with a fake curl and a fake mise, so nothing is installed. The first run
# needs network once to cache two pinned zsh plugin tarballs; then it is offline.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
. "$repo/tests/harness.sh"

for t in "$repo"/tests/*.test.sh "$repo"/bases/*/tests/*.test.sh; do
  [ -f "$t" ] || continue
  printf '\n# %s\n' "${t#"$repo"/}"
  . "$t"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
