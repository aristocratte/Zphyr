#!/usr/bin/env python3
"""
Adjust splits to ensure hard negative coverage in val/test.

Move 1 ambiguous_command_content from train to test.
Move 1 regular example from test to train to preserve 210/45/45.
"""

import json
import random
from pathlib import Path


def load_split(name: str) -> list:
    """Load a split file."""
    path = Path(f"datasets/splits/{name}.jsonl")
    rows = []
    with open(path) as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def write_split(rows: list, name: str):
    """Write a split file."""
    path = Path(f"datasets/splits/{name}.jsonl")
    with open(path, "w") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


def main():
    random.seed(42)

    # Load current splits
    train = load_split("train")
    val = load_split("val")
    test = load_split("test")

    print("Current state:")
    print(f"  Train: {len(train)}")
    print(f"  Val: {len(val)}")
    print(f"  Test: {len(test)}")
    print()

    # Find ambiguous_command_content in train
    train_ambiguous = [r for r in train if r.get("subcategory") == "ambiguous_command_content"]
    print(f"ambiguous_command_content in train: {len(train_ambiguous)}")
    for r in train_ambiguous:
        print(f"  - {r.get('id')}")
    print()

    # Find candidates to swap back from test to train
    # Choose a non-critical, non-hard-negative from test
    test_candidates = [
        r for r in test
        if not r.get("subcategory") in ["intentional_repetition", "no_list_ambiguous", "ambiguous_command_content"]
        and not r.get("notes", "").startswith("CRITICAL")
    ]
    print(f"Non-critical candidates in test: {len(test_candidates)}")

    if test_candidates:
        swap_from_test = test_candidates[0]
        print(f"  Selected to move to train: {swap_from_test.get('id')} ({swap_from_test.get('category')}/{swap_from_test.get('subcategory')})")
    print()

    # Perform the swap
    # Move 1 ambiguous_command_content from train to test
    move_to_test = train_ambiguous[0]
    print(f"Moving {move_to_test.get('id')} from train to test")

    # Remove from train, add to test
    train = [r for r in train if r.get("id") != move_to_test.get("id")]
    test.append(move_to_test)

    # Move selected candidate from test to train
    if test_candidates:
        test = [r for r in test if r.get("id") != swap_from_test.get("id")]
        train.append(swap_from_test)

    print(f"Moving {swap_from_test.get('id')} from test to train")
    print()

    # Verify counts
    print("After adjustment:")
    print(f"  Train: {len(train)}")
    print(f"  Val: {len(val)}")
    print(f"  Test: {len(test)}")
    print()

    if len(train) != 210 or len(val) != 45 or len(test) != 45:
        print("WARNING: Counts don't match targets!")
        return

    print("✓ Counts preserved (210/45/45)")
    print()

    # Verify hard negative distribution
    print("New hard negative distribution:")
    for split_name, split_data in [("train", train), ("val", val), ("test", test)]:
        hard_negs = [
            r for r in split_data
            if r.get("subcategory") in ["intentional_repetition", "no_list_ambiguous", "ambiguous_command_content"]
        ]
        print(f"  {split_name}: {len(hard_negs)}")
        for r in hard_negs:
            print(f"    - {r.get('id')} ({r.get('subcategory')})")
    print()

    # Write adjusted splits
    print("Writing adjusted splits...")
    write_split(train, "train")
    write_split(val, "val")
    write_split(test, "test")
    print("Done!")


if __name__ == "__main__":
    main()
