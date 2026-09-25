# `content-quant-problems/` — the quant tree's problem bank

design.md §5.2's evidence instrument, for the quant-interview corpus. Same
schema, same validator and same CI step as [`../problems/`](../problems/README.md),
which is normative for everything this file does not add — read it first.

## Why this exists now

Until Phase 13 the quant tree deliberately shipped **no** bank: `--problems
content-quant-problems` pointed at a directory that did not exist, the bank
loaded empty, and every review in the quant window fell back to self-report.
That was defensible while the tree was content plus a reader. §6.7 ends it: a
lesson now finishes on a **mastery set**, and a mastery set with nothing in it
is a lesson that ends by asking you how you feel.

So this bank is authored mastery-first, which changes two conventions:

- **Hardest first, not easiest first.** `ProblemBank.masterySet(for:)` takes the
  hardest problems targeting a node, the inverse of the probe ladder's order
  (D13.6). A node whose only problem is `routine` has a mastery set that tests
  nothing the lesson has not just handed over, so **every targeted node carries
  at least one `demanding` problem**.
- **Typed answers wherever the answer is a number.** §5.2's "math free response
  cannot be machine-graded" is scoped rather than repealed (D13.3): the *final
  value* of a quant problem is usually a number, and a number can be checked. A
  problem that ends in one carries `expects:`, and the app grades it before the
  reveal; the rubric stays, because the reveal is still where the reasoning is
  read. A `justify` problem still self-grades — a proof is not a number.

## The added fields

```yaml
- id: qfnd-complement-01
  kind: work
  difficulty: demanding
  statement: >
    ...
  answer: >
    ...
  expects: "0.3"          # quoted: the loader wants a string, and 1 would decode as an int
  tolerance: 0.0005       # absolute; omit for an exact match
  rubric:
    - >
      ...
  targets: [...]
  exercises: [...]
```

- **`expects` is always quoted.** It is a `String` in the schema — an unquoted
  `expects: 1` decodes as an integer and fails the build with a type mismatch.
- **`expects` never contains LaTeX.** Write `7/15`, not `\frac{7}{15}`: the
  parser reads both, but the value is also *displayed* on a wrong answer, and
  the plain form is what a reader would have typed.
- **`tolerance` is absolute and optional.** Omit it and the match is effectively
  exact, which is right for a fraction or a short decimal. State it whenever the
  honest answer is rounded — `0.4914` needs `tolerance: 0.0005`, or a reader who
  answered correctly is told they did not.
- **`choices`** is the alternative for a `decide` problem whose answer is not a
  number. Exactly one row carries `correct: true`.
- **`feedback`** is optional; the worked `answer` is used when it is absent,
  which is usually what you want here.

## The bar, and the author's check

Every content node of a unit carries **at least two** problems, at least one
`demanding` (so the mastery set opens with one) and at least one `standard` or
`routine` (so the unit test has something fair to ask). Every `work` and
`decide` problem is machine-checked — `expects` where the answer is a number,
`choices` otherwise; only `justify` self-grades. The worked `answer` shows the
computation that produces `expects`, because the reveal is the teaching
surface and the reviewer's check on the author. Landmark nodes (prominence 2)
carry three.

The author's pre-flight check mirrors `ProblemValidator`, the check faults and
this coverage bar with nothing but python3 (D12.7):

```
python3 Scripts/check-problem-file.py <unit-id>
```

File layout mirrors the lessons: `content-quant-problems/<branch>/<subbranch>.yaml`
holds the problems whose primary target lives in that unit. Ids are
`<unit-tail-abbreviation>-<node-slug>-<nn>` (`qfnd-complement-01`), permanent.

## Coverage

Every one of the 58 units meets the bar (Phase 15): 2,278 problems over all
958 content nodes, each node with a `demanding` problem and a fair one, every
`work`/`decide` problem machine-checked. By part — probability 13 units,
tools 4, processes 8, statistics 8, finance 7, games 6, mental 4, programming
4, puzzles 4 — with a file per unit under the branch directory. `ContentBuild
validate` prints the corpus-wide number on every run, and the per-unit
pre-flight check is the author's gate.

Placement readiness is *not* declared per unit for the quant tree.
`problems/README.md`'s manifest and `PlacementFixtureTests` cover the math
tree; the quant tree's placement is served by the same bank without a
manifest, because the bank is complete by construction once every unit file
passes the pre-flight check.
