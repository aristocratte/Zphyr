# Zphyr v1 Pilot Fine-Tuning Setup for Qwen

**Generated:** 2026-03-09
**Model:** Qwen2.5-0.5B-Instruct (or similar)
**Dataset:** 300 examples, 210 train / 45 val / 45 test
**Task:** Constrained post-ASR text formatting

---

## 1. EXECUTIVE SUMMARY

This document defines the complete pilot fine-tuning setup for Zphyr's constrained post-ASR formatting task using Qwen.

**Approach:** Instruction fine-tuning using Qwen's chat format with a strongly constrained system prompt.

**Key constraint:** The model must learn to be conservative — when uncertain, make no edit. Under-formatting is preferred over over-formatting.

---

## 2. TRAINING SAMPLE FORMAT

### Exact Transformation from Dataset Row to Qwen Training Sample

Each dataset row transforms into a single training example with three messages:

```json
{
  "messages": [
    {
      "role": "system",
      "content": "<SYSTEM_PROMPT>"
    },
    {
      "role": "user",
      "content": "Format this text: <RAW_ASR_TEXT>"
    },
    {
      "role": "assistant",
      "content": "<FINAL_EXPECTED_TEXT>"
    }
  ]
}
```

### Field Mappings

| Dataset Field | Usage | Format |
|---------------|-------|--------|
| `raw_asr_text` | User input | Plain text, prefixed with "Format this text:" |
| `final_expected_text` | Assistant target | Plain text, exactly as specified |
| `protected_terms` | **Injected into prompt** | Comma-separated list if non-empty |
| `no_translation` | **Injected into prompt** | Explicit instruction if true |
| `rewrite_allowed_level` | **NOT injected** | Implied through examples, not explicit |
| `category` | **NOT injected** | Used for analysis only, not in prompt |
| `subcategory` | **NOT injected** | Used for analysis only, not in prompt |
| `notes` | **NOT injected** | Annotation-only field |

### Example Transformation

**Input row:**
```json
{
  "id": "zphyr-null-short-002",
  "raw_asr_text": "exact",
  "final_expected_text": "exact",
  "protected_terms": [],
  "no_translation": true,
  "is_null_edit": true
}
```

**Output training sample:**
```json
{
  "messages": [
    {
      "role": "system",
      "content": "You are a conservative text formatter for speech-to-text output..."
    },
    {
      "role": "user",
      "content": "Format this text: exact"
    },
    {
      "role": "assistant",
      "content": "exact"
    }
  ]
}
```

**Input row (with protected terms):**
```json
{
  "id": "zphyr-technical-001",
  "raw_asr_text": "configure NEXT_PUBLIC_API_URL=https://api.zphyr.app avant de lancer le build",
  "final_expected_text": "Configure NEXT_PUBLIC_API_URL=https://api.zphyr.app avant de lancer le build.",
  "protected_terms": ["NEXT_PUBLIC_API_URL", "https://api.zphyr.app"],
  "no_translation": true
}
```

**Output training sample:**
```json
{
  "messages": [
    {
      "role": "system",
      "content": "You are a conservative text formatter...\n\nPROTECTED TERMS: NEXT_PUBLIC_API_URL, https://api.zphyr.app"
    },
    {
      "role": "user",
      "content": "Format this text: configure NEXT_PUBLIC_API_URL=https://api.zphyr.app avant de lancer le build"
    },
    {
      "role": "assistant",
      "content": "Configure NEXT_PUBLIC_API_URL=https://api.zphyr.app avant de lancer le build."
    }
  ]
}
```

### What to Omit

**OMIT from prompt:**
- `category` - inferred, not instructed
- `subcategory` - inferred, not instructed
- `rewrite_allowed_level` - behavior learned from examples
- `difficulty` - not relevant to model
- `severity_if_wrong` - not relevant to model
- `constraint_ids` - internal annotation
- `notes` - annotation-only
- `source_type` - not relevant

**INCLUDE in prompt when present:**
- `protected_terms` - injected as "PROTECTED TERMS: ..."
- `no_translation` - implicit in system prompt, reinforced in examples

---

## 3. SYSTEM PROMPT

```
You are a conservative text formatter for speech-to-text output. Your task is to apply minimal formatting to raw transcribed text while preserving the original meaning exactly.

CORE PRINCIPLES:
1. CONSERVATISM: When uncertain, make no edit. Under-formatting is preferred over over-formatting.
2. NO TRANSLATION: Never translate from one language to another. Preserve the source language exactly.
3. NO PARAPHRASING: Never rewrite or rephrase. Only add punctuation, capitalization, and remove obvious speech errors.
4. PRESERVE TECHNICAL TERMS: Technical terms, code, package names, URLs, and identifiers must survive verbatim.
5. PRESERVE LIST STRUCTURE: When explicit list signals are present (premièrement/deuxièmement, and then/and then), format as a list. Otherwise, use prose.

FORMATTING RULES:
- Add sentence-final punctuation (. ? !) where clearly appropriate
- Capitalize the first letter of sentences and proper nouns
- Remove obvious speech disfluencies (um, uh, euh) only at utterance boundaries
- DO NOT remove intentional repetition (e.g., "vraiment vraiment" should be preserved)
- DO NOT create lists where no explicit signal exists (a simple "et" does not make a list)
- DO NOT expand short utterances or add words
- DO NOT "fix" informal language or slang

PROTECTED TERMS PRECEDENCE:
If protected terms are specified, they must survive verbatim. No character-level changes allowed.

WHEN IN DOUBT:
- Output the input text with minimal changes
- A single capitalization or period is safer than aggressive editing
```

### Dynamic Prompt Extension

When `protected_terms` is non-empty, append to system prompt:

```
PROTECTED TERMS: <comma-separated list>

These terms MUST survive verbatim. Do not change capitalization, punctuation, or spacing within these terms.
```

---

## 4. PILOT TRAINING CONFIG

### Conservative Hyperparameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Base model** | Qwen2.5-0.5B-Instruct | Small, fast, sufficient for pilot |
| **Learning rate** | 2e-5 | Conservative for fine-tuning small model |
| **Epochs** | 3-5 | Small dataset, risk of overfitting |
| **Batch size** | 8 | Fits in GPU memory, good gradient estimates |
| **Gradient accumulation** | 2 | Effective batch size = 16 |
| **Warmup ratio** | 0.1 | Gradual learning rate ramp-up |
| **Weight decay** | 0.01 | Regularization |
| **Max sequence length** | 512 | Sufficient for all examples |
| **Eval cadence** | Every 50 steps | Monitor for overfitting |
| **Logging** | Every 10 steps | Track training progress |

### Early Stopping Logic

```
Monitor validation loss
- If val_loss doesn't improve for 3 evaluations: early stop
- Save checkpoint with best val_loss
- Minimum epochs: 2 (ensure at least some learning)
```

### Checkpointing Strategy

```
Checkpoints to save:
1. best_model.pt (lowest val_loss)
2. last_model.pt (final epoch)
3. epoch_N_model.pt (each epoch for analysis)

Artifacts to save per checkpoint:
- model state dict
- optimizer state dict
- training epoch
- val_loss
- val_metrics
```

### Overfitting Prevention

```
Monitor:
- train_loss vs val_loss gap (divergence = overfitting)
- null_edit_preservation on val set (dropping = over-editing)
- protected_term_accuracy on val set (dropping = violating constraints)

Stop if:
- val_gap > 0.5 (train_loss - val_loss)
- null_edit_preservation drops below 70% on val
- protected_term_accuracy drops below 75% on val
```

---

## 5. BASELINE RUN PROCEDURE

### Step 1: Generate Baseline Outputs

**Goal:** Run current (unfine-tuned) model on test.jsonl

**Command:**
```bash
cd /Users/aris/Documents/VoiceProject/Zphyr/Evals

python scripts/run_baseline_inference.py \
    --model-path Qwen/Qwen2.5-0.5B-Instruct \
    --test-file datasets/splits/test.jsonl \
    --output-file baselines/baseline_outputs.jsonl \
    --system-prompt-file training/system_prompt.txt
```

**Expected output:**
- `baselines/baseline_outputs.jsonl` - one line per test example with model output
- Console summary with WER, CER, preservation rates

### Step 2: Compute Baseline Metrics

**Command:**
```bash
python scripts/evaluate_baseline.py \
    --input-file baselines/baseline_outputs.jsonl \
    --output-file baselines/baseline_outputs_detailed.jsonl \
    --metrics-file baselines/baseline_metrics.json
```

**Output files:**
- `baselines/baseline_metrics.json` - aggregated metrics
- `baselines/baseline_outputs_detailed.jsonl` - per-example results

### Step 3: Save Baseline Summary

```bash
python scripts/generate_baseline_report.py \
    --metrics-file baselines/baseline_metrics.json \
    --output-file baselines/baseline_report.md
```

---

## 6. POST-TRAINING EVALUATION PROCEDURE

### Step 1: Run Fine-Tuned Model on Test Set

**Command:**
```bash
python scripts/run_finetuned_inference.py \
    --model-path checkpoints/pilot_v1/best_model.pt \
    --test-file datasets/splits/test.jsonl \
    --output-file outputs/pilot_outputs.jsonl \
    --system-prompt-file training/system_prompt.txt
```

### Step 2: Compute Pilot Metrics

**Command:**
```bash
python scripts/evaluate_baseline.py \
    --input-file outputs/pilot_outputs.jsonl \
    --output-file outputs/pilot_outputs_detailed.jsonl \
    --metrics-file outputs/pilot_metrics.json
```

### Step 3: Compare Baseline vs Pilot

**Command:**
```bash
python scripts/compare_runs.py \
    --baseline-file baselines/baseline_metrics.json \
    --pilot-file outputs/pilot_metrics.json \
    --output-file comparisons/baseline_vs_pilot.md
```

**Comparison metrics:**
- Delta WER/CER per category
- Delta null_edit_preservation
- Delta protected_term_accuracy
- Delta hard_negative_pass_rate
- List of improved examples
- List of regressed examples

---

## 7. EXACT COMMANDS

### 7.1 Dataset Preparation

```bash
cd /Users/aris/Documents/VoiceProject/Zphyr/Evals

# Convert dataset to Qwen training format
python scripts/prepare_qwen_dataset.py \
    --train-file datasets/splits/train.jsonl \
    --val-file datasets/splits/val.jsonl \
    --output-dir training/qwen_format \
    --system-prompt-file training/system_prompt.txt
```

### 7.2 Baseline Inference

```bash
# Run baseline (current model on test set)
python scripts/run_inference.py \
    --model Qwen/Qwen2.5-0.5B-Instruct \
    --input datasets/splits/test.jsonl \
    --output baselines/baseline_outputs.jsonl

# Score baseline
python scripts/evaluate_baseline.py \
    --test-file datasets/splits/test.jsonl \
    --input-file baselines/baseline_outputs.jsonl \
    --metrics-file baselines/baseline_metrics.json
```

### 7.3 Pilot Fine-Tuning

```bash
# Using MLX (Apple Silicon)
python -m mlx.experts.train \
    --model Qwen/Qwen2.5-0.5B-Instruct \
    --train-data training/qwen_format/train.jsonl \
    --val-data training/qwen_format/val.jsonl \
    --learning-rate 2e-5 \
    --epochs 3 \
    --batch-size 8 \
    --gradient-accumulation-steps 2 \
    --output-dir checkpoints/pilot_v1 \
    --eval-steps 50 \
    --save-best-only \
    --early-stopping-patience 3

# OR using Hugging Face transformers
python scripts/train_qwen.py \
    --model-name-or-path Qwen/Qwen2.5-0.5B-Instruct \
    --train-file training/qwen_format/train.jsonl \
    --validation-file training/qwen_format/val.jsonl \
    --output-dir checkpoints/pilot_v1 \
    --num-train-epochs 3 \
    --per-device-train-batch-size 8 \
    --gradient-accumulation-steps 2 \
    --learning-rate 2e-5 \
    --warmup-ratio 0.1 \
    --weight-decay 0.01 \
    --evaluation-strategy steps \
    --eval-steps 50 \
    --save-strategy epoch \
    --load-best-model-at-end \
    --early-stopping-patience 3 \
    --logging-steps 10
```

### 7.4 Post-Training Evaluation

```bash
# Run fine-tuned model on test set
python scripts/run_inference.py \
    --model checkpoints/pilot_v1/best_model \
    --input datasets/splits/test.jsonl \
    --output outputs/pilot_outputs.jsonl

# Score pilot
python scripts/evaluate_baseline.py \
    --test-file datasets/splits/test.jsonl \
    --input-file outputs/pilot_outputs.jsonl \
    --metrics-file outputs/pilot_metrics.json

# Compare
python scripts/compare_runs.py \
    --baseline baselines/baseline_metrics.json \
    --pilot outputs/pilot_metrics.json \
    --output comparisons/baseline_vs_pilot.md
```

### 7.5 Scoring Command Summary

```bash
# Quick score summary
python scripts/summarize_metrics.py \
    --baseline baselines/baseline_metrics.json \
    --pilot outputs/pilot_metrics.json
```

---

## 8. FINAL RECOMMENDATION

### Is the 300-row pilot worth running now?

**YES.** The pilot is worth running for these reasons:

1. **Pipeline validation:** Tests the full training → evaluation → comparison pipeline
2. **Format validation:** Verifies the Qwen chat format works for this task
3. **Baseline establishment:** Creates metrics to compare against after scaling
4. **Learning signal:** 210 examples is enough to show if the model can learn the constraints
5. **Failure mode discovery:** Will reveal which categories need more data

### What This Pilot CAN Validate

| Aspect | Can Validate | How |
|--------|-------------|-----|
| Training pipeline | ✅ | End-to-end run succeeds |
| Qwen chat format | ✅ | Model produces correct outputs |
| Conservative behavior | ✅ | Null edit preservation, restraint |
| Protected term preservation | ✅ | Technical terms survive |
| Hard negative learning | ✅ | Critical examples pass |
| Category-specific learning | Partial | Commands may not improve (only 15 train) |

### What This Pilot CANNOT Validate

| Aspect | Cannot Validate | Why |
|--------|----------------|-----|
| Commands effectiveness | ❌ | Only 15 training examples |
| Non-FR languages | ❌ | No ES/JA/ZH/RU examples |
| Long-form performance | ❌ | Most examples < 15 words |
|重度 ASR artifacts | ❌ | Limited true dysfluency examples |
| Production readiness | ❌ | 300 examples is pilot scale |
| Generalization | ❌ | Test set may have train-like examples |

### Success Criteria for Pilot

| Metric | Minimum | Good | Strong |
|--------|---------|------|--------|
| WER improvement (core categories) | >3% | >7% | >12% |
| Null edit preservation | ≥70% | ≥85% | ≥90% |
| Protected term accuracy | ≥75% | ≥85% | ≥90% |
| Hard negative pass rate | ≥80% | 95% | 100% |
| Translation violations | 0 | 0 | 0 |

**Pilot FAILS if:**
- Regression on any category
- Null edit < 70%
- Protected terms < 75%
- Any translations
- Training loss doesn't decrease

### Next Dataset Expansion Priority (After Pilot)

**Priority 1: Commands (target +30-55 examples)**
- Current: 20 total, 15 in train
- Need: formatting_commands (3 → 15-20)
- Need: ambiguous_command_content (2 → 8-10)
- Need: Better trigger_mode coverage

**Priority 2: Non-FR Languages (target +30-50 examples)**
- Current: Only FR + EN/FR mixed
- Add: ES + EN, JA + EN, ZH + EN, RU + EN
- Focus: Same categories as FR (short, prose, technical)

**Priority 3: Long-form Prose (target +15-20 examples)**
- Current: Most < 15 words
- Add: 3+ sentence examples in prose, technical
- Test: Model behavior on longer passages

**Priority 4:重度 Dysfluencies (target +10-15 examples)**
- Current: Mostly clean input
- Add: True filler patterns, speech restarts
- Test: Correction without over-cleaning

**Scale-up target:** 1000-1500 examples total

---

## APPENDIX A: Training Script Template

```python
#!/usr/bin/env python3
"""
Qwen fine-tuning script for Zphyr pilot.
"""

import json
import argparse
from pathlib import Path
from transformers import (
    AutoTokenizer,
    AutoModelForCausalLM,
    TrainingArguments,
    Trainer
)

def load_qwen_format(file_path):
    """Load dataset in Qwen chat format."""
    with open(file_path) as f:
        return [json.loads(line) for line in f]

def train():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="Qwen/Qwen2.5-0.5B-Instruct")
    parser.add_argument("--train-data", required=True)
    parser.add_argument("--val-data", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--learning-rate", type=float, default=2e-5)
    parser.add_argument("--eval-steps", type=int, default=50)
    args = parser.parse_args()

    # Load model and tokenizer
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    model = AutoModelForCausalLM.from_pretrained(args.model)

    # Load datasets
    train_data = load_qwen_format(args.train_data)
    val_data = load_qwen_format(args.val_data)

    # Training arguments
    training_args = TrainingArguments(
        output_dir=args.output_dir,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=2,
        learning_rate=args.learning_rate,
        warmup_ratio=0.1,
        weight_decay=0.01,
        eval_strategy="steps",
        eval_steps=args.eval_steps,
        save_strategy="epoch",
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        logging_steps=10,
        save_total_limit=3,
    )

    # TODO: Add custom compute_metrics for null_edit_preservation
    # TODO: Add early stopping callback

    # Initialize trainer
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_data,
        eval_dataset=val_data,
        tokenizer=tokenizer,
    )

    # Train
    trainer.train()

    # Save final model
    trainer.save_model(f"{args.output_dir}/best_model")

if __name__ == "__main__":
    train()
```

---

**Status:** ✅ READY FOR PILOT TRAINING

**Next Step:** Run baseline evaluation, then start pilot fine-tuning.

**Last Updated:** 2026-03-09
**Package Version:** v1.0-pilot-training-setup
