#!/usr/bin/env bash
# Guard for the Phase 2 exit criterion: "CI fails on a deliberately broken
# content file." Seeds one violation at a time into a copy of content/ and
# asserts `ContentBuild validate` exits non-zero for each.
#
# This tests the *gate*, not the validator — GraphCore's own tests cover the
# rules. What can silently rot is the wiring: a swallowed exit code makes CI
# green on broken content, which is worse than no check at all.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build --product ContentBuild >/dev/null || exit 1
BIN="$(swift build --show-bin-path)/ContentBuild"

failures=0

expect_rejected() {
    local label="$1" yaml="$2"
    local tmp
    tmp="$(mktemp -d)"
    cp -R content/. "$tmp/"
    printf '%s\n' "$yaml" > "$tmp/broken.yaml"

    local output status
    output="$("$BIN" validate --content "$tmp" 2>&1)"
    status=$?
    rm -rf "$tmp"

    if [ "$status" -eq 0 ]; then
        echo "FAIL: $label — validator accepted broken content (exit 0)"
        failures=$((failures + 1))
    else
        echo "ok:   $label — rejected (exit $status): $(printf '%s' "$output" | grep -o '\[[a-z-]*\]' | sort -u | tr '\n' ' ')"
    fi
}

expect_rejected "dangling requires" 'nodes:
  - id: analysis.svc.broken-dangling
    kind: lemma
    prominence: 0
    title: "Broken"
    statement: "x"
    parent: analysis.svc
    requires:
      - analysis.svc.no-such-node'

expect_rejected "requires cycle" 'nodes:
  - id: analysis.svc.broken-cycle-a
    kind: lemma
    prominence: 0
    title: "Cycle A"
    statement: "x"
    parent: analysis.svc
    requires:
      - analysis.svc.broken-cycle-b
  - id: analysis.svc.broken-cycle-b
    kind: lemma
    prominence: 0
    title: "Cycle B"
    statement: "x"
    parent: analysis.svc
    requires:
      - analysis.svc.broken-cycle-a'

# def-limit is already an ancestor of ftc-part-2 by every path (§2.3).
expect_rejected "transitive-redundant requires" 'nodes:
  - id: analysis.svc.broken-redundant
    kind: lemma
    prominence: 0
    title: "Redundant"
    statement: "x"
    parent: analysis.svc
    requires:
      - analysis.svc.ftc-part-2
      - analysis.svc.def-limit'

expect_rejected "duplicate id" 'nodes:
  - id: analysis.svc.mvt
    kind: theorem
    prominence: 1
    title: "Mean Value Theorem (duplicate)"
    statement: "x"
    parent: analysis.svc'

expect_rejected "malformed id" 'nodes:
  - id: analysis.svc.Broken_ID
    kind: lemma
    prominence: 0
    title: "Bad id"
    statement: "x"
    parent: analysis.svc'

expect_rejected "structural node with requires" 'nodes:
  - id: analysis.broken
    kind: subbranch
    title: "Structural with prerequisites"
    parent: analysis
    requires:
      - analysis.svc.mvt'

if [ "$failures" -ne 0 ]; then
    echo
    echo "$failures broken-content case(s) were NOT rejected"
    exit 1
fi

echo
echo "all broken-content cases rejected; clean content still passes:"
"$BIN" validate || exit 1
