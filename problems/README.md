# `problems/` — the authored problem bank

design.md §5.2's evidence instrument. Hand-authored YAML, reviewed like content
and gated by the same CI step (`ContentBuild validate`); the compiled
`problems.json` is a build artifact produced from these files and is never edited
directly. Schema and semantics live in [../design.md](../design.md) §5.2–§5.4;
this file records only the conventions the spec leaves open.

## Why this exists

Phase 6 shipped self-report ("I know this", with a confidence grade) as a
*placeholder* instrument. §5.4 wants review to happen "via problems, not
flashcard-style restatement, whenever possible", and §5.3's placement cannot work
at all without something to probe with. Self-report is not deleted — it remains
the fallback for a node the bank cannot ask about — but problems are the primary
instrument from here.

## File layout

```
problems/
  <branch>/
    <subbranch>.yaml     # problems whose targets live under that subbranch
```

Mirrors `content/`, and for the same reason: reviewable diffs and an obvious
place to look. Nothing in the loader depends on it — a build is the
concatenation of the `problems:` lists of all `problems/**/*.yaml`, ids are
authoritative, and a problem may target nodes in any file. Directory placement
follows the *primary* target.

`problems/` is optional. A corpus with no bank still builds, validates and runs;
the app falls back to self-report.

## Problem shape

```yaml
- id: svc-mvt-02             # permanent, globally unique, lowercase-kebab
  kind: justify              # work | decide | justify
  difficulty: demanding      # routine | standard | demanding
  statement: >               # the prompt, LaTeX inline as $...$
    Use the Mean Value Theorem to prove that ...
  answer: >                  # the worked answer, revealed after an attempt
    If $x = y$ both sides are $0$. Otherwise ...
  rubric:                    # what a correct solution must contain; required
    - >
      Applies the MVT on the interval with endpoints $x$ and $y$, without
      assuming $x < y$.
  targets:                   # what the problem primarily tests; at least one
    - analysis.svc.mvt
  exercises:                 # prerequisites it necessarily drills in passing
    - analysis.svc.rolle
  connects: []               # `relates` edge keys the problem works both ends of
  tags: []
```

- **Ids are permanent**, exactly like node ids: renaming a statement is free,
  changing an id orphans the evidence that references it. The convention is
  `<subbranch-tail>-<node-slug>-<nn>`; ids are a single kebab component, so no
  dots.
- **`kind` is about what the sheet shows**, not about machine grading. Math free
  response cannot be auto-checked, so the solver grades themselves against
  `answer` + `rubric`; `decide` exists for prompts short enough that
  self-deception is hard.
- **`difficulty` is a property of the problem**, and never enters the memory
  model — FSRS fits its own per-node difficulty from grades. This one only orders
  a probe ladder (easiest first).
- **`targets` and `exercises` are not interchangeable.** A target receives the
  graded review; an exercised node receives a *full-strength* implicit review
  "regardless of graph distance" (§4.3). Damped γᵈ propagation to the rest of the
  ancestry happens on top of both — the tags only say which nodes skip the
  damping. A node cannot be both.
- **The bank is indexed by `targets` only.** A problem that merely drills
  `def-limit` in passing is not a test *of* `def-limit`; probing it there would
  attribute a failure to the wrong node, which is what §5.4's diagnosis exists to
  prevent.
- **`connects`** carries canonical `"a ~ b"` edge keys. §4.4 says an edge review
  happens when a problem explicitly exercises the connection, so this is the only
  writer of edge evidence in the system. The problem must target or exercise both
  endpoints.

Same YAML rules as content: block scalars (`>`) for anything with LaTeX, never
double quotes around a string containing backslashes, uniform continuation
indent.

## Authoring checklist

Mechanical checks — unique and well-formed ids, no dangling or structural
targets, `exercises` really being prerequisites, targets not also exercised,
`connects` naming real edges with both ends tagged, non-empty statement, answer
and rubric — are the validator's job, run in CI and exercised by
`Scripts/check-broken-content.sh`. What a human reviewer owns:

1. **Mathematical correctness of `answer`, hypotheses included.** The same bar as
   content §5. Half the interesting problems here are *about* a hypothesis; an
   answer that quietly drops one teaches the wrong thing.
2. **Does the problem actually test the target?** A problem tagged
   `targets: [mvt]` that can be answered by quoting the statement tests recall of
   the statement, not the theorem. If the target is a definition, testing recall
   is fine and expected; if it is a theorem or technique, the problem should need
   it.
3. **Are `exercises` genuinely drilled?** The tag emits full-strength evidence.
   Tag what solving the problem *forces* the solver through, not everything
   nearby. Over-tagging inflates scores across the map.
4. **Is the rubric gradeable?** The solver grades themselves. Each criterion
   should be something a person can check yes/no against their own written
   solution. "Understands the MVT" is not a criterion; "applies it without
   assuming $x < y$" is.
5. **Does the answer explain, or only assert?** The answer is read after a failed
   attempt, so it is the teaching surface. It should say *why*, not just what.
6. **LaTeX renders.** The panel is LaTeX-lite (implementation-plan D4.9): inline
   `$...$`, super/subscripts, fractions, and a wide macro table, but no stacked
   notation. Nothing here needs a matrix or a continued fraction. `\underline`
   over a large operator is known not to render (D4.10) — avoid it.

## Coverage

Every content node in the corpus is targeted by at least one problem, asserted by
`ProblemBankFixtureTests.everyContentNodeHasAProblem`. That is not decoration:
§5.3's placement can only *resolve* a node it can ask about, and an unprobeable
node is settled by inference or not at all.

Landmark and high-traffic nodes carry two, so a session that spends a problem on
one node can still probe it again later.

## Current contents

32 problems over the 22 content nodes of the seed corpus (design.md Appendix A —
which *is* the single-variable-calculus content; the M2 authoring track never ran
separately, see the Phase 8 decision log). `mvc-leibniz-01` is the bank's one
`connects` problem, and the only thing in the system that can score a `relates`
edge.
