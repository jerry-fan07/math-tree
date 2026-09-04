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

## Coverage

Two units, 76 problems, 2 per node — every node with a `demanding` problem, so
every mastery set opens with one:

| Unit | Nodes | Problems |
|---|---|---|
| `quant-probability.foundations` | 18 | 36 |
| `quant-probability.expectation` | 20 | 40 |

The other 56 units are lesson-covered but bank-empty, and their lessons end on
self-report alone and say so. `ContentBuild validate` prints the corpus-wide
number on every run, so the gap stays visible rather than becoming a test
somebody weakened.

Placement readiness is *not* declared for these units. `problems/README.md`'s
manifest and `PlacementFixtureTests` cover the math tree; the quant tree has no
equivalent yet, and adding one is the natural next step now that the bank
exists.
