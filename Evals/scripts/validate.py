#!/usr/bin/env python3
"""
Zphyr Training Dataset Validator — v1

Validates JSONL files in Evals/datasets/raw/seed/ against the v1 training schema.
Does NOT validate eval harness files in Evals/datasets/*.jsonl (different schema).

Training schema: Evals/datasets/schema/training.json
Eval schema: Evals/datasets/schema/eval.json

Usage:
  python validate.py <file.jsonl> [<file2.jsonl> ...]
  python validate.py Evals/datasets/raw/seed/*.jsonl
  python validate.py --verbose Evals/datasets/raw/seed/seed_technical.jsonl
  python validate.py --no-dedup Evals/datasets/raw/seed/*.jsonl
  python validate.py --errors-only Evals/datasets/raw/seed/*.jsonl

Exit codes:
  0  All files pass (no errors). Warnings may be present.
  1  One or more files have errors, or duplicate IDs found.
"""

import json
import sys
import argparse
from pathlib import Path
from dataclasses import dataclass, field
from collections import defaultdict
from typing import Optional


# ── Schema constants ───────────────────────────────────────────────────────────

REQUIRED_FIELDS = [
    "id",
    "raw_asr_text",
    "final_expected_text",
    "category",
    "subcategory",
    "language",
    "rewrite_allowed_level",
    "is_null_edit",
    "difficulty",
    "severity_if_wrong",
    "source_type",
]

VALID_CATEGORIES: dict[str, list[str]] = {
    "prose":        ["email_body", "chat", "notes", "long_form", "prompt_query", "informal"],
    "short":        ["short_sentence", "single_word_phrase", "title", "filename_tag", "near_empty"],
    "multilingual": ["fr_primary_en_terms", "en_primary_fr_terms", "code_switching",
                     "quoted_foreign", "other_pairs"],
    "lists":        ["numbered_spoken", "bulleted_spoken", "structured_outline",
                     "inline_enumeration", "no_list_ambiguous"],
    "technical":    ["code_identifiers", "terminal_commands", "urls_paths",
                     "package_names", "config_env_vars", "version_numbers", "data_values"],
    "corrections":  ["filler_removal", "word_repetition", "spoken_restart",
                     "filler_and_repetition", "intentional_repetition"],
    "commands":     ["trigger_mode", "spoken_punctuation", "formatting_commands",
                     "navigation_commands", "ambiguous_command_content"],
    "null_edits":   ["already_correct", "short_passthrough",
                     "technical_passthrough", "multilingual_passthrough"],
}

VALID_REWRITE_LEVELS  = ["no_edit", "punctuation_only", "light_polish"]
VALID_DIFFICULTIES    = ["easy", "medium", "hard"]
VALID_SEVERITIES      = ["low", "medium", "high", "critical"]
VALID_SOURCES         = ["hand_written", "semi_synthetic", "synthetic", "eval_derived"]
VALID_LANGUAGES       = ["fr", "en", "es", "zh", "ja", "ru", "mixed"]
VALID_ARTIFACT_TYPES  = frozenset(["filler_word", "repetition", "split_word",
                                    "wrong_number", "hallucination"])
VALID_CONSTRAINTS     = frozenset(f"CONSTRAINT-{i:02d}" for i in range(1, 11))
VALID_CONFIDENCES     = ["high", "medium", "low"]
VALID_REVIEW_STATUSES = ["draft", "approved", "rejected", "needs_review"]

# null_edits must use no_edit level
NULL_EDIT_CATEGORIES = {"null_edits"}

# Categories where length increase is expected (list formatting expands output)
LENGTH_EXEMPT_CATEGORIES = {"lists"}

# Categories that should always declare protected_terms
PROTECTED_REQUIRED_CATEGORIES = {"technical"}


# ── Data model ─────────────────────────────────────────────────────────────────

@dataclass
class Issue:
    code: str    # e.g. "R-07"
    level: str   # "ERROR" or "WARN"
    message: str

    def __str__(self) -> str:
        return f"{self.code}  {self.message}"


@dataclass
class RowResult:
    row_id: str
    line_number: int
    issues: list[Issue] = field(default_factory=list)

    @property
    def errors(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "ERROR"]

    @property
    def warnings(self) -> list[Issue]:
        return [i for i in self.issues if i.level == "WARN"]

    @property
    def is_valid(self) -> bool:
        return not self.errors

    @property
    def has_warnings(self) -> bool:
        return bool(self.warnings)


@dataclass
class FileReport:
    filepath: str
    results: list[RowResult] = field(default_factory=list)
    parse_errors: list[tuple[int, str]] = field(default_factory=list)

    @property
    def total_rows(self) -> int:
        return len(self.results)

    @property
    def valid_rows(self) -> int:
        return sum(1 for r in self.results if r.is_valid)

    @property
    def error_rows(self) -> int:
        return self.total_rows - self.valid_rows

    @property
    def warned_rows(self) -> int:
        return sum(1 for r in self.results if r.has_warnings and r.is_valid)


# ── Validation helpers ─────────────────────────────────────────────────────────

def _e(result: RowResult, code: str, msg: str) -> None:
    """Append an ERROR issue."""
    result.issues.append(Issue(code=code, level="ERROR", message=msg))


def _w(result: RowResult, code: str, msg: str) -> None:
    """Append a WARNING issue."""
    result.issues.append(Issue(code=code, level="WARN", message=msg))


# ── Core row validation ────────────────────────────────────────────────────────

def validate_row(row: dict, line_number: int) -> RowResult:
    """Validate a single parsed row. Returns a RowResult with all issues found."""
    row_id = str(row.get("id", f"<no-id @ line {line_number}>"))
    result = RowResult(row_id=row_id, line_number=line_number)

    # ── R-01  Required fields ──────────────────────────────────────────────────
    missing = [f for f in REQUIRED_FIELDS if f not in row or row[f] is None]
    for f in missing:
        _e(result, "R-01", f"MISSING_REQUIRED  field='{f}'")
    if missing:
        # Skip remaining checks — too noisy without required fields
        return result

    raw     = str(row["raw_asr_text"])
    exp     = str(row["final_expected_text"])
    cat     = str(row["category"])
    sub     = str(row["subcategory"])
    is_null = row["is_null_edit"]

    # ── R-02  ID format ────────────────────────────────────────────────────────
    if not str(row["id"]).startswith("zphyr-"):
        _w(result, "R-02",
           f"ID_FORMAT  id='{row['id']}' should start with 'zphyr-' "
           f"(format: zphyr-{{category}}-{{subcategory_short}}-{{NNN}})")

    # ── R-03  is_null_edit must be boolean ────────────────────────────────────
    if not isinstance(is_null, bool):
        _e(result, "R-03",
           f"IS_NULL_EDIT_TYPE  expected bool, got {type(is_null).__name__}='{is_null}'")
        is_null = bool(is_null)  # coerce for further checks

    # ── R-04  Category / subcategory ──────────────────────────────────────────
    if cat not in VALID_CATEGORIES:
        _e(result, "R-04",
           f"INVALID_CATEGORY  '{cat}'  valid: {sorted(VALID_CATEGORIES.keys())}")
    elif sub not in VALID_CATEGORIES[cat]:
        _e(result, "R-04",
           f"INVALID_SUBCATEGORY  '{sub}' is not valid for category='{cat}'  "
           f"valid: {VALID_CATEGORIES[cat]}")

    # ── R-05  Enum fields ──────────────────────────────────────────────────────
    for fname, valid_set in [
        ("rewrite_allowed_level", VALID_REWRITE_LEVELS),
        ("difficulty",            VALID_DIFFICULTIES),
        ("severity_if_wrong",     VALID_SEVERITIES),
        ("source_type",           VALID_SOURCES),
        ("language",              VALID_LANGUAGES),
    ]:
        val = row.get(fname)
        if val not in valid_set:
            _e(result, "R-05",
               f"INVALID_ENUM  {fname}='{val}'  valid={valid_set}")

    # ── R-06  null_edits category must use no_edit level ──────────────────────
    if cat in NULL_EDIT_CATEGORIES and row.get("rewrite_allowed_level") != "no_edit":
        _e(result, "R-06",
           f"NULL_EDIT_CATEGORY_WRONG_LEVEL  "
           f"category='null_edits' requires rewrite_allowed_level='no_edit', "
           f"got '{row.get('rewrite_allowed_level')}'")

    # ── R-07  Null edit flag consistency ──────────────────────────────────────
    if is_null and raw != exp:
        _e(result, "R-07",
           "NULL_EDIT_MISMATCH  is_null_edit=true but "
           "raw_asr_text != final_expected_text (must be byte-identical)")
    if not is_null and raw == exp:
        _w(result, "R-07",
           "UNTAGGED_NULL_EDIT  raw == expected but is_null_edit=false — "
           "should is_null_edit be true?")

    # ── R-08  no_edit rewrite level requires null content ─────────────────────
    if row.get("rewrite_allowed_level") == "no_edit" and raw != exp:
        _e(result, "R-08",
           "NO_EDIT_LEVEL_HAS_CHANGES  rewrite_allowed_level='no_edit' "
           "but raw_asr_text != final_expected_text")

    # ── R-09  Protected terms verbatim in both fields ─────────────────────────
    for term in row.get("protected_terms", []):
        if not isinstance(term, str) or not term:
            _e(result, "R-09",
               f"INVALID_PROTECTED_TERM  must be non-empty string, got: {term!r}")
            continue
        if term not in raw:
            _e(result, "R-09",
               f"PROTECTED_TERM_ABSENT_FROM_RAW  '{term}'  "
               f"(must appear verbatim in raw_asr_text)")
        if term not in exp:
            _e(result, "R-09",
               f"PROTECTED_TERM_ABSENT_FROM_EXPECTED  '{term}'  "
               f"(must appear verbatim in final_expected_text)")

    # ── R-10  Technical category should declare protected_terms ───────────────
    if cat in PROTECTED_REQUIRED_CATEGORIES and not row.get("protected_terms"):
        _w(result, "R-10",
           "MISSING_PROTECTED_TERMS  category='technical' has no protected_terms — "
           "add all technical tokens that must survive verbatim")

    # ── R-11  Multilingual must have no_translation=true ─────────────────────
    if cat == "multilingual" and row.get("no_translation") is False:
        _e(result, "R-11",
           "TRANSLATION_ALLOWED_IN_MULTILINGUAL  "
           "no_translation must be true for category='multilingual'")

    # ── R-12  Output word count (non-list categories) ─────────────────────────
    if cat not in LENGTH_EXEMPT_CATEGORIES:
        raw_wc = len(raw.split())
        exp_wc = len(exp.split())
        if raw_wc > 3 and exp_wc > raw_wc * 1.4:
            _w(result, "R-12",
               f"SUSPICIOUS_LENGTH_INCREASE  "
               f"raw={raw_wc}w → expected={exp_wc}w "
               f"(+{exp_wc - raw_wc} words, {(exp_wc/raw_wc - 1)*100:.0f}% increase)  "
               f"did the model add content?")

    # ── R-13  Possible added content words ────────────────────────────────────
    if cat not in LENGTH_EXEMPT_CATEGORIES and not is_null:
        # Normalize apostrophes, strip punctuation, tokenize
        def normalize(text: str) -> set[str]:
            t = text.lower().replace("\u2019", " ").replace("'", " ")
            return {tok.strip(".,!?:;-–—") for tok in t.split() if len(tok) > 2}
        raw_tokens = normalize(raw)
        exp_tokens = normalize(exp)
        added = exp_tokens - raw_tokens
        # Filter structural tokens: numbers, list markers, short tokens
        added_content = [w for w in added if any(c.isalpha() for c in w) and len(w) > 2]
        if added_content:
            _w(result, "R-13",
               f"POSSIBLE_ADDED_WORDS  words in expected not found in raw: "
               f"{sorted(added_content)[:5]}  "
               f"(verify these are not spurious additions)")

    # ── R-14  Acceptable variants ─────────────────────────────────────────────
    variants = row.get("acceptable_variants", [])
    if not isinstance(variants, list):
        _e(result, "R-14",
           "ACCEPTABLE_VARIANTS_NOT_LIST  must be an array (even if empty)")
    else:
        if len(variants) > 3:
            _w(result, "R-14",
               f"TOO_MANY_VARIANTS  {len(variants)} variants (max 3) — "
               "if more than 3 outputs are correct, the example is too ambiguous")
        for i, v in enumerate(variants):
            if v == exp:
                _w(result, "R-14",
                   f"VARIANT_EQUALS_EXPECTED  acceptable_variants[{i}] is identical "
                   "to final_expected_text (redundant — remove it)")
            if not is_null and v == raw:
                _w(result, "R-14",
                   f"VARIANT_EQUALS_RAW  acceptable_variants[{i}] equals raw_asr_text "
                   "(only valid when is_null_edit=true)")

    # ── R-15  Artifact type validity ──────────────────────────────────────────
    for t in row.get("asr_artifact_types", []):
        if t not in VALID_ARTIFACT_TYPES:
            _e(result, "R-15",
               f"INVALID_ARTIFACT_TYPE  '{t}'  "
               f"valid: {sorted(VALID_ARTIFACT_TYPES)}")

    # ── R-16  Artifact flag consistency ───────────────────────────────────────
    has_artifact  = row.get("has_asr_artifact", False)
    artifact_types = row.get("asr_artifact_types", [])
    if has_artifact and not artifact_types:
        _w(result, "R-16",
           "ARTIFACT_TYPE_MISSING  has_asr_artifact=true but asr_artifact_types is empty")
    if not has_artifact and artifact_types:
        _w(result, "R-16",
           "ARTIFACT_FLAG_MISSING  asr_artifact_types is populated but has_asr_artifact=false")

    # ── R-17  Constraint ID format ────────────────────────────────────────────
    for cid in row.get("constraint_ids", []):
        if cid not in VALID_CONSTRAINTS:
            _w(result, "R-17",
               f"INVALID_CONSTRAINT_ID  '{cid}'  "
               "valid format: CONSTRAINT-01 through CONSTRAINT-10")

    # ── R-18  Low confidence must be resolved before merging ──────────────────
    if row.get("annotation_confidence") == "low":
        _w(result, "R-18",
           "LOW_CONFIDENCE  annotation_confidence='low' — "
           "must be resolved (rewrite or reject) before adding to any split")

    # ── R-19  Raw text should not end with sentence punctuation (non-null) ────
    if not is_null and raw.rstrip().endswith((".", "!", "?")):
        _w(result, "R-19",
           "RAW_HAS_TERMINAL_PUNCT  raw_asr_text ends with sentence punctuation — "
           "verify this is realistic Whisper output "
           "(acceptable for null_edits; unusual for other categories)")

    # ── R-20  Technical passthrough null edits should have protected_terms ────
    if cat == "null_edits" and sub == "technical_passthrough":
        if not row.get("protected_terms"):
            _w(result, "R-20",
               "TECHNICAL_NULL_EDIT_NO_TERMS  technical_passthrough without protected_terms — "
               "add the technical tokens being protected verbatim")

    # ── R-21  eval_derived source must be flagged for test split ──────────────
    if row.get("source_type") == "eval_derived":
        _w(result, "R-21",
           "EVAL_DERIVED_SOURCE  eval_derived examples must go to test split only — "
           "never include in train or val")

    return result


# ── Cross-file checks ──────────────────────────────────────────────────────────

def check_duplicate_ids(
    all_results: list[tuple[str, RowResult]],
) -> list[str]:
    """Find duplicate IDs across all validated files."""
    seen: dict[str, list[str]] = defaultdict(list)
    for filepath, result in all_results:
        seen[result.row_id].append(filepath)
    return [
        f"DUPLICATE_ID  id='{id_val}'  found in: {files}"
        for id_val, files in seen.items()
        if len(files) > 1
    ]


def _ngrams(text: str, n: int) -> set[tuple[str, ...]]:
    words = text.lower().split()
    return set(tuple(words[i:i + n]) for i in range(max(0, len(words) - n + 1)))


def jaccard(t1: str, t2: str, n: int = 3) -> float:
    """N-gram Jaccard similarity for near-duplicate detection."""
    s1, s2 = _ngrams(t1, n), _ngrams(t2, n)
    if not s1 and not s2:
        # Both texts too short to generate n-grams — use exact match instead
        return 1.0 if t1.lower().strip() == t2.lower().strip() else 0.0
    if not s1 or not s2:
        return 0.0
    return len(s1 & s2) / len(s1 | s2)


def check_near_duplicates(
    rows: list[dict],
    threshold: float = 0.7,
) -> list[str]:
    """
    O(n²) pairwise near-duplicate check on raw_asr_text.
    Only run on datasets <= 5000 rows. Use --no-dedup for larger files.
    Near-duplicate pairs should be assigned to the same split (not cross-split).
    """
    pairs = [(r.get("id", ""), r.get("raw_asr_text", "")) for r in rows]
    results = []
    for i in range(len(pairs)):
        for j in range(i + 1, len(pairs)):
            sim = jaccard(pairs[i][1], pairs[j][1])
            if sim >= threshold:
                results.append(
                    f"NEAR_DUPLICATE  similarity={sim:.2f}  "
                    f"'{pairs[i][0]}' ↔ '{pairs[j][0]}'  "
                    f"(assign to same split to prevent leakage)"
                )
    return results


# ── File processing ────────────────────────────────────────────────────────────

def validate_file(filepath: Path) -> tuple[FileReport, list[dict]]:
    """
    Parse and validate a JSONL file.
    Returns (FileReport, list of successfully parsed rows).
    """
    report = FileReport(filepath=str(filepath))
    rows: list[dict] = []

    with open(filepath, encoding="utf-8-sig") as f:
        for lineno, raw_line in enumerate(f, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
                if not isinstance(row, dict):
                    report.parse_errors.append(
                        (lineno, f"Expected JSON object, got {type(row).__name__}")
                    )
                    continue
                rows.append(row)
                report.results.append(validate_row(row, lineno))
            except json.JSONDecodeError as exc:
                report.parse_errors.append((lineno, str(exc)))

    return report, rows


# ── Terminal output ────────────────────────────────────────────────────────────

_USE_COLOR = sys.stdout.isatty()

def _c(ansi: str, text: str) -> str:
    return f"\033[{ansi}m{text}\033[0m" if _USE_COLOR else text

RED    = "31"
YELLOW = "33"
GREEN  = "32"
BOLD   = "1"
DIM    = "2"


def print_file_report(
    report: FileReport,
    *,
    verbose: bool,
    errors_only: bool,
) -> None:
    ok = report.error_rows == 0 and not report.parse_errors
    status = _c(GREEN, "✓") if ok else _c(RED, "✗")
    name = _c(BOLD, report.filepath)
    print(f"\n{status} {name}")
    print(
        f"   {report.total_rows} rows  •  "
        f"{_c(GREEN, str(report.valid_rows))} valid  •  "
        f"{_c(RED, str(report.error_rows))} errors  •  "
        f"{_c(YELLOW, str(report.warned_rows))} warnings"
    )

    for lineno, msg in report.parse_errors:
        print(f"   {_c(RED, 'PARSE ERROR')} line {lineno}: {msg}")

    for res in report.results:
        if not res.errors and not res.warnings:
            if verbose:
                print(f"   {_c(DIM, '✓ ' + res.row_id)}")
            continue

        if errors_only and not res.errors:
            continue

        print(f"\n   {_c(BOLD, res.row_id)}  {_c(DIM, f'(line {res.line_number})')}")
        for issue in res.issues:
            if issue.level == "ERROR":
                print(f"     {_c(RED, 'ERROR')}  {issue}")
            elif not errors_only:
                print(f"     {_c(YELLOW, 'WARN ')}  {issue}")


def print_summary(
    reports: list[FileReport],
    dup_errors: list[str],
    near_dup_warnings: list[str],
) -> None:
    total  = sum(r.total_rows for r in reports)
    valid  = sum(r.valid_rows for r in reports)
    warned = sum(r.warned_rows for r in reports)
    errors = total - valid

    print(f"\n{'─' * 60}")
    print(_c(BOLD, "SUMMARY"))
    print(f"  Files   {len(reports)}")
    print(f"  Rows    {total}")
    if total:
        pct = valid / total * 100
        print(f"  Valid   {_c(GREEN, str(valid))}  ({pct:.1f}%)")
    print(f"  Errors  {_c(RED, str(errors))}")
    print(f"  Warned  {_c(YELLOW, str(warned))}")

    if dup_errors:
        print(f"\n  {_c(RED, f'DUPLICATE IDs  ({len(dup_errors)})')}")
        for msg in dup_errors:
            print(f"    {_c(RED, '✗')} {msg}")

    if near_dup_warnings:
        print(f"\n  {_c(YELLOW, f'NEAR DUPLICATES  ({len(near_dup_warnings)})')}")
        for msg in near_dup_warnings[:10]:
            print(f"    {_c(YELLOW, '~')} {msg}")
        if len(near_dup_warnings) > 10:
            print(f"    {_c(DIM, f'... and {len(near_dup_warnings) - 10} more')}")

    blocking = errors + len(dup_errors)
    print()
    if blocking == 0:
        print(f"  {_c(f'{BOLD};{GREEN}', 'All checks passed.')}")
    else:
        print(f"  {_c(f'{BOLD};{RED}', f'{blocking} blocking issue(s) must be resolved before split.')}")


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "files", nargs="+",
        help="JSONL file(s) to validate (training schema only)",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Show passing rows in output",
    )
    parser.add_argument(
        "--errors-only", action="store_true",
        help="Suppress warnings, show errors only",
    )
    parser.add_argument(
        "--no-dedup", action="store_true",
        help="Skip near-duplicate detection (use for datasets > 5000 rows)",
    )
    args = parser.parse_args()

    all_reports: list[FileReport] = []
    all_rows:    list[dict]       = []
    all_results: list[tuple[str, RowResult]] = []

    for fp_str in args.files:
        fp = Path(fp_str)
        if not fp.exists():
            print(f"{_c(RED, 'ERROR')} File not found: {fp}", file=sys.stderr)
            continue

        report, rows = validate_file(fp)
        all_reports.append(report)
        all_rows.extend(rows)
        all_results.extend((str(fp), res) for res in report.results)

        print_file_report(report, verbose=args.verbose, errors_only=args.errors_only)

    if not all_reports:
        print("No files validated.", file=sys.stderr)
        return 1

    dup_errors        = check_duplicate_ids(all_results)
    near_dup_warnings = [] if args.no_dedup else check_near_duplicates(all_rows)

    print_summary(all_reports, dup_errors, near_dup_warnings)

    has_errors = any(r.error_rows > 0 for r in all_reports) or bool(dup_errors)
    return 1 if has_errors else 0


if __name__ == "__main__":
    sys.exit(main())
