# `content/` — authored knowledge graph

Source of truth for the graph. Hand-authored YAML, reviewed like code; the
compiled `graph.json` + layout are build artifacts produced from these files by
`ContentBuild` and are never edited directly. Schema and invariants live in
[../design.md](../design.md) §2–§3; this file records only the file-layout
conventions that the spec leaves open.

## File layout

```
content/
  <branch>/
    _branch.yaml        # the `branch` node itself, alone in this file
    <subbranch>.yaml    # the `subbranch` node + all content nodes under it
```

- `content/<branch>/<subbranch>.yaml` is design.md §3.3's layout. The file stem
  is the subbranch's last id component, so `content/analysis/svc.yaml` holds
  `analysis.svc` and its `analysis.svc.*` children.
- **Branch nodes live in `_branch.yaml`** in their branch directory. The leading
  underscore cannot occur in an id component (`[a-z0-9]+(-[a-z0-9]+)*`), so this
  filename can never collide with a subbranch file. The alternative — declaring
  the branch node inside its "first" subbranch file — was rejected because it
  gives one arbitrary subbranch file a special shape.
- **Every file has the same top-level shape: a single `nodes:` list.** No file
  is special-cased by the parser; a build is the concatenation of the `nodes`
  lists of all `content/**/*.yaml`. Directory and file names are organizational
  only — ids are authoritative, and edges may cross files freely.

## Node shape

Fields and their meaning are design.md §3.1. Conventions used here:

- Field order is fixed for reviewable diffs:
  `id, kind, prominence, title, statement, summary, parent, also_under,
  requires, relates, tags`.
- **Content nodes** carry every field. Empty list fields are written explicitly
  (`also_under: []`, `requires: []`, `relates: []`, `tags: []`) rather than
  omitted, so a node's shape is uniform and a missing field reads as an
  authoring mistake.
- **Structural nodes** (`branch`, `subbranch`) use the same schema *minus*
  `statement`, `requires` and `relates` (§3.1). They also omit `prominence`:
  structural nodes are implicitly maximal prominence for display (§2.1). They do
  carry `summary` — it is what the UI shows for a hub.
- **`parent` is omitted on `branch` nodes only** (a branch is a root of the
  taxonomy); every other node has exactly one `parent`, its primary
  `contains` parent. Secondary parents go in `also_under`.
- `statement` and `summary` use folded block scalars (`>`). LaTeX goes inline as
  `$...$`. Keep continuation lines at a uniform indent — a deeper-indented line
  inside a folded scalar is taken literally and stops folding. Never
  double-quote a string containing LaTeX (backslashes become escapes); use a
  block scalar, or single quotes for short strings.

## Authoring checklist

Mechanical checks (unique ids, id format, dangling references, `requires`
acyclicity, transitive redundancy, one primary parent, structural-node shape)
are the validator's job — `ContentBuild validate`, run in CI. What a human
reviewer owns:

1. **Atomicity (§2.2).** Would any consumer of this node need only *part* of it?
   If so, split the node. Never weaken an edge to fit an oversized node.
2. **Edge direction.** `requires` is authored on the *destination* — the node
   that needs the prerequisite — and lists that node's prerequisites. An
   inverted edge validates cleanly and is wrong; wrong edges are worse than
   missing nodes (§7.1).
3. **Direct prerequisites only (§2.3).** If a candidate prerequisite is already
   reachable through another prerequisite, drop it. Ancestor sets are computed,
   not authored.
4. **Kind and prominence.** `theorem` covers statement and understanding; if a
   proof is substantial knowledge in its own right it becomes a separate
   `lemma`/`technique`/`example` node that `requires` the statement (§2.2).
   Prominence is display weight (`2` = landmark), not importance-as-semantics.
5. **Mathematical correctness of `statement`**, hypotheses included. Half the
   named theorems here fail without "closed bounded interval" or the
   open-interval differentiability hypothesis; state them.
6. **`relates` edges carry a real `note`** — the connection is itself knowledge
   that gets scored (§2.3, §4.4), so the note must say what the connection *is*.

## Current contents

Seed content: design.md Appendix A, encoded whole (27 nodes — 2 branches,
3 subbranches, 22 content nodes). `analysis/mvc.yaml` exists only to give the
Appendix A `relates` edge a real cross-file endpoint and is intentionally
two nodes deep, not a multivariable curriculum.
