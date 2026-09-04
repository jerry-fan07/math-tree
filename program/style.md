# Math program — lesson authoring guide (read fully before writing any lesson)

You are authoring one lessons file of `program/`, the teaching layer (§6.6,
§6.7) over the math tree in `content/`. The corpus's node files say *what to
know*; your file says *how to come to know it*, in the style of a Khan Academy
course: build the idea from what the reader already holds, make it concrete
before making it precise, compute an example to the end, ask the reader to do
something every few beats, and name the trap. The app shows, for each step, the
node's title, its full `statement`, and then your lesson — so a lesson that
restates the statement says nothing. Teach.

This guide is `content-quant-program/style.md` adapted to a mathematics course.
Where the two disagree, this one governs `program/`.

## File shape

- Path: `program/lessons/<unit-id>.yaml`, where `<unit-id>` is the subbranch id
  (e.g. `foundations.logic`, `analysis.svc`).
- Top level:

  ```yaml
  unit: foundations.logic
  opening: >
    Three to five sentences that open the chapter: what this unit is for, the
    arc of its steps, and what the reader will be able to do at the end.
  lessons:
    - node: foundations.logic.def-proposition
      hook: >
        ...
      explanation: >
        ...
      worked: >
        ...
      pitfalls: >
        ...
      recap: >
        ...
      steps:
        - teach: >
            ...
  ```

- **One lesson per content node of the unit** — every node in
  `content/<branch>/<subbranch>.yaml` whose `parent` is the unit, no more, no
  fewer. The validator rejects a file that misses one, invents one, or teaches
  a node that lives elsewhere.
- Field order is fixed: `node, hook, explanation, worked, pitfalls, recap,
  steps`. **Do not write `interview`** — that section is the quant tree's; the
  reader labels it "In the interview", which is wrong here. Omit an optional
  section entirely rather than leaving it empty.
- Every section is a folded block scalar (`>`) with a **uniform 2-space
  continuation indent**. A blank line inside `explanation` becomes a paragraph
  break in the reader — use 2–5 paragraphs. Never double-quote a string
  containing LaTeX.

## The sections

Required: `hook`, `explanation`, `recap`, and — for this corpus — `steps`.
Optional: `worked`, `pitfalls`; include each wherever it can be filled
*honestly* (for a theorem, technique, example or proposition, `worked` is all
but mandatory; for an `intuition` or `axiom` node it is often filler).

- **hook** (1–2 sentences): why this node earns a step — what it unlocks, where
  it is used, what goes wrong without it. Not a summary; a reason to care.
- **explanation** (2–5 paragraphs, 700–1800 characters): the actual teaching.
  Start from the node's prerequisites and *build*: motivate the definition
  with the problem it solves, or derive the result — a proof *sketch* with the
  load-bearing step shown beats a citation. Give the mental model that makes it
  obvious, and the general pattern later theorems will reuse. Assume the reader
  holds the node's `requires` (and everything those require) and **nothing
  else** — never lean on a node taught later in the unit or in a later unit.
- **worked** (one example, computed to the end): a *different* instance from
  any the statement already works. For a definition, an object checked against
  the definition clause by clause; for a theorem, the theorem applied to a
  concrete case and the answer reached; for a technique, one problem solved
  with it start to finish. End in the actual object or number.
- **pitfalls** (1–3 concrete traps): the hypothesis people drop, the
  quantifier order that flips, the edge case (empty set, $n = 0$, the constant
  function) that voids the claim. Concrete, not "be careful".
- **recap** (one sentence): the one breath to retain.

Target 1,800–3,500 characters per lesson across the prose sections; the linter
flags explanations under 400 and lessons over 6,000.

## `steps` — the lesson as cards (§6.7), required here

A lesson plays as an ordered list of cards, one per screen. This corpus ships
every lesson with authored `steps`: 6–9 cards, at least two of them checks
(three where the node computes anything).

```yaml
      steps:
        - teach: >
            One beat — a single idea, two or three sentences, reading size.
        - ask: >
            A question with a numeric answer.
          expects: "12"
          hint: >
            Offered on request, before the answer. Never shown unasked.
          feedback: >
            Why that is the answer, with the computation shown.
        - ask: >
            A question whose answer is a judgement, a choice of object, or a
            formula — anything that is not a single number.
          choices:
            - text: >
                A wrong option worth naming.
              feedback: >
                The specific mistake this option corresponds to.
            - text: >
                The right one.
              correct: true
              feedback: >
                Why it is right.
          feedback: >
            The canonical explanation, shown whatever was picked.
```

- **The arc.** Motivate (one card) → define or state precisely (one) → a first
  concrete instance (one) → a check on that instance → the general pattern or
  the load-bearing step of the proof (one or two) → a check that needs the
  pattern → the standard trap (one) → the recap beat. A `teach` card carries
  *one* idea; a card that restates the previous card is a card to delete.
- **A card is `teach` xor `ask`** — one beat or one question, never both, and
  never neither.
- **`expects` must be quoted and must be a number.** It decodes as a `String`,
  so an unquoted `expects: 1` fails the build. The parser reads decimals,
  fractions `a/b`, percentages and `\frac{a}{b}` — nothing else. In a
  mathematics course most answers are *not* single numbers: "which hypothesis
  fails", "which of these is a subgroup", "$\neg\forall x\,P(x)$ is equivalent
  to…", "the derivative is…" are all `choices` (three or four rows, each wrong
  row's `feedback` naming the specific mistake). Use a typed check only when
  the answer is genuinely one number: a count, a value, a bound, an index.
- **Write `expects` in plain form** (`7/15`, not `\frac{7}{15}`) and **state
  `tolerance`** whenever the honest answer is rounded (`0.3333` needs
  `tolerance: 0.0005`; `1/3` needs none). Tolerance is absolute.
- **Show the computation that produces `expects` inside `feedback`.** It is
  the only place a correct answer is explained, and the reviewer's check on the
  author.
- **Exactly one choice carries `correct: true`**, at least two rows, and
  `feedback` is required on every check.
- Checks are formative and record nothing (D13.2). Do not narrate the app
  ("click continue", "mark this lesson").

## Voice and references

- Match the corpus: direct, precise, warm rather than sober — this is a course,
  and the reader is a student meeting the idea for the first time. Address the
  reader as "you". Never pad ("it is important to note", "in this lesson we
  will").
- Never start a follow-on thought with "Moreover,"/"Furthermore,"/"In
  addition," — the linter reads these as two lessons bolted together.
- Refer to other nodes by their **title** in prose ("recall the Extreme Value
  Theorem"), never by raw id, and never as "above"/"below"/"step 7" — the
  reader reorders and compresses steps per user.

## LaTeX

Exactly the corpus's rules — `content-quant/style.md` §LaTeX is normative for
both trees. The short version: inline `$...$` only; no display math, no
environments (no `cases`, `align`, `pmatrix` — write piecewise definitions in
prose and matrices as row lists); only allow-listed macros (`\mathbb{R}`,
`\varepsilon`, `\operatorname{...}` for anything unlisted); balanced `$`
everywhere; never `\$`; never nest `$` inside `\text{...}`. `*emphasis*`
renders as italic prose; nothing else in markdown renders. The corpus
self-check renders every section of every lesson and CI fails on any deviation.

## Before you finish

Run the author's check and fix everything it reports:

```
python3 Scripts/check-lesson-file.py <unit-id>
```

It verifies: YAML parses, the unit matches, coverage is exact, required
sections are present, optional sections are omitted rather than empty, lengths
are inside the bar, every card is playable, and the LaTeX stays on the
allow-list. It must end `ok:` with *every* lesson interactive. `ContentBuild
validate` remains the authority and runs in CI.
