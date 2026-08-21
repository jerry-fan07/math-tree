#!/usr/bin/env python3
"""Pre-flight check for one lessons file of the quant program (§6.6).

Usage: Scripts/check-lesson-file.py <unit-id>
  e.g. Scripts/check-lesson-file.py quant-probability.foundations

This is the *author's* half of validation — runnable with nothing but python3,
so a content author (human or agent) can check their one file without building
the Swift toolchain. `ContentBuild validate` remains the authority; this mirrors
its per-file lesson rules plus the LaTeX-lite subset of content-quant/style.md,
and disagreements resolve in ContentBuild's favour.
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
    psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega""".split()
)

REQUIRED = ["hook", "explanation", "recap"]
OPTIONAL = ["worked", "interview", "pitfalls"]
# §6.7's cards. Optional at the lesson level (a lesson with no `steps` pages off
# its prose — D13.1), but a `steps` list that exists must be playable.
CARD_FIELDS = ["teach", "ask", "choices", "expects", "tolerance", "hint", "feedback"]
CHOICE_FIELDS = ["text", "correct", "feedback"]


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


def card_errors(node, index, card):
    """The per-card rules of ProgramValidator.cardChecks plus AnswerCheck.faults."""
    where = f"{node}.steps[{index}]"
    errors = []
    if not isinstance(card, dict):
        return [f"{where}: is not a mapping"]

    for key in card:
        if key not in CARD_FIELDS:
            errors.append(f"{where}: unknown field `{key}`")

    teach = (card.get("teach") or "").strip()
    ask = (card.get("ask") or "").strip()
    choices = card.get("choices") or []
    expects = card.get("expects")
    expectation = "" if expects is None else str(expects).strip()
    tolerance = card.get("tolerance")
    feedback = (card.get("feedback") or "").strip()

    if not teach and not ask:
        return errors + [f"{where}: has neither `teach` nor `ask`"]
    if teach and ask:
        errors.append(f"{where}: has both `teach` and `ask` — one beat or one question")

    for field in ["teach", "ask", "hint"]:
        text = (card.get(field) or "").strip()
        if text:
            errors += latex_errors(f"{where}.{field}", text)

    if teach and not ask:
        stranded = [f for f in ["choices", "expects", "tolerance", "feedback"] if f in card]
        if stranded:
            errors.append(
                f"{where}: `teach` card carrying {', '.join(stranded)} — "
                "add an `ask`, or delete the answer fields"
            )
        return errors

    if not choices and not expectation:
        errors.append(f"{where}: needs either `choices` or an `expects` value")
    if choices and expectation:
        errors.append(f"{where}: declares both `choices` and `expects`")

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


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    unit = sys.argv[1]
    branch, _, sub = unit.partition(".")
    content_path = ROOT / "content-quant" / branch / f"{sub}.yaml"
    lesson_path = ROOT / "content-quant-program" / "lessons" / f"{unit}.yaml"

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
    for i, lesson in enumerate(lessons.get("lessons") or []):
        node = lesson.get("node", f"lessons[{i}]")
        taught.append(node)
        if node not in expected:
            errors.append(f"{node}: not a content node of {unit}")
        for key in lesson:
            if key not in ["node", "steps"] + REQUIRED + OPTIONAL:
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
                if checks == 0:
                    errors.append(
                        f"{node}: {len(steps)} authored cards and not one `ask` — "
                        "a paged slideshow still measures nothing"
                    )
                if len(steps) < 4:
                    errors.append(
                        f"{node}: {len(steps)} authored card(s) — one idea per screen means more"
                    )
                interactive.append(node)

    duplicates = {n for n in taught if taught.count(n) > 1}
    for node in sorted(duplicates):
        errors.append(f"{node}: taught more than once")
    missing = expected - set(taught)
    for node in sorted(missing):
        errors.append(f"{node}: no lesson — every content node of the unit needs one")

    if errors:
        fail(errors)
    cards = sum(
        len(lesson.get("steps") or [])
        for lesson in (lessons.get("lessons") or [])
    )
    print(
        f"ok: {unit} — opening + {len(taught)} lessons "
        f"({len(interactive)} interactive, {cards} cards), all checks pass"
    )


if __name__ == "__main__":
    main()
