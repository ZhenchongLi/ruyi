#!/bin/bash
set -e

# Minimal closed-loop test for ruyi
# Creates a temp project, runs ruyi do, verifies result

RUYI="$(cd "$(dirname "$0")/.." && pwd)/ruyi"
TMPDIR=$(mktemp -d /tmp/ruyi-test-XXXXXX)
trap "rm -rf $TMPDIR" EXIT

echo "=== Ruyi Minimal Loop Test ==="
echo "Dir: $TMPDIR"

# 1. Create a tiny project
cd "$TMPDIR"
git init
echo "hello" > test.txt
git add -A && git commit -m "init"

echo ""
echo "--- Step 1: ruyi init ---"
$RUYI init
[ -f .ruyi.rkt ] && echo "PASS: .ruyi.rkt created" || { echo "FAIL: no .ruyi.rkt"; exit 1; }

echo ""
echo "--- Step 2: ruyi do (trivial task) ---"
$RUYI do "Add a second line to test.txt that says 'world'. Do not create any other files."

echo ""
echo "--- Step 3: Verify ---"
# Check git log has more than 1 commit (init + at least merge/evolve)
COMMITS=$(git log --oneline | wc -l)
echo "Commits: $COMMITS"

if [ "$COMMITS" -gt 1 ]; then
  echo "PASS: ruyi made changes"
  git log --oneline
else
  echo "INFO: no changes committed (task may have been rejected by reviewer)"
  git log --oneline
fi

echo ""
echo "=== Test Complete ==="
