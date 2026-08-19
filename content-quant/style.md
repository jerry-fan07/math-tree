# Quant tree — authoring style guide (read fully before writing any node)

You are authoring one subbranch file of `content-quant/`, the quant-trading-interview
knowledge tree of this repo. The math tree's conventions apply unchanged
(`design.md` §2–§3, `content/README.md`); this file compresses them plus the
quant-tree specifics into one checklist. The reference file for tone, depth and
shape is `content/analysis/svc.yaml` — read it first and match it.

## File shape

- Path: `content-quant/<branch>/<subbranch>.yaml` where `<subbranch>` is the last
  id component. The file already exists as a stub holding only the `subbranch`
  node; **replace the whole file**, keeping that subbranch node as the first
  entry (keep its existing `title`/`summary`/`parent` unless clearly improvable).
- Top level is a single `nodes:` list. Field order is fixed:
  `id, kind, prominence, title, statement, summary, parent, also_under,
  requires, relates, tags`.
- Content nodes carry **every** field; empty lists are written explicitly
  (`also_under: []`, `requires: []`, `relates: []`, `tags: []`).
- The subbranch node omits `statement`, `prominence`, `requires`, `relates`; it
  keeps `summary` (the UI shows it), `parent`, `also_under: []`, `tags: []`.
- `statement` and `summary` are folded block scalars (`>`) with a **uniform
  2-space continuation indent** — a deeper-indented line stops folding and is
  taken literally. Never double-quote a string containing LaTeX (backslashes
  become escapes); use the block scalar, or single quotes for short strings.

## Node schema

- `id`: `<branch>.<subbranch>.<slug>`, lowercase-kebab (`[a-z0-9]+(-[a-z0-9]+)*`
  per component). Ids are permanent — choose sober, descriptive slugs.
- `kind`: one of `definition | axiom | theorem | lemma | proposition |
  corollary | technique | example | intuition`.
  - Problem-solving methods (first-step analysis, indicator trick, quote
    skewing) are `technique`.
  - Canonical interview problems worked in full (coupon collector, airplane
    seat, ants on a stick) are `example` — the problem *and its solution idea*
    are the knowledge.
  - Mental models worth tracking ("variance buys the right to bet bigger",
    "the order book is a queue") are `intuition`.
  - Named results with hypotheses (CLT, optional stopping, put–call parity) are
    `theorem`/`proposition`/`lemma`/`corollary` by weight, exactly as in math.
- `prominence`: 2 = landmark (CLT, Bayes, Kelly, Black–Scholes — at most ~1 in 5
  content nodes of your file, or the linter flags landmark inflation); 1 =
  standard topic; 0 = fine detail.
- `parent`: your subbranch id. `also_under`: usually `[]`; only structural ids
  may appear.
- `statement`: the full, precise content — for theorems include hypotheses; for
  techniques include *when to reach for it* and the mechanics; for examples
  state the problem **and** the solution with the actual numbers worked out.
  Target 300–800 characters; hard ceiling ~900 (linter flags oversize). If it
  wants to be longer, split the node.
- `summary`: 1–2 sentences, informal gloss, used in tooltips.
- Never start a second thought with "Moreover,", "Furthermore,", "In addition,",
  "Additionally,", "Separately," — the linter reads these as two nodes bolted
  together (and it is usually right).

## Edges

- `requires` = hard prerequisite, authored on the destination: list the nodes a
  learner must fully master *first*. Semantics are AND, and every listed node's
  content is needed **whole** (atomicity; if you need only part, the model is
  wrong — pick a finer node or note it, see below).
- **Direct prerequisites only** (transitive reduction). If A is reachable from
  another listed prerequisite, do not list A. Typical nodes have 1–3 `requires`;
  the validator rejects redundant edges and the linter flags fans > 6.
- Build a clear internal chain: definitions → results → techniques → examples.
  Every node must be connected (requires or is-required-by or relates) — no
  islands.
- **Cross-subbranch references**: you may reference ONLY (a) nodes in your own
  file, and (b) spine ids of subbranches listed EARLIER than yours in
  `content-quant/outline.md` (lower order number). Never reference a
  later-ordered subbranch and never reference the math tree (`analysis.*`,
  `foundations.*`, … do not exist in this graph). Keep cross-file `requires`
  sparse — put them on your entry nodes (typically 2–6 cross-file edges per
  file), and let your internal chain carry the rest.
- If a prerequisite you want is not in the spine of any earlier subbranch, use
  the nearest listed ancestor instead and add a comment line at the top of the
  file: `# NEEDS: <exact-id-you-wanted> — <why>`. Never invent a foreign id.
- `relates` = soft, undirected, with a `note` of at least 20 characters saying
  what the connection *is* (the note is scored knowledge). Declare each
  connection on ONE endpoint only — when connecting to an earlier subbranch,
  declare it in YOUR file. 1–4 per file, only where genuinely illuminating.

## LaTeX (the app renders a strict subset — deviations fail CI)

- Inline `$...$` only. **No display math, no `\begin{...}`/`\end{...}`
  environments of any kind** (no `cases`, `align`, `pmatrix`, `array`). Write
  piecewise definitions in prose ("and $0$ otherwise"), matrices in prose or as
  row lists.
- The handbook's custom macros do not exist here. Use: `\mathbb{E}[X]` not
  `\E`; `\Pr` or `\mathbb{P}` not `\Prob`; `\varepsilon` not `\eps`;
  `\mathbb{R}`, `\mathbb{N}` not `\R`, `\N`. Indicators: write
  `\mathbf{1}\{X > t\}` (bold one, escaped braces — both allow-listed).
- Known-good macros (everything else is a gamble — do not use it):
  `\frac \dfrac \tfrac \sqrt \binom \sum \prod \int \iint \oint \bigcup \bigcap`
  `\text \mathrm \mathbf \mathcal \mathbb \mathfrak \operatorname \boldsymbol`
  `\hat \bar \tilde \vec \dot \overline \underline \widehat \widetilde`
  `\le \ge \ne \approx \sim \simeq \cong \equiv \propto \ll \gg \mid \nmid \perp`
  `\in \notin \subset \subseteq \supseteq \cup \cap \setminus \emptyset \varnothing`
  `\to \rightarrow \Rightarrow \Leftarrow \Leftrightarrow \iff \implies \mapsto \uparrow \downarrow`
  `\pm \mp \times \cdot \circ \ast \oplus \otimes \wedge \vee \lor \land`
  `\infty \partial \nabla \forall \exists \neg \ell \prime \angle \degree`
  `\lim \limsup \liminf \sup \inf \max \min \arg \exp \log \ln \sin \cos \tan \sinh \cosh \tanh \arcsin \arccos \arctan`
  `\Pr \det \dim \ker \deg \gcd \tr \rank \sgn \mod \bmod \pmod \Var \Cov \erf`
  greek (`\alpha`…`\Omega`, `\varepsilon \varphi`), `\langle \rangle \lfloor
  \rfloor \lceil \rceil \lvert \rvert \lVert \rVert \left \right \middle`
  `\, \; \! \quad \qquad \dots \ldots \cdots` plus `\{` `\}` (escaped braces) and `\%`.
- `\binom{n}{k}` linearises to `C(n, k)` — fine. `\frac{a}{b}` linearises to
  `(a)/(b)` — fine, but prefer simple numerators/denominators.
- `\operatorname{...}` for anything not listed (e.g.
  `\operatorname{VaR}_\alpha`, `\operatorname{ES}`, `\operatorname{sech}`).
- Subscripts/superscripts: `x_i`, `x^{2}`, `S_{n}` all fine, including nested
  like `e^{-\lambda t}`.
- Balance every `$`; a stray `$` fails the corpus self-check.

## Content bar

This tree prepares a candidate for quantitative trading interviews. Every node
must be *correct*, *self-contained*, and *useful under interview pressure*:

- State exact hypotheses (optional stopping needs its conditions; Kelly needs
  the bet structure; put–call parity needs European + same strike/expiry +
  no-dividend caveat or the dividend-adjusted form).
- Numbers worked to the end in examples ("the answer is $2/3$", "expected tosses
  $= 6$"), because the interview answer is the number.
- Where a canonical interview phrasing exists, name it in the summary or
  statement ("make me a market on X", "should you take this bet?").
- Prefer more small nodes over fewer big ones. 14–24 content nodes per file.

## Before you finish

Self-check every box:
1. YAML parses (mind folded-scalar indentation; no tabs).
2. First node is the subbranch node; every content node's `parent` is the
   subbranch; every id starts with `<subbranch-id>.`.
3. No `requires`/`relates` id outside {your file} ∪ {earlier spines}.
4. No requires cycles inside your file; no redundant (transitively implied)
   requires; fans ≤ 6.
5. Landmark count ≤ ~20% of content nodes; statements ≤ ~900 chars.
6. LaTeX: only allow-listed macros, balanced `$`, no environments.
7. Every spine id assigned to YOUR subbranch in the outline exists in your file
   with exactly that id and a matching meaning.
