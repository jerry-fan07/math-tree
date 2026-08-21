# Quant program — lesson authoring guide (read fully before writing any lesson)

You are authoring one lessons file of `content-quant-program/`, the teaching
layer (§6.6) over the quant-interview tree. The corpus's node files say *what to
know*; your file says *how to come to know it*. The app's reader shows, for each
step: the node's title, its full `statement`, and then your lesson — so a lesson
that restates the statement says nothing. Teach.

## File shape

- Path: `content-quant-program/lessons/<unit-id>.yaml`, where `<unit-id>` is the
  subbranch id (e.g. `quant-probability.foundations`).
- Top level:

  ```yaml
  unit: quant-probability.foundations
  opening: >
    Two to four sentences that open the chapter: what this unit is for, the arc
    of its steps, and where it sits in the program.
  lessons:
    - node: quant-probability.foundations.sample-space
      hook: >
        ...
      explanation: >
        ...
      worked: >
        ...
      interview: >
        ...
      pitfalls: >
        ...
      recap: >
        ...
  ```

- **One lesson per content node of the unit** — every node in the unit's
  `content-quant/<branch>/<subbranch>.yaml` whose `parent` is the unit, no more,
  no fewer. The validator rejects a file that misses one, invents one, or
  teaches a node that lives elsewhere.
- Field order is fixed: `node, hook, explanation, worked, interview, pitfalls,
  recap, steps`. Omit an optional section entirely rather than leaving it empty.
- Every section is a folded block scalar (`>`) with a **uniform 2-space
  continuation indent**. A blank line inside `explanation` becomes a paragraph
  break in the reader — use 2–5 paragraphs. Never double-quote a string
  containing LaTeX.

## The sections

Required: `hook`, `explanation`, `recap`. Optional: `worked`, `interview`,
`pitfalls` — include each wherever it can be filled *honestly* (for a theorem,
technique or example, `worked` is all but mandatory; for an `intuition` node it
is often filler, so leave it out).

- **hook** (1–2 sentences): why this node earns a step — where it bites at a
  desk or in an interview. Not a summary; a reason to care.
- **explanation** (2–5 paragraphs, 700–1800 characters): the actual teaching.
  Build it from the node's prerequisites: motivate the definition or derive the
  result (a proof *sketch* with the load-bearing step shown beats a citation),
  give the mental model that makes it obvious, state the general pattern the
  interview will disguise. Assume the reader holds the node's `requires` (and
  everything those require) and **nothing else** — never lean on a node that
  comes later.
- **worked** (one example, computed to the end): pick a *different* instance
  from the one in the statement when the statement already works one. End in
  the actual number ("so the answer is $7/15$") — the interview answer is the
  number.
- **interview** (2–4 sentences): how this is actually asked — the canonical
  phrasings, what the interviewer is listening for, the ten-second version you
  should be able to say cold.
- **pitfalls** (1–3 concrete traps): the hypothesis people drop, the sign that
  flips, the edge case that voids the formula. Concrete, not "be careful".
- **recap** (one sentence): the one breath to retain.

Target 1,800–3,500 characters per lesson across all sections; the linter flags
explanations under 400 and lessons over 6,000.

## Voice and references

- Match the corpus: direct, precise, sober. Address the reader as "you" where
  it helps; never pad ("it is important to note", "in this lesson we will").
- Never start a follow-on thought with "Moreover,"/"Furthermore,"/"In
  addition," — the linter reads these as two lessons bolted together.
- Refer to other nodes by their **title** in prose ("recall Bayes' rule"),
  never by raw id, and never as "above"/"below"/"step 7" — the reader reorders
  and compresses steps per user.
- Do not narrate the app ("mark this lesson", "click details").

## LaTeX

Exactly the corpus's rules — `content-quant/style.md` §LaTeX is normative.
The short version: inline `$...$` only; no display math, no environments; only
allow-listed macros (`\mathbb{E}[X]`, `\Pr`, `\operatorname{...}` for anything
unlisted); balanced `$` everywhere. Two traps the first batches hit: **never
write a currency dollar sign** (`\$10` renders a literal `$` and fails the
corpus check — write "$10$ dollars" or a bare number), and **never nest `$`
inside `\text{...}`** (it splits the enclosing span — write digits in the
`\text` directly). The corpus self-check renders every section of every lesson
and CI fails on any deviation.

## `steps` — the lesson as cards (§6.7)

Optional, and worth authoring wherever you can. A lesson with no `steps` still
plays: the app derives one card per prose section, so the reader gets the lesson
in pieces but is never *asked* anything. Authoring `steps` is what upgrades a
node from paged prose to a checked lesson.

```yaml
      recap: >
        ...
      steps:
        - teach: >
            One beat — a single idea, two or three sentences.
        - ask: >
            A question with a numeric answer.
          expects: "7/15"
          tolerance: 0.0005
          hint: >
            Offered on request, before the answer. Never shown unasked.
          feedback: >
            Why that is the answer. Shown however the check resolves.
        - ask: >
            A question whose answer is a judgement, not a number.
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

- **A card is `teach` xor `ask`** — one beat or one question, never both, and
  never neither. A `teach` card carrying `choices`/`expects`/`feedback` is an
  error, not a shorthand.
- **Aim for 5–7 cards and at least two checks per lesson.** Below four cards the
  lint says so; zero checks makes it a slideshow, which the lint also says.
  Alternate: teach, teach, check, teach, check.
- **`expects` must be quoted and must be a number.** It decodes as a `String`,
  so an unquoted `expects: 1` fails the build as an integer. And the parser
  reads decimals, fractions `a/b`, percentages and `\frac{a}{b}` — nothing else.
  A **symbolic** answer (`1/n`, `1/i`, "the median") is not a typed check: make
  it `choices`. `check-unparsable-answer` fails the build rather than telling a
  correct reader they are wrong.
- **Write `expects` in plain form** (`7/15`, not `\frac{7}{15}`): it is shown
  back on a wrong answer, and the plain form is what the reader typed.
- **State `tolerance` whenever the honest answer is rounded.** With none, the
  match is effectively exact, so `0.4914` for $1 - (35/36)^{24}$ needs
  `tolerance: 0.0005`. Tolerance is absolute.
- **Exactly one choice carries `correct: true`**, and there must be at least
  two. Give each wrong option a `feedback` naming the *specific* mistake it
  corresponds to — a distractor nobody would pick teaches nothing, and
  "incorrect" teaches less.
- **`feedback` is required on every check**, including choice checks that also
  have per-row feedback: a reader who guessed right still needs the reason.
- Checks are formative and record nothing (D13.2). Do not write a card that
  claims otherwise, and do not narrate the app ("click continue").

## No markdown, anywhere

`*emphasis*`, `**bold**`, `_underscores_` and backticks are **not** rendered —
`MathText` is LaTeX-lite, and asterisks reach the reader as asterisks. Carry
emphasis with word order instead. (Some older lesson files still contain these;
they are a known defect, not a precedent.)

## Before you finish

Run the author's check and fix everything it reports:

```
python3 Scripts/check-lesson-file.py <unit-id>
```

It verifies: YAML parses, the unit matches, coverage is exact, required
sections are present, optional sections are omitted rather than empty, lengths
are inside the bar, and the LaTeX stays on the allow-list. `ContentBuild
validate` remains the authority and runs in CI.
