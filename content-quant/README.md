# `content-quant/` — the quant-interview knowledge tree

A second authored corpus beside `content/`: everything needed for a
quantitative-trading interview — concepts, problem-solving techniques, and the
canonical problems themselves — as one prerequisite graph. Same schema, same
validators, same pipeline as the math tree (`design.md` §2–§3,
`content/README.md`); this file records only what differs.

## Separate tree, separate everything

- **Own artifact root.** Compiled to `build/quant` (never `build/content`):

  ```
  swift run ContentBuild validate --content content-quant --problems content-quant-problems --out build/quant
  swift run ContentBuild build    --content content-quant --problems content-quant-problems --out build/quant
  swift run ContentBuild layout   --content content-quant --problems content-quant-problems --out build/quant
  ```

  `content-quant-problems` does not exist on disk; naming it keeps the math
  problem bank from being validated against this graph, and the loader treats a
  missing directory as an empty bank (the app then reviews by self-report).
- **Own window.** The app shows this tree in the "Quant Interview Tree" window
  (Window menu, or ⌘2), loading `Resources/quant` / `build/quant` via
  `TreeSpec.quant`. Its user state is `evidence-quant.jsonl` and
  `placement-quant.json` — ids may collide across trees (both trees could own a
  `probability` branch), so the logs must never be shared.
- **No cross-tree edges.** `requires`/`relates` may only name ids in this
  corpus. The math tree does not exist from here.

## Branch ids

Branches are prefixed `quant-` (`quant-probability`, `quant-finance`, …) so the
id spaces of the two trees stay disjoint even where the subjects overlap —
defence in depth for any state or intake that ever crosses trees.

## The canonical outline

The 9-branch / 58-subbranch skeleton, the per-subbranch topic lists, the fixed
authoring order, and the **spine** contract (which node ids other subbranches
may reference) live in `content-quant/outline.md`, with the compressed
authoring rules in `content-quant/style.md`. A subbranch file may reference
spine ids only of subbranches earlier in the outline order — that ordering is
what makes cross-file `requires` acyclic by construction.

## Content bar

Beyond the math tree's checklist (`content/README.md`), nodes here must be
useful under interview pressure: exact hypotheses, worked examples that end in
the actual number, and the canonical interview phrasing named where one exists
("make me a market on X"). Techniques are first-class nodes; classic problems
are `example` nodes whose solution idea is the knowledge.
