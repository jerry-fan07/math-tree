# `content-quant-program/` — the quant tree's program (§6.6)

The authored curriculum over `content-quant/`: the **spine** (`program.yaml` —
the outline's §1–§58 order as parts and units) and the **lessons**
(`lessons/<unit-id>.yaml` — one teaching lesson per content node, one file per
unit). Compiled by `ContentBuild` into `build/quant/program.json` alongside the
graph:

```
swift run ContentBuild validate --content content-quant \
  --problems content-quant-problems --program content-quant-program \
  --out build/quant
```

The spine is validated as a linear extension of cross-unit `requires` — the
property that makes each unit a self-contained chapter — and a lessons file
that exists must teach its whole unit exactly. Corpus-wide lesson coverage is
*reported* by `validate` and grows batch by batch.

Authoring rules live in `style.md` here (lessons) and `content-quant/style.md`
(everything else, LaTeX above all). The author's pre-flight check is
`python3 Scripts/check-lesson-file.py <unit-id>`.

The app reads the compiled artifact in the Quant Interview Tree window: the
rail's **Program** section resumes at the bookmark, the reader teaches the
units in order, and any lesson is reachable at any time from the map via the
node panel's "Read the lesson".
