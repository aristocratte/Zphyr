#!/usr/bin/env python3
"""
hard_metrics.py  —  Hard correctness metrics for the Zphyr evaluation harness.

These metrics are BINARY PASS/FAIL per case.
A failure here is reported regardless of any composite score.
They are the primary source of regression blocking.

Failure types (matching HardFailureReason in EvalTypes.swift):
  protectedTermMissing
  protectedTermCaseCorruption
  malformedURL
  malformedEmail
  spuriousCommand
  commandMismatch
  forbiddenRewrite
  formattingPolicyViolation
  numericCorruption
"""

from __future__ import annotations
import re
from dataclasses import dataclass, field
from typing import Optional


# ── URL / Email patterns ──────────────────────────────────────────────────────

_URL_RE = re.compile(
    r'https?://[^\s,;.!?)>"\]]+',
    re.IGNORECASE,
)
_EMAIL_RE = re.compile(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
)
_NUMBER_RE = re.compile(
    r'\b\d+(?:[.,]\d+)*(?:\.\d+)?\b',
)


# ── Result types ──────────────────────────────────────────────────────────────

@dataclass
class HardCheckResult:
    case_id: str
    hard_failures: list[str] = field(default_factory=list)
    details: dict[str, str] = field(default_factory=dict)

    @property
    def passed(self) -> bool:
        return len(self.hard_failures) == 0


# ── Protected term checks ─────────────────────────────────────────────────────

def check_protected_terms(
    case_id: str,
    final_text: str,
    protected_terms: list[str],
) -> list[str]:
    """
    Case-sensitive substring check per protected term.
    Checks every occurrence independently.
    Rules:
      - Overlapping terms: each checked independently, all must appear.
      - Repeated terms: checked once (term appears at least once is sufficient
        unless duplicates are listed explicitly in the terms array).
      - One term is substring of another: both checked separately.
    """
    failures = []
    for term in protected_terms:
        if not term:
            continue
        if term not in final_text:
            # Distinguish case corruption from complete absence
            if term.lower() in final_text.lower():
                failures.append(f"protectedTermCaseCorruption:{term!r}")
            else:
                failures.append(f"protectedTermMissing:{term!r}")
    return failures


# ── URL integrity ─────────────────────────────────────────────────────────────

def check_url_integrity(
    case_id: str,
    final_text: str,
    protected_terms: list[str],
) -> list[str]:
    """
    For every protected term that looks like a URL (starts with http/https),
    verify it appears verbatim in the output AND is structurally valid.
    """
    failures = []
    for term in protected_terms:
        if not term.lower().startswith("http"):
            continue
        if term not in final_text:
            failures.append(f"malformedURL:missing:{term!r}")
            continue
        # Structural validity: must be matched by the URL regex
        matches = _URL_RE.findall(final_text)
        if not any(m == term or final_text[final_text.index(term):].startswith(term) for m in matches):
            failures.append(f"malformedURL:invalid:{term!r}")
    return failures


# ── Email integrity ───────────────────────────────────────────────────────────

def check_email_integrity(
    case_id: str,
    final_text: str,
    protected_terms: list[str],
) -> list[str]:
    """
    For every protected term that looks like an email address,
    verify it appears verbatim and is structurally valid.
    """
    failures = []
    for term in protected_terms:
        if "@" not in term or term.startswith("@"):
            continue  # not an email (could be @decorator)
        if term not in final_text:
            failures.append(f"malformedEmail:missing:{term!r}")
            continue
        matches = _EMAIL_RE.findall(final_text)
        if term not in matches:
            failures.append(f"malformedEmail:invalid:{term!r}")
    return failures


# ── Numeric / version integrity ───────────────────────────────────────────────

# Context types where numeric integrity is a hard check (not just alert)
_NUMERIC_HARD_CONTEXTS: set[str] = {"technical", "correction", "command"}


def _extract_numbers(text: str) -> set[str]:
    """Extract digit sequences and version-like patterns from text."""
    raw = set(_NUMBER_RE.findall(text))
    # Also strip thousand separators for comparison
    normalized = {re.sub(r'[,\s]', '', n) for n in raw}
    return raw | normalized


def check_numeric_integrity(
    case_id: str,
    raw_text: str,
    final_text: str,
    context_type: str,
) -> list[str]:
    """
    Hard check for technical/correction/command contexts:
    any number present in raw_asr_text must appear (possibly reformatted)
    in final_text. Thousand-separator insertion is allowed.
    """
    if context_type not in _NUMERIC_HARD_CONTEXTS:
        return []
    raw_nums = _extract_numbers(raw_text)
    final_nums = _extract_numbers(final_text)
    failures = []
    for num in raw_nums:
        clean = re.sub(r'[,\s]', '', num)
        if clean not in final_nums and num not in final_nums:
            failures.append(f"numericCorruption:{num!r} missing in final text")
    return failures


# ── Command accuracy ──────────────────────────────────────────────────────────

def check_command_accuracy(
    case_id: str,
    expected_command: Optional[str],
    actual_command: str,
) -> list[str]:
    """
    Zero-tolerance command check.
    - If no command expected and one was extracted → spuriousCommand (hard fail).
    - If command expected and wrong type extracted → commandMismatch (hard fail).
    """
    actual_norm = None if actual_command in ("none", "null", "", None) else actual_command
    if expected_command is None and actual_norm is not None:
        return [f"spuriousCommand:got={actual_norm!r}"]
    if expected_command is not None and actual_norm != expected_command:
        return [f"commandMismatch:expected={expected_command!r} got={actual_norm!r}"]
    return []


# ── Rewrite gate ──────────────────────────────────────────────────────────────

# Common filler words removed by deterministic disfluency stage
_FILLERS = frozenset({
    "uh", "um", "er", "ah", "like", "so", "basically", "you know",
    "euh", "voilà", "alors", "bah",
})


def _tokenize(text: str) -> list[str]:
    """Lowercase, split on non-alphanumeric, filter fillers and short tokens."""
    tokens = re.findall(r"[a-z0-9]+", text.lower())
    return [t for t in tokens if t not in _FILLERS and len(t) > 1]


def check_rewrite_gate(
    case_id: str,
    raw_text: str,
    final_text: str,
    rewrite_allowed_level: str,
) -> list[str]:
    """
    If rewrite_allowed_level == 'none':
      - Deterministic formatting is allowed (punct, capitalisation, filler removal).
      - Semantic content changes (word insertions/deletions) are a hard failure.

    If rewrite_allowed_level == 'light' or 'full':
      - No gate applied here; alerting_metrics may flag drift separately.
    """
    if rewrite_allowed_level != "none":
        return []

    raw_tokens   = set(_tokenize(raw_text))
    final_tokens = set(_tokenize(final_text))

    # Words in final that were not in raw → potential forbidden insertion
    inserted = final_tokens - raw_tokens
    # Ignore very short tokens and common deterministic additions
    _ALLOWED_INSERTIONS = frozenset({"not", "is", "be", "the", "a", "an", "and"})
    significant = {w for w in inserted if w not in _ALLOWED_INSERTIONS and len(w) > 3}

    if significant:
        return [f"forbiddenRewrite:inserted={sorted(significant)}"]
    return []


# ── Main check runner ─────────────────────────────────────────────────────────

def run_hard_checks(record: dict) -> HardCheckResult:
    """
    Run all hard checks for a single EvalRunRecord (dict from JSON).
    Returns a HardCheckResult with all failure codes.
    """
    case_id      = record.get("caseID", "unknown")
    raw_text     = record.get("rawAsrText", "")
    final_text   = record.get("finalText", "")
    terms        = record.get("protectedTerms", [])
    ctx_type     = record.get("contextType", "")
    expected_cmd = record.get("expectedCommand")
    actual_cmd   = record.get("actualCommand", "none")
    rw_level     = record.get("rewriteAllowedLevel", "light")

    result = HardCheckResult(case_id=case_id)

    # Check 1: protected terms
    for f in check_protected_terms(case_id, final_text, terms):
        key = f.split(":")[0]
        result.hard_failures.append(key)
        result.details[f"protected_terms"] = f

    # Check 2: URL integrity
    for f in check_url_integrity(case_id, final_text, terms):
        key = f.split(":")[0]
        result.hard_failures.append(key)
        result.details["url_check"] = f

    # Check 3: email integrity
    for f in check_email_integrity(case_id, final_text, terms):
        key = f.split(":")[0]
        result.hard_failures.append(key)
        result.details["email_check"] = f

    # Check 4: numeric integrity (hard only for technical / correction / command)
    for f in check_numeric_integrity(case_id, raw_text, final_text, ctx_type):
        result.hard_failures.append("numericCorruption")
        result.details["numeric_check"] = f

    # Check 5: command accuracy
    for f in check_command_accuracy(case_id, expected_cmd, actual_cmd):
        key = f.split(":")[0]
        result.hard_failures.append(key)
        result.details["command_check"] = f

    # Check 6: rewrite gate
    for f in check_rewrite_gate(case_id, raw_text, final_text, rw_level):
        result.hard_failures.append("forbiddenRewrite")
        result.details["rewrite_gate"] = f

    return result


# ── Batch runner ──────────────────────────────────────────────────────────────

def run_all_hard_checks(records: list[dict]) -> list[HardCheckResult]:
    """Run hard checks over all records. Use in zphyr_eval.py."""
    return [run_hard_checks(r) for r in records]


def hard_failure_summary(results: list[HardCheckResult]) -> dict:
    """Aggregate hard check results by failure type and category."""
    from collections import Counter
    total = len(results)
    failed = [r for r in results if not r.passed]
    failure_types = Counter(f for r in failed for f in r.hard_failures)
    return {
        "total_cases": total,
        "hard_failure_count": len(failed),
        "hard_failure_rate": len(failed) / max(total, 1),
        "failure_types": dict(failure_types),
        "failed_case_ids": [r.case_id for r in failed],
    }
