#!/usr/bin/env bash
# Build and launch MathTree.app against per-workspace state.
# Usage: Scripts/run-app.sh [debug|release] [-- app args...]   (default: debug)
#
# The app's evidence log, intake directory and placement file otherwise all live
# under ~/Library/Application Support/MathTree, which is shared by every checkout
# on the machine. Two Conductor workspaces running at once would interleave
# appends into one evidence.jsonl — corrupting the developer's real review
# history and destroying the replay determinism §6's exit criterion rests on. The
# three environment overrides exist for exactly this (D3.7: configuration reaches
# an AppKit process through the environment), so each workspace gets its own
# state under build/, which is gitignored and survives bundle-app.sh.
set -euo pipefail

CONFIG="debug"
if [ $# -gt 0 ] && [ "$1" != "--" ]; then
    CONFIG="$1"
    shift
fi
# Drop the separator rather than forwarding it: D3.7 — AppKit turns leftover
# argv tokens into NSUserDefaults, and a stray one has hung this app before.
if [ "${1:-}" = "--" ]; then
    shift
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STATE="$ROOT/build/state"
mkdir -p "$STATE/intake"
export MATHTREE_EVIDENCE_LOG="$STATE/evidence.jsonl"
export MATHTREE_INTAKE="$STATE/intake"
export MATHTREE_PLACEMENT="$STATE/placement.json"

Scripts/bundle-app.sh "$CONFIG"

echo "state: $STATE"
# Exec the binary inside the bundle rather than `open`: the app stays in the
# foreground so Conductor's stop button reaches it, and LaunchServices does not
# fold a second workspace's launch into the first one's running instance.
exec "$ROOT/build/MathTree.app/Contents/MacOS/MathTree" "$@"
