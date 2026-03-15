#!/usr/bin/env python3
"""
Comprehensive analysis of Zphyr v1 seed dataset splits.
"""

import json
from pathlib import Path
from collections import Counter, defaultdict


def load_split(name: str) -> list:
    """Load a split file."""
    path = Path(f"datasets/splits/{name}.jsonl")
    rows = []
    with open(path) as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def compute_detailed_stats(name: str, rows: list) -> dict:
    """Compute detailed statistics."""
    stats = {
        "name": name,
        "total": len(rows),
        "categories": defaultdict(int),
        "subcategories": defaultdict(int),
        "null_edits": 0,
        "critical": 0,
        "hard_negatives": 0,
        "severity": defaultdict(int),
        "languages": defaultdict(int),
        "rewrite_levels": defaultdict(int),
        "difficulty": defaultdict(int),
    }

    for r in rows:
        stats["categories"][r.get("category")] += 1
        stats["subcategories"][r.get("subcategory")] += 1
        stats["severity"][r.get("severity", "unknown")] += 1
        stats["languages"][r.get("language", "unknown")] += 1
        stats["rewrite_levels"][r.get("rewrite_allowed_level", "unknown")] += 1
        stats["difficulty"][r.get("difficulty", "unknown")] += 1

        if r.get("is_null_edit"):
            stats["null_edits"] += 1
        if r.get("notes", "").startswith("CRITICAL"):
            stats["critical"] += 1
        sub = r.get("subcategory", "")
        if "ambiguous" in sub or "intentional" in sub:
            stats["hard_negatives"] += 1

    return stats


def print_comparison(train_stats, val_stats, test_stats):
    """Print split comparison."""
    print("=" * 80)
    print("SPLIT COMPARISON")
    print("=" * 80)
    print()

    # Overall
    total = train_stats["total"] + val_stats["total"] + test_stats["total"]
    print(f"{'METRIC':<25} {'TRAIN':>12} {'VAL':>10} {'TEST':>10} {'TOTAL':>10}")
    print("-" * 70)
    print(f"{'Total rows':<25} {train_stats['total']:>12} {val_stats['total']:>10} {test_stats['total']:>10} {total:>10}")
    print(f"{'% of dataset':<25} {train_stats['total']/total*100:>11.1f}% {val_stats['total']/total*100:>9.1f}% {test_stats['total']/total*100:>9.1f}% {100:>9.1f}%")
    print()

    # Null edits
    train_null = train_stats["null_edits"] / train_stats["total"] * 100 if train_stats["total"] else 0
    val_null = val_stats["null_edits"] / val_stats["total"] * 100 if val_stats["total"] else 0
    test_null = test_stats["null_edits"] / test_stats["total"] * 100 if test_stats["total"] else 0
    print(f"{'Null edits (count)':<25} {train_stats['null_edits']:>12} {val_stats['null_edits']:>10} {test_stats['null_edits']:>10} {train_stats['null_edits']+val_stats['null_edits']+test_stats['null_edits']:>10}")
    print(f"{'Null edits (%)':<25} {train_null:>11.1f}% {val_null:>9.1f}% {test_null:>9.1f}%")
    print()

    # Critical examples
    print(f"{'Critical examples':<25} {train_stats['critical']:>12} {val_stats['critical']:>10} {test_stats['critical']:>10} {train_stats['critical']+val_stats['critical']+test_stats['critical']:>10}")
    print(f"{'Hard negatives':<25} {train_stats['hard_negatives']:>12} {val_stats['hard_negatives']:>10} {test_stats['hard_negatives']:>10} {train_stats['hard_negatives']+val_stats['hard_negatives']+test_stats['hard_negatives']:>10}")
    print()


def print_category_distribution(train_stats, val_stats, test_stats):
    """Print category distribution."""
    print("=" * 80)
    print("CATEGORY DISTRIBUTION")
    print("=" * 80)
    print()

    all_cats = set(train_stats["categories"].keys()) | set(val_stats["categories"].keys()) | set(test_stats["categories"].keys())

    print(f"{'Category':<20} {'TRAIN':>8} {'VAL':>8} {'TEST':>8} {'TOTAL':>8}")
    print("-" * 55)

    for cat in sorted(all_cats):
        train_c = train_stats["categories"].get(cat, 0)
        val_c = val_stats["categories"].get(cat, 0)
        test_c = test_stats["categories"].get(cat, 0)
        total = train_c + val_c + test_c
        print(f"{cat:<20} {train_c:>8} {val_c:>8} {test_c:>8} {total:>8}")

    print()


def print_subcategory_detail(train_stats, val_stats, test_stats):
    """Print subcategory distribution for key categories."""
    print("=" * 80)
    print("KEY SUBCATEGORY DISTRIBUTION")
    print("=" * 80)
    print()

    # Groups of related subcategories
    key_groups = {
        "corrections": ["filler_removal", "word_repetition", "spoken_restart", "intentional_repetition"],
        "lists": ["numbered_spoken", "bulleted_spoken", "inline_enumeration", "no_list_ambiguous"],
        "short": ["short_sentence", "single_word_phrase", "title", "filename_tag", "near_empty"],
        "technical": ["code_identifiers", "terminal_commands", "urls_paths", "package_names", "config_env_vars"],
        "commands": ["spoken_punctuation", "trigger_mode", "formatting_commands", "navigation_commands", "ambiguous_command_content"],
    }

    for cat, subs in key_groups.items():
        print(f"{cat.upper()}:")
        print(f"  {'Subcategory':<25} {'TRAIN':>6} {'VAL':>6} {'TEST':>6} {'TOTAL':>6}")
        print(f"  {'-' * 55}")

        for sub in subs:
            train_c = train_stats["subcategories"].get(sub, 0)
            val_c = val_stats["subcategories"].get(sub, 0)
            test_c = test_stats["subcategories"].get(sub, 0)
            total = train_c + val_c + test_c
            if total > 0:
                print(f"  {sub:<25} {train_c:>6} {val_c:>6} {test_c:>6} {total:>6}")
        print()


def main():
    train = load_split("train")
    val = load_split("val")
    test = load_split("test")

    train_stats = compute_detailed_stats("train", train)
    val_stats = compute_detailed_stats("val", val)
    test_stats = compute_detailed_stats("test", test)

    print_comparison(train_stats, val_stats, test_stats)
    print_category_distribution(train_stats, val_stats, test_stats)
    print_subcategory_detail(train_stats, val_stats, test_stats)


if __name__ == "__main__":
    main()
