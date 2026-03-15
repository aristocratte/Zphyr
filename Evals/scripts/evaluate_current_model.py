#!/usr/bin/env python3
"""
Evaluate arhesstide/zphyr_qwen_v1-MLX-4bit on Zphyr test set.

This script evaluates the CURRENT fine-tuned model on the new 300-example
seed split to identify failure modes before deciding on patch fine-tuning.

Usage:
    cd Evals
    python scripts/evaluate_current_model.py --test-file datasets/splits/test.jsonl
"""

import json
import argparse
import subprocess
import sys
from pathlib import Path
from collections import defaultdict
from typing import Dict, List, Optional


def load_test_data(test_file: str) -> List[Dict]:
    """Load test set examples."""
    with open(test_file) as f:
        return [json.loads(line) for line in f if line.strip()]


def compute_wer(reference: str, hypothesis: str) -> float:
    """Compute Word Error Rate."""
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
            cost = 0 if ref_words[i-1].lower() == hyp_words[j-1].lower() else 1
            dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)

    return dp[m][n] / m


def compute_cer(reference: str, hypothesis: str) -> float:
    """Compute Character Error Rate."""
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
            cost = 0 if ref_chars[i-1].lower() == hyp_chars[j-1].lower() else 1
            dp[i][j] = min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)

    return dp[m][n] / m


class ModelEvaluator:
    """Base class for model evaluation."""

    def format(self, text: str) -> Optional[str]:
        """Format text using the model. To be implemented by subclass."""
        raise NotImplementedError


class MockConservativeEvaluator(ModelEvaluator):
    """
    Mock evaluator that simulates a conservative baseline.
    For testing when the actual model is unavailable.
    """

    def format(self, text: str) -> Optional[str]:
        """Conservative: mostly capitalize and add period."""
        text = text.strip()
        if not text:
            return None

        # Very conservative: capitalize first letter, add period
        result = text[0].upper() + text[1:]
        if not any(text.endswith(p) for p in '.!?…'):
            result += '.'
        return result


class HuggingFaceEvaluator(ModelEvaluator):
    """Evaluate using Hugging Face transformers (if model available)."""

    def __init__(self, model_path: str):
        self.model_path = model_path
        self.model = None
        self.tokenizer = None
        self._load_attempted = False

    def _ensure_loaded(self):
        if self._load_attempted:
            return
        self._load_attempted = True

        try:
            from transformers import AutoModelForCausalLM, AutoTokenizer

            print(f"Loading model from {self.model_path}...")
            self.tokenizer = AutoTokenizer.from_pretrained(self.model_path)
            self.model = AutoModelForCausalLM.from_pretrained(self.model_path)
            print("Model loaded successfully")
        except Exception as e:
            print(f"Failed to load HuggingFace model: {e}")
            print("This is expected if using MLX-quantized weights")
            print("Falling back to mock evaluation for pipeline verification")

    def format(self, text: str) -> Optional[str]:
        """Format text using the model."""
        try:
            self._ensure_loaded()
            if self.model is None or self.tokenizer is None:
                return None

            # Qwen chat format
            messages = [
                {"role": "system", "content": self._get_system_prompt()},
                {"role": "user", "content": f"Format this text: {text}"}
            ]

            text_prompt = self.tokenizer.apply_chat_template(
                messages,
                tokenize=False,
                add_generation_prompt=True
            )

            inputs = self.tokenizer(text_prompt, return_tensors="pt")
            outputs = self.model.generate(
                **inputs,
                max_new_tokens=256,
                temperature=0,
                do_sample=False
            )

            result = self.tokenizer.decode(outputs[0][inputs["input_ids"].shape[1]:], skip_special_tokens=True)
            return result.strip()

        except Exception as e:
            print(f"Error during inference: {e}")
            return None

    def _get_system_prompt(self) -> str:
        """Get the system prompt for the model."""
        # This is the CURRENT prompt from AdvancedLLMFormatter.swift
        return """You are a highly precise text formatting engine. Your ONLY job is to take raw voice dictation text and output clean, professionally formatted text.

STRICT RULES:

SPOKEN PUNCTUATION: You MUST convert spoken commands into actual symbols.
"virgule" -> ,
"point" -> .
"à la ligne" -> \\n
"nouveau paragraphe" -> \\n\\n

CODE VARIABLES: If the user dictates code variables, functions, or classes, you MUST format them correctly (camelCase by default) and fix their spelling if the raw text wrote them phonetically (e.g., "fetch user data" -> "fetchUserData", "max retraise alloud" -> "maxRetriesAllowed").

CLEANUP: Remove hesitation words like "euh", "hum", "bah". Fix obvious phonetic transcription errors.

DO NOT add conversational filler (e.g., "Voici le texte", "Sure"). Output ONLY the final text."""


class SwiftMLXBridge(ModelEvaluator):
    """
    Bridge to Swift/MLX model via command line.

    This requires building a small Swift command-line tool that exposes
    the formatting function. For now, documents the interface.
    """

    def format(self, text: str) -> Optional[str]:
        """
        Format text by calling Swift/MLX model.

        Requires: Zphyr/eval/format.swift to be compiled as:
          swiftc eval/format.swift -o eval/format -L ...MLX dependencies...
        """
        tool_path = Path("../Zphyr/eval/format")
        if not tool_path.exists():
            print(f"Swift tool not found at {tool_path}")
            print("To evaluate the MLX model, you need to either:")
            print("1. Build a Swift CLI wrapper for AdvancedLLMFormatter")
            print("2. Convert the model to HuggingFace format")
            print("3. Use the evaluation harness in ZphyrTests/")
            return None

        try:
            result = subprocess.run(
                [str(tool_path), text],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                return result.stdout.strip()
            else:
                print(f"Swift tool error: {result.stderr}")
                return None
        except Exception as e:
            print(f"Error calling Swift tool: {e}")
            return None


def evaluate_example(example: Dict, model_output: str) -> Dict:
    """Evaluate a single example."""
    expected = example.get("final_expected_text", "")
    raw = example.get("raw_asr_text", "")

    result = {
        "id": example.get("id"),
        "category": example.get("category"),
        "subcategory": example.get("subcategory"),
        "raw": raw,
        "expected": expected,
        "output": model_output,
        "wer": compute_wer(expected, model_output) if model_output else None,
        "cer": compute_cer(expected, model_output) if model_output else None,
        "is_null_edit": example.get("is_null_edit", False),
        "null_edit_preserved": (raw == model_output) if model_output else None,
        "has_protected_terms": bool(example.get("protected_terms")),
        "protected_terms": example.get("protected_terms", []),
        "no_translation": example.get("no_translation", False),
        "is_hard_negative": example.get("subcategory") in [
            "intentional_repetition", "no_list_ambiguous", "ambiguous_command_content"
        ],
        "notes": example.get("notes", "")
    }

    # Check protected term preservation
    if result["protected_terms"]:
        missing = [t for t in result["protected_terms"] if t not in model_output]
        result["protected_terms_preserved"] = len(missing) == 0
        result["protected_terms_missing"] = missing
    else:
        result["protected_terms_preserved"] = None
        result["protected_terms_missing"] = []

    # Hard negative pass = output matches expected (conservative behavior)
    result["hard_negative_pass"] = result["is_hard_negative"] and (model_output == expected) if model_output else False

    # Check for obvious translation violations (simplified)
    result["translation_violation"] = False  # Would need linguistic analysis

    return result


def print_summary(results: List[Dict]):
    """Print evaluation summary."""
    print("=" * 70)
    print("CURRENT MODEL EVALUATION SUMMARY")
    print("=" * 70)
    print()

    valid_results = [r for r in results if r["output"] is not None]
    failed_results = [r for r in results if r["output"] is None]

    print(f"Total examples: {len(results)}")
    print(f"Successful inference: {len(valid_results)}")
    print(f"Failed inference: {len(failed_results)}")
    print()

    if not valid_results:
        print("No successful results to analyze")
        return

    # Overall metrics
    overall_wer = sum(r["wer"] for r in valid_results) / len(valid_results)
    overall_cer = sum(r["cer"] for r in valid_results) / len(valid_results)

    print(f"Overall WER: {overall_wer:.4f}")
    print(f"Overall CER: {overall_cer:.4f}")
    print()

    # Null edit preservation
    null_edit_results = [r for r in valid_results if r["is_null_edit"]]
    if null_edit_results:
        preserved = sum(1 for r in null_edit_results if r["null_edit_preserved"])
        total = len(null_edit_results)
        print(f"Null edit preservation: {preserved}/{total} ({preserved/total:.1%})")

    # Protected term preservation
    protected_results = [r for r in valid_results if r["has_protected_terms"]]
    if protected_results:
        preserved = sum(1 for r in protected_results if r["protected_terms_preserved"])
        total = len(protected_results)
        total_terms = sum(len(r["protected_terms"]) for r in protected_results)
        survived = sum(
            len(r["protected_terms"]) - len(r["protected_terms_missing"])
            for r in protected_results
        )
        print(f"Protected term accuracy: {survived}/{total_terms} ({survived/total_terms:.1%})")

    # Hard negative pass rate
    hard_negatives = [r for r in valid_results if r["is_hard_negative"]]
    if hard_negatives:
        passed = sum(1 for r in hard_negatives if r["hard_negative_pass"])
        total = len(hard_negatives)
        print(f"Hard negative pass rate: {passed}/{total} ({passed/total:.1%})")

    print()
    print("-" * 70)
    print("CATEGORY BREAKDOWN")
    print("-" * 70)

    categories = {}
    for r in valid_results:
        cat = r["category"]
        if cat not in categories:
            categories[cat] = {"wer": [], "cer": [], "count": 0}
        categories[cat]["wer"].append(r["wer"])
        categories[cat]["cer"].append(r["cer"])
        categories[cat]["count"] += 1

    for cat in sorted(categories.keys()):
        data = categories[cat]
        avg_wer = sum(data["wer"]) / len(data["wer"])
        avg_cer = sum(data["cer"]) / len(data["cer"])
        print(f"  {cat:15} WER={avg_wer:.4f}  CER={avg_cer:.4f}  (n={data['count']})")

    print()
    print("-" * 70)
    print("FAILURE MODES TO INVESTIGATE")
    print("-" * 70)

    # Null edit failures
    null_failures = [r for r in null_edit_results if not r["null_edit_preserved"]]
    if null_failures:
        print(f"\nNull edit failures ({len(null_failures)}):")
        for r in null_failures[:5]:
            print(f"  - {r['id']}: '{r['raw']}' → '{r['output']}'")

    # Protected term failures
    protected_failures = [r for r in protected_results if not r["protected_terms_preserved"]]
    if protected_failures:
        print(f"\nProtected term failures ({len(protected_failures)}):")
        for r in protected_failures[:5]:
            print(f"  - {r['id']}: missing {r['protected_terms_missing']}")

    # Hard negative failures
    hn_failures = [r for r in hard_negatives if not r["hard_negative_pass"]]
    if hn_failures:
        print(f"\nHard negative failures ({len(hn_failures)}):")
        for r in hn_failures:
            print(f"  - {r['id']}: {r['subcategory']}")
            print(f"    Expected: '{r['expected']}'")
            print(f"    Got:      '{r['output']}'")


def main():
    parser = argparse.ArgumentParser(
        description="Evaluate current Zphyr model on test set"
    )
    parser.add_argument(
        "--test-file",
        default="datasets/splits/test.jsonl",
        help="Path to test.jsonl"
    )
    parser.add_argument(
        "--output-file",
        default="baselines/current_model_outputs.jsonl",
        help="Path to save outputs"
    )
    parser.add_argument(
        "--metrics-file",
        default="baselines/current_model_metrics.json",
        help="Path to save metrics"
    )
    parser.add_argument(
        "--model-path",
        help="Path to model (for HuggingFace format)"
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Use mock conservative evaluator instead of real model"
    )
    args = parser.parse_args()

    # Load test data
    print(f"Loading test data from {args.test_file}")
    test_data = load_test_data(args.test_file)
    print(f"Loaded {len(test_data)} examples")
    print()

    # Create evaluator
    if args.mock:
        print("Using MOCK conservative evaluator")
        print("This simulates a conservative baseline for pipeline verification")
        print()
        evaluator = MockConservativeEvaluator()
    elif args.model_path:
        print(f"Using HuggingFace model from {args.model_path}")
        evaluator = HuggingFaceEvaluator(args.model_path)
    else:
        print("No model specified, using MOCK evaluator")
        print("To evaluate the actual MLX model, you need to either:")
        print("1. Build a Swift CLI wrapper for AdvancedLLMFormatter")
        print("2. Convert the model to HuggingFace format")
        print("3. Use --mock flag for pipeline verification")
        print()
        evaluator = MockConservativeEvaluator()

    # Evaluate each example
    print("Running evaluation...")
    results = []

    for example in test_data:
        raw_text = example.get("raw_asr_text", "")
        output = evaluator.format(raw_text)

        result = evaluate_example(example, output or "")
        results.append(result)

        if (len(results) % 10 == 0):
            print(f"  Processed {len(results)}/{len(test_data)}...")

    print()

    # Save outputs
    output_path = Path(args.output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        for result in results:
            f.write(json.dumps(result, ensure_ascii=False) + "\n")

    metrics_path = Path(args.metrics_file)
    metrics_path.parent.mkdir(parents=True, exist_ok=True)

    # Compute and save metrics
    metrics = {
        "overall": {
            "total": len(results),
            "successful": sum(1 for r in results if r["output"] is not None),
            "failed": sum(1 for r in results if r["output"] is None)
        }
    }

    with open(metrics_path, "w") as f:
        json.dump(metrics, f, indent=2)

    print(f"Saved outputs to {args.output_file}")
    print(f"Saved metrics to {args.metrics_file}")
    print()

    # Print summary
    print_summary(results)

    print()
    print("=" * 70)
    print("EVALUATION COMPLETE")
    print("=" * 70)
    print()
    print("Next steps:")
    print("1. Review failure modes above")
    print("2. Check hard_negative_failures.jsonl for detailed analysis")
    print("3. Decide if patch fine-tuning is warranted")


if __name__ == "__main__":
    main()
