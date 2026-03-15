from __future__ import annotations

import difflib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path("/Users/aris/Documents/VoiceProject/Zphyr")
TMP = ROOT / "Evals/datasets/raw/patch/.tmp_round5"
REPORT_PATH = TMP / "agent_f_qa_report.md"

SHARDS = {
    "agent_a_hard_negatives_and_ambiguity": (
        TMP / "agent_a_hard_negatives_and_ambiguity.jsonl",
        900,
    ),
    "agent_b_intentional_repetition_preservation": (
        TMP / "agent_b_intentional_repetition_preservation.jsonl",
        700,
    ),
    "agent_c_protected_terms_verbatim": (
        TMP / "agent_c_protected_terms_verbatim.jsonl",
        600,
    ),
    "agent_d_spoken_lists_and_structuring": (
        TMP / "agent_d_spoken_lists_and_structuring.jsonl",
        450,
    ),
    "agent_e_email_prose_punctuation": (
        TMP / "agent_e_email_prose_punctuation.jsonl",
        350,
    ),
}

REQUIRED_KEYS = {"id", "category", "subcategory", "raw", "expected", "language", "notes"}
TAG_PATTERN = re.compile(r"</?think>")
NORMALIZE_PATTERN = re.compile(r"[^\w\s]", re.UNICODE)


def normalize(text: str) -> str:
    text = text.lower().replace("\n", " ")
    text = NORMALIZE_PATTERN.sub(" ", text)
    return " ".join(text.split())


def token_diff(left: str, right: str) -> int:
    left_counts = Counter(left.split())
    right_counts = Counter(right.split())
    return sum((left_counts - right_counts).values()) + sum((right_counts - left_counts).values())


def load_rows() -> tuple[list[dict[str, str]], list[str], dict[str, int]]:
    rows: list[dict[str, str]] = []
    parse_errors: list[str] = []
    per_shard_counts: dict[str, int] = {}
    for shard_name, (path, _) in SHARDS.items():
        count = 0
        with path.open(encoding="utf-8") as handle:
            for line_no, line in enumerate(handle, start=1):
                count += 1
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as exc:
                    parse_errors.append(f"{path}:{line_no}: {exc}")
                    continue
                row["_file"] = str(path)
                row["_line"] = line_no
                rows.append(row)
        per_shard_counts[shard_name] = count
    return rows, parse_errors, per_shard_counts


def find_near_duplicates(rows: list[dict[str, str]]) -> tuple[Counter[str], list[str]]:
    by_subcategory: dict[str, list[tuple[dict[str, str], str, str, str, int]]] = defaultdict(list)
    for row in rows:
        raw_norm = normalize(row["raw"])
        expected_norm = normalize(row["expected"])
        raw_tokens = raw_norm.split()
        bucket = " ".join(raw_tokens[:4]) if len(raw_tokens) >= 4 else raw_norm
        by_subcategory[row["subcategory"]].append((row, raw_norm, expected_norm, bucket, len(raw_tokens)))

    counts: Counter[str] = Counter()
    samples: list[str] = []
    for subcategory, group in by_subcategory.items():
        buckets: dict[str, list[tuple[dict[str, str], str, str, str, int]]] = defaultdict(list)
        for item in group:
            buckets[item[3]].append(item)
        for items in buckets.values():
            for index, (left_row, left_raw, left_expected, _, left_len) in enumerate(items):
                for right_row, right_raw, right_expected, _, right_len in items[index + 1 :]:
                    if abs(left_len - right_len) > 2:
                        continue
                    raw_ratio = difflib.SequenceMatcher(None, left_raw, right_raw).ratio()
                    expected_ratio = difflib.SequenceMatcher(None, left_expected, right_expected).ratio()
                    if raw_ratio < 0.975 or expected_ratio < 0.975:
                        continue
                    if token_diff(left_raw, right_raw) > 5:
                        continue
                    counts[subcategory] += 1
                    if len(samples) < 12:
                        samples.append(
                            (
                                f"- {subcategory}: {left_row['id']} vs {right_row['id']} "
                                f"(raw_ratio={raw_ratio:.3f}, expected_ratio={expected_ratio:.3f})"
                            )
                        )
    return counts, samples


def main() -> None:
    rows, parse_errors, per_shard_counts = load_rows()

    per_subcategory = Counter(row["subcategory"] for row in rows)
    schema_issues: list[str] = []
    missing_key_issues: list[str] = []
    language_issues: list[str] = []
    tag_issues: list[str] = []
    empty_field_issues: list[str] = []

    for row in rows:
        keys = set(row.keys()) - {"_file", "_line"}
        if keys != REQUIRED_KEYS:
            schema_issues.append(
                f"{row['_file']}:{row['_line']}: keys={sorted(keys)}"
            )
            missing = REQUIRED_KEYS - keys
            extra = keys - REQUIRED_KEYS
            if missing or extra:
                missing_key_issues.append(
                    f"{row['_file']}:{row['_line']}: missing={sorted(missing)} extra={sorted(extra)}"
                )
        if row.get("language") != "fr":
            language_issues.append(
                f"{row['_file']}:{row['_line']}: language={row.get('language')!r}"
            )
        if TAG_PATTERN.search(row.get("raw", "")) or TAG_PATTERN.search(row.get("expected", "")):
            tag_issues.append(f"{row['_file']}:{row['_line']}: {row['id']}")
        for field in ("raw", "expected", "notes"):
            if not str(row.get(field, "")).strip():
                empty_field_issues.append(
                    f"{row['_file']}:{row['_line']}: empty {field}"
                )

    id_counts = Counter(row["id"] for row in rows)
    duplicate_ids = sorted(row_id for row_id, count in id_counts.items() if count > 1)

    tuple_counts = Counter((row["subcategory"], row["raw"], row["expected"]) for row in rows)
    exact_duplicates = [
        key for key, count in tuple_counts.items() if count > 1
    ]

    near_duplicate_counts, near_duplicate_samples = find_near_duplicates(rows)

    total_expected = sum(expected for _, expected in SHARDS.values())
    per_shard_expected_issues = [
        f"- {name}: expected {expected}, found {per_shard_counts.get(name, 0)}"
        for name, (_, expected) in SHARDS.items()
        if per_shard_counts.get(name, 0) != expected
    ]

    qa_pass = not any(
        [
            parse_errors,
            schema_issues,
            missing_key_issues,
            language_issues,
            tag_issues,
            empty_field_issues,
            duplicate_ids,
            exact_duplicates,
            len(rows) != total_expected,
            per_shard_expected_issues,
        ]
    )

    lines: list[str] = [
        "# Round5 QA Report",
        "",
        "## Summary",
        f"- Total rows: {len(rows)}",
        f"- Expected total rows: {total_expected}",
        f"- QA pass: {'yes' if qa_pass else 'no'}",
        "",
        "## Per-shard Counts",
    ]
    lines.extend(
        f"- {name}: {per_shard_counts[name]}" for name in sorted(per_shard_counts)
    )

    lines.extend(
        [
            "",
            "## Counts by Subcategory",
        ]
    )
    lines.extend(
        f"- {subcategory}: {per_subcategory[subcategory]}"
        for subcategory in sorted(per_subcategory)
    )

    lines.extend(
        [
            "",
            "## QA Checks",
            f"- JSON parse errors: {len(parse_errors)}",
            f"- Schema mismatches: {len(schema_issues)}",
            f"- Missing or extra key issues: {len(missing_key_issues)}",
            f"- Non-fr language rows: {len(language_issues)}",
            f"- `<think>` contamination rows: {len(tag_issues)}",
            f"- Empty raw/expected/notes rows: {len(empty_field_issues)}",
            f"- Duplicate IDs: {len(duplicate_ids)}",
            f"- Exact duplicate `(subcategory, raw, expected)` rows: {len(exact_duplicates)}",
            f"- Near-duplicate candidates (strict heuristic): {sum(near_duplicate_counts.values())}",
            f"- Exact final count check (=3000): {'pass' if len(rows) == total_expected else 'fail'}",
        ]
    )

    lines.extend(
        [
            "",
            "## Exact Duplicate Detection",
            "- No exact duplicate rows detected." if not exact_duplicates else "",
        ]
    )
    if exact_duplicates:
        for subcategory, raw, expected in exact_duplicates[:10]:
            lines.append(f"- {subcategory}: raw={raw!r} | expected={expected!r}")

    lines.extend(
        [
            "",
            "## Near-Duplicate Review",
            (
                "- No risky near-duplicate pairs were flagged by the strict heuristic "
                "(same subcategory, shared opening tokens, raw/expected similarity >= 0.975, token diff <= 5)."
            )
            if not near_duplicate_counts
            else "",
        ]
    )
    if near_duplicate_counts:
        for subcategory in sorted(near_duplicate_counts):
            lines.append(f"- {subcategory}: {near_duplicate_counts[subcategory]}")
        lines.extend(near_duplicate_samples)

    lines.extend(
        [
            "",
            "## Issues To Fix",
        ]
    )
    issues = (
        parse_errors
        + schema_issues
        + missing_key_issues
        + language_issues
        + tag_issues
        + empty_field_issues
        + [f"duplicate id: {row_id}" for row_id in duplicate_ids]
        + per_shard_expected_issues
    )
    if not issues and not exact_duplicates:
        lines.append("- None.")
    else:
        lines.extend(f"- {issue}" for issue in issues[:50])
        if exact_duplicates:
            lines.append(f"- Exact duplicate groups to resolve: {len(exact_duplicates)}")

    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
