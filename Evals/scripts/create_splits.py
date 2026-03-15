#!/usr/bin/env python3
"""
Create stratified train/val/test splits from the Zphyr seed dataset.

Target splits: 70% train, 15% val, 15% test
Exact target: 210 train, 45 val, 45 test (from 300 total)
"""

import json
import random
from pathlib import Path
from collections import defaultdict, Counter
from typing import Dict, List, Set
import hashlib


def load_seed_data() -> List[Dict]:
    """Load all seed JSONL files."""
    seed_dir = Path("datasets/raw/seed")
    all_rows = []

    for seed_file in sorted(seed_dir.glob("seed_*.jsonl")):
        with open(seed_file) as f:
            for line in f:
                if line.strip():
                    all_rows.append(json.loads(line))

    return all_rows


def compute_row_signature(row: Dict) -> str:
    """Compute a signature for deduplication."""
    raw = row.get("raw_asr_text", "").lower().strip()
    expected = row.get("final_expected_text", "").lower().strip()
    combined = f"{raw}|{expected}"
    return hashlib.md5(combined.encode()).hexdigest()


def find_exact_duplicates(rows: List[Dict]) -> Dict[str, List[str]]:
    """Find exact duplicates."""
    signatures = defaultdict(list)

    for row in rows:
        sig = compute_row_signature(row)
        signatures[sig].append(row.get("id"))

    return {sig: ids for sig, ids in signatures.items() if len(ids) > 1}


def categorize_rows(rows: List[Dict]) -> Dict[str, List[Dict]]:
    """Categorize rows by category.subcategory for stratified splitting."""
    groups = defaultdict(list)

    for row in rows:
        cat = row.get("category", "unknown")
        sub = row.get("subcategory", "unknown")
        key = f"{cat}/{sub}"
        groups[key].append(row)

    return groups


def is_critical(row: Dict) -> bool:
    """Check if row is marked as critical."""
    notes = row.get("notes", "")
    return notes.startswith("CRITICAL") or "NEGATIVE EXAMPLE" in notes.upper()


def is_hard_negative(row: Dict) -> bool:
    """Check if row is a hard negative example."""
    sub = row.get("subcategory", "")
    notes = row.get("notes", "")
    return "ambiguous" in sub.lower() or "intentional" in sub.lower() or "NEGATIVE" in notes.upper()


def create_exact_split(
    rows: List[Dict],
    target_train: int = 210,
    target_val: int = 45,
    target_test: int = 45,
    seed: int = 42
) -> tuple[List[Dict], List[Dict], List[Dict]]:
    """
    Create exact target splits (210/45/45).

    Strategy:
    1. First, reserve critical examples for val/test (2 each)
    2. Stratify remaining by category
    3. Fill to exact counts
    """

    random.seed(seed)

    groups = categorize_rows(rows)

    # Separate critical/hard_negative examples
    critical_examples = [r for r in rows if is_critical(r) or is_hard_negative(r)]
    regular_examples = [r for r in rows if not is_critical(r) and not is_hard_negative(r)]

    random.shuffle(critical_examples)
    random.shuffle(regular_examples)

    # Allocate critical examples: at least 1 to val, 1 to test, rest to train
    crit_val = min(2, len(critical_examples))
    crit_test = min(2, len(critical_examples) - crit_val)
    crit_train = len(critical_examples) - crit_val - crit_test

    val_critical = critical_examples[:crit_val]
    test_critical = critical_examples[crit_val:crit_val + crit_test]
    train_critical = critical_examples[crit_val + crit_test:]

    # Now allocate regular examples by category to maintain balance
    remaining_train = target_train - len(train_critical)
    remaining_val = target_val - len(val_critical)
    remaining_test = target_test - len(test_critical)

    train_regular, val_regular, test_regular = [], [], []

    for group_key, group_rows in groups.items():
        # Filter out critical examples (already allocated)
        group_regular = [r for r in group_rows if r not in critical_examples]
        if not group_regular:
            continue

        group_size = len(group_regular)

        # Proportional allocation
        group_train = max(0, round(group_size * remaining_train / len(regular_examples)))
        group_val = max(0, round(group_size * remaining_val / len(regular_examples)))
        group_test = group_size - group_train - group_val

        random.shuffle(group_regular)

        train_regular.extend(group_regular[:group_train])
        val_regular.extend(group_regular[group_train:group_train + group_val])
        test_regular.extend(group_regular[group_train + group_val:])

    # Trim to exact remaining targets
    train_regular = train_regular[:remaining_train]
    val_regular = val_regular[:remaining_val]
    test_regular = test_regular[:remaining_test]

    # If short, add more from regular pool (use IDs for set operations)
    used_ids = {r.get("id") for r in train_regular + val_regular + test_regular}
    remaining_regular = [r for r in regular_examples if r.get("id") not in used_ids]
    random.shuffle(remaining_regular)

    while len(train_regular) < remaining_train and remaining_regular:
        train_regular.append(remaining_regular.pop())
    while len(val_regular) < remaining_val and remaining_regular:
        val_regular.append(remaining_regular.pop())
    while len(test_regular) < remaining_test and remaining_regular:
        test_regular.append(remaining_regular.pop())

    # Combine
    train = train_critical + train_regular
    val = val_critical + val_regular
    test = test_critical + test_regular

    # Final trim to exact targets
    train = train[:target_train]
    val = val[:target_val]
    test = test[:target_test]

    return train, val, test


def compute_statistics(split_name: str, rows: List[Dict]) -> Dict:
    """Compute detailed statistics for a split."""
    stats = {
        "split": split_name,
        "total_rows": len(rows),
        "categories": Counter(r.get("category") for r in rows),
        "subcategories": Counter(r.get("subcategory") for r in rows),
        "null_edit_count": sum(1 for r in rows if r.get("is_null_edit", False)),
        "null_edit_ratio": sum(1 for r in rows if r.get("is_null_edit", False)) / len(rows) if rows else 0,
        "severity": Counter(r.get("severity_if_wrong", "unknown") for r in rows),
        "languages": Counter(r.get("language", "unknown") for r in rows),
        "critical_examples": sum(1 for r in rows if is_critical(r)),
        "hard_negatives": sum(1 for r in rows if is_hard_negative(r)),
        "rewrite_levels": Counter(r.get("rewrite_allowed_level", "unknown") for r in rows),
        "difficulty": Counter(r.get("difficulty", "unknown") for r in rows),
    }
    return stats


def write_split(rows: List[Dict], output_path: Path):
    """Write split to JSONL file."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


def print_split_table(all_rows: List[Dict], train: List[Dict], val: List[Dict], test: List[Dict]):
    """Print category balance table."""
    print("  CATEGORY         TRAIN    VAL      TEST     TOTAL")
    print("  " + "-" * 52)

    all_categories = sorted(set(r.get("category") for r in all_rows))

    for cat in all_categories:
        train_c = sum(1 for r in train if r.get("category") == cat)
        val_c = sum(1 for r in val if r.get("category") == cat)
        test_c = sum(1 for r in test if r.get("category") == cat)
        total = train_c + val_c + test_c

        if total > 0:
            print(f"  {cat:15} {train_c:3} ({train_c/total*100:.0f}%)  "
                  f"{val_c:3} ({val_c/total*100:.0f}%)  "
                  f"{test_c:3} ({test_c/total*100:.0f}%)  {total:3}")

    print("  " + "-" * 52)
    print(f"  {'TOTAL':15} {len(train):3} ({len(train)/len(all_rows)*100:.0f}%)  "
          f"{len(val):3} ({len(val)/len(all_rows)*100:.0f}%)  "
          f"{len(test):3} ({len(test)/len(all_rows)*100:.0f}%)  {len(all_rows):3}")


def check_near_duplicate_leakage(train: List[Dict], val: List[Dict], test: List[Dict], threshold: float = 0.85):
    """Check for near-duplicates across splits."""
    from difflib import SequenceMatcher

    id_to_split = {}
    for r in train:
        id_to_split[r.get("id")] = "train"
    for r in val:
        id_to_split[r.get("id")] = "val"
    for r in test:
        id_to_split[r.get("id")] = "test"

    all_rows = train + val + test
    leakage_found = []

    # Check every 5th row for efficiency
    for i in range(0, len(all_rows), 5):
        for j in range(i + 1, len(all_rows), 5):
            raw1 = all_rows[i].get("raw_asr_text", "").lower()
            raw2 = all_rows[j].get("raw_asr_text", "").lower()

            if len(raw1) < 10 or len(raw2) < 10:
                continue

            similarity = SequenceMatcher(None, raw1, raw2).ratio()

            if similarity >= threshold:
                split1 = id_to_split.get(all_rows[i].get("id"), "?")
                split2 = id_to_split.get(all_rows[j].get("id"), "?")

                if split1 != split2:
                    leakage_found.append((
                        all_rows[i].get("id"),
                        split1,
                        all_rows[j].get("id"),
                        split2,
                        similarity
                    ))

    return leakage_found


def main():
    print("=" * 70)
    print("Zphyr v1 Seed Dataset — Exact 70/15/15 Split Creation")
    print("=" * 70)
    print()

    # Load data
    print("Loading seed data...")
    rows = load_seed_data()
    print(f"Loaded {len(rows)} rows")
    print()

    # Check duplicates
    print("Checking for exact duplicates...")
    exact_dups = find_exact_duplicates(rows)
    if exact_dups:
        print(f"Found {len(exact_dups)} exact duplicate group(s):")
        for sig, ids in list(exact_dups.items())[:5]:
            print(f"  {', '.join(ids)}")
    else:
        print("  No exact duplicates found")
    print()

    # Create splits with exact targets
    target_train, target_val, target_test = 210, 45, 45
    print(f"Creating exact splits: {target_train}/{target_val}/{target_test}")
    train, val, test = create_exact_split(rows, target_train, target_val, target_test)

    actual_train, actual_val, actual_test = len(train), len(val), len(test)
    print(f"  Result: {actual_train}/{actual_val}/{actual_test}")

    if actual_train != target_train or actual_val != target_val or actual_test != target_test:
        print(f"  WARNING: Targets not met exactly!")
        print(f"    Train: {actual_train}/{target_train} ({target_train - actual_train} diff)")
        print(f"    Val: {actual_val}/{target_val} ({target_val - actual_val} diff)")
        print(f"    Test: {actual_test}/{target_test} ({target_test - actual_test} diff)")
    else:
        print(f"  ✓ Exact targets achieved!")
    print()

    # Verify total
    if actual_train + actual_val + actual_test != len(rows):
        print(f"  ERROR: Row count mismatch! {actual_train + actual_val + actual_test} != {len(rows)}")
    else:
        print(f"  ✓ All {len(rows)} rows accounted for")
    print()

    # Write splits
    print("Writing split files...")
    splits_dir = Path("datasets/splits")
    write_split(train, splits_dir / "train.jsonl")
    write_split(val, splits_dir / "val.jsonl")
    write_split(test, splits_dir / "test.jsonl")
    print(f"  Written to {splits_dir}/")
    print()

    # Statistics
    print("=" * 70)
    print("SPLIT STATISTICS")
    print("=" * 70)
    print()

    total_rows = len(rows)
    for name, data in [("train", train), ("val", val), ("test", test)]:
        stats = compute_statistics(name, data)
        print(f"## {name.upper()} ({stats['total_rows']} rows, {stats['total_rows']/total_rows*100:.1f}%)")
        print()
        print(f"  Null edits: {stats['null_edit_count']} ({stats['null_edit_ratio']:.1%})")
        print(f"  Critical examples: {stats['critical_examples']}")
        print(f"  Hard negatives: {stats['hard_negatives']}")
        print(f"  Severity: {dict(sorted(stats['severity'].items()))}")
        print(f"  Languages: {dict(stats['languages'])}")
        print(f"  Difficulty: {dict(sorted(stats['difficulty'].items()))}")
        print()

    print("=" * 70)
    print("CATEGORY BALANCE")
    print("=" * 70)
    print()
    print_split_table(rows, train, val, test)
    print()

    print("=" * 70)
    print("CRITICAL & HARD NEGATIVE DISTRIBUTION")
    print("=" * 70)
    print()

    for split_name, split_data in [("TRAIN", train), ("VAL", val), ("TEST", test)]:
        critical_in_split = [r for r in split_data if is_critical(r)]
        hard_neg_in_split = [r for r in split_data if is_hard_negative(r) and r not in critical_in_split]

        if critical_in_split or hard_neg_in_split:
            print(f"{split_name}:")
            for r in critical_in_split:
                print(f"  - {r.get('id')} ({r.get('category')}/{r.get('subcategory')})")
            for r in hard_neg_in_split:
                print(f"  - {r.get('id')} ({r.get('category')}/{r.get('subcategory')}) [hard negative]")

    print()

    print("=" * 70)
    print("NEAR-DUPLICATE LEAKAGE CHECK")
    print("=" * 70)
    print()

    leakage = check_near_duplicate_leakage(train, val, test)
    if leakage:
        print(f"Found {len(leakage)} potential leakage pairs:")
        for id1, s1, id2, s2, sim in leakage[:10]:
            print(f"  ⚠️ {id1} ({s1}) ↔ {id2} ({s2}) sim={sim:.2f}")
    else:
        print("  No near-duplicate leakage detected (threshold=0.85)")

    print()
    print("=" * 70)
    print("Split creation complete!")
    print("=" * 70)


if __name__ == "__main__":
    main()
