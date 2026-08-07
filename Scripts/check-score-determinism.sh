#!/usr/bin/env bash
# Phase 6 exit criterion: relaunching the app reproduces identical colours.
#
# Launches the real app twice against the same evidence log with the clock pinned
# and diffs the probe's score read-out — which reports the rgba8 words read back
# out of the buffer the GPU drew from, not a recomputation. Then launches it once
# against the fixture-with-one-more-review log and requires the output to *differ*,
# because a check that cannot fail proves nothing.
#
# Deliberately not in CI: it needs a Metal device, and the existing smoke test
# passes even when the renderer fails to come up, so a green CI run would not mean
# what this script means. Run it locally.
#
# Usage: Scripts/check-score-determinism.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/MathTree.app/Contents/MacOS/MathTree"
NOW="${MATHTREE_NOW:-2026-08-07T12:00:00Z}"
BEFORE="$ROOT/fixtures/fixture-user.jsonl"
AFTER="$ROOT/fixtures/fixture-user-reviewed.jsonl"

[ -x "$APP" ] || Scripts/bundle-app.sh

probe() {
    MATHTREE_EVIDENCE_LOG="$1" MATHTREE_NOW="$NOW" "$APP" --probe |
        python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["scores"], indent=2, sort_keys=True))'
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

probe "$BEFORE" > "$WORK/run1.json"
probe "$BEFORE" > "$WORK/run2.json"
probe "$AFTER"  > "$WORK/reviewed.json"

if ! diff -u "$WORK/run1.json" "$WORK/run2.json" > "$WORK/relaunch.diff"; then
    echo "FAIL: two launches over the same log produced different colours" >&2
    head -40 "$WORK/relaunch.diff" >&2
    exit 1
fi

if diff -q "$WORK/run1.json" "$WORK/reviewed.json" > /dev/null; then
    echo "FAIL: one more self-report changed nothing — the check is vacuous" >&2
    exit 1
fi

changed=$(python3 - "$WORK/run1.json" "$WORK/reviewed.json" <<'PY'
import json, sys
before, after = (json.load(open(p)) for p in sys.argv[1:3])
index = {n["id"]: n for n in before["nodes"]}
moved = [n["id"] for n in after["nodes"] if index[n["id"]]["packed"] != n["packed"]]
print(f'{len(moved)} nodes repainted by one self-report:')
for node in moved:
    print(f'  {node}: {index[node]["ramp"]} -> {[n for n in after["nodes"] if n["id"] == node][0]["ramp"]}')
print(f'frontier {before["frontierCount"]} -> {after["frontierCount"]}, '
      f'learned {before["learnedNodes"]} -> {after["learnedNodes"]}')
PY
)

nodes=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["nodes"]))' "$WORK/run1.json")
echo "PASS: two launches painted all $nodes nodes identically (clock pinned at $NOW)"
echo "$changed"
