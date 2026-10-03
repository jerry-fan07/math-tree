# Latin Modern — the lessons' face

Computer Modern is what a LaTeX document on Overleaf sets in by default, text and
maths alike; Latin Modern is its OpenType release by GUST e-foundry. The app
registers these files for its own process at launch (`Typeface.reading…`) and uses
them for lesson prose and every `$…$` span.

| file | role |
|---|---|
| `lmroman10-regular.otf`, `-italic`, `-bold`, `-bolditalic` | Latin Modern Roman 10 — prose and maths letters (`cmr10`, `cmti10`) |
| `latinmodern-math.otf` | Latin Modern Math — the symbols the text face lacks (`∑ ∫ ≤ ≈ ∈`) and italic Greek (`cmmi10`) |

Downloaded unmodified from CTAN (`fonts/lm/fonts/opentype/public/lm/`,
`fonts/lm-math/opentype/`). Licensed under the GUST Font License
(`GUST-FONT-LICENSE.txt`), which permits redistribution.
