#!/usr/bin/env python3
"""Pre-flight check for one lessons file of a program (§6.6, §6.7, §6.9).

Usage: Scripts/check-lesson-file.py [--dialogue] <unit-id>
  e.g. Scripts/check-lesson-file.py quant-probability.foundations
       Scripts/check-lesson-file.py --dialogue analysis.svc

`--dialogue` additionally demands that *every* lesson of the unit is taught as a
§6.9 Socratic dialogue — the flag a dialogue-authoring pass runs with, so a
lesson left on its old `steps` is an error rather than a note.

The tree is inferred from the unit id: a `quant-` prefix means the quant tree
(content-quant/ + content-quant-program/), anything else the math tree
(content/ + program/).

This is the *author's* half of validation — runnable with nothing but python3,
so a content author (human or agent) can check their one file without building
the Swift toolchain. `ContentBuild validate` remains the authority; this mirrors
its per-file lesson rules plus the LaTeX-lite subset of the style guides, and
disagreements resolve in ContentBuild's favour.
"""

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent

# The known-good macro list of content-quant/style.md, plus the spacing/escape
# tokens it names. Anything else is a gamble the renderer may lose.
ALLOWED_MACROS = set(
    """frac dfrac tfrac sqrt binom sum prod int iint oint bigcup bigcap
    text mathrm mathbf mathcal mathbb mathfrak operatorname boldsymbol
    hat bar tilde vec dot overline underline widehat widetilde
    le ge ne approx sim simeq cong equiv propto ll gg mid nmid perp
    in notin subset subseteq supseteq cup cap setminus emptyset varnothing
    to rightarrow Rightarrow Leftarrow Leftrightarrow iff implies mapsto uparrow downarrow
    pm mp times cdot circ ast oplus otimes wedge vee lor land
    infty partial nabla forall exists neg ell prime angle degree
    lim limsup liminf sup inf max min arg exp log ln sin cos tan sinh cosh tanh
    arcsin arccos arctan
    Pr det dim ker deg gcd tr rank sgn mod bmod pmod Var Cov erf
    langle rangle lfloor rfloor lceil rceil lvert rvert lVert rVert left right middle
    quad qquad dots ldots cdots
    alpha beta gamma delta epsilon varepsilon zeta eta theta vartheta iota kappa
    lambda mu nu xi pi varpi rho varrho sigma varsigma tau upsilon phi varphi chi
    psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega
    leftrightarrow longrightarrow aleph im lcm ncong subsetneq unlhd displaystyle""".split()
)
# The last line: macros the math corpus's own statements use and the renderer
# knows, which the quant guide's list predates. Anything the corpus check
# passes is fair for a lesson to echo.

REQUIRED = ["hook", "explanation", "recap"]
OPTIONAL = ["worked", "interview", "pitfalls"]
# §6.7's cards. Optional at the lesson level (a lesson with no `steps` pages off
# its prose — D13.1), but a `steps` list that exists must be playable.
CARD_FIELDS = [
    "part", "teach", "ask", "reflect", "answer",
    "choices", "expects", "tolerance", "hint", "feedback",
]
CHOICE_FIELDS = ["text", "correct", "feedback"]

# §6.9's dialogue contract — ProgramValidator.DialogueContract's numbers, which
# this must agree with.
MAX_BEATS_IN_A_ROW = 2
MIN_QUESTIONS = 5
MIN_PARTS = 2
# Checker-only bars (the validator has no length rules for cards): a beat in a
# dialogue is a paragraph, not a page, and a part title is a heading.
MAX_BEAT_CHARS = 1100
MAX_PART_TITLE_CHARS = 70


def tree_roots(unit):
    """(content root, program root) for the tree a unit id belongs to."""
    if unit.startswith("quant-"):
        return ROOT / "content-quant", ROOT / "content-quant-program"
    return ROOT / "content", ROOT / "program"


def fail(errors):
    for error in errors:
        print(f"  ✗ {error}")
    print(f"\n{len(errors)} problem(s) — fix and re-run")
    sys.exit(1)


def latex_errors(where, text):
    errors = []
    if "\t" in text:
        errors.append(f"{where}: contains a tab")
    # The renderer flags ANY literal $ in its output, so \$ is unusable —
    # write "10 dollars" or a bare math number, never a currency sign.
    if "\\$" in text:
        errors.append(f"{where}: \\$ renders a literal $ and fails the corpus check")
    # A folded scalar keeps a backslash literally, so \" reaches the renderer as
    # a leftover backslash (the corpus check's "macro was not consumed").
    if '\\"' in text or "\\'" in text:
        errors.append(f"{where}: backslash-escaped quote — YAML keeps the backslash; write a plain quote")
    # A $ nested inside \text{...} splits the enclosing span and mangles it.
    if re.search(r"\\text\{[^}]*\$", text):
        errors.append(f"{where}: $ nested inside \\text{{...}} — un-nest the math")
    unescaped = re.sub(r"\\\$", "", text)
    if unescaped.count("$") % 2 != 0:
        errors.append(f"{where}: unbalanced $ delimiters")
    if "$$" in text:
        errors.append(f"{where}: display math ($$) is not supported")
    if re.search(r"\\begin\{|\\end\{", text):
        errors.append(f"{where}: LaTeX environments are not supported")
    for macro in re.findall(r"\\([a-zA-Z]+)", text):
        if macro not in ALLOWED_MACROS:
            errors.append(f"{where}: macro \\{macro} is not on the allow-list")
    # Markdown other than *emphasis* never renders (D14.4): it reaches the reader
    # as itself.
    if "**" in text:
        errors.append(f"{where}: `**bold**` is not rendered — use *emphasis* or plain prose")
    if "`" in text:
        errors.append(f"{where}: backticks are not rendered — write the term plainly")
    return errors


def numeric_value(source):
    """Mirror of GraphCore's NumericAnswer (D13.4): generous spelling, strict value.

    Returns a float, or None when the text is not a number this parser reads —
    which is exactly when `check-unparsable-answer` fires in ContentBuild.
    """
    text = str(source).strip()
    if not text:
        return None
    text = text.replace("$", "")
    for spacing in ["\\,", "\\;", "\\!", "\\ ", "\\quad", "\\qquad", "\\left", "\\right"]:
        text = text.replace(spacing, "")
    # \frac{a}{b} / \dfrac / \tfrac → a/b. Non-nesting, like the Swift side's
    # common case; a malformed macro simply fails to parse below.
    text = re.sub(r"\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}", r"\1/\2", text)
    text = text.replace("\\times", "").replace("\\%", "%")
    text = text.replace("\u2212", "-").replace("\u2044", "/")
    for junk in [",", " ", "(", ")"]:
        text = text.replace(junk, "")
    percent = text.endswith("%")
    if percent:
        text = text[:-1]
    if not text:
        return None
    parts = text.split("/")
    if len(parts) > 2:
        return None
    try:
        values = [float(p) for p in parts]
    except ValueError:
        return None
    if any(v != v or v in (float("inf"), float("-inf")) for v in values):
        return None
    if not all(re.fullmatch(r"[-+]?[0-9.]*(?:[eE][-+]?[0-9]+)?", p) and any(c.isdigit() for c in p)
               for p in parts):
        return None
    if len(values) == 2:
        if values[1] == 0:
            return None
        result = values[0] / values[1]
    else:
        result = values[0]
    return result / 100 if percent else result


def card_errors(node, index, card, list_name="steps"):
    """The per-card rules of ProgramValidator.cardFaults plus AnswerCheck.faults."""
    where = f"{node}.{list_name}[{index}]"
    errors = []
    if not isinstance(card, dict):
        return [f"{where}: is not a mapping"]

    for key in card:
        if key not in CARD_FIELDS:
            errors.append(f"{where}: unknown field `{key}`")

    teach = (card.get("teach") or "").strip()
    ask = (card.get("ask") or "").strip()
    reflect = (card.get("reflect") or "").strip()
    answer = (card.get("answer") or "").strip()
    part = (card.get("part") or "").strip()
    choices = card.get("choices") or []
    expects = card.get("expects")
    expectation = "" if expects is None else str(expects).strip()
    tolerance = card.get("tolerance")
    feedback = (card.get("feedback") or "").strip()

    kinds = [k for k, v in [("teach", teach), ("ask", ask), ("reflect", reflect)] if v]
    if not kinds:
        return errors + [f"{where}: has none of `teach`, `ask` or `reflect`"]
    if len(kinds) > 1:
        errors.append(
            f"{where}: combines {' and '.join(f'`{k}`' for k in kinds)} — "
            "one beat, one check or one reflection"
        )

    for field in ["part", "teach", "ask", "reflect", "answer", "hint"]:
        text = (card.get(field) or "").strip()
        if text:
            errors += latex_errors(f"{where}.{field}", text)
    if "part" in card and not part:
        errors.append(f"{where}: `part` is present but empty — omit it instead")

    if reflect and not answer:
        errors.append(
            f"{where}: `reflect` with no `answer` — the reader compares theirs with the tutor's"
        )
    if answer and not reflect:
        errors.append(
            f"{where}: `answer` without `reflect` — `answer` is a reflection's model answer; "
            "a check's explanation is `feedback`"
        )

    if not ask:
        stranded = [f for f in ["choices", "expects", "tolerance", "feedback"] if f in card]
        if stranded:
            errors.append(
                f"{where}: `{'reflect' if reflect else 'teach'}` card carrying "
                f"{', '.join(stranded)} — add an `ask`, or delete the answer fields"
            )
        return errors

    if not choices and not expectation:
        errors.append(f"{where}: needs either `choices` or an `expects` value")
    if choices and expectation:
        errors.append(f"{where}: declares both `choices` and `expects`")

    if expects is not None and not isinstance(expects, str):
        errors.append(
            f"{where}: `expects: {expects}` must be quoted — an unquoted number decodes "
            "as an int and fails the build"
        )

    if choices:
        if len(choices) < 2:
            errors.append(f"{where}: has {len(choices)} choice — a choice needs at least two rows")
        correct = 0
        for j, choice in enumerate(choices):
            if not isinstance(choice, dict):
                errors.append(f"{where}.choices[{j}]: is not a mapping")
                continue
            for key in choice:
                if key not in CHOICE_FIELDS:
                    errors.append(f"{where}.choices[{j}]: unknown field `{key}`")
            text = (choice.get("text") or "").strip()
            if not text:
                errors.append(f"{where}.choices[{j}]: has no text")
            else:
                errors += latex_errors(f"{where}.choices[{j}].text", text)
            if choice.get("correct"):
                correct += 1
            note = (choice.get("feedback") or "").strip()
            if "feedback" in choice and not note:
                errors.append(f"{where}.choices[{j}]: `feedback` is present but empty")
            elif note:
                errors += latex_errors(f"{where}.choices[{j}].feedback", note)
        if correct == 0:
            errors.append(f"{where}: marks no choice `correct: true`")
        elif correct > 1:
            errors.append(f"{where}: marks {correct} choices correct — exactly one is right")

    if expectation:
        errors += latex_errors(f"{where}.expects", expectation)
        if numeric_value(expectation) is None:
            errors.append(
                f"{where}: `expects: {expectation}` is not a number the answer parser reads — "
                "write a decimal, a fraction `a/b`, a percentage, or use `choices`"
            )

    if tolerance is not None and not (isinstance(tolerance, (int, float)) and tolerance > 0):
        errors.append(f"{where}: `tolerance: {tolerance}` is not a positive number")

    if not feedback:
        errors.append(f"{where}: has no `feedback` — a reader who guessed right needs the reason")
    else:
        errors += latex_errors(f"{where}.feedback", feedback)

    return errors


def dialogue_errors(node, dialogue):
    """§6.9's contract — ProgramValidator.cardChecks's `dialogue-` rules, plus the
    checker-only length bars."""
    where = f"{node}.dialogue"
    errors = []
    cards = [c for c in dialogue if isinstance(c, dict)]

    def text(card, field):
        return (card.get(field) or "").strip()

    def is_question(card):
        return bool(text(card, "ask") or text(card, "reflect"))

    if not cards or not text(cards[0], "part"):
        errors.append(f"{where}: opens without a `part:` — the first step names the first part")

    beats = 0
    for j, card in enumerate(cards):
        beats = 0 if is_question(card) else beats + 1
        if beats == MAX_BEATS_IN_A_ROW + 1:
            errors.append(
                f"{where}[{j}]: {beats} `teach` steps in a row — ask something before the "
                "third beat (that is the whole difference between a dialogue and a textbook)"
            )
        beat = text(card, "teach")
        if len(beat) > MAX_BEAT_CHARS:
            errors.append(
                f"{where}[{j}]: a {len(beat)}-char beat — split it with a question "
                f"(ceiling {MAX_BEAT_CHARS})"
            )
        title = text(card, "part")
        if len(title) > MAX_PART_TITLE_CHARS:
            errors.append(f"{where}[{j}]: part title is {len(title)} chars — it is a heading")

    questions = sum(1 for c in cards if is_question(c))
    parts = sum(1 for c in cards if text(c, "part"))
    if questions < MIN_QUESTIONS or parts < MIN_PARTS:
        errors.append(
            f"{where}: {questions} question(s) in {parts} part(s) — a dialogue asks at least "
            f"{MIN_QUESTIONS} across at least {MIN_PARTS} parts"
        )
    if not any(text(c, "reflect") for c in cards):
        errors.append(
            f"{where}: no `reflect` step — somewhere the reader must put the idea in their "
            "own words before it is named"
        )
    for j, card in enumerate(cards):
        if not text(card, "ask"):
            continue
        silent = [
            str(k + 1)
            for k, choice in enumerate(card.get("choices") or [])
            if isinstance(choice, dict) and not (choice.get("feedback") or "").strip()
        ]
        if silent:
            errors.append(
                f"{where}[{j}]: choice(s) {', '.join(silent)} have no `feedback` — "
                "a wrong pick is where a dialogue teaches"
            )
    return errors


def main():
    args = sys.argv[1:]
    require_dialogue = "--dialogue" in args
    args = [a for a in args if a != "--dialogue"]
    if len(args) != 1:
        print(__doc__)
        sys.exit(2)
    unit = args[0]
    branch, _, sub = unit.partition(".")
    content_root, program_root = tree_roots(unit)
    content_path = content_root / branch / f"{sub}.yaml"
    lesson_path = program_root / "lessons" / f"{unit}.yaml"

    errors = []
    if not content_path.exists():
        fail([f"no such unit: {content_path} does not exist"])
    if not lesson_path.exists():
        fail([f"{lesson_path} does not exist"])

    try:
        content = yaml.safe_load(content_path.read_text())
        lessons = yaml.safe_load(lesson_path.read_text())
    except yaml.YAMLError as e:
        fail([f"YAML does not parse: {e}"])

    expected = {
        node["id"]
        for node in content["nodes"]
        if node.get("parent") == unit and node.get("kind") != "subbranch"
    }

    if lessons.get("unit") != unit:
        errors.append(f"unit: is {lessons.get('unit')!r}, expected {unit!r}")
    opening = (lessons.get("opening") or "").strip()
    if len(opening) < 80:
        errors.append("opening: missing or too short to open a chapter (< 80 chars)")
    else:
        errors += latex_errors("opening", opening)

    taught = []
    interactive = []
    dialogues = []
    checks_total = 0
    reflections_total = 0
    for i, lesson in enumerate(lessons.get("lessons") or []):
        node = lesson.get("node", f"lessons[{i}]")
        taught.append(node)
        if node not in expected:
            errors.append(f"{node}: not a content node of {unit}")
        for key in lesson:
            if key not in ["node", "steps", "dialogue"] + REQUIRED + OPTIONAL:
                errors.append(f"{node}: unknown field `{key}`")
        for section in REQUIRED:
            text = (lesson.get(section) or "").strip()
            if not text:
                errors.append(f"{node}: required section `{section}` is missing/empty")
            else:
                errors += latex_errors(f"{node}.{section}", text)
        for section in OPTIONAL:
            if section in lesson:
                text = (lesson.get(section) or "").strip()
                if not text:
                    errors.append(f"{node}: `{section}` is present but empty — omit it instead")
                else:
                    errors += latex_errors(f"{node}.{section}", text)
        explanation = (lesson.get("explanation") or "").strip()
        if explanation and len(explanation) < 400:
            errors.append(
                f"{node}: explanation is {len(explanation)} chars — a lesson teaches "
                "(target 700–1800)"
            )
        total = sum(len((lesson.get(s) or "")) for s in REQUIRED + OPTIONAL)
        if total > 6000:
            errors.append(f"{node}: sections total {total} chars — probably two lessons")

        # §6.7. `steps` is optional; a `steps` list that exists must be playable.
        steps = lesson.get("steps")
        if steps is not None:
            if not isinstance(steps, list) or not steps:
                errors.append(f"{node}: `steps` is present but empty — omit it instead")
            else:
                for j, card in enumerate(steps):
                    errors += card_errors(node, j, card)
                checks = sum(
                    1 for c in steps if isinstance(c, dict) and (c.get("ask") or "").strip()
                )
                checks_total += checks
                if checks == 0:
                    errors.append(
                        f"{node}: {len(steps)} authored cards and not one `ask` — "
                        "a paged slideshow still measures nothing"
                    )
                elif checks < 2:
                    errors.append(
                        f"{node}: only one `ask` in {len(steps)} cards — "
                        "a checked lesson asks at least twice"
                    )
                if len(steps) < 4:
                    errors.append(
                        f"{node}: {len(steps)} authored card(s) — one idea per screen means more"
                    )
                interactive.append(node)

        # §6.9. A dialogue replaces `steps`, and is held to the dialogue contract.
        dialogue = lesson.get("dialogue")
        if dialogue is not None:
            if steps is not None:
                errors.append(
                    f"{node}: carries both `steps` and `dialogue` — a dialogue replaces the "
                    "steps; delete the `steps`"
                )
            if not isinstance(dialogue, list) or not dialogue:
                errors.append(f"{node}: `dialogue` is present but empty — omit it instead")
            else:
                for j, card in enumerate(dialogue):
                    errors += card_errors(node, j, card, "dialogue")
                errors += dialogue_errors(node, dialogue)
                checks_total += sum(
                    1 for c in dialogue if isinstance(c, dict) and (c.get("ask") or "").strip()
                )
                reflections_total += sum(
                    1
                    for c in dialogue
                    if isinstance(c, dict)
                    and (c.get("reflect") or "").strip()
                    and not (c.get("ask") or "").strip()
                )
                dialogues.append(node)
                if node not in interactive:
                    interactive.append(node)
        elif require_dialogue:
            errors.append(f"{node}: no `dialogue` — --dialogue wants every lesson taught as one")

    duplicates = {n for n in taught if taught.count(n) > 1}
    for node in sorted(duplicates):
        errors.append(f"{node}: taught more than once")
    missing = expected - set(taught)
    for node in sorted(missing):
        errors.append(f"{node}: no lesson — every content node of the unit needs one")

    if errors:
        fail(errors)
    cards = sum(
        len(lesson.get("dialogue") or lesson.get("steps") or [])
        for lesson in (lessons.get("lessons") or [])
    )
    print(
        f"ok: {unit} — opening + {len(taught)} lessons "
        f"({len(interactive)} interactive, {len(dialogues)} dialogues, {cards} cards, "
        f"{checks_total} checks, {reflections_total} reflections), all checks pass"
    )
    if len(interactive) < len(taught):
        print(f"note: {len(taught) - len(interactive)} lesson(s) still page off their prose (no `steps`)")


if __name__ == "__main__":
    main()
