#!/usr/bin/env python3
"""
formatting_scorer.py  —  Structure-aware formatting quality scorer.

NOT exact-match. NOT loose semantic.
Checks structural correctness where it matters:
  - List structure (marker presence, item count)
  - Paragraph boundary placement
  - Spoken punctuation intent (?, ,, .)
  - Technical identifier form preservation
  - Sentence count parity

Returns a float 0.0–1.0 per case. Also flags specific structural failures.

Acceptable variants are checked first — if output ∈ {expected} ∪ {variants},
the case gets a perfect score of 1.0 without further structural analysis.
"""

from __future__ import annotations
import re
from dataclasses import dataclass, field
from typing import Optional


# ── Result types ──────────────────────────────────────────────────────────────

@dataclass
class FormattingScore:
    case_id: str
    score: float               # 0.0–1.0
    checks_passed: int = 0
    checks_total: int = 0
    structural_flags: list[str] = field(default_factory=list)
    exact_match: bool = False
    acceptable_variant_match: bool = False


# ── List structure ────────────────────────────────────────────────────────────

_BULLET_PATTERNS = [
    re.compile(r'^[-•*]\s', re.MULTILINE),      # bullet lists
    re.compile(r'^\d+\.\s', re.MULTILINE),       # numbered lists
]


def _count_list_items(text: str) -> int:
    for pat in _BULLET_PATTERNS:
        items = pat.findall(text)
        if items:
            return len(items)
    return 0


def score_list_structure(expected: str, actual: str) -> tuple[float, list[str]]:
    """
    Expected bullet count must match. Extra blank bullets = fail.
    Returns (score 0.0-1.0, flags).
    """
    expected_count = _count_list_items(expected)
    actual_count   = _count_list_items(actual)
    flags = []

    if expected_count == 0:
        # No list expected — actual should not have a list
        if actual_count > 0:
            flags.append(f"unexpected_list:got={actual_count}_items")
            return 0.0, flags
        return 1.0, flags

    if actual_count == 0:
        flags.append(f"list_missing:expected={expected_count}_items")
        return 0.0, flags

    # Allow ±1 item tolerance
    discrepancy = abs(expected_count - actual_count)
    if discrepancy == 0:
        return 1.0, flags
    elif discrepancy == 1:
        flags.append(f"list_item_count_off_by_1:expected={expected_count} got={actual_count}")
        return 0.7, flags
    else:
        flags.append(f"list_item_count_wrong:expected={expected_count} got={actual_count}")
        return 0.3, flags


# ── Paragraph boundaries ──────────────────────────────────────────────────────

def _count_paragraph_breaks(text: str) -> int:
    return len(re.findall(r'\n\n', text))


def score_paragraph_boundaries(expected: str, actual: str) -> tuple[float, list[str]]:
    """
    Double-newline count must match within ±1.
    """
    exp_breaks = _count_paragraph_breaks(expected)
    act_breaks = _count_paragraph_breaks(actual)
    flags = []

    diff = abs(exp_breaks - act_breaks)
    if diff == 0:
        return 1.0, flags
    elif diff == 1:
        flags.append(f"paragraph_breaks_off_by_1:expected={exp_breaks} got={act_breaks}")
        return 0.7, flags
    else:
        flags.append(f"paragraph_breaks_wrong:expected={exp_breaks} got={act_breaks}")
        return 0.3, flags


# ── Punctuation intent ────────────────────────────────────────────────────────

def score_punctuation_intent(expected: str, actual: str) -> tuple[float, list[str]]:
    """
    Check that key punctuation marks are present in approximately correct positions.
    Expected ? → actual should have ?
    Expected ! → actual should have !
    Expected , count → actual within ±2
    """
    flags = []
    scores = []

    # Question mark
    if "?" in expected:
        if "?" not in actual:
            flags.append("missing_question_mark")
            scores.append(0.0)
        else:
            scores.append(1.0)

    # Exclamation
    if "!" in expected:
        if "!" not in actual:
            flags.append("missing_exclamation")
            scores.append(0.5)
        else:
            scores.append(1.0)

    # Comma count (loose)
    exp_commas = expected.count(",")
    act_commas = actual.count(",")
    if exp_commas > 0:
        diff = abs(exp_commas - act_commas)
        if diff <= 2:
            scores.append(1.0)
        else:
            flags.append(f"comma_count_off:expected={exp_commas} got={act_commas}")
            scores.append(max(0.3, 1.0 - diff * 0.2))

    if not scores:
        return 1.0, flags
    return sum(scores) / len(scores), flags


# ── Technical identifier form ─────────────────────────────────────────────────

_CAMEL_RE        = re.compile(r'\b[a-z][A-Za-z0-9]*[A-Z][A-Za-z0-9]*\b')
_SNAKE_RE        = re.compile(r'\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b')
_SCREAMING_RE    = re.compile(r'\b[A-Z][A-Z0-9_]{2,}\b')
_VERSION_RE      = re.compile(r'\b\d+\.\d+(?:\.\d+)*\b')


def _extract_technical_tokens(text: str) -> set[str]:
    tokens: set[str] = set()
    for pat in (_CAMEL_RE, _SNAKE_RE, _SCREAMING_RE, _VERSION_RE):
        tokens.update(pat.findall(text))
    return tokens


def score_technical_form(expected: str, actual: str) -> tuple[float, list[str]]:
    """
    Technical identifiers (camelCase, snake_case, SCREAMING_CAPS, semver)
    in the expected output must also appear in actual with exact form.
    """
    expected_tokens = _extract_technical_tokens(expected)
    flags = []

    if not expected_tokens:
        return 1.0, flags

    missing = []
    for tok in expected_tokens:
        if tok not in actual:
            if tok.lower() in actual.lower():
                flags.append(f"technical_form_case_wrong:{tok!r}")
            else:
                flags.append(f"technical_form_missing:{tok!r}")
            missing.append(tok)

    score = 1.0 - (len(missing) / len(expected_tokens))
    return max(0.0, score), flags


# ── Sentence count ────────────────────────────────────────────────────────────

_SENT_END_RE = re.compile(r'[.!?]\s')


def _sentence_count(text: str) -> int:
    return max(1, len(_SENT_END_RE.findall(text)) + 1)


def score_sentence_count(expected: str, actual: str) -> tuple[float, list[str]]:
    """±1 sentence tolerance."""
    exp_count = _sentence_count(expected)
    act_count = _sentence_count(actual)
    flags = []
    diff = abs(exp_count - act_count)
    if diff == 0:
        return 1.0, flags
    elif diff == 1:
        return 0.8, flags
    else:
        flags.append(f"sentence_count_off:expected={exp_count} got={act_count}")
        return max(0.4, 1.0 - diff * 0.15), flags


# ── Main scorer ───────────────────────────────────────────────────────────────

# Weights for each structural dimension
_WEIGHTS = {
    "list":          0.30,
    "paragraph":     0.20,
    "punctuation":   0.25,
    "technical":     0.15,
    "sentence":      0.10,
}


def score_formatting(record: dict) -> FormattingScore:
    """
    Compute structure-aware formatting score for a single EvalRunRecord.
    Returns FormattingScore with composite 0.0-1.0 and per-dimension flags.
    """
    case_id   = record.get("caseID", "unknown")
    expected  = record.get("finalExpectedText", "")
    actual    = record.get("finalText", "")
    variants  = record.get("acceptableVariants", [])

    # Exact match or acceptable variant → perfect score
    if actual == expected or actual in variants:
        return FormattingScore(
            case_id=case_id,
            score=1.0,
            checks_passed=5,
            checks_total=5,
            exact_match=(actual == expected),
            acceptable_variant_match=(actual in variants and actual != expected),
        )

    all_flags: list[str] = []
    component_scores: dict[str, float] = {}

    list_score, list_flags         = score_list_structure(expected, actual)
    para_score, para_flags         = score_paragraph_boundaries(expected, actual)
    punct_score, punct_flags       = score_punctuation_intent(expected, actual)
    tech_score, tech_flags         = score_technical_form(expected, actual)
    sent_score, sent_flags         = score_sentence_count(expected, actual)

    component_scores = {
        "list":        list_score,
        "paragraph":   para_score,
        "punctuation": punct_score,
        "technical":   tech_score,
        "sentence":    sent_score,
    }
    all_flags = list_flags + para_flags + punct_flags + tech_flags + sent_flags

    composite = sum(_WEIGHTS[k] * v for k, v in component_scores.items())
    passed    = sum(1 for v in component_scores.values() if v >= 0.9)

    result = FormattingScore(
        case_id=case_id,
        score=composite,
        checks_passed=passed,
        checks_total=len(component_scores),
        structural_flags=all_flags,
    )
    return result


def score_all_formatting(records: list[dict]) -> list[FormattingScore]:
    return [score_formatting(r) for r in records]


def formatting_summary(scores: list[FormattingScore]) -> dict:
    if not scores:
        return {}
    mean_score = sum(s.score for s in scores) / len(scores)
    exact_matches = sum(1 for s in scores if s.exact_match)
    variant_matches = sum(1 for s in scores if s.acceptable_variant_match)
    return {
        "mean_formatting_score": mean_score,
        "exact_match_count": exact_matches,
        "acceptable_variant_count": variant_matches,
        "total": len(scores),
        "top_flags": _top_flags(scores),
    }


def _top_flags(scores: list[FormattingScore], n: int = 10) -> list[str]:
    from collections import Counter
    c: Counter = Counter()
    for s in scores:
        for f in s.structural_flags:
            # Normalize: strip the specifics for aggregation
            key = f.split(":")[0]
            c[key] += 1
    return [f"{k}: {v}" for k, v in c.most_common(n)]
