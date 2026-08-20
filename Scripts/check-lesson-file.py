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


def fail(errors):
    for error in errors:
        print(f"  ✗ {error}")
    print(f"\n{len(errors)} problem(s) — fix and re-run")
    sys.exit(1)


def latex_errors(where, text):
    errors = []
    if "\t" in text:
        errors.append(f"{where}: contains a tab")
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
    for i, lesson in enumerate(lessons.get("lessons") or []):
        node = lesson.get("node", f"lessons[{i}]")
        taught.append(node)
        if node not in expected:
            errors.append(f"{node}: not a content node of {unit}")
        for key in lesson:
            if key not in ["node"] + REQUIRED + OPTIONAL:
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

    duplicates = {n for n in taught if taught.count(n) > 1}
    for node in sorted(duplicates):
        errors.append(f"{node}: taught more than once")
    missing = expected - set(taught)
    for node in sorted(missing):
        errors.append(f"{node}: no lesson — every content node of the unit needs one")

    if errors:
        fail(errors)
    print(f"ok: {unit} — opening + {len(taught)} lessons, all checks pass")


if __name__ == "__main__":
    main()
