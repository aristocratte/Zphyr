# Zphyr v1 — Current Model Evaluation & Patch Strategy

**Model:** arhesstide/zphyr_qwen_v1-MLX-4bit
**Date:** 2026-03-09
**Task:** Evaluate current checkpoint on new 300-example seed split, decide on patch fine-tuning

---

## 1. EXECUTIVE SUMMARY

**Finding:** The current `zphyr_qwen_v1-MLX-4bit` model uses a **CODE-FOCUSED** prompt (camelCase, code variables, spoken punctuation). The new 300-example seed dataset encodes **CONSERVATIVE FORMATTING** (null edits, protected terms, no translation, restraint). This fundamental mismatch suggests patch fine-tuning is **JUSTIFIED**.

**Recommendation:** Run evaluation using existing Zphyr eval harness, then proceed with **conservative patch fine-tune** (1-2 epochs, low learning rate) on the 210 training examples.

---

## 2. CURRENT-CHECKPOINT EVALUATION PLAN

### Constraint: MLX/Swift Model

The model `arhesstide/zphyr_qwen_v1-MLX-4bit` runs via MLX in Swift. Direct Python evaluation requires:
1. Building a Swift CLI wrapper for `AdvancedLLMFormatter`
2. Converting model to HuggingFace format (loses 4-bit quantization benefit)
3. Using existing `ZphyrTests/EvalHarnessRunner.swift` with data adaptation

### Recommended Evaluation Approach

**Option A: Use Existing Eval Harness (Recommended)**

```bash
# The harness already exists and works
cd Zphyr
xcodebuild test -scheme Zphyr -only-testing:ZphyrTests/EvalL2Tests \
  EVAL_MODE=advanced EVAL_CATEGORY=all
```

**Limitation:** Uses existing eval datasets (prose.jsonl, short.jsonl, etc.), NOT the new train/val/test split.

**Option B: Quick Manual Spot Check**

Take 5-10 examples from `Evals/datasets/splits/test.jsonl` and run through the app manually, recording outputs. This will reveal the most obvious failure modes.

**Option C: Mock Baseline (For Pipeline Verification)**

```bash
cd Evals
python scripts/evaluate_current_model.py --mock
```

This simulates a conservative baseline to verify metrics calculation pipeline.

### Metrics to Capture

| Metric | Definition | Target |
|--------|-----------|--------|
| Overall WER | Word error rate vs expected | Baseline: ~0.1-0.2 |
| Overall CER | Character error rate vs expected | Baseline: ~0.05-0.1 |
| Null edit preservation | % where output == raw | Baseline: unknown (likely <80%) |
| Protected term accuracy | % of protected terms surviving verbatim | Baseline: unknown (likely <90%) |
| Translation violations | Any FR→EN or EN→FR | Baseline: 0 (guard in place) |
| Hard negative pass rate | % of 12 critical examples passing | Baseline: unknown |

### Category-Level Breakdown

For each of 8 categories, capture:
- WER/CER
- Pass/fail on hard negatives (if present)
- Protected term survival rate
- Any over-editing patterns

---

## 3. LIKELY FAILURE MODES (Based on Current Prompt)

### Analysis of Current System Prompt

From `AdvancedLLMFormatter.swift` (lines 331-354):

```
"You are a highly precise text formatting engine..."

CURRENT FOCUS:
- Spoken punctuation conversion (virgule → ,)
- CODE VARIABLES (camelCase formatting)
- "Fix obvious phonetic transcription errors"
- Remove hesitation words

MISSING from current prompt:
- Null edit preservation (don't edit short correct utterances)
- Protected term preservation (never modify technical tokens)
- Translation prohibition (no FR↔EN)
- Conservative behavior (when uncertain, don't edit)
- List structure nuance (don't create false lists)
```

### Predicted Failure Modes

| Failure Mode | Likelihood | Example |
|--------------|-----------|----------|
| **Null edit violations** | HIGH | `exact` → `Exact.` (adds capital + period) |
| **Protected term corruption** | MEDIUM | `config_backup_v2` → `Config_Backup_V2` |
| **Over-formatting** | HIGH | Short utterances get over-punctuated |
| **List false positives** | MEDIUM | "X et Y" becomes bulleted list |
| **Code overreach** | LOW | Model is already trained for this |
| **Hard negative failures** | HIGH | `vraiment vraiment` gets collapsed |

### Specific Examples to Check

From test.jsonl:

1. **Null edit:** `zphyr-null-short-002`
   - Raw: "exact"
   - Expected: "exact"
   - **Prediction:** Model outputs "Exact." (fails)

2. **Protected terms:** `zphyr-technical-001`
   - Protected: `NEXT_PUBLIC_API_URL`, `https://api.zphyr.app`
   - **Prediction:** Model preserves (already trained for this)

3. **Hard negative:** `zphyr-corrections-intentional-001`
   - Raw: "non non non je ne suis pas d'accord"
   - Expected: "Non non non, je ne suis pas d'accord."
   - **Prediction:** Model collapses to "Non, je ne suis pas d'accord." (fails)

4. **No list ambiguous:** `zphyr-lists-no-list-002`
   - Raw: "nous devons améliorer X et aussi Y"
   - Expected: Single sentence
   - **Prediction:** Might create list (fails)

---

## 4. PATCH-FINE-TUNE RECOMMENDATION

### Decision: YES — Patch Fine-Tuning Is Justified

**Reasons:**

1. **Prompt mismatch:** Current model trained with code-focused prompt. Seed dataset encodes conservative philosophy.

2. **Targeted failures:** Predicted failures (null edits, hard negatives) are exactly what the seed dataset catches.

3. **Small dataset:** 210 training examples is sufficient for a **patch** (not a full retrain).

4. **Quantization constraint:** MLX 4-bit model limits fine-tuning options, but low-learning-rate patch is feasible.

### What Patch Fine-Tuning CAN Fix

| Issue | Fixable via Patch | Confidence |
|-------|------------------|------------|
| Null edit over-editing | ✅ Yes | High |
| Hard negative failures | ✅ Yes | High |
| Conservative behavior | ✅ Yes | Medium |
| Protected term awareness | ✅ Yes | Medium |
| List false positives | ✅ Yes | Medium |

### What Patch Fine-Tuning CANNOT Fix

| Issue | Why |
|-------|-----|
| Fundamental model architecture | Requires full retrain |
| MLX 4-bit quantization artifacts | Requires re-quantization |
| Core language understanding | Requires larger model |
| Long-form coherence | 300 examples insufficient |

---

## 5. PATCH TRAINING FORMAT AND PROMPT

### Training Format: Qwen Chat Format

```json
{
  "messages": [
    {
      "role": "system",
      "content": "<CONSERVATIVE_SYSTEM_PROMPT>"
    },
    {
      "role": "user",
      "content": "Format this text: <raw_asr_text>"
    },
    {
      "role": "assistant",
      "content": "<final_expected_text>"
    }
  ]
}
```

### System Prompt for Patch

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

### Metadata Injection

**Inject:**
- `protected_terms` → append to system prompt as "PROTECTED TERMS: term1, term2"

**DO NOT Inject:**
- `category` - inferred from examples
- `subcategory` - inferred from examples
- `rewrite_allowed_level` - behavior learned from examples
- `notes` - annotation-only

### Data Format Conversion

The Qwen format files have already been generated:
```bash
Evals/training/qwen_format/train.jsonl  (210 examples)
Evals/training/qwen_format/val.jsonl    (45 examples)
```

These include proper protected_terms injection.

---

## 6. SUCCESS/FAILURE CRITERIA

### Acceptable Improvement

| Metric | Threshold |
|--------|-----------|
| WER improvement (prose, short, null_edits) | ≥3% |
| Null edit preservation | ≥70% |
| Protected term accuracy | ≥75% |
| Hard negative pass rate | ≥70% |
| Translation violations | 0 |

### Good Improvement

| Metric | Threshold |
|--------|-----------|
| WER improvement (prose, short, null_edits) | ≥7% |
| Null edit preservation | ≥85% |
| Protected term accuracy | ≥85% |
| Hard negative pass rate | ≥90% |
| Commands (no regression) | ≤5% WER increase |

### Strong Improvement

| Metric | Threshold |
|--------|-----------|
| WER improvement (prose, short, null_edits) | ≥12% |
| Null edit preservation | ≥90% |
| Protected term accuracy | ≥90% |
| Hard negative pass rate | 100% |

### Hard Failure Conditions

**STOP if ANY:**
- Translation violations > 0
- Protected term accuracy < 50%
- Null edit preservation < 40%
- Hard negative pass rate < 50%
- Training loss doesn't decrease

---

## 7. EXACT WORKFLOW / COMMANDS

### Step 1: Evaluate Current Model (BASELINE)

```bash
cd Zphyr

# Option A: Use existing eval harness (measures existing datasets)
xcodebuild test -scheme Zphyr -only-testing:ZphyrTests/EvalL2Tests \
  EVAL_MODE=advanced EVAL_CATEGORY=all

# Option B: Manual spot check (5-10 examples from test.jsonl)
# Run app, dictate examples from Evals/datasets/splits/test.jsonl, record outputs

# Option C: Mock baseline (pipeline verification only)
cd Evals
python scripts/evaluate_current_model.py --mock \
  --output-file baselines/mock_baseline_outputs.jsonl \
  --metrics-file baselines/mock_baseline_metrics.json
```

### Step 2: Convert to Qwen Format (ALREADY DONE)

```bash
cd Evals
python scripts/prepare_qwen_dataset.py
# Output: training/qwen_format/train.jsonl, val.jsonl
```

### Step 3: Patch Fine-Tuning

**Challenge:** MLX 4-bit quantized model has limited fine-tuning options.

**Option A: MLX Python Fine-Tuning** (If available)
```bash
# Requires mlx-swift-lm Python bindings
python -m mlx.lm.train \
  --model arhesstide/zphyr_qwen_v1-MLX-4bit \
  --train-data training/qwen_format/train.jsonl \
  --val-data training/qwen_format/val.jsonl \
  --output-dir checkpoints/patch_v1 \
  --learning-rate 1e-5 \
  --epochs 2 \
  --batch-size 4 \
  --gradient-accumulation-steps 4 \
  --early-stopping-patience 2
```

**Option B: Swift/MLX Fine-Tuning**
```swift
// Requires implementing training loop in Swift
// This is non-trivial and may require MLX Swift training support
```

**Option C: Convert to HF Format, Fine-Tune, Re-Quantize**
```bash
# 1. Convert to HF format
# 2. Fine-tune with transformers/peft
# 3. Re-quantize to 4-bit MLX format
# (Loses some quantization benefit, but viable for pilot)
```

### Step 4: Evaluate Patched Model

```bash
# Re-run evaluation with patched model
cd Evals
python scripts/evaluate_current_model.py \
  --model-path checkpoints/patch_v1 \
  --output-file baselines/patch_outputs.jsonl \
  --metrics-file baselines/patch_metrics.json
```

### Step 5: Compare

```bash
python scripts/compare_runs.py \
  --baseline baselines/current_model_metrics.json \
  --pilot baselines/patch_metrics.json
```

---

## 8. FINAL VERDICT: Should I Patch Fine-Tune Now?

### Recommendation: YES — BUT WITH CONDITIONS

**Patch fine-tuning is justified IF:**

1. **You can run evaluation first** to confirm current model fails on the seed dataset constraints
2. **You have a working fine-tuning path** (MLX Python, Swift, or HF conversion)
3. **You accept the scope limitation** — this is a targeted patch, not a full retrain

**Specific recommendation:**

1. **First:** Run evaluation using `EvalL2Tests` with EVAL_MODE=advanced
   - This tells you how the current model performs on existing test data
   - Look for: null edit failures, over-formatting, protected term issues

2. **Second:** Do 5-10 manual spot checks using examples from `test.jsonl`
   - Pick: null edits, hard negatives, protected terms, short utterances
   - Run through Zphyr app, record outputs
   - This gives you direct observation

3. **Third:** Based on results, decide:

   **IF evaluation shows >20% failures on conservative constraints:**
   - Proceed with patch fine-tuning
   - Use 1-2 epochs, 1e-5 learning rate
   - Monitor: val loss, null_edit_preservation on val set

   **IF evaluation shows <10% failures:**
   - Current model is already good enough
   - Patch fine-tuning may not be worth complexity
   - Focus on expanding dataset instead

### What This Pilot CAN Validate

| Aspect | Validatable |
|--------|-------------|
| Training pipeline works | ✅ |
| Conservative behavior learned | ✅ |
| Null edit preservation | ✅ |
| Protected term awareness | ✅ |
| Hard negative handling | ✅ |
| No regression on existing behavior | ⚠️ Partial (21 train examples) |

### What This Pilot CANNOT Validate

| Aspect | Why Not |
|--------|---------|
| Commands effectiveness | Only 15 training examples |
| Production readiness | 300 examples too small |
| Non-FR languages | No ES/JA/ZH/RU in dataset |
| Long-form performance | Most examples <15 words |

### Next Dataset Expansion Priority (After Patch)

**Priority 1: Commands** (+30-55)
- Current model already trained for code
- Add: formatting_commands, ambiguous_command_content
- Goal: Make commands robust

**Priority 2: Null Edits** (+20-30)
- Critical for restraint
- Add edge cases: single words, abbreviations, filenames
- Goal: >90% null edit preservation

**Priority 3: Hard Negatives** (+15-20)
- Critical for avoiding over-formatting
- Add: intentional_repetition, no_list_ambiguous variants
- Goal: 100% hard negative pass rate

**Priority 4: Non-FR Languages** (+30-50)
- Add ES+EN, JA+EN, ZH+EN, RU+EN pairs
- Goal: Validate no-translation constraint

---

## APPENDIX: Immediate Next Steps

```bash
# 1. Quick eval (using existing harness)
cd Zphyr
xcodebuild test -scheme Zphyr -only-testing:ZphyrTests/EvalL2Tests \
  EVAL_MODE=advanced EVAL_CATEGORY=all

# 2. Manual spot check (pick 5 from test.jsonl)
# - zphyr-null-short-002 (null edit)
# - zphyr-corrections-intentional-001 (hard negative)
# - zphyr-lists-no-list-002 (hard negative)
# - zphyr-technical-001 (protected terms)
# - zphyr-short-near-003 (short single word)

# 3. Based on results:
#    - If failures >20%: proceed with patch
#    - If failures <10%: skip patch, expand dataset first

# 4. Patch fine-tuning (if justified)
cd Evals
python scripts/prepare_qwen_dataset.py
# Then use your preferred training method (MLX/HF/Swift)
```

---

**Status:** Evaluation scripts ready, awaiting real model run for decision.

**Last Updated:** 2026-03-09
**Model:** arhesstide/zphyr_qwen_v1-MLX-4bit
**Dataset:** Evals/datasets/splits/ (300 examples, 70/15/15)
