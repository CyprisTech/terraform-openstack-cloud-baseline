#!/usr/bin/env bash
# Runs every check of the bench, step 0 first, and prints a summary. Run on the bench host, from a
# copy of the repository, after install.sh. Each check cleans up before and after itself.
# Usage: ./check-all.sh [check...]      e.g. ./check-all.sh step0 networks
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
if [ "$#" -gt 0 ]; then
  checks=("$@")
else
  checks=(step0)
  for f in "$here"/check-*.sh; do
    name=$(basename "$f" .sh); name=${name#check-}
    case "$name" in step0 | all) ;; *) checks+=("$name") ;; esac
  done
fi

summary=()
status=0
for c in "${checks[@]}"; do
  echo "== $c"
  if "$here/check-$c.sh"; then summary+=("ok   $c"); else summary+=("FAIL $c"); status=1; fi
done

echo
echo "== summary"
printf '%s\n' "${summary[@]}"
exit "$status"
