# Zphyr v1 — Corrected Evaluation Plan

**Model:** arhesstide/zphyr_qwen_v1-MLX-4bit
**Date:** 2026-03-09
**Status:** CORRECTED — Uses actual TEST split counts

---

## 1. EXECUTIVE SUMMARY

This plan evaluates the **current MLX checkpoint** on the new 45-example test split to determine if patch fine-tuning is warranted.

**Key corrections from previous plan:**
- All decision thresholds now use TEST split counts (not dataset totals)
- Evaluation path uses existing Xcode project infrastructure (not ad-hoc swiftc)
- Clear distinction between: current checkpoint evaluation / patch adaptation / full retrain

---

## 2. TEST SPLIT COUNTS (VERIFIED)

```json
{
  "total": 45,
  "null_edits": 9,
  "hard_negatives": 3,
  "protected_term_examples": 25,
  "total_protected_terms": 41,
  "category_breakdown": {
    "corrections": 3,
    "lists": 3,
    "commands": 3,
    "multilingual": 7,
    "null_edits": 8,
    "prose": 5,
    "short": 7,
    "technical": 9
  }
}
```

**Hard negative subcategories** (1 each):
- `intentional_repetition`: "c'est vraiment vraiment important"
- `no_list_ambiguous`: "nous devons améliorer X et aussi Y"
- `ambiguous_command_content`: command-like but not a command

---

## 3. CORRECTED DECISION THRESHOLDS

All thresholds are based on **TEST split only** (n=45).

### 3.1 Null Edit Preservation (9 examples)

| Grade | Threshold | Interpretation |
|-------|-----------|----------------|
| **Strong** | 9/9 (100%) | Perfect restraint |
| **Good** | 8/9 (89%) | Minimal over-editing |
| **Acceptable** | 7/9 (78%) | Minor issues, patch likely helps |
| **Poor** | <7/9 (<78%) | Significant over-editing, patch needed |

### 3.2 Hard Negative Pass Rate (3 examples)

| Grade | Threshold | Interpretation |
|-------|-----------|----------------|
| **Strong** | 3/3 (100%) | Perfect conservative behavior |
| **Good** | 3/3 (100%) | Same — 100% required for pass |
| **Acceptable** | 2/3 (67%) | 1 failure acceptable |
| **Poor** | 1/3 (33%) | Major over-formatting issue |

**Note:** Hard negatives are the MOST critical — they measure whether the model applies inappropriate transformations.

### 3.3 Protected Term Accuracy (41 terms across 25 examples)

| Grade | Threshold | Interpretation |
|-------|-----------|----------------|
| **Strong** | ≥37/41 (90%) | Near-perfect preservation |
| **Good** | ≥35/41 (85%) | Minor corruption only |
| **Acceptable** | ≥31/41 (75%) | Some failures, patch helps |
| **Poor** | <31/41 (<75%) | Systematic corruption issue |

### 3.4 Overall WER/CER (all 45 examples)

| Grade | WER | CER | Interpretation |
|-------|-----|-----|----------------|
| **Strong** | ≤0.05 | ≤0.03 | Near-perfect formatting |
| **Good** | ≤0.08 | ≤0.05 | Excellent formatting |
| **Acceptable** | ≤0.12 | ≤0.08 | Minor issues, patch helps |
| **Poor** | >0.12 | >0.08 | Significant formatting issues |

### 3.5 Translation Violations (HARD REQUIREMENT)

| Grade | Threshold |
|-------|-----------|
| **Pass** | 0 violations |
| **FAIL** | Any violation |

**Translation is a hard constraint** — any FR→EN or EN→FR transformation is an immediate failure.

---

## 4. GO/NO-GO DECISION MATRIX

### 4.1 Green Light: Patch Fine-Tuning WARRANTED

Patch fine-tuning is justified if **ANY** of these conditions are met:

1. Null edit preservation < 8/9 (89%)
2. Hard negative pass rate < 3/3 (100%)
3. Protected term accuracy < 35/41 (85%)
4. Overall WER > 0.08
5. Category-specific failures (prose WER > 0.10, technical WER > 0.12)

**Rationale:** The current prompt is code-focused; the seed dataset encodes conservative behavior. A mismatch is expected and patchable.

### 4.2 Yellow Light: Patch OPTIONAL

Patch is optional if:

- Null edit preservation = 8/9 or 9/9
- Hard negative pass rate = 3/3
- Protected term accuracy ≥ 35/41
- Overall WER ≤ 0.08

**Rationale:** Model is already good. Patch may provide marginal improvement but not critical.

### 4.3 Red Light: PROBLEM — Do NOT Patch

Do NOT patch if:

- Translation violations > 0
- Protected term accuracy < 20/41 (50%)
- Null edit preservation < 4/9 (44%)

**Rationale:** These indicate fundamental issues that patch won't fix. Requires:
- Model architecture review
- Training data quality audit
- Possibly full retrain

---

## 5. REPO-COMPATIBLE EVALUATION PATH

### 5.1 Problem with Previous Approach

The previous `eval_formatter.swift` standalone build fails because:
- `AdvancedLLMFormatter` is internal to Zphyr module
- MLX dependencies are linked via Xcode package manager
- Building standalone requires duplicating all dependencies

### 5.2 Solution: Extend EvalHarnessRunner

**Approach:** Add a new test class that evaluates the seed split using the existing harness infrastructure.

**Step 1:** Create new test class `EvalSeedSplitTests.swift` in `ZphyrTests/`

This file:
- Loads `Evals/datasets/splits/test.jsonl`
- Uses the same `FormattingPipeline` as `EvalL2Tests`
- Outputs to `Evals/reports/seed_split_L2.json`
- Computes the same metrics (WER, CER, null edit preservation, etc.)

**Step 2:** Build and run via xcodebuild

```bash
cd /Users/aris/Documents/VoiceProject/Zphyr
xcodebuild test -scheme Zphyr \
  -only-testing:ZphyrTests/EvalSeedSplitTests \
  EVAL_MODE=advanced
```

This uses:
- Existing MLX integration in `AdvancedLLMFormatter.swift`
- Existing `FormattingPipeline` from `FormattingPipeline.swift`
- All existing dependencies linked in Xcode

### 5.3 Alternative: Manual Testing via Zphyr App

For quick spot-checking (5-10 examples):

1. Open Zphyr app
2. Ensure Advanced Mode is loaded (Settings → System → Formatting Mode: Advanced)
3. For each test example:
   - Copy `raw_asr_text`
   - Dictate using ⌥+click (paste into dictation target)
   - Record output
   - Compare to `final_expected_text`

This gives immediate feedback but doesn't scale to 45 examples.

---

## 6. PATCH TRAINING STRATEGY

### 6.1 What "Patch" Means Here

**Patch = Lightweight continuation training** on existing checkpoint:

- Starting point: `arhesstide/zphyr_qwen_v1-MLX-4bit`
- Training data: 210 examples from `train.jsonl`
- Validation: 45 examples from `val.jsonl`
- Epochs: 1-2 (prevents catastrophic forgetting)
- Learning rate: 1e-5 (conservative)
- Goal: Shift behavior from code-focused to conservative

### 6.2 What Patch CAN Fix

| Issue | Fixable | Confidence |
|-------|---------|------------|
| Null edit over-editing | ✅ Yes | High |
| Hard negative failures | ✅ Yes | High |
| Conservative behavior | ✅ Yes | Medium |
| Protected term awareness | ✅ Yes | Medium |
| List false positives | ✅ Yes | Medium |

### 6.3 What Patch CANNOT Fix

| Issue | Why |
|-------|-----|
| Fundamental model architecture | Requires full retrain |
| MLX 4-bit quantization artifacts | Requires re-quantization |
| Translation violations | Constraint enforcement needed |
| Long-form coherence | 210 examples insufficient |

### 6.4 Training Format: Qwen Chat

**System prompt** (conservative):
```
You are a CONSERVATIVE text formatter for speech-to-text output.
Apply MINIMAL formatting. When uncertain, make NO edit.

CORE PRINCIPLES:
1. CONSERVATISM: Less is more. Under-formatting is better than over-formatting.
2. NO TRANSLATION: Never translate between languages.
3. NO PARAPHRASING: Never rewrite or rephrase.
4. PRESERVE TECHNICAL TERMS: Code, URLs, package names must survive verbatim.

FORMATTING:
- Add sentence-final punctuation (. ! ?) only when clear
- Capitalize first letter of sentences
- Remove obvious disfluences (um, uh) at boundaries ONLY

DO NOT:
- Don't remove intentional repetition ("vraiment vraiment" → preserve)
- Don't create lists from simple "et" connections
- Don't expand short utterances
- Don't add conversational filler
```

**Metadata injection:**
- ✅ **Inject:** `protected_terms` → append to system prompt as "PROTECTED TERMS: term1, term2"
- ✅ **Inject:** `no_translation` → add to system prompt as "NO TRANSLATION: true"
- ❌ **Don't inject:** `category`, `subcategory` (learned from examples)
- ❌ **Don't inject:** `language` (visible in text)
- ❌ **Don't inject:** `rewrite_allowed_level` (encoded in examples)
- ❌ **Don't inject:** `notes` (annotation-only)

---

## 7. EXACT NEXT COMMANDS

### Step 1: Evaluate Current Model (BASELINE)

```bash
cd /Users/aris/Documents/VoiceProject/Zphyr

# Option A: Use extended harness (RECOMMENDED)
xcodebuild test -scheme Zphyr \
  -only-testing:ZphyrTests/EvalSeedSplitTests \
  EVAL_MODE=advanced

# Option B: Manual spot check (5-10 examples)
# Run app, dictate examples, record outputs
```

### Step 2: Score Results

```bash
cd Evals
python metrics/zphyr_eval.py score \
  --input reports/seed_split_L2.json \
  --output baselines/current_model_metrics.json
```

### Step 3: Apply Decision Matrix

| Metric | Your Result | Decision |
|--------|-------------|----------|
| Null edit preservation | ___/9 | If <8 → Patch |
| Hard negative pass rate | ___/3 | If <3 → Patch |
| Protected term accuracy | ___/41 | If <35 → Patch |
| Overall WER | ___ | If >0.08 → Patch |

### Step 4: If Patch Warranted

```bash
cd Evals/training

# Training data already prepared:
# qwen_format/train.jsonl (210 examples)
# qwen_format/val.jsonl (45 examples)

# Run patch training (requires MLX Python or Swift)
python -m mlx.lm.train \
  --model arhesstide/zphyr_qwen_v1-MLX-4bit \
  --train-data qwen_format/train.jsonl \
  --val-data qwen_format/val.jsonl \
  --output-dir checkpoints/patch_v1 \
  --learning-rate 1e-5 \
  --epochs 2 \
  --batch-size 4 \
  --gradient-accumulation-steps 4 \
  --early-stopping-patience 2
```

### Step 5: Evaluate Patched Model

```bash
cd /Users/aris/Documents/VoiceProject/Zphyr
# Update model path in AdvancedLLMFormatter to point to patched checkpoint
xcodebuild test -scheme Zphyr \
  -only-testing:ZphyrTests/EvalSeedSplitTests \
  EVAL_MODE=advanced
```

---

## 8. FINAL VERDICT FRAMEWORK

### Before Patching

**MUST COMPLETE:**
1. ✅ Run evaluation on current checkpoint
2. ✅ Compute metrics using corrected thresholds
3. ✅ Verify translation violations = 0
4. ✅ Check null edit preservation ≥ 4/9 (red light check)

**IF red light condition met:**
- Stop and investigate root cause
- Check for fundamental issues

**IF yellow/green condition:**
- Proceed with patch training

### After Patching

**SUCCESS CRITERIA:**
- Null edit preservation ≥ 8/9 (89%)
- Hard negative pass rate = 3/3 (100%)
- Protected term accuracy ≥ 35/41 (85%)
- Translation violations = 0
- No regression on technical category (WER change ≤ +0.02)

**IF success criteria met:**
- Deploy patched model
- Expand dataset for next iteration

**IF success criteria NOT met:**
- Investigate failure modes
- Consider: more epochs, higher learning rate, or full retrain

---

**Status:** Ready for evaluation run.
**Last Updated:** 2026-03-09
**Next Step:** Run `xcodebuild test` with EvalSeedSplitTests to get baseline metrics.
