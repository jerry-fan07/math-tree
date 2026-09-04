#!/usr/bin/env python3
"""Pre-flight check for one problem-bank file (§5.2, §6.7).

Usage: Scripts/check-problem-file.py <unit-id>
  e.g. Scripts/check-problem-file.py quant-probability.foundations
       Scripts/check-problem-file.py analysis.svc

The tree is inferred from the unit id: a `quant-` prefix means the quant tree
(content-quant/ + content-quant-problems/), anything else the math tree
(content/ + problems/). The file checked is
`<problems root>/<branch>/<subbranch>.yaml`.

The author's half of validation, like check-lesson-file.py (D12.7): runnable
with python3 alone so one author checks one file without contending on the
Swift build. It mirrors `ProblemValidator` + `AnswerCheck.faults` + the LaTeX
allow-list, and adds the *coverage* bar the mastery set needs (§6.7): every
content node of the unit targeted by at least two problems, at least one of
them `demanding` and one `standard` or easier. `ContentBuild validate` remains
the authority and disagreements resolve in its favour.
"""

import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib import import_module  # noqa: E402

lesson_check = import_module("check-lesson-file")
latex_errors = lesson_check.latex_errors
numeric_value = lesson_check.numeric_value

ROOT = Path(__file__).resolve().parent.parent

FIELDS = [
    "id", "kind", "difficulty", "statement", "answer", "rubric", "targets", "exercises",
    "connects", "tags", "expects", "tolerance", "choices", "feedback",
]
KINDS = {"work", "decide", "justify"}
DIFFICULTIES = {"routine", "standard", "demanding"}
CHOICE_FIELDS = ["text", "correct", "feedback"]
KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def tree_roots(unit):
    if unit.startswith("quant-"):
        return ROOT / "content-quant", ROOT / "content-quant-problems"
    return ROOT / "content", ROOT / "problems"


def fail(errors):
    for error in errors:
        print(f"  ✗ {error}")
    print(f"\n{len(errors)} problem(s) — fix and re-run")
    sys.exit(1)


def load_graph(content_root):
    """Every node of the tree, so targets/exercises outside the unit resolve too."""
    nodes = {}
    for path in sorted(content_root.glob("*/*.yaml")):
        data = yaml.safe_load(path.read_text()) or {}
        for node in data.get("nodes") or []:
            nodes[node["id"]] = node
    return nodes


def ancestors(node_id, nodes, memo):
    """Transitive `requires` closure — what `exercises` must lie inside."""
    if node_id in memo:
        return memo[node_id]
    memo[node_id] = set()  # cycle guard; the content validator rejects real cycles
    out = set()
    for r in nodes.get(node_id, {}).get("requires") or []:
        out.add(r)
        out |= ancestors(r, nodes, memo)
    memo[node_id] = out
    return out


def problem_errors(problem, index, nodes, memo, seen_ids):
    where = problem.get("id") or f"problems[{index}]"
    errors = []
    if not isinstance(problem, dict):
        return [f"problems[{index}]: is not a mapping"]

    for key in problem:
        if key not in FIELDS:
            errors.append(f"{where}: unknown field `{key}`")

    pid = problem.get("id")
    if not pid or not isinstance(pid, str) or not KEBAB.match(pid):
        errors.append(f"{where}: id must be lowercase-kebab, one component (no dots)")
    elif pid in seen_ids:
        errors.append(f"{where}: duplicate id")
    else:
        seen_ids.add(pid)

    kind = problem.get("kind", "work")
    if kind not in KINDS:
        errors.append(f"{where}: kind `{kind}` is not one of {sorted(KINDS)}")
    difficulty = problem.get("difficulty", "standard")
    if difficulty not in DIFFICULTIES:
        errors.append(f"{where}: difficulty `{difficulty}` is not one of {sorted(DIFFICULTIES)}")

    statement = (problem.get("statement") or "").strip()
    answer = (problem.get("answer") or "").strip()
    if not statement:
        errors.append(f"{where}: empty statement")
    else:
        errors += latex_errors(f"{where}.statement", statement)
    if not answer:
        errors.append(f"{where}: empty answer")
    else:
        errors += latex_errors(f"{where}.answer", answer)
        if len(answer) < 120:
            errors.append(
                f"{where}: answer is {len(answer)} chars — the reveal is the teaching surface; "
                "show the computation, not just the number"
            )

    rubric = problem.get("rubric")
    if not isinstance(rubric, list) or not rubric or any(
        not isinstance(r, str) or not r.strip() for r in rubric
    ):
        errors.append(f"{where}: needs a rubric — one non-empty criterion per line")
    else:
        for j, criterion in enumerate(rubric):
            errors += latex_errors(f"{where}.rubric[{j}]", criterion)

    targets = problem.get("targets") or []
    exercises = problem.get("exercises") or []
    connects = problem.get("connects") or []
    if not targets:
        errors.append(f"{where}: names no target node")
    for label, ids in [("targets", targets), ("exercises", exercises)]:
        if not isinstance(ids, list):
            errors.append(f"{where}: `{label}` must be a list")
            continue
        if len(set(ids)) != len(ids):
            errors.append(f"{where}: `{label}` repeats an id")
        for nid in ids:
            node = nodes.get(nid)
            if node is None:
                errors.append(f"{where}: {label} unknown node `{nid}`")
            elif node.get("kind") in ("branch", "subbranch"):
                errors.append(f"{where}: {label} `{nid}` is structural — not learnable")
    if isinstance(targets, list) and isinstance(exercises, list):
        for nid in set(targets) & set(exercises):
            errors.append(f"{where}: `{nid}` is both a target and exercised")
        ancestry = set()
        for t in targets:
            ancestry |= ancestors(t, nodes, memo)
        for nid in exercises:
            if nid in nodes and nid not in ancestry and nid not in targets:
                errors.append(
                    f"{where}: exercises `{nid}`, which is not a prerequisite of any target"
                )
    for key in connects:
        ends = [e.strip() for e in str(key).split("~")]
        if len(ends) != 2:
            errors.append(f"{where}: connects `{key}` is not a canonical `a ~ b` key")
            continue
        tagged = set(targets) | set(exercises)
        for end in ends:
            if end not in tagged:
                errors.append(f"{where}: connects `{key}` but neither targets nor exercises `{end}`")
        a, b = ends
        if not a <= b:
            errors.append(
                f"{where}: connects `{key}` is not canonical — RelatesEdge sorts its ends, write `{b} ~ {a}`"
            )
        relates = {r.get("id") if isinstance(r, dict) else r for r in nodes.get(a, {}).get("relates") or []}
        relates_b = {r.get("id") if isinstance(r, dict) else r for r in nodes.get(b, {}).get("relates") or []}
        if b not in relates and a not in relates_b:
            errors.append(f"{where}: connects `{key}`, which is not an authored `relates` edge")

    # §6.7's check, where the problem declares one (AnswerCheck.faults, isRequired: false).
    expects = problem.get("expects")
    expectation = "" if expects is None else str(expects).strip()
    choices = problem.get("choices") or []
    tolerance = problem.get("tolerance")
    feedback = (problem.get("feedback") or "").strip()
    if expects is not None and not isinstance(expects, str):
        errors.append(
            f"{where}: `expects: {expects}` must be quoted — an unquoted number decodes as an "
            "int and fails the build"
        )
    if not choices and not expectation:
        if tolerance is not None or feedback:
            errors.append(f"{where}: carries `tolerance`/`feedback` but no `expects` and no `choices`")
        if kind != "justify":
            errors.append(
                f"{where}: a `{kind}` problem with neither `expects` nor `choices` cannot be "
                "checked — give it a typed answer or choices (only `justify` self-grades)"
            )
    if choices and expectation:
        errors.append(f"{where}: declares both `choices` and `expects`")
    if choices:
        if len(choices) < 2:
            errors.append(f"{where}: has {len(choices)} choice — needs at least two rows")
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
    if feedback:
        errors += latex_errors(f"{where}.feedback", feedback)

    return errors


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    unit = sys.argv[1]
    branch, _, sub = unit.partition(".")
    content_root, problems_root = tree_roots(unit)
    problems_path = problems_root / branch / f"{sub}.yaml"

    if not (content_root / branch / f"{sub}.yaml").exists():
        fail([f"no such unit: {unit}"])
    if not problems_path.exists():
        fail([f"{problems_path} does not exist"])

    nodes = load_graph(content_root)
    try:
        data = yaml.safe_load(problems_path.read_text())
    except yaml.YAMLError as e:
        fail([f"YAML does not parse: {e}"])
    if not isinstance(data, dict) or not isinstance(data.get("problems"), list):
        fail(["top level must be a single `problems:` list"])

    expected = sorted(
        nid for nid, n in nodes.items()
        if n.get("parent") == unit and n.get("kind") not in ("branch", "subbranch")
    )

    errors = []
    memo = {}
    seen_ids = set()
    by_target = {nid: [] for nid in expected}
    foreign = 0
    for i, problem in enumerate(data["problems"]):
        errors += problem_errors(problem, i, nodes, memo, seen_ids)
        if not isinstance(problem, dict):
            continue
        targets = problem.get("targets") or []
        if isinstance(targets, list) and targets and targets[0] not in by_target:
            foreign += 1
        for t in targets if isinstance(targets, list) else []:
            if t in by_target:
                by_target[t].append(problem.get("difficulty", "standard"))

    # The mastery bar (§6.7, content-quant-problems/README.md): every node of the
    # unit carries at least two problems, one of them demanding, so a mastery
    # set never opens with something the lesson just handed over — and one that
    # is not demanding, so the unit test has something fair to ask.
    for nid in expected:
        ds = by_target[nid]
        if len(ds) < 2:
            errors.append(f"{nid}: targeted by {len(ds)} problem(s) — every node needs at least two")
        if ds and "demanding" not in ds:
            errors.append(f"{nid}: no `demanding` problem — the mastery set needs one")
        if ds and all(d == "demanding" for d in ds):
            errors.append(f"{nid}: only `demanding` problems — add a `standard` or `routine` one")
    if foreign:
        errors.append(
            f"{foreign} problem(s) have a primary target outside {unit} — a file holds the "
            "problems whose primary target lives in its unit"
        )

    if errors:
        fail(errors)
    checked = sum(
        1 for p in data["problems"]
        if isinstance(p, dict) and (p.get("expects") is not None or p.get("choices"))
    )
    print(
        f"ok: {unit} — {len(data['problems'])} problems over {len(expected)} nodes "
        f"({checked} machine-checked), all checks pass"
    )


if __name__ == "__main__":
    main()
