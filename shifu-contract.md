# Shifu evidence intake — the contract

**Status**: v1, frozen.
**Implements**: [design.md](design.md) §8.2, with the evidence model of §5.1 and the
inferred tier of §5.3.
**Audience**: whoever writes the producer. Nothing in this document requires reading any
other file in this repository.

design.md §8.2 says the integration is "a data contract, not a code dependency": Shifu owns
observation and inference-to-node mapping, this project owns the graph, scoring and display.
This file is the whole of what crosses. There is no library to link, no header to include and
no version of this project to build against — a producer that can write a JSON file and
rename it is a complete implementation.

---

## Transport: a watched drop-directory

```
~/Library/Application Support/MathTree/intake/
  ├── <name>.json        ← write documents here
  ├── accepted/          ← consumed, each with a <name>.receipt.txt
  └── rejected/          ← not consumed, each with a <name>.receipt.txt saying why
```

- **Write to `<name>.json.part`, then rename to `<name>.json`.** Only `*.json` directly in
  the root is read, and a drain that catches a half-written file will correctly reject it —
  losing the evidence for a reason that was nobody's fault. The rename is what makes the
  handoff atomic.
- **Names should sort in the order you want them read** (an ISO-8601 prefix works). Ordering
  affects only the report; the events carry their own timestamps and the scoring fold sorts
  by those.
- **The queue survives both processes.** A document dropped while the app is closed is
  consumed the next time it launches or is activated. That is the reason the transport is a
  directory rather than XPC or a socket: Shifu observes usage all day and the map is open for
  minutes of it, so a live channel would silently drop evidence exactly when the user is not
  looking.
- **Documents are consumed once.** A drain moves the file before appending, so re-reading is
  never attempted. If you want an observation counted twice, send it twice.

The directory can be relocated with the `MATHTREE_INTAKE` environment variable, which is what
the test harness does.

---

## The document

```json
{
  "schema": 1,
  "producer": "shifu/0.4.2",
  "events": [
    {
      "at": "2026-08-06T14:20:00Z",
      "nodes": ["analysis.svc.def-derivative", "analysis.svc.chain-rule"],
      "edges": ["analysis.mvc.leibniz-rule ~ analysis.svc.ftc-part-2"],
      "confidence": 0.45,
      "activity": "twenty minutes in a notebook differentiating composites"
    }
  ]
}
```

| field | required | meaning |
|---|---|---|
| `schema` | yes | Must be `1`. A document carrying any other number is rejected whole, unread. |
| `producer` | no | Free text, for the receipt. Not stored. |
| `events` | yes | An array of observations. May be empty. |

Each observation:

| field | required | meaning |
|---|---|---|
| `at` | yes | ISO-8601 UTC instant, with or without fractional seconds. |
| `nodes` | one of | Content node ids the observation is about. |
| `edges` | these two | `relates` edge keys, in the canonical `"a ~ b"` form (endpoints sorted). |
| `confidence` | yes | A number in `(0, 1]`. How strongly this observation says the user has the knowledge. |
| `activity` | no | Free text describing what was observed. Stored on the evidence event and shown in the audit trail. |

Node ids and edge keys are the ones in the compiled `graph.json` this build ships. They are
permanent: a node's statement can be rewritten freely, but its id never changes, so a producer
can hold ids indefinitely.

### There is no `source` field, and no `grade` field

Both are refused by design, and both are *ignored with a note* rather than treated as an
error, so an early producer sees the message instead of silently getting what it asked for.

- **The transport determines the source.** Everything arriving through this directory is
  stamped `source: shifu`. A document cannot promote itself to `test` — the evidence tiers
  would stop meaning anything if the least trustworthy channel could claim the most
  trustworthy label.
- **Shifu observes; it does not assess.** `confidence` is the only strength dial. Grades come
  from problems the user actually answered (§5.2); an observation says *whether* the user
  seems to have the knowledge, never how fluently.

---

## What an accepted observation does

One evidence event per named target, `source: shifu`, carrying your `confidence`.

- It counts as a **successful retrieval**, so the node becomes *learned* and stops being grey
  on the map (§4.5).
- `confidence` is the **weight**: it buys a fraction of the memory stability a passed problem
  would, and lower stability is steeper decay. That is §5.3's "inferred knowledge decays
  faster until confirmed by a direct test", with no second decay model — a later real review
  takes the full path and replaces it.
- It **never lowers** an existing score (§4.3). An observation at confidence 0.1 on a node the
  user has just aced does nothing.
- It **does not propagate to prerequisites.** §4.3's propagation is defined for a graded
  review, and §8.2 gives Shifu ownership of inference-to-node mapping: if watching someone
  apply the chain rule is also evidence about limits, Shifu is the component that knows that,
  and the contract already lets one observation name every node it exercised. Naming them is
  the supported way to say it.

---

## Rejection

Rejection is per-document for anything wrong with the envelope, and per-observation for
anything wrong inside one. **An observation is atomic**: if any id it names is unknown, the
whole observation is dropped rather than partially honoured, because an observation naming
three nodes is one claim about a moment of usage and keeping two of them changes what it says.
One bad observation never costs the good ones in the same document.

Every document — accepted or rejected — is filed with a `*.receipt.txt` beside it recording
what happened and every diagnostic, so a producer can debug without access to this process.

Document-level rejections:

| condition | receipt says |
|---|---|
| not JSON | `not JSON — <parser message>` |
| top level is not an object | `top level must be an object with schema and events` |
| `schema` missing or not an integer | `missing required field schema` / `schema must be an integer` |
| `schema` is not 1 | `schema N is not supported by this build` |
| `events` missing or not an array | `missing required field events` / `events must be an array` |

Observation-level rejections:

| condition | receipt says |
|---|---|
| not an object | `must be an object` |
| `at` missing or unparseable | `missing required field at` / `at is not an ISO-8601 UTC timestamp` |
| `confidence` missing, not a number, or outside `(0, 1]` | `confidence must lie in (0, 1]` |
| neither `nodes` nor `edges` names anything | `names no target` |
| a node id is not in this corpus | `no such node in this corpus: <id>` |
| a node id names a branch or subbranch | `<id> is a branch or subbranch` |
| an edge key is not a `relates` edge | `no such relates edge in this corpus: <key>` |

A boolean is not a number: `"confidence": true` is rejected rather than read as 1.0.

---

## Trying it without Shifu

`ContentBuild shifu-sim` is the test double — it drops documents exactly as a producer would
and drains them, sharing no code with the intake beyond this format:

```
swift run ContentBuild shifu-sim --intake /tmp/intake --log /tmp/evidence.jsonl
```

With no `--stream`, it replays the canned documents in [`fixtures/shifu/`](fixtures/shifu),
which include the rejection cases above. `Scripts/check-shifu-intake.sh` runs the whole path
and reads the resulting colours back out of the buffer the GPU drew from.

---

## Versioning

`schema` is the contract's version and changes only when a field's *meaning* changes. Adding
an optional field does not take a new number: unknown keys are ignored and reported, so a
producer may send more than this document describes without breaking. A consumer that sees a
number it does not know rejects the document whole rather than interpreting it under a guess —
which means a producer must not raise `schema` until the consumer it is talking to understands
the new number.
