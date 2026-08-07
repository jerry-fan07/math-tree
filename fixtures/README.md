# `fixtures/` — the fixture user

An evidence log (§3.2) for a made-up user of the seed content, used wherever a
*reproducible* knowledge state is needed: Phase 6's frontier and propagation
tests, the score snapshots, and the determinism check.

| file | what it is |
|---|---|
| `fixture-user.jsonl` | the fixture user's history |
| `fixture-user-reviewed.jsonl` | the same history plus one self-report on `analysis.svc.ftc-part-2` |

The pair exists so propagation can be *seen*: the second log differs from the
first by one explicit review and the nine implicit reviews it induced (§4.3), so
diffing two renders of them shows exactly what one report changes.

## These are generated, not hand-edited

Propagation is a write-time expansion (see the Phase 5 decision log, D5.5): a log
must *contain* the implicit events it induced, and hand-typing those would encode
a human's arithmetic rather than `Propagation`'s. So the explicit reviews are
authored in `Tests/ContentBuildTests/FixtureUser.swift` and these files are a
golden copy of what `EvidenceLog` writes from them. `FixtureUserTests` fails when
they drift; regenerate with:

```
MATHTREE_UPDATE_FIXTURES=1 swift test
```

They are committed rather than generated on demand because the app reads them
directly, and a fixture the app can only get by running a test is not a fixture
the app can be launched against.

## Running the app against one

```
MATHTREE_EVIDENCE_LOG=$PWD/fixtures/fixture-user.jsonl \
MATHTREE_NOW=2026-08-07T12:00:00Z \
build/MathTree.app/Contents/MacOS/MathTree
```

`MATHTREE_NOW` matters: retrievability decays continuously (§4.1), so without a
pinned clock the same log renders differently every day — which is correct
behaviour and useless for comparison. `2026-08-07T12:00:00Z` is the instant the
fixture's assertions are written against (`FixtureUser.now`).

Runs that pass `--probe`, `--smoke-test`, or set `MATHTREE_SNAPSHOT` /
`MATHTREE_PANEL_SHOT` are read-only: they never append, so a verification run
cannot alter the fixture it is measuring — or the developer's own history in
Application Support. Phase 8's placement session obeys the same rule, and
`MATHTREE_PLACEMENT` redirects it the way `MATHTREE_EVIDENCE_LOG` redirects the
log:

```
MATHTREE_EVIDENCE_LOG=/tmp/mine.jsonl \
MATHTREE_PLACEMENT=/tmp/mine-placement.json \
build/MathTree.app/Contents/MacOS/MathTree
```

## Phase 8's fixture is code, not a file

The placement personas (`Tests/ContentBuildTests/PlacementFixtureTests.swift`)
are written as knowledge *sets* and drive the real `Placement` engine, so there
is no golden log to keep in step — the probes a persona answers depend on the
policy, and freezing them would freeze the policy. What is pinned instead is the
conclusion: the boundary, and the probe count that reaches it.
