# Dialogues — the Socratic lesson contract (§6.9, both trees)

Read this whole file, then the reference dialogue, which is the quality bar:
`analysis.svc.mvt` in `program/lessons/analysis.svc.yaml` (search for
`node: analysis.svc.mvt` and read its `dialogue:`). This file governs the
`dialogue:` list of a lesson in **both** programs — `program/` (the math tree)
and `content-quant-program/` (the quant tree). Each tree's `style.md` still
governs everything else in a lessons file: the prose sections, LaTeX, voice,
references.

## What a dialogue is

A lesson's `steps` teach the way a textbook does: define, then quiz the
definition. A **dialogue** teaches the way a tutor does: it puts a concrete
problem in front of the reader, asks them to try it, lets the naive attempt
run into its obstacle, and asks them to reach for the fix — and only then
names the idea the reader has half-built. The reader should *discover* each
idea one step before being told it.

The player shows a dialogue as one growing transcript. Everything up to the
first unanswered question is on the page; answering unfolds the next stretch.
Consequences for the author:

- **The text after a question may give its answer away, and should.** The
  next beat is written for someone who has just answered.
- **A wrong pick stays on the page with its `feedback`, and the reader picks
  again.** Wrong rows are read — so a wrong row's feedback is where most of
  the teaching happens.
- The reader can always ask for the hint, or say "show me". Nothing locks.
- Earlier steps stay visible above. A later question may refer back to "the
  toll road" or "the pace car" without restating it.

A dialogue **replaces** the lesson's `steps` (delete them; the validator
rejects a lesson carrying both). The prose sections (`hook`, `explanation`,
`worked`, `pitfalls`, `recap`, `interview`) stay exactly as they are — the
chapter reader shows them, and the player closes on `recap`. Do not rewrite
them unless one is wrong.

## The steps

```yaml
    dialogue:
      - part: Two photographs and a fine      # opens a part; allowed on any step
        teach: >
          A beat: the tutor talks. A concrete situation, a consequence, a name.
      - ask: >
          A machine-checked question with a numeric answer.
        expects: "100"
        hint: >
          A nudge, never the answer. Optional.
        feedback: >
          Why, with the computation shown.
      - ask: >
          A machine-checked question whose answer is a choice.
        choices:
          - text: >
              A misconception a real reader holds.
            feedback: >
              What exactly is wrong with it — often a counterexample.
          - text: >
              The right answer.
            correct: true
            feedback: >
              Confirms, and adds one sentence of insight.
        feedback: >
          Consolidates once the question is done: the principle, a name, what
          comes next.
      - reflect: >
          An open question: the reader writes their idea, then reads yours.
        hint: >
          Optional nudge.
        answer: >
          The tutor's answer, 2–5 sentences, better than what a reader will
          write: it names the idea and says why.
```

A step is exactly one of `teach`, `ask`, `reflect`. `part:` may sit on any
step and opens a new part; the first step must carry one. Field order within a
step: `part, teach | ask | reflect, answer, choices, expects, tolerance, hint,
feedback`. Every string is a folded block scalar (`>`), uniformly indented.

## The arc

Per node, in parts. A typical theorem or technique dialogue runs through all
of these; shorter nodes compress them, but the order holds — **the question
comes before the explanation**.

1. **A concrete situation**, with numbers: a toll road, a deck of cards, a
   specific function on a specific interval. Not "consider a function $f$".
2. **The reader's first attempt**: compute or predict something about it
   (`ask`, typed where the answer is a number).
3. **The obstacle**: what the naive idea cannot do, or where it fails
   (`ask` with choices whose wrong rows are the things a real reader says).
4. **The reach**: a `reflect` that asks for the idea *before* it is named —
   "what could you subtract so the endpoints agree?", "what does the brute
   force count twice?". This is the heart of the dialogue.
5. **The name**: a `teach` that names the idea and states it precisely —
   now, not earlier. The precise statement is the payoff, not the premise.
6. **Why it holds**: the load-bearing step of the proof, asked ("what must
   you check before applying Rolle's Theorem?"), not recited.
7. **An instance by hand**: the reader computes a case to the end (typed).
8. **Where it breaks**: a dropped hypothesis, a boundary case, a
   counterexample — the reader diagnoses it (choices).
9. **A last beat**: the one sentence to keep, and what it opens up.

### By node kind

- **definition** — show two or three objects, some of which should count and
  some not; ask which, and why; *then* state the clauses as the answer to
  "what exactly were you checking?". Test clause by clause on a new object.
  End on the non-example that fails exactly one clause.
- **theorem / lemma / proposition / corollary** — the reader predicts the
  claim on an instance; the proof idea is reached for (`reflect`) before it is
  given; the hypotheses are broken one at a time.
- **technique** — a problem the reader can already do slowly; its cost; the
  wasted or repeated work; the technique falls out of removing the waste.
- **example** — the reader computes it, scaffolded by questions that each
  decide one sub-step; the beats only connect them.
- **intuition** — the reader predicts; the prediction is tested; the dialogue
  shows where the intuition holds and where it misleads.
- **axiom** — why would we want this? what goes wrong without it? which
  familiar structure satisfies it, and which does not?

For the **quant tree**, the concrete situation is usually the interview
question itself, and a dialogue often closes on how the answer is said aloud
under pressure — but it is still built question-first, never "here is the
formula; now use it".

### The anti-pattern

`teach: (states the definition) → ask: (which of these matches the
definition?)` is a textbook followed by a quiz. So is `teach: (states the
theorem) → teach: (proves it) → ask: (apply it)`. If a beat explains
something, the question should come *before* it — or the question should ask
the reader to apply the idea to a case the beat did not cover.

## Rules the checker enforces

`python3 Scripts/check-lesson-file.py --dialogue <unit-id>` must print `ok:`.
`ContentBuild validate` holds the same contract (the length bars are the
checker's alone).

- The first step carries `part:`. At least **2 parts**; aim for **3–4**.
  Part titles are headings — a phrase, sentence case, at most 70 characters,
  and they should read in sequence like the outline of a conversation.
- **At most 2 `teach` steps in a row.** A beat is at most 1100 characters;
  most are 250–600.
- At least **5 questions** (`ask` + `reflect`); aim for **7–12**, fewer only
  for the smallest definitions.
- At least **1 `reflect`**; aim for 1–2. A reflection that could be answered
  with one number should be a typed `ask` instead.
- **Every choice row has `feedback`.** "Incorrect." is not feedback.
- All of §6.7's check rules still hold: exactly one `correct: true`; `expects`
  quoted and a plain number (`"7/15"`, `"0.25"`, `"12"`); `tolerance` stated
  whenever the honest answer is rounded; `feedback` on every `ask`.

## Writing good questions

- **Wrong options are where the teaching happens.** Each is a misconception a
  real reader holds, and its feedback says what exactly is wrong — often with
  a counterexample or the computation that refutes it. The correct row's
  feedback confirms and adds one sentence of insight.
- 3–4 options; vary the position of the correct one. Options are one line of
  prose or math.
- Prefer typed numeric answers wherever the answer is a number: a number the
  reader produced is a stronger retrieval than a row they recognised.
- `hint` is a nudge toward the method, never the answer.
- Use concrete numbers and tiny examples the reader can compute in their head
  or on a scrap of paper.
- No trivia. Every question forces a prediction, a decision, a computation, or
  catches a detail that costs a proof.
- A `reflect` asks for the insight *before* it is given ("what does the first
  attempt do twice?"), never for a summary of what was just said.

## Voice

Second person, plain, specific, warm, a little dry. No exclamation marks, no
"great job", no "let's dive in", no emojis. Numbers over adjectives. Never
narrate the app ("click", "press show me", "the next card"). Refer to other
nodes by title, never by id. LaTeX exactly as the tree's `style.md` allows —
inline `$...$` only, allow-listed macros, `*emphasis*` is the only markdown.

## Checklist before you report back

- `python3 Scripts/check-lesson-file.py --dialogue <unit-id>` prints `ok:`.
- Read each dialogue top to bottom *answering every question wrongly first*:
  does each wrong row's feedback teach?
- Is there a point in every dialogue where the reader reaches for the idea
  before being told it?
- Does any beat explain something that a question right after merely asks the
  reader to recall? Reorder it.
