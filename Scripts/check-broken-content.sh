#!/usr/bin/env bash
# Guard for the Phase 2 exit criterion: "CI fails on a deliberately broken
# content file." Seeds one violation at a time into a copy of content/ and
# asserts `ContentBuild validate` exits non-zero for each. Phase 8 extends it
# over problems/ — the bank is content, validated by the same CI step, so it
# needs the same proof that the step is actually wired up.
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

# --- problem bank (§5.2) ----------------------------------------------------
#
# Same shape, seeded into a copy of problems/ against the *real* content, since
# every bank invariant is a fact about the pair.

expect_problem_rejected() {
    local label="$1" yaml="$2"
    local tmp
    tmp="$(mktemp -d)"
    cp -R problems/. "$tmp/"
    printf '%s\n' "$yaml" > "$tmp/broken.yaml"

    local output status
    output="$("$BIN" validate --problems "$tmp" 2>&1)"
    status=$?
    rm -rf "$tmp"

    if [ "$status" -eq 0 ]; then
        echo "FAIL: $label — validator accepted a broken problem (exit 0)"
        failures=$((failures + 1))
    else
        echo "ok:   $label — rejected (exit $status): $(printf '%s' "$output" | grep -o '\[[a-z-]*\]' | sort -u | tr '\n' ' ')"
    fi
}

expect_problem_rejected "dangling problem target" 'problems:
  - id: broken-dangling-target
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc.no-such-node'

expect_problem_rejected "structural problem target" 'problems:
  - id: broken-structural-target
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc'

expect_problem_rejected "duplicate problem id" 'problems:
  - id: svc-mvt-01
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc.mvt'

expect_problem_rejected "malformed problem id" 'problems:
  - id: Broken_Problem_ID
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc.mvt'

expect_problem_rejected "missing rubric" 'problems:
  - id: broken-no-rubric
    kind: work
    statement: "x"
    answer: "y"
    targets:
      - analysis.svc.mvt'

expect_problem_rejected "no targets" 'problems:
  - id: broken-no-targets
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets: []'

# u-sub is a *dependent* of mvt, not a prerequisite of it — the tag is backwards.
expect_problem_rejected "exercises a non-prerequisite" 'problems:
  - id: broken-exercises-descendant
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc.mvt
    exercises:
      - analysis.svc.u-sub'

expect_problem_rejected "target also exercised" 'problems:
  - id: broken-target-also-exercised
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc.mvt
    exercises:
      - analysis.svc.mvt'

expect_problem_rejected "connects a non-edge" 'problems:
  - id: broken-connects-nonedge
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc.mvt
    connects:
      - "analysis.svc.mvt ~ analysis.svc.u-sub"'

expect_problem_rejected "connects an untagged endpoint" 'problems:
  - id: broken-connects-untagged
    kind: work
    statement: "x"
    answer: "y"
    rubric: ["z"]
    targets:
      - analysis.svc.ftc-part-2
    connects:
      - "analysis.mvc.leibniz-rule ~ analysis.svc.ftc-part-2"'

if [ "$failures" -ne 0 ]; then
    echo
    echo "$failures broken-content case(s) were NOT rejected"
    exit 1
fi

echo
echo "all broken-content cases rejected; clean content still passes:"
"$BIN" validate || exit 1
