# `program/` — the math tree's program (§6.6, §6.7)

The authored curriculum over `content/`: the **spine** (`program.yaml` — the
canonical outline's 82 subbranches as units, in teaching order, grouped into a
part per branch) and the **lessons** (`lessons/<unit-id>.yaml` — one teaching
lesson per content node, one file per authored unit, every lesson carrying
`steps` so it plays as a checked sequence of cards). Compiled by
`ContentBuild` into `build/content/program.json` alongside the graph:

```
swift run ContentBuild validate     # defaults: content/, problems/, program/
```

The spine is validated as a linear extension of cross-unit `requires`, with
the exceptions the math corpus forces declared under `forward:` and held exact
(D15.2): an undeclared forward edge fails the build, and so does a declaration
that is no longer forward. A lessons file that exists must teach its whole unit
exactly. Corpus-wide lesson and card coverage is *reported* by `validate`.

Authoring rules live in `style.md` here (lessons and cards — the quant guide
adapted to a mathematics course) and `content/README.md` (nodes). The author's
pre-flight check is `python3 Scripts/check-lesson-file.py <unit-id>`.

The app reads the compiled artifact in the Knowledge Tree window as the
**course**: a course home with a continue action and per-unit mastery, a unit
page listing its skills in teaching order, the lesson player, and a unit test
drawn from `problems/`. 67 of the 82 units are outlined but not yet authored
(`content/README.md` tracks which); the course states that per part rather
than listing empty chapters.

## Drafts

A lessons file cut off mid-write belongs in `drafts/`, not `lessons/`: the
loader reads only `lessons/`, so a draft never reaches the build, while a
partial file left in `lessons/` fails validation for the lessons it lacks.
To resume one, move it back into `lessons/` and run `check-lesson-file.py` —
its missing-lesson list is the remaining work. The convention was used during
the Phase 15 campaign (D15.7); every draft has since been finished, so the
directory is empty and untracked.
