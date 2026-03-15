#!/usr/bin/env python3
"""
Score MLX baseline outputs from eval_formatter.swift

Computes metrics on baselines/mlx_baseline_outputs.jsonl
"""

import json
import argparse
from pathlib import Path
from collections import defaultdict


def load_results(results_file: str):
    """Load MLX baseline results."""
    results = []
    with open(results_file) as f:
        for line in f:
            if line.strip():
                # Parse the JSONL output
                try:
                    # Remove surrounding braces if present
                    cleaned = line.strip()
                    if cleaned.startswith('{') and cleaned.endswith('}'):
                        cleaned = cleaned[1:-1]
                    results.append(json.loads("{" + cleaned + "}"))
                except:
                    continue
    return results


def compute_wer(ref, hyp):
    """Word Error Rate."""
    ref_words = ref.split()
    hyp_words = hyp.split()
    if not ref_words:
        return 0.0
    m, n = len(ref_words), len(hyp_words)
    dp = [[0] * (n + 1) for _ in range(m + 1)]
    for i in range(m + 1):
        dp[i][0] = i
    for j in range(n + 1):
        dp[0][j] = j
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            cost = 0 if ref_words[i-1].lower() == hyp_words[j-1].lower() else 1
            dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
    return dp[m][n] / m


def compute_cer(ref, hyp):
    """Character Error Rate."""
    ref_chars = list(ref)
    hyp_chars = list(hyp)
    if not ref_chars:
        return 0.0
    m, n = len(ref_chars), len(hyp_chars)
    dp = [[0] * (n + 1) for _ in range(m + 1)]
    for i in range(m + 1):
        dp[i][0] = i
    for j in range(n + 1):
        dp[0][j] = j
    for i in range(1, m + 1):
        for j in range(1, n + 1):
            cost = 0 if ref_chars[i-1].lower() == hyp_chars[j-1].lower() else 1
            dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
    return dp[m][n] / m


def score_results(results):
    """Score MLX baseline results."""
    results = [r for r in results if r.get("output") and r["output"] != "ERROR"]

    metrics = {
        "total_examples": len(results),
        "successful_inference": len(results),
        "overall_wer": sum(r["wer"] for r in results) / len(results),
        "overall_cer": sum(r["cer"] for r in results) / len(results),
        "categories": defaultdict(lambda: {"wer": [], "cer": [], "count": 0}),
        "null_edit_preserved": 0,
        "null_edit_total": 0,
        "protected_term_preserved": 0,
        "protected_term_total": 0,
        "hard_negatives": {"total": 0, "passed": 0},
        "failures": {
            "null_edit_failures": [],
            "protected_term_failures": [],
            "hard_negative_failures": []
        }
    }

    for r in results:
        cat = r["category"]
        metrics["categories"][cat]["wer"].append(r["wer"])
        metrics["categories"][cat]["cer"].append(r["cer"])
        metrics["categories"][cat]["count"] += 1

        # Null edits
        if r.get("is_null_edit"):
            metrics["null_edit_total"] += 1
            if r["raw"] == r["output"]:
                metrics["null_edit_preserved"] += 1
            else:
                metrics["failures"]["null_edit_failures"].append(r)

        # Protected terms
        protected = r.get("protected_terms", [])
        if protected:
            metrics["protected_term_total"] += len(protected)
            surviving = sum(1 for t in protected if t in r["output"])
            metrics["protected_term_preserved"] += surviving
            if surviving < len(protected):
                metrics["failures"]["protected_term_failures"].append({
                    "id": r["id"],
                    "missing": [t for t in protected if t not in r["output"]]
                })

        # Hard negatives (inferred from subcategory)
        if r["subcategory"] in ["intentional_repetition", "no_list_ambiguous", "ambiguous_command_content"]:
            metrics["hard_negatives"]["total"] += 1
            if r["output"] == r["expected"]:
                metrics["hard_negatives"]["passed"] += 1
            else:
                metrics["failures"]["hard_negative_failures"].append(r)

    return metrics


def print_metrics(metrics):
    """Print evaluation metrics."""
    print("=" * 70)
    print("MLX BASELINE EVALUATION RESULTS")
    print("=" * 70)
    print()

    print(f"Total examples: {metrics['total_examples']}")
    print(f"Successful: {metrics['successful_inference']}")
    print()

    print(f"Overall WER: {metrics['overall_wer']:.4f}")
    print(f"Overall CER: {metrics['overall_cer']:.4f}")
    print()

    print(f"Null edit preservation: {metrics['null_edit_preserved']}/{metrics['null_edit_total']} ({metrics['null_edit_preserved']/max(metrics['null_edit_total'],1):.1%})")

    if metrics['protected_term_total'] > 0:
        print(f"Protected term accuracy: {metrics['protected_term_preserved']}/{metrics['protected_term_total']} ({metrics['protected_term_preserved']/metrics['protected_term_total']:.1%})")

    if metrics['hard_negatives']['total'] > 0:
        print(f"Hard negative pass rate: {metrics['hard_negatives']['passed']}/{metrics['hard_negatives']['total']} ({metrics['hard_negatives']['passed']/metrics['hard_negatives']['total']:.1%})")

    print()
    print("-" * 70)
    print("CATEGORY BREAKDOWN")
    print("-" * 70)

    for cat in sorted(metrics["categories"].keys()):
        data = metrics["categories"][cat]
        avg_wer = sum(data["wer"]) / len(data["wer"])
        avg_cer = sum(data["cer"]) / len(data["cer"])
        print(f"  {cat:15} WER={avg_wer:.4f}  CER={avg_cer:.4f}  (n={data['count']})")

    print()
    print("-" * 70)
    print("FAILURE ANALYSIS")
    print("-" * 70)

    if metrics["failures"]["null_edit_failures"]:
        print(f"\nNull edit failures ({len(metrics['failures']['null_edit_failures'])}):")
        for r in metrics["failures"]["null_edit_failures"][:5]:
            print(f"  - {r['id']}: '{r['raw']}' → '{r['output']}'")

    if metrics["failures"]["protected_term_failures"]:
        print(f"\nProtected term failures ({len(metrics['failures']['protected_term_failures'])}):")
        for r in metrics["failures"]["protected_term_failures"][:5]:
            print(f"  - {r['id']}: missing {r['missing']}")

    if metrics["failures"]["hard_negative_failures"]:
        print(f"\nHard negative failures ({len(metrics['failures']['hard_negative_failures'])}):")
        for r in metrics["failures"]["hard_negative_failures"]:
            print(f"  - {r['id']}: {r['subcategory']}")
            print(f"    Expected: '{r['expected']}'")
            print(f"    Got:      '{r['output']}'")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default="baselines/mlx_baseline_outputs.jsonl")
    parser.add_argument("--output", default="baselines/mlx_baseline_metrics.json")
    args = parser.parse_args()

    results = load_results(args.input)
    metrics = score_results(results)

    # Save metrics
    with open(args.output, "w") as f:
        json.dump(metrics, f, indent=2, default=str)

    print_metrics(metrics)


if __name__ == "__main__":
    main()
