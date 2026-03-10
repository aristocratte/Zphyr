#!/usr/bin/env python3
"""
Convert Zphyr split datasets from annotation format to Qwen chat training format.

The generated directory is directly compatible with `python3 -m mlx_lm lora`
which expects `train.jsonl` and `valid.jsonl`, with an optional `test.jsonl`.
"""

import json
import argparse
from pathlib import Path
from collections import Counter


ALPACA_INSTRUCTION = (
    "Return only the final formatted text. No reasoning. No explanation. "
    "No <think> tags. No XML or HTML-like tags. Preserve meaning and technical "
    "tokens exactly. Apply only the minimal formatting needed."
)


def load_system_prompt(prompt_file: str) -> str:
    """Load system prompt from file."""
    with open(prompt_file) as f:
        return f.read().strip()


def create_qwen_sample(row: dict, system_prompt: str) -> dict:
    """
    Convert a dataset row to Qwen chat format.

    System prompt is extended with protected terms if present.
    """
    raw_text = row.get("raw_asr_text", "")
    expected_text = row.get("final_expected_text", "")
    protected_terms = row.get("protected_terms", [])

    if "<think>" in expected_text or "</think>" in expected_text:
        raise ValueError(f"Assistant target contains reasoning tags for row {row.get('id')}")

    # Build system prompt
    full_system_prompt = system_prompt

    # Add protected terms instruction if present
    if protected_terms:
        terms_str = ", ".join(protected_terms)
        full_system_prompt += f"\n\nPROTECTED TERMS: {terms_str}\nThese terms MUST survive verbatim."

    # Create messages
    messages = [
        {"role": "system", "content": full_system_prompt},
        {"role": "user", "content": raw_text},
        {"role": "assistant", "content": expected_text}
    ]

    return {"messages": messages}


def create_alpaca_text_sample(row: dict) -> dict:
    raw_text = row.get("raw_asr_text", "")
    expected_text = row.get("final_expected_text", "")
    protected_terms = row.get("protected_terms", [])

    if "<think>" in expected_text or "</think>" in expected_text:
        raise ValueError(f"Assistant target contains reasoning tags for row {row.get('id')}")

    instruction = ALPACA_INSTRUCTION
    if protected_terms:
        instruction += "\nProtected terms that must survive verbatim: " + ", ".join(protected_terms)

    prompt = "\n".join(
        [
            "Below is an instruction that describes a task, paired with an input that provides further context. Write a response that appropriately completes the request.",
            "Instruction:",
            instruction,
            "",
            "Input:",
            raw_text,
            "",
            "Response:",
            expected_text,
        ]
    )
    return {"text": prompt}


def convert_dataset(input_file: str, output_file: str, system_prompt: str, dataset_format: str) -> dict:
    """Convert dataset from annotation format to Qwen format."""
    input_path = Path(input_file)
    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    converted = []
    source_rows = []

    with open(input_path) as f:
        for line in f:
            if not line.strip():
                continue

            row = json.loads(line)
            source_rows.append(row)
            if dataset_format == "alpaca_text":
                sample = create_alpaca_text_sample(row)
            else:
                sample = create_qwen_sample(row, system_prompt)
            converted.append(sample)

    # Write output
    with open(output_path, "w") as f:
        for sample in converted:
            f.write(json.dumps(sample, ensure_ascii=False) + "\n")

    print(f"Converted {len(converted)} examples from {input_file} to {output_file}")

    # Print stats
    if dataset_format == "alpaca_text":
        with_protected = sum(
            1 for sample in converted
            if "Protected terms that must survive verbatim:" in sample["text"]
        )
    else:
        with_protected = sum(
            1 for sample in converted
            if "PROTECTED TERMS:" in sample["messages"][0]["content"]
            and "terms MUST survive verbatim" in sample["messages"][0]["content"]
        )
    print(f"  Examples with protected terms: {with_protected}")
    return {
        "input_file": str(input_path),
        "output_file": str(output_path),
        "row_count": len(converted),
        "categories": dict(sorted(Counter(row.get("category") for row in source_rows).items())),
        "subcategories": dict(sorted(Counter(row.get("subcategory") for row in source_rows).items())),
        "languages": dict(sorted(Counter(row.get("language") for row in source_rows).items())),
        "protected_term_rows": sum(1 for row in source_rows if row.get("protected_terms")),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Convert Zphyr dataset to Qwen chat format"
    )
    parser.add_argument(
        "--train-file",
        default="datasets/splits/train.jsonl",
        help="Path to training data"
    )
    parser.add_argument(
        "--val-file",
        default="datasets/splits/val.jsonl",
        help="Path to validation data"
    )
    parser.add_argument(
        "--output-dir",
        default="training/qwen_format",
        help="Output directory"
    )
    parser.add_argument(
        "--test-file",
        help="Optional path to test split for inference-ready evaluation datasets"
    )
    parser.add_argument(
        "--system-prompt-file",
        default="training/system_prompt.txt",
        help="Path to system prompt file"
    )
    parser.add_argument(
        "--dataset-format",
        choices=["chat", "alpaca_text"],
        default="chat",
        help="Output dataset packing format."
    )
    parser.add_argument(
        "--skip-valid-alias",
        action="store_true",
        help="Do not create valid.jsonl as an alias of the validation split"
    )
    args = parser.parse_args()

    # Load system prompt
    system_prompt = load_system_prompt(args.system_prompt_file)
    print(f"Loaded system prompt from {args.system_prompt_file}")
    print(f"System prompt length: {len(system_prompt)} characters\n")

    # Convert train and val
    manifest = {
        "system_prompt_file": args.system_prompt_file,
        "system_prompt_length": len(system_prompt),
        "dataset_format": args.dataset_format,
        "splits": {},
    }

    manifest["splits"]["train"] = convert_dataset(
        args.train_file,
        f"{args.output_dir}/train.jsonl",
        system_prompt,
        args.dataset_format
    )

    manifest["splits"]["val"] = convert_dataset(
        args.val_file,
        f"{args.output_dir}/val.jsonl",
        system_prompt,
        args.dataset_format
    )

    if not args.skip_valid_alias:
        val_output = Path(args.output_dir) / "val.jsonl"
        valid_output = Path(args.output_dir) / "valid.jsonl"
        valid_output.write_text(val_output.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"Created MLX-compatible validation alias at {valid_output}")
        manifest["splits"]["valid"] = {
            "input_file": args.val_file,
            "output_file": str(valid_output),
            "row_count": manifest["splits"]["val"]["row_count"],
            "alias_of": "val",
        }

    if args.test_file:
        manifest["splits"]["test"] = convert_dataset(
            args.test_file,
            f"{args.output_dir}/test.jsonl",
            system_prompt,
            args.dataset_format
        )

    manifest_path = Path(args.output_dir) / "manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(f"Wrote dataset manifest to {manifest_path}")

    print("\nConversion complete!")


if __name__ == "__main__":
    main()
