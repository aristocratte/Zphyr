#!/usr/bin/env python3
"""
Aggregate baseline metrics for Zphyr split evaluations.

Supported inputs:
1. A split JSONL + an optional outputs JSONL.
2. A Swift run artifact produced by EvalSeedSplitTests.
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Dict, List


SCRIPT_DIR = Path(__file__).resolve().parent
EVALS_DIR = SCRIPT_DIR.parent


def load_jsonl(path: Path) -> List[Dict]:
    with open(path, encoding="utf-8-sig") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def compute_wer(reference: str, hypothesis: str) -> float:
    ref_words = reference.split()
    hyp_words = hypothesis.split()

    if not ref_words:
        return 0.0 if not hyp_words else 1.0

    m, n = len(ref_words), len(hyp_words)
    dp = [[0] * (n + 1) for _ in range(m + 1)]

    for i in range(m + 1):
        dp[i][0] = i
    for j in range(n + 1):
        dp[0][j] = j

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if ref_words[i - 1].lower() == hyp_words[j - 1].lower():
                dp[i][j] = dp[i - 1][j - 1]
            else:
                dp[i][j] = 1 + min(
                    dp[i - 1][j],
                    dp[i][j - 1],
                    dp[i - 1][j - 1],
                )

    return dp[m][n] / m


def compute_cer(reference: str, hypothesis: str) -> float:
    ref_chars = list(reference)
    hyp_chars = list(hypothesis)

    if not ref_chars:
        return 0.0 if not hyp_chars else 1.0

    m, n = len(ref_chars), len(hyp_chars)
    dp = [[0] * (n + 1) for _ in range(m + 1)]

    for i in range(m + 1):
        dp[i][0] = i
    for j in range(n + 1):
        dp[0][j] = j

    for i in range(1, m + 1):
        for j in range(1, n + 1):
            if ref_chars[i - 1].lower() == hyp_chars[j - 1].lower():
                dp[i][j] = dp[i - 1][j - 1]
            else:
                dp[i][j] = 1 + min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])

    return dp[m][n] / m


def is_hard_negative(subcategory: str) -> bool:
    return subcategory in [
        "intentional_repetition",
        "no_list_ambiguous",
        "ambiguous_command_content",
    ]


def protected_term_summary(protected_terms: List[str], output: str) -> Dict:
    missing = [term for term in protected_terms if term not in output]
    return {
        "total": len(protected_terms),
        "preserved": not missing,
        "missing": missing,
        "survived": len(protected_terms) - len(missing),
    }


def evaluate_example(example: Dict, output: str) -> Dict:
    expected = example.get("final_expected_text", "")
    raw = example.get("raw_asr_text", "")
    protected = example.get("protected_terms", [])

    result = {
        "id": example.get("id"),
        "category": example.get("category"),
        "subcategory": example.get("subcategory"),
        "raw": raw,
        "expected": expected,
        "output": output,
        "wer": compute_wer(expected, output),
        "cer": compute_cer(expected, output),
        "is_null_edit": example.get("is_null_edit", False),
        "null_edit_preserved": (raw == output) if example.get("is_null_edit") else None,
        "protected_terms": protected_term_summary(protected, output),
        "is_hard_negative": is_hard_negative(example.get("subcategory", "")),
        "notes": example.get("notes", ""),
        "translation_violation": None,
        "total_duration_ms": None,
    }
    result["hard_negative_pass"] = result["is_hard_negative"] and (output == expected)
    return result


def convert_swift_run_record(record: Dict) -> Dict:
    protected_terms = record.get("protectedTerms", [])
    missing_terms = record.get("protectedTermsMissing", [])

    return {
        "id": record.get("caseID"),
        "category": record.get("category"),
        "subcategory": record.get("subcategory"),
        "raw": record.get("rawAsrText", ""),
        "expected": record.get("finalExpectedText", ""),
        "output": record.get("finalText", ""),
        "wer": record.get("wer"),
        "cer": record.get("cer"),
        "is_null_edit": record.get("isNullEdit", False),
        "null_edit_preserved": record.get("nullEditPreserved"),
        "protected_terms": {
            "total": len(protected_terms),
            "preserved": record.get("protectedTermsPreserved", not missing_terms),
            "missing": missing_terms,
            "survived": len(protected_terms) - len(missing_terms),
        },
        "is_hard_negative": record.get("isHardNegative", False),
        "hard_negative_pass": record.get("hardNegativePass", False),
        "notes": "",
        "translation_violation": record.get("translationViolation", False),
        "total_duration_ms": record.get("totalDurationMs"),
        "rewrite_stage_ran": record.get("rewriteStageRan", False),
        "reasoning_tag_contamination": record.get("reasoningTagContamination", False),
    }


def aggregate_metrics(results: List[Dict], split_name: str | None, source_artifact: str) -> Dict:
    category_metrics = defaultdict(lambda: {"wer": [], "cer": [], "count": 0})
    for result in results:
        category = result.get("category", "unknown")
        category_metrics[category]["wer"].append(result["wer"])
        category_metrics[category]["cer"].append(result["cer"])
        category_metrics[category]["count"] += 1

    metrics = {
        "split_name": split_name,
        "source_artifact": source_artifact,
        "overall": {
            "wer": sum(result["wer"] for result in results) / len(results),
            "cer": sum(result["cer"] for result in results) / len(results),
            "total_examples": len(results),
        },
        "by_category": {},
        "null_edit_preservation": {
            "total": sum(1 for result in results if result["is_null_edit"]),
            "preserved": sum(1 for result in results if result["null_edit_preserved"] is True),
            "rate": 0.0,
        },
        "protected_terms": {
            "total_examples_with_terms": sum(1 for result in results if result["protected_terms"]["total"] > 0),
            "total_terms": sum(result["protected_terms"]["total"] for result in results),
            "survived": sum(result["protected_terms"]["survived"] for result in results),
            "accuracy": 0.0,
        },
        "hard_negatives": {
            "total": sum(1 for result in results if result["is_hard_negative"]),
            "passed": sum(1 for result in results if result["hard_negative_pass"]),
            "pass_rate": 0.0,
        },
        "translation_violations": {
            "total": sum(1 for result in results if result.get("translation_violation") is True),
        },
        "reasoning_tag_contamination": {
            "total": sum(1 for result in results if result.get("reasoning_tag_contamination") is True),
        },
        "latency_ms": {
            "mean": None,
        },
        "rewrite_stage": {
            "ran_count": sum(1 for result in results if result.get("rewrite_stage_ran") is True),
            "ran_rate": 0.0,
        },
    }

    if metrics["null_edit_preservation"]["total"] > 0:
        metrics["null_edit_preservation"]["rate"] = (
            metrics["null_edit_preservation"]["preserved"]
            / metrics["null_edit_preservation"]["total"]
        )

    if metrics["protected_terms"]["total_terms"] > 0:
        metrics["protected_terms"]["accuracy"] = (
            metrics["protected_terms"]["survived"]
            / metrics["protected_terms"]["total_terms"]
        )

    if metrics["hard_negatives"]["total"] > 0:
        metrics["hard_negatives"]["pass_rate"] = (
            metrics["hard_negatives"]["passed"]
            / metrics["hard_negatives"]["total"]
        )

    durations = [result["total_duration_ms"] for result in results if result.get("total_duration_ms") is not None]
    if durations:
        metrics["latency_ms"]["mean"] = sum(durations) / len(durations)
    metrics["rewrite_stage"]["ran_rate"] = (
        metrics["rewrite_stage"]["ran_count"] / len(results)
        if results else 0.0
    )

    for category, data in category_metrics.items():
        metrics["by_category"][category] = {
            "wer": sum(data["wer"]) / len(data["wer"]),
            "cer": sum(data["cer"]) / len(data["cer"]),
            "count": data["count"],
        }

    return metrics


def write_jsonl(path: Path, rows: List[Dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")


def write_report(path: Path, metrics: Dict, results: List[Dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines: List[str] = []
    lines.append("# Zphyr Split Baseline Report")
    lines.append("")
    if metrics.get("split_name"):
        lines.append(f"- Split: `{metrics['split_name']}`")
    lines.append(f"- Source artifact: `{metrics['source_artifact']}`")
    lines.append(f"- Total examples: `{metrics['overall']['total_examples']}`")
    lines.append(f"- WER: `{metrics['overall']['wer']:.4f}`")
    lines.append(f"- CER: `{metrics['overall']['cer']:.4f}`")
    lines.append("")
    lines.append("## Core Metrics")
    lines.append("")
    lines.append(f"- Null edit preservation: `{metrics['null_edit_preservation']['preserved']}/{metrics['null_edit_preservation']['total']}` (`{metrics['null_edit_preservation']['rate']:.1%}`)")
    lines.append(f"- Protected term accuracy: `{metrics['protected_terms']['survived']}/{metrics['protected_terms']['total_terms']}` (`{metrics['protected_terms']['accuracy']:.1%}`)")
    lines.append(f"- Hard negative pass rate: `{metrics['hard_negatives']['passed']}/{metrics['hard_negatives']['total']}` (`{metrics['hard_negatives']['pass_rate']:.1%}`)")
    lines.append(f"- Translation violations: `{metrics['translation_violations']['total']}`")
    lines.append(f"- Reasoning tag contamination: `{metrics['reasoning_tag_contamination']['total']}`")
    lines.append(f"- Rewrite stage ran: `{metrics['rewrite_stage']['ran_count']}/{metrics['overall']['total_examples']}` (`{metrics['rewrite_stage']['ran_rate']:.1%}`)")
    if metrics["latency_ms"]["mean"] is not None:
        lines.append(f"- Mean latency: `{metrics['latency_ms']['mean']:.1f} ms`")
    lines.append("")
    lines.append("## Category Breakdown")
    lines.append("")
    lines.append("| Category | WER | CER | Count |")
    lines.append("| --- | ---: | ---: | ---: |")
    for category in sorted(metrics["by_category"]):
        data = metrics["by_category"][category]
        lines.append(f"| {category} | {data['wer']:.4f} | {data['cer']:.4f} | {data['count']} |")
    lines.append("")

    failures = [result for result in results if result["output"] != result["expected"]]
    if failures:
        lines.append("## Sample Failures")
        lines.append("")
        for result in failures[:10]:
            lines.append(f"- `{result['id']}` `{result['category']}/{result['subcategory']}`")
            lines.append(f"  expected: `{result['expected']}`")
            lines.append(f"  output:   `{result['output']}`")
        lines.append("")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def resolve_path(path_str: str) -> Path:
    path = Path(path_str)
    if path.is_absolute():
        return path
    return (EVALS_DIR / path).resolve()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Aggregate baseline metrics for Zphyr split runs.")
    parser.add_argument(
        "--test-file",
        default="datasets/splits/test.jsonl",
        help="Path to split JSONL when evaluating from raw split + outputs.",
    )
    parser.add_argument(
        "--input-file",
        help="Path to model outputs JSONL keyed by id/output when not using a Swift run artifact.",
    )
    parser.add_argument(
        "--run-file",
        help="Path to a Swift run artifact JSON generated by EvalSeedSplitTests.",
    )
    parser.add_argument(
        "--split-name",
        help="Optional human-readable split label stored in the metrics.",
    )
    parser.add_argument(
        "--output-file",
        default="baselines/baseline_outputs.jsonl",
        help="Path to save normalized per-example results.",
    )
    parser.add_argument(
        "--metrics-file",
        default="baselines/baseline_metrics.json",
        help="Path to save aggregated metrics.",
    )
    parser.add_argument(
        "--report-file",
        help="Optional Markdown summary path.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output_path = resolve_path(args.output_file)
    metrics_path = resolve_path(args.metrics_file)
    report_path = resolve_path(args.report_file) if args.report_file else metrics_path.with_suffix(".md")

    if args.run_file:
        run_path = resolve_path(args.run_file)
        print(f"Loading Swift run artifact from {run_path}")
        with open(run_path, encoding="utf-8") as handle:
            run_records = json.load(handle)
        results = [convert_swift_run_record(record) for record in run_records]
        source_artifact = str(run_path)
    else:
        test_path = resolve_path(args.test_file)
        print(f"Loading split data from {test_path}")
        split_rows = load_jsonl(test_path)

        if args.input_file:
            input_path = resolve_path(args.input_file)
            print(f"Loading outputs from {input_path}")
            outputs = {
                row["id"]: row
                for row in load_jsonl(input_path)
            }
        else:
            print("No input file provided; using expected outputs as a perfect-reference baseline.")
            outputs = {
                row["id"]: {"output": row["final_expected_text"]}
                for row in split_rows
            }

        results = [
            evaluate_example(row, outputs.get(row["id"], {}).get("output", ""))
            for row in split_rows
        ]
        source_artifact = str(test_path)

    metrics = aggregate_metrics(results, args.split_name, source_artifact)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    metrics_path.parent.mkdir(parents=True, exist_ok=True)
    write_jsonl(output_path, results)
    metrics_path.write_text(json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_report(report_path, metrics, results)

    print("\n" + "=" * 70)
    print("BASELINE EVALUATION SUMMARY")
    print("=" * 70)
    if metrics.get("split_name"):
        print(f"Split: {metrics['split_name']}")
    print(f"Overall WER: {metrics['overall']['wer']:.4f}")
    print(f"Overall CER: {metrics['overall']['cer']:.4f}")
    print(
        f"Null edit preservation: {metrics['null_edit_preservation']['preserved']}/{metrics['null_edit_preservation']['total']} "
        f"({metrics['null_edit_preservation']['rate']:.1%})"
    )
    print(
        f"Protected term accuracy: {metrics['protected_terms']['survived']}/{metrics['protected_terms']['total_terms']} "
        f"({metrics['protected_terms']['accuracy']:.1%})"
    )
    print(
        f"Hard negative pass rate: {metrics['hard_negatives']['passed']}/{metrics['hard_negatives']['total']} "
        f"({metrics['hard_negatives']['pass_rate']:.1%})"
    )
    print(f"Translation violations: {metrics['translation_violations']['total']}")
    print(f"Reasoning tag contamination: {metrics['reasoning_tag_contamination']['total']}")
    print(
        f"Rewrite stage ran: {metrics['rewrite_stage']['ran_count']}/{metrics['overall']['total_examples']} "
        f"({metrics['rewrite_stage']['ran_rate']:.1%})"
    )
    if metrics["latency_ms"]["mean"] is not None:
        print(f"Mean latency: {metrics['latency_ms']['mean']:.1f} ms")
    print(f"\nNormalized outputs: {output_path}")
    print(f"Metrics JSON:        {metrics_path}")
    print(f"Markdown report:     {report_path}")


if __name__ == "__main__":
    main()
