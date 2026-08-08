#!/usr/bin/env bash
# Phase 10 exit criterion, end to end:
#
#   "simulated Shifu events flow through to visible score changes; malformed and
#    unknown-id events are rejected with diagnostics, never crash, never corrupt
#    the log."
#
# The unit tests cover the parser and the directory. What they cannot show is that
# an event Shifu dropped on disk reaches the rgba8 word the GPU drew from — so this
# does what Phase 6's determinism check does, and reads the colours back out of the
# instance buffer with `--probe` before and after an ingest.
#
# Both doors are exercised: `ContentBuild shifu-sim` (the CLI test double, which
# has no app in it) and the app's own launch-time drain (`MATHTREE_INTAKE`), because
# a working CLI would prove nothing about the thing the user actually runs.
#
# Deliberately not in CI, for the same reason as check-score-determinism.sh: it
# needs a Metal device.
#
# Usage: Scripts/check-shifu-intake.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/MathTree.app/Contents/MacOS/MathTree"
NOW="${MATHTREE_NOW:-2026-08-07T12:00:00Z}"

[ -x "$APP" ] || Scripts/bundle-app.sh
swift build --product ContentBuild >/dev/null
BIN="$(swift build --show-bin-path)/ContentBuild"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

probe() {
    MATHTREE_EVIDENCE_LOG="$1" MATHTREE_NOW="$NOW" "$APP" --probe |
        python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["scores"], indent=2, sort_keys=True))'
}

repainted() {
    python3 - "$1" "$2" <<'PY'
import json, sys
before, after = (json.load(open(p)) for p in sys.argv[1:3])
index = {n["id"]: n for n in before["nodes"]}
moved = [n for n in after["nodes"] if index[n["id"]]["packed"] != n["packed"]]
for node in moved:
    print(f'  {node["id"]}: {index[node["id"]]["ramp"]} -> {node["ramp"]}')
print(f'{len(moved)} node(s) repainted, '
      f'learned {before["learnedNodes"]} -> {after["learnedNodes"]}')
sys.exit(0 if moved else 1)
PY
}

events() { python3 -c 'import sys; print(sum(1 for line in open(sys.argv[1]) if line.strip()) - 1)' "$1"; }

# ---------------------------------------------------------------- 1. the CLI door
cp "$ROOT/fixtures/fixture-user.jsonl" "$WORK/cli.jsonl"
BEFORE_EVENTS="$(events "$WORK/cli.jsonl")"
probe "$WORK/cli.jsonl" > "$WORK/cli-before.json"

echo "== ContentBuild shifu-sim over the canned stream =="
"$BIN" shifu-sim --intake "$WORK/intake" --log "$WORK/cli.jsonl" --quiet
AFTER_EVENTS="$(events "$WORK/cli.jsonl")"
probe "$WORK/cli.jsonl" > "$WORK/cli-after.json"

echo
echo "evidence log: $BEFORE_EVENTS -> $AFTER_EVENTS events"
if ! repainted "$WORK/cli-before.json" "$WORK/cli-after.json"; then
    echo "FAIL: the ingest changed no colour — the criterion is 'visible score changes'" >&2
    exit 1
fi

# The rejection half. Three of the four canned documents are unusable in different
# ways; each must be filed under rejected/ with a receipt, and none of them may
# have contributed an event.
for doc in 002-partly-unusable 003-unsupported-schema 004-truncated; do
    case "$doc" in
        002-partly-unusable) want="accepted" ;;   # one good observation, six bad
        *)                   want="rejected" ;;
    esac
    if [ ! -f "$WORK/intake/$want/$doc.json" ]; then
        echo "FAIL: $doc.json was not filed under $want/" >&2
        exit 1
    fi
    if [ ! -f "$WORK/intake/$want/$doc.receipt.txt" ]; then
        echo "FAIL: $doc.json was filed with no receipt" >&2
        exit 1
    fi
done
echo
echo "-- diagnostics for the unusable documents --"
cat "$WORK/intake/rejected"/*.receipt.txt "$WORK/intake/accepted/002-partly-unusable.receipt.txt"

# Nothing from a rejected document may have reached the log. `def-limit` is the
# only node the two whole-document rejections name — and the fixture user has
# reviewed it themselves, so the test has to be "no *shifu* event mentions it",
# not "the string is absent". A grep for the bare id passes for the wrong reason.
if python3 - "$WORK/cli.jsonl" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    event = json.loads(line)
    if event.get("source") == "shifu" and "def-limit" in json.dumps(event.get("target", {})):
        sys.exit(0)
sys.exit(1)
PY
then
    echo "FAIL: an event from a rejected document reached the evidence log" >&2
    exit 1
fi

# …and every shifu event that *did* land carries a confidence and no grade of its
# own choosing, which is the contract's central claim (D10.2).
python3 - "$WORK/cli.jsonl" <<'PY'
import json, sys
shifu = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    event = json.loads(line)
    if event.get("source") == "shifu":
        shifu.append(event)
assert shifu, "no shifu events reached the log"
for event in shifu:
    assert event.get("confidence") is not None, f"shifu event with no confidence: {event}"
    assert event.get("grade") == 3, f"shifu event was not stamped with the neutral grade: {event}"
    assert "weight" not in event and "depth" not in event, f"shifu event was expanded: {event}"
print(f"{len(shifu)} shifu events, all confidence-weighted, neutrally graded, unexpanded")
PY

# ---------------------------------------------------------------- 2. the app door
cp "$ROOT/fixtures/fixture-user.jsonl" "$WORK/app.jsonl"
mkdir -p "$WORK/app-intake"
cp "$ROOT/fixtures/shifu/001-derivative-session.json" "$WORK/app-intake/"
probe "$WORK/app.jsonl" > "$WORK/app-before.json"

echo
echo "== the app's own launch-time drain =="
MATHTREE_INTAKE="$WORK/app-intake" MATHTREE_INTAKE_DRAIN=1 \
    MATHTREE_EVIDENCE_LOG="$WORK/app.jsonl" MATHTREE_NOW="$NOW" "$APP" --probe > /dev/null
probe "$WORK/app.jsonl" > "$WORK/app-after.json"

if [ ! -f "$WORK/app-intake/accepted/001-derivative-session.json" ]; then
    echo "FAIL: the app did not consume the document" >&2
    exit 1
fi
if ! repainted "$WORK/app-before.json" "$WORK/app-after.json"; then
    echo "FAIL: the app's drain changed no colour" >&2
    exit 1
fi

# A second launch must not re-ingest: the document is gone from the drop directory,
# so the log has to be identical.
BEFORE_SECOND="$(events "$WORK/app.jsonl")"
MATHTREE_INTAKE="$WORK/app-intake" MATHTREE_INTAKE_DRAIN=1 \
    MATHTREE_EVIDENCE_LOG="$WORK/app.jsonl" MATHTREE_NOW="$NOW" "$APP" --probe > /dev/null
if [ "$(events "$WORK/app.jsonl")" != "$BEFORE_SECOND" ]; then
    echo "FAIL: relaunching ingested the same document twice" >&2
    exit 1
fi

# And a read-only run without the override must leave a pending document alone —
# the guard D6.6 requires of every write path.
cp "$ROOT/fixtures/shifu/001-derivative-session.json" "$WORK/app-intake/"
MATHTREE_INTAKE="$WORK/app-intake" MATHTREE_EVIDENCE_LOG="$WORK/app.jsonl" \
    MATHTREE_NOW="$NOW" "$APP" --probe > /dev/null
if [ ! -f "$WORK/app-intake/001-derivative-session.json" ]; then
    echo "FAIL: a --probe run drained the intake without MATHTREE_INTAKE_DRAIN" >&2
    exit 1
fi

echo
echo "PASS: Shifu documents reach the buffer the GPU drew from, through both doors;"
echo "      unusable documents were filed with diagnostics and changed nothing."
