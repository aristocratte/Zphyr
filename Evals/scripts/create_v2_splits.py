#!/usr/bin/env python3
"""
Freeze the validated Zphyr v2 dataset subset and generate deterministic
anti-leakage train/val/test splits.

This script intentionally uses only the seven source files explicitly approved
for the current finetuning handoff. It does not mutate the raw source files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SCRIPT_DIR = Path(__file__).resolve().parent
EVALS_DIR = SCRIPT_DIR.parent
DATASETS_DIR = EVALS_DIR / "datasets"
RAW_V2_DIR = DATASETS_DIR / "raw" / "v2"
FROZEN_V2_DIR = DATASETS_DIR / "frozen" / "v2"
SPLITS_V2_DIR = DATASETS_DIR / "splits" / "v2_validated"

DEFAULT_SOURCE_FILES = [
    "technical.jsonl",
    "multilingual.jsonl",
    "commands.jsonl",
    "corrections.jsonl",
    "short.jsonl",
    "prose.jsonl",
    "lists.jsonl",
]

DEFAULT_EXCLUDED_FILES = ["null_edits.jsonl"]
DEFAULT_SEED = 42
DEFAULT_THRESHOLD = 0.70
DEFAULT_NGRAM_SIZE = 3
DEFAULT_RATIOS = {"train": 0.70, "val": 0.15, "test": 0.15}
SPLIT_ORDER = ["train", "val", "test"]


sys.path.insert(0, str(SCRIPT_DIR))
from validate import check_duplicate_ids, jaccard, validate_file  # noqa: E402


@dataclass(frozen=True)
class Group:
    group_id: str
    items: list[dict]

    @property
    def size(self) -> int:
        return len(self.items)

    @property
    def categories(self) -> Counter:
        return Counter(row["category"] for row in self.items)

    @property
    def subcategories(self) -> Counter:
        return Counter(row["subcategory"] for row in self.items)

    @property
    def languages(self) -> Counter:
        return Counter(row["language"] for row in self.items)

    @property
    def source_types(self) -> Counter:
        return Counter(row["source_type"] for row in self.items)

    @property
    def critical_count(self) -> int:
        return sum(row["severity_if_wrong"] == "critical" for row in self.items)


class DSU:
    def __init__(self, size: int) -> None:
        self.parent = list(range(size))
        self.rank = [0] * size

    def find(self, idx: int) -> int:
        while self.parent[idx] != idx:
            self.parent[idx] = self.parent[self.parent[idx]]
            idx = self.parent[idx]
        return idx

    def union(self, left: int, right: int) -> None:
        left_root = self.find(left)
        right_root = self.find(right)
        if left_root == right_root:
            return
        if self.rank[left_root] < self.rank[right_root]:
            left_root, right_root = right_root, left_root
        self.parent[right_root] = left_root
        if self.rank[left_root] == self.rank[right_root]:
            self.rank[left_root] += 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Freeze validated v2 data and generate deterministic anti-leakage splits."
    )
    parser.add_argument(
        "--source-files",
        nargs="+",
        default=DEFAULT_SOURCE_FILES,
        help="Validated raw v2 JSONL files to include.",
    )
    parser.add_argument(
        "--excluded-files",
        nargs="*",
        default=DEFAULT_EXCLUDED_FILES,
        help="Files present in raw/frozen v2 but intentionally excluded from this split.",
    )
    parser.add_argument(
        "--raw-dir",
        default=str(RAW_V2_DIR),
        help="Directory containing raw v2 source JSONL files.",
    )
    parser.add_argument(
        "--frozen-dir",
        default=str(FROZEN_V2_DIR),
        help="Directory where the frozen copy and manifest should live.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(SPLITS_V2_DIR),
        help="Directory where train/val/test splits and reports should be written.",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help="Deterministic seed recorded in manifests.",
    )
    parser.add_argument(
        "--near-duplicate-threshold",
        type=float,
        default=DEFAULT_THRESHOLD,
        help="Jaccard threshold reused from validate.py for grouping near duplicates.",
    )
    parser.add_argument(
        "--ngram-size",
        type=int,
        default=DEFAULT_NGRAM_SIZE,
        help="N-gram size used by the validator similarity function.",
    )
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_jsonl(path: Path) -> list[dict]:
    rows: list[dict] = []
    with open(path, encoding="utf-8-sig") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def write_jsonl(path: Path, rows: Iterable[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def write_json(path: Path, payload: dict | list) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def set_read_only(path: Path) -> None:
    try:
        path.chmod(0o444)
    except OSError:
        pass


def freeze_sources(raw_dir: Path, frozen_dir: Path, source_files: list[str]) -> dict:
    frozen_dir.mkdir(parents=True, exist_ok=True)
    file_entries: list[dict] = []

    merged_rows: list[dict] = []
    for name in source_files:
        raw_path = raw_dir / name
        frozen_path = frozen_dir / name
        if not raw_path.exists():
            raise FileNotFoundError(f"Missing raw source file: {raw_path}")

        if frozen_path.exists():
            try:
                frozen_path.chmod(0o644)
            except OSError:
                pass
        shutil.copy2(raw_path, frozen_path)
        set_read_only(frozen_path)

        rows = load_jsonl(raw_path)
        for row in rows:
            row["_source_file"] = name
            merged_rows.append(row)

        file_entries.append(
            {
                "file": name,
                "raw_path": str(raw_path),
                "frozen_path": str(frozen_path),
                "row_count": len(rows),
                "sha256": sha256_file(raw_path),
            }
        )

    merged_path = frozen_dir / "zphyr_v2_validated_ft.jsonl"
    if merged_path.exists():
        try:
            merged_path.chmod(0o644)
        except OSError:
            pass
    write_jsonl(merged_path, merged_rows)
    set_read_only(merged_path)

    return {
        "files": file_entries,
        "merged_path": str(merged_path),
        "merged_row_count": len(merged_rows),
        "merged_sha256": sha256_file(merged_path),
        "rows": merged_rows,
    }


def compute_bucket_targets(
    counts: Counter,
    split_targets: dict[str, int],
    ratios: dict[str, float],
) -> dict[str, dict[str, int]]:
    base: dict[str, dict[str, int]] = {
        bucket: {split: int(count * ratios[split]) for split in SPLIT_ORDER}
        for bucket, count in counts.items()
    }
    bucket_remainders = {
        bucket: counts[bucket] - sum(base[bucket].values())
        for bucket in counts
    }
    split_deficits = {
        split: split_targets[split] - sum(base[bucket][split] for bucket in counts)
        for split in SPLIT_ORDER
    }
    fractions = {
        bucket: {
            split: counts[bucket] * ratios[split] - base[bucket][split]
            for split in SPLIT_ORDER
        }
        for bucket in counts
    }

    for bucket in sorted(counts):
        for _ in range(bucket_remainders[bucket]):
            candidates = [split for split in SPLIT_ORDER if split_deficits[split] > 0]
            if not candidates:
                break
            chosen = max(
                candidates,
                key=lambda split: (
                    fractions[bucket][split],
                    -SPLIT_ORDER.index(split),
                ),
            )
            base[bucket][chosen] += 1
            split_deficits[chosen] -= 1

    return base


def compute_global_targets(total_rows: int, ratios: dict[str, float]) -> dict[str, int]:
    split_targets = {
        split: int(total_rows * ratios[split])
        for split in SPLIT_ORDER
    }
    remainder = total_rows - sum(split_targets.values())
    remainders = sorted(
        ((total_rows * ratios[split] - split_targets[split], split) for split in SPLIT_ORDER),
        reverse=True,
    )
    for _, split in remainders[:remainder]:
        split_targets[split] += 1
    return split_targets


def detect_groups(rows: list[dict], threshold: float, ngram_size: int) -> tuple[list[Group], list[dict]]:
    dsu = DSU(len(rows))
    pair_details: list[dict] = []

    for left in range(len(rows)):
        left_text = rows[left]["raw_asr_text"]
        for right in range(left + 1, len(rows)):
            similarity = jaccard(left_text, rows[right]["raw_asr_text"], n=ngram_size)
            if similarity >= threshold:
                dsu.union(left, right)
                pair_details.append(
                    {
                        "left_id": rows[left]["id"],
                        "right_id": rows[right]["id"],
                        "similarity": round(similarity, 4),
                    }
                )

    grouped_rows: dict[int, list[dict]] = defaultdict(list)
    for idx, row in enumerate(rows):
        grouped_rows[dsu.find(idx)].append(row)

    groups: list[Group] = []
    near_duplicate_index = 1
    for _, items in sorted(
        grouped_rows.items(),
        key=lambda pair: (
            -len(pair[1]),
            pair[1][0]["category"],
            pair[1][0]["id"],
        ),
    ):
        sorted_items = sorted(items, key=lambda row: row["id"])
        if len(sorted_items) == 1:
            group_id = f"singleton-{sorted_items[0]['id']}"
        else:
            group_id = f"ndg-{near_duplicate_index:03d}"
            near_duplicate_index += 1
        groups.append(Group(group_id=group_id, items=sorted_items))

    return groups, pair_details


def category_split_targets(rows: list[dict], split_targets: dict[str, int], ratios: dict[str, float]) -> dict[str, dict[str, int]]:
    counts = Counter(row["category"] for row in rows)
    return compute_bucket_targets(counts, split_targets, ratios)


def exact_bucket_targets_for_category(
    counts: Counter,
    category_split_targets: dict[str, int],
) -> dict[str, dict[str, int]]:
    total = sum(counts.values())
    if total == 0:
        return {}
    ratios = {split: category_split_targets[split] / total for split in SPLIT_ORDER}
    return compute_bucket_targets(counts, category_split_targets, ratios)


def choose_feasible_counts_without_singletons(groups: list[Group], nominal_targets: dict[str, int]) -> tuple[dict[str, int], dict[str, str]]:
    total = sum(group.size for group in groups)
    groups = sorted(
        groups,
        key=lambda group: (-group.size, -group.critical_count, group.group_id),
    )

    states: dict[tuple[int, int], tuple[tuple[int, int] | None, str | None]] = {(0, 0): (None, None)}
    for group in groups:
        next_states: dict[tuple[int, int], tuple[tuple[int, int], str]] = {}
        for (val_count, test_count), _ in states.items():
            for split in SPLIT_ORDER:
                new_val = val_count + (group.size if split == "val" else 0)
                new_test = test_count + (group.size if split == "test" else 0)
                key = (new_val, new_test)
                if key in next_states:
                    continue
                next_states[key] = ((val_count, test_count), split)
        states = next_states

    best_key = min(
        states,
        key=lambda key: (
            abs(key[0] - nominal_targets["val"])
            + abs(key[1] - nominal_targets["test"])
            + abs((total - key[0] - key[1]) - nominal_targets["train"]),
            abs(key[0] - nominal_targets["val"]),
            abs(key[1] - nominal_targets["test"]),
        ),
    )

    states = {(0, 0): (None, None)}
    trace: list[dict[tuple[int, int], tuple[tuple[int, int], str]]] = []
    for group in groups:
        next_states = {}
        for (val_count, test_count), _ in states.items():
            for split in SPLIT_ORDER:
                new_val = val_count + (group.size if split == "val" else 0)
                new_test = test_count + (group.size if split == "test" else 0)
                key = (new_val, new_test)
                if key not in next_states:
                    next_states[key] = ((val_count, test_count), split)
        trace.append(next_states)
        states = next_states
    assignment = {}
    current_key = best_key
    for group, trace_states in zip(reversed(groups), reversed(trace)):
        previous_key, split = trace_states[current_key]
        assignment[group.group_id] = split
        current_key = previous_key

    feasible_counts = {
        "train": total - best_key[0] - best_key[1],
        "val": best_key[0],
        "test": best_key[1],
    }
    return feasible_counts, assignment


def assign_category_with_singletons(
    category: str,
    groups: list[Group],
    target_counts: dict[str, int],
) -> tuple[dict[str, list[dict]], dict[str, list[dict]]]:
    by_split_rows: dict[str, list[dict]] = {split: [] for split in SPLIT_ORDER}
    by_split_groups: dict[str, list[dict]] = {split: [] for split in SPLIT_ORDER}

    multi_groups = [group for group in groups if group.size > 1]
    single_groups = [group for group in groups if group.size == 1]

    remaining_counts = dict(target_counts)
    sub_targets = exact_bucket_targets_for_category(
        Counter(row["subcategory"] for group in groups for row in group.items),
        target_counts,
    )
    language_targets = exact_bucket_targets_for_category(
        Counter(row["language"] for group in groups for row in group.items),
        target_counts,
    )
    source_targets = exact_bucket_targets_for_category(
        Counter(row["source_type"] for group in groups for row in group.items),
        target_counts,
    )

    current_sub = {split: Counter() for split in SPLIT_ORDER}
    current_lang = {split: Counter() for split in SPLIT_ORDER}
    current_source = {split: Counter() for split in SPLIT_ORDER}

    def squared_delta(before: int, after: int) -> int:
        return after * after - before * before

    multi_groups.sort(
        key=lambda group: (-group.size, -group.critical_count, group.group_id)
    )
    for group in multi_groups:
        candidates = [split for split in SPLIT_ORDER if remaining_counts[split] >= group.size]
        if not candidates:
            candidates = SPLIT_ORDER[:]

        def score(split: str) -> float:
            penalty = 0.0
            before = remaining_counts[split]
            after = before - group.size
            penalty += squared_delta(before, after) * 5.0
            if after < 0:
                penalty += abs(after) * abs(after) * 500.0

            for subcategory, count in group.subcategories.items():
                target = sub_targets[subcategory][split]
                current = current_sub[split][subcategory]
                penalty += squared_delta(target - current, target - current - count) * 4.0
            for language, count in group.languages.items():
                target = language_targets[language][split]
                current = current_lang[split][language]
                penalty += squared_delta(target - current, target - current - count) * 1.5
            for source_type, count in group.source_types.items():
                target = source_targets[source_type][split]
                current = current_source[split][source_type]
                penalty += squared_delta(target - current, target - current - count) * 0.5
            return penalty

        chosen = min(candidates, key=lambda split: (score(split), SPLIT_ORDER.index(split)))
        remaining_counts[chosen] -= group.size
        current_sub[chosen].update(group.subcategories)
        current_lang[chosen].update(group.languages)
        current_source[chosen].update(group.source_types)
        by_split_rows[chosen].extend(group.items)
        by_split_groups[chosen].append({"group_id": group.group_id, "category": category, "size": group.size})

    def singleton_priority(group: Group) -> tuple[float, int, str]:
        row = group.items[0]
        subcategory = row["subcategory"]
        max_need = max(
            sub_targets[subcategory][split] - current_sub[split][subcategory]
            for split in SPLIT_ORDER
        )
        return (
            max_need,
            1 if row["severity_if_wrong"] == "critical" else 0,
            row["id"],
        )

    for group in sorted(single_groups, key=singleton_priority, reverse=True):
        row = group.items[0]

        def singleton_score(split: str) -> float:
            remaining = remaining_counts[split]
            if remaining <= 0:
                return -1e12
            sub_need = sub_targets[row["subcategory"]][split] - current_sub[split][row["subcategory"]]
            lang_need = language_targets[row["language"]][split] - current_lang[split][row["language"]]
            source_need = source_targets[row["source_type"]][split] - current_source[split][row["source_type"]]
            return sub_need * 100.0 + lang_need * 10.0 + source_need * 5.0 + remaining

        chosen = max(SPLIT_ORDER, key=lambda split: (singleton_score(split), -SPLIT_ORDER.index(split)))
        remaining_counts[chosen] -= 1
        current_sub[chosen][row["subcategory"]] += 1
        current_lang[chosen][row["language"]] += 1
        current_source[chosen][row["source_type"]] += 1
        by_split_rows[chosen].append(row)
        by_split_groups[chosen].append({"group_id": group.group_id, "category": category, "size": 1})

    if any(remaining_counts[split] != 0 for split in SPLIT_ORDER):
        raise RuntimeError(
            f"Category '{category}' could not hit exact targets with singleton fill: {remaining_counts}"
        )

    return by_split_rows, by_split_groups


def assign_category_without_singletons(
    category: str,
    groups: list[Group],
    nominal_targets: dict[str, int],
) -> tuple[dict[str, list[dict]], dict[str, list[dict]], dict[str, int]]:
    feasible_counts, group_assignment = choose_feasible_counts_without_singletons(groups, nominal_targets)
    by_split_rows: dict[str, list[dict]] = {split: [] for split in SPLIT_ORDER}
    by_split_groups: dict[str, list[dict]] = {split: [] for split in SPLIT_ORDER}

    for group in groups:
        split = group_assignment[group.group_id]
        by_split_rows[split].extend(group.items)
        by_split_groups[split].append({"group_id": group.group_id, "category": category, "size": group.size})

    return by_split_rows, by_split_groups, feasible_counts


def build_initial_splits(
    groups: list[Group],
    split_targets: dict[str, int],
    ratios: dict[str, float],
) -> tuple[dict[str, list[dict]], dict[str, list[dict]], dict[str, dict[str, int]], dict[str, dict[str, int]]]:
    rows_by_category: dict[str, list[Group]] = defaultdict(list)
    for group in groups:
        categories = set(group.categories)
        if len(categories) != 1:
            raise RuntimeError(
                f"Near-duplicate group spans multiple categories, cannot split safely: {group.group_id} -> {sorted(categories)}"
            )
        rows_by_category[next(iter(categories))].append(group)

    nominal_category_targets = category_split_targets(
        [row for group in groups for row in group.items],
        split_targets,
        ratios,
    )
    actual_category_targets = {
        category: dict(targets)
        for category, targets in nominal_category_targets.items()
    }

    split_rows: dict[str, list[dict]] = {split: [] for split in SPLIT_ORDER}
    split_groups: dict[str, list[dict]] = {split: [] for split in SPLIT_ORDER}

    categories_without_singletons = []
    categories_with_singletons = []
    for category, category_groups in rows_by_category.items():
        if any(group.size == 1 for group in category_groups):
            categories_with_singletons.append(category)
        else:
            categories_without_singletons.append(category)

    for category in sorted(categories_with_singletons):
        category_rows, category_groups = assign_category_with_singletons(
            category,
            rows_by_category[category],
            nominal_category_targets[category],
        )
        for split in SPLIT_ORDER:
            split_rows[split].extend(category_rows[split])
            split_groups[split].extend(category_groups[split])

    for category in sorted(categories_without_singletons):
        category_rows, category_groups, feasible_counts = assign_category_without_singletons(
            category,
            rows_by_category[category],
            nominal_category_targets[category],
        )
        actual_category_targets[category] = feasible_counts
        for split in SPLIT_ORDER:
            split_rows[split].extend(category_rows[split])
            split_groups[split].extend(category_groups[split])

    return split_rows, split_groups, nominal_category_targets, actual_category_targets


def adjust_with_singleton_moves(
    split_rows: dict[str, list[dict]],
    split_groups: dict[str, list[dict]],
    split_targets: dict[str, int],
    nominal_category_targets: dict[str, dict[str, int]],
) -> list[dict]:
    moves: list[dict] = []
    deficits = {
        split: split_targets[split] - len(split_rows[split])
        for split in SPLIT_ORDER
    }

    if all(deficit == 0 for deficit in deficits.values()):
        return moves

    while any(deficit != 0 for deficit in deficits.values()):
        receivers = [split for split, deficit in deficits.items() if deficit > 0]
        donors = [split for split, deficit in deficits.items() if deficit < 0]
        if not receivers or not donors:
            raise RuntimeError(f"Unresolvable split deficits after singleton adjustment: {deficits}")

        receiver = max(receivers, key=lambda split: deficits[split])
        donor = min(donors, key=lambda split: deficits[split])

        donor_category_counts = Counter(row["category"] for row in split_rows[donor])
        receiver_category_counts = Counter(row["category"] for row in split_rows[receiver])
        donor_sub_counts = Counter(row["subcategory"] for row in split_rows[donor])
        receiver_sub_counts = Counter(row["subcategory"] for row in split_rows[receiver])

        candidate_rows = [
            row
            for row in split_rows[donor]
            if str(row.get("_group_id", "")).startswith("singleton-")
        ]
        if not candidate_rows:
            raise RuntimeError(
                f"Cannot fix split deficits: donor split '{donor}' has no singleton rows to move."
            )

        def move_penalty(row: dict) -> tuple[float, str]:
            category = row["category"]
            subcategory = row["subcategory"]
            donor_before = donor_category_counts[category] - nominal_category_targets[category][donor]
            donor_after = donor_before - 1
            receiver_before = receiver_category_counts[category] - nominal_category_targets[category][receiver]
            receiver_after = receiver_before + 1

            penalty = (
                donor_after * donor_after - donor_before * donor_before
                + receiver_after * receiver_after - receiver_before * receiver_before
            ) * 10.0

            donor_sub_before = donor_sub_counts[subcategory]
            receiver_sub_before = receiver_sub_counts[subcategory]
            penalty += abs((receiver_sub_before + 1) - donor_sub_before) * 0.5

            if row["severity_if_wrong"] == "critical":
                penalty += 0.1
            return (penalty, row["id"])

        chosen_row = min(candidate_rows, key=move_penalty)

        split_rows[donor] = [row for row in split_rows[donor] if row["id"] != chosen_row["id"]]
        split_rows[receiver].append(chosen_row)

        deficits[donor] += 1
        deficits[receiver] -= 1

        group_id = chosen_row["_group_id"]
        split_groups[donor] = [entry for entry in split_groups[donor] if entry["group_id"] != group_id]
        split_groups[receiver].append({"group_id": group_id, "category": chosen_row["category"], "size": 1})

        moves.append(
            {
                "group_id": group_id,
                "row_id": chosen_row["id"],
                "category": chosen_row["category"],
                "subcategory": chosen_row["subcategory"],
                "from_split": donor,
                "to_split": receiver,
            }
        )

    return moves


def finalize_split_rows(split_rows: dict[str, list[dict]]) -> dict[str, list[dict]]:
    finalized: dict[str, list[dict]] = {}
    for split in SPLIT_ORDER:
        cleaned_rows = []
        for row in split_rows[split]:
            cleaned = dict(row)
            cleaned.pop("_group_id", None)
            cleaned_rows.append(cleaned)
        finalized[split] = sorted(cleaned_rows, key=lambda row: row["id"])
    return finalized


def validate_split_files(split_paths: dict[str, Path]) -> dict:
    validation_report: dict[str, dict] = {}
    combined_results: list[tuple[str, object]] = []

    for split, path in split_paths.items():
        file_report, _ = validate_file(path)
        validation_report[split] = {
            "path": str(path),
            "total_rows": file_report.total_rows,
            "valid_rows": file_report.valid_rows,
            "error_rows": file_report.error_rows,
            "warned_rows": file_report.warned_rows,
            "parse_errors": [{"line": line, "message": message} for line, message in file_report.parse_errors],
            "row_errors": [
                {
                    "row_id": result.row_id,
                    "line_number": result.line_number,
                    "errors": [str(issue) for issue in result.errors],
                }
                for result in file_report.results
                if result.errors
            ],
            "row_warnings": [
                {
                    "row_id": result.row_id,
                    "line_number": result.line_number,
                    "warnings": [str(issue) for issue in result.warnings],
                }
                for result in file_report.results
                if result.warnings and not result.errors
            ],
        }
        combined_results.extend((split, result) for result in file_report.results)

    duplicate_ids = check_duplicate_ids(combined_results)
    return {
        "per_split": validation_report,
        "duplicate_ids": duplicate_ids,
    }


def build_stats(rows: list[dict]) -> dict:
    return {
        "row_count": len(rows),
        "categories": dict(sorted(Counter(row["category"] for row in rows).items())),
        "subcategories": dict(sorted(Counter(row["subcategory"] for row in rows).items())),
        "languages": dict(sorted(Counter(row["language"] for row in rows).items())),
        "source_types": dict(sorted(Counter(row["source_type"] for row in rows).items())),
        "rewrite_allowed_levels": dict(sorted(Counter(row["rewrite_allowed_level"] for row in rows).items())),
        "severity_if_wrong": dict(sorted(Counter(row["severity_if_wrong"] for row in rows).items())),
        "difficulty": dict(sorted(Counter(row["difficulty"] for row in rows).items())),
        "null_edit_count": sum(1 for row in rows if row["is_null_edit"]),
        "protected_term_rows": sum(1 for row in rows if row["protected_terms"]),
        "critical_rows": sum(1 for row in rows if row["severity_if_wrong"] == "critical"),
    }


def final_category_counts_by_split(finalized_rows: dict[str, list[dict]]) -> dict[str, dict[str, int]]:
    categories = sorted(
        {
            row["category"]
            for split in SPLIT_ORDER
            for row in finalized_rows[split]
        }
    )
    return {
        category: {
            split: sum(1 for row in finalized_rows[split] if row["category"] == category)
            for split in SPLIT_ORDER
        }
        for category in categories
    }


def build_group_report(groups: list[Group], split_lookup: dict[str, str]) -> list[dict]:
    report: list[dict] = []
    for group in groups:
        if group.size == 1:
            continue
        report.append(
            {
                "group_id": group.group_id,
                "split": split_lookup[group.group_id],
                "size": group.size,
                "category": group.items[0]["category"],
                "subcategory_counts": dict(sorted(group.subcategories.items())),
                "members": [row["id"] for row in group.items],
                "raw_asr_preview": group.items[0]["raw_asr_text"][:160],
            }
        )
    return report


def check_group_leakage(groups: list[Group], finalized_rows: dict[str, list[dict]]) -> dict:
    row_to_split = {
        row["id"]: split
        for split in SPLIT_ORDER
        for row in finalized_rows[split]
    }
    leaking_groups = []
    for group in groups:
        splits = sorted({row_to_split[row["id"]] for row in group.items})
        if len(splits) > 1:
            leaking_groups.append(
                {
                    "group_id": group.group_id,
                    "members": [row["id"] for row in group.items],
                    "splits": splits,
                }
            )
    return {
        "clean": not leaking_groups,
        "leaking_groups": leaking_groups,
    }


def build_markdown_report(manifest: dict) -> str:
    lines: list[str] = []
    lines.append("# Zphyr v2 Validated Split Report")
    lines.append("")
    lines.append(f"- Dataset subset: `{manifest['dataset_name']}`")
    lines.append(f"- Seed: `{manifest['seed']}`")
    lines.append(
        f"- Ratios: train `{manifest['ratios']['train']:.2f}` / val `{manifest['ratios']['val']:.2f}` / test `{manifest['ratios']['test']:.2f}`"
    )
    lines.append(
        f"- Near-duplicate grouping: Jaccard `{manifest['near_duplicate_threshold']}` on `{manifest['ngram_size']}`-grams"
    )
    lines.append("")
    lines.append("## Source")
    lines.append("")
    lines.append(f"- Included files: {', '.join(manifest['included_files'])}")
    lines.append(f"- Excluded files: {', '.join(manifest['excluded_files']) or 'none'}")
    lines.append(f"- Frozen merged file: `{manifest['freeze']['merged_path']}`")
    lines.append(f"- Frozen row count: `{manifest['freeze']['merged_row_count']}`")
    lines.append("")
    lines.append("## Split Sizes")
    lines.append("")
    lines.append("| Split | Rows |")
    lines.append("| --- | ---: |")
    for split in SPLIT_ORDER:
        lines.append(f"| {split} | {manifest['splits'][split]['row_count']} |")
    lines.append("")
    lines.append("## Verification")
    lines.append("")
    verification = manifest["verification"]
    lines.append(f"- Total rows preserved: `{verification['total_rows_match']}`")
    lines.append(f"- Group leakage clean: `{verification['group_leakage']['clean']}`")
    lines.append(f"- Duplicate IDs across splits: `{len(verification['schema_validation']['duplicate_ids'])}`")
    lines.append("")
    lines.append("## Category Counts")
    lines.append("")
    category_names = sorted(
        {
            category
            for split in SPLIT_ORDER
            for category in manifest["splits"][split]["categories"]
        }
    )
    lines.append("| Category | Train | Val | Test | Total |")
    lines.append("| --- | ---: | ---: | ---: | ---: |")
    for category in category_names:
        train_count = manifest["splits"]["train"]["categories"].get(category, 0)
        val_count = manifest["splits"]["val"]["categories"].get(category, 0)
        test_count = manifest["splits"]["test"]["categories"].get(category, 0)
        total = train_count + val_count + test_count
        lines.append(f"| {category} | {train_count} | {val_count} | {test_count} | {total} |")
    lines.append("")
    lines.append("## Near-Duplicate Groups")
    lines.append("")
    lines.append(f"- Non-singleton groups: `{len(manifest['near_duplicate_groups'])}`")
    lines.append(f"- Pair edges over threshold: `{len(manifest['near_duplicate_pairs'])}`")
    lines.append("")
    for group in manifest["near_duplicate_groups"][:20]:
        members = ", ".join(group["members"])
        lines.append(f"- `{group['group_id']}` -> `{group['split']}` ({group['size']} rows): {members}")
    if len(manifest["near_duplicate_groups"]) > 20:
        lines.append(f"- ... `{len(manifest['near_duplicate_groups']) - 20}` additional groups omitted in Markdown; see JSON manifest.")
    lines.append("")
    return "\n".join(lines) + "\n"


def main() -> None:
    args = parse_args()
    raw_dir = Path(args.raw_dir).resolve()
    frozen_dir = Path(args.frozen_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    split_targets = compute_global_targets(
        total_rows=sum(len(load_jsonl(raw_dir / name)) for name in args.source_files),
        ratios=DEFAULT_RATIOS,
    )

    freeze_result = freeze_sources(raw_dir, frozen_dir, args.source_files)
    rows = freeze_result["rows"]

    row_ids = [row["id"] for row in rows]
    if len(row_ids) != len(set(row_ids)):
        raise RuntimeError("Duplicate IDs detected before split generation.")

    groups, near_duplicate_pairs = detect_groups(
        rows,
        threshold=args.near_duplicate_threshold,
        ngram_size=args.ngram_size,
    )
    for group in groups:
        for row in group.items:
            row["_group_id"] = group.group_id

    split_rows, split_groups, nominal_category_targets, actual_category_targets = build_initial_splits(
        groups,
        split_targets,
        DEFAULT_RATIOS,
    )
    singleton_moves = adjust_with_singleton_moves(
        split_rows,
        split_groups,
        split_targets,
        nominal_category_targets,
    )
    finalized_rows = finalize_split_rows(split_rows)

    output_dir.mkdir(parents=True, exist_ok=True)
    split_paths = {}
    for split in SPLIT_ORDER:
        path = output_dir / f"{split}.jsonl"
        write_jsonl(path, finalized_rows[split])
        split_paths[split] = path

    group_split_lookup = {
        row["_group_id"]: split
        for split in SPLIT_ORDER
        for row in split_rows[split]
    }

    verification = {
        "total_source_rows": len(rows),
        "total_split_rows": sum(len(finalized_rows[split]) for split in SPLIT_ORDER),
        "total_rows_match": len(rows) == sum(len(finalized_rows[split]) for split in SPLIT_ORDER),
        "group_leakage": check_group_leakage(groups, finalized_rows),
    }
    verification["schema_validation"] = validate_split_files(split_paths)

    manifest = {
        "dataset_name": "zphyr_v2_validated_ft",
        "seed": args.seed,
        "ratios": DEFAULT_RATIOS,
        "target_split_sizes": split_targets,
        "near_duplicate_threshold": args.near_duplicate_threshold,
        "ngram_size": args.ngram_size,
        "included_files": args.source_files,
        "excluded_files": args.excluded_files,
        "freeze": {
            "directory": str(frozen_dir),
            "merged_path": freeze_result["merged_path"],
            "merged_row_count": freeze_result["merged_row_count"],
            "merged_sha256": freeze_result["merged_sha256"],
            "files": freeze_result["files"],
        },
        "nominal_category_targets": nominal_category_targets,
        "actual_category_targets": final_category_counts_by_split(finalized_rows),
        "singleton_moves_after_category_assignment": singleton_moves,
        "splits": {
            split: {
                "path": str(split_paths[split]),
                **build_stats(finalized_rows[split]),
            }
            for split in SPLIT_ORDER
        },
        "near_duplicate_pairs": near_duplicate_pairs,
        "near_duplicate_groups": build_group_report(groups, group_split_lookup),
        "verification": verification,
    }

    write_json(frozen_dir / "freeze_manifest_validated_ft.json", manifest["freeze"])
    write_json(output_dir / "manifest.json", manifest)
    write_json(output_dir / "verification.json", verification)
    write_json(output_dir / "near_duplicate_groups.json", manifest["near_duplicate_groups"])
    (output_dir / "report.md").write_text(build_markdown_report(manifest), encoding="utf-8")

    print("Created validated v2 freeze and splits.")
    print(f"  Frozen directory: {frozen_dir}")
    print(f"  Split directory:  {output_dir}")
    for split in SPLIT_ORDER:
        print(f"  {split:5} -> {len(finalized_rows[split])} rows")
    print(f"  Near-duplicate groups kept together: {len(manifest['near_duplicate_groups'])}")
    print(f"  Verification clean: {verification['group_leakage']['clean']}")


if __name__ == "__main__":
    main()
