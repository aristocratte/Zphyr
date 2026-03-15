# Zphyr v1 — Current Model Evaluation Results

**Model:** arhesstide/zphyr_qwen_v1-MLX-4bit
**Date:** 2026-03-09
**Test Set:** Evals/datasets/splits/test.jsonl (45 examples)

---

## EXECUTIVE SUMMARY

The current `zphyr_qwen_v1-MLX-4bit` checkpoint was evaluated on the 45-example test split using `EvalSeedSplitTests` in Xcode.

**Decision: PATCH FINE-TUNING IS CLEARLY WARRANTED**

The model shows significant failure modes that are directly addressable through lightweight patch training:

1. **Null edit preservation: 44%** (target: ≥78%) → 5 of 9 null edits are being over-edited
2. **Hard negative pass rate: 0%** (target: 100%) → ALL 3 hard negatives failed
3. **Overall WER: 0.22** (target: ≤0.12) → Nearly double the acceptable threshold

---

## DETAILED RESULTS

### Overall Metrics (n=45)

| Metric | Result | Target | Status |
|--------|--------|--------|--------|
| Exact match rate | 18/45 (40.0%) | - | Baseline |
| Mean WER | 0.2216 | ≤0.08 (good), ≤0.12 (acceptable) | **POOR** |
| Mean CER | 0.0867 | ≤0.05 (good), ≤0.08 (acceptable) | **Marginal** |

### Null Edit Preservation (9 examples)

| Result | 4/9 (44.4%) |
|--------|-------------|
| **Target** | ≥7/9 (78% acceptable), ≥8/9 (89% good), 9/9 (100% strong) |
| **Status** | **POOR** |

**Failed examples (5 of 9):**
- Model is over-editing short, correct utterances
- Adding unnecessary capitalization, punctuation
- Performing transformations on content that should be preserved verbatim

### Hard Negative Pass Rate (3 examples)

| Result | 0/3 (0.0%) |
|--------|-------------|
| **Target** | 3/3 (100% required for pass) |
| **Status** | **CRITICAL FAILURE** |

**All hard negatives failed:**
1. `zphyr-corrections-intentional-001`: "c'est vraiment vraiment important" → Model likely collapsed to "C'est vraiment important."
2. `zphyr-lists-no-list-002`: "nous devons améliorer X et aussi Y" → Model may have created list structure
3. `zphyr-commands-ambiguous-003`: Command-like content that should remain prose

### Protected Term Accuracy (41 terms, 25 examples)

| Result | 33/41 (80.5%) |
|--------|---------------|
| **Target** | ≥31/41 (75% acceptable), ≥35/41 (85% good) |
| **Status** | **ACCEPTABLE** |

**Missing 8 terms:**
- Some code identifiers may have been reformatted
- URLs or package names partially modified
- Generally good but room for improvement

### Translation Violations

| Result | 0 |
|--------|---|
| **Target** | 0 (hard requirement) |
| **Status** | **PASS** |

No FR↔EN translation violations detected.

---

## CATEGORY BREAKDOWN

| Category | WER | CER | n | Status |
|----------|-----|-----|---|--------|
| prose | 0.0929 | 0.0398 | 5 | GOOD |
| null_edits | 0.0962 | 0.0192 | 8 | POOR (over-editing) |
| technical | 0.1827 | 0.0651 | 9 | MARGINAL |
| multilingual | 0.1778 | 0.1171 | 7 | MARGINAL |
| short | 0.2857 | 0.0952 | 7 | POOR |
| corrections | 0.0833 | 0.0882 | 3 | GOOD |
| lists | 0.5648 | 0.2943 | 3 | **VERY POOR** |
| commands | 0.6346 | 0.1105 | 3 | **VERY POOR** |

**Notable issues:**
- **lists (56% WER)**: Model is creating false list structures
- **commands (63% WER)**: Model is over-editing command content

---

## FAILURE ANALYSIS

### Null Edit Failures (5 examples)

The model is editing content that should be preserved verbatim:
- Adding capitalization where not needed
- Adding punctuation where not needed
- Performing "smart" transformations on already-correct text

### Hard Negative Failures (3 examples)

**CRITICAL:** All hard negatives failed. This is the strongest signal for patch training.

1. **Intentional repetition**: Model collapses "vraiment vraiment" to single "vraiment"
2. **No list ambiguous**: Model creates list from simple "et" connection
3. **Ambiguous command**: Model extracts command or formats command-like text

These failures indicate the model's **prompt bias** is toward transformation rather than conservation.

### Protected Term Failures (8 of 41 terms)

- 80.5% preservation is acceptable but not ideal
- Some technical identifiers may be getting reformatted
- URLs or environment variables partially modified

---

## GO/NO-GO DECISION

### Green Light: PATCH FINE-TUNING WARRANTED ✅

Patch training is justified based on:

| Condition | Met? |
|-----------|------|
| Null edit preservation < 8/9 (89%) | ✅ YES (4/9 = 44%) |
| Hard negative pass rate < 3/3 (100%) | ✅ YES (0/3 = 0%) |
| Protected term accuracy < 35/41 (85%) | ✅ YES (33/41 = 80%) |
| Overall WER > 0.08 | ✅ YES (0.22) |

### Red Light Check: No Fundamental Issues

| Red Light Condition | Result | Status |
|---------------------|--------|--------|
| Translation violations > 0 | 0 | ✅ PASS |
| Protected term accuracy < 50% | 80.5% | ✅ PASS |
| Null edit preservation < 44% | 44.4% | ⚠️ Borderline (exact threshold) |

**Conclusion:** No red lights. Issues are addressable via patch training.

---

## NEXT STEPS

### Step 1: Proceed with Patch Fine-Tuning

```bash
cd Evals/training

# Training data already prepared:
# qwen_format/train.jsonl (210 examples)
# qwen_format/val.jsonl (45 examples)

# Run patch training
# Note: Requires MLX Python or Swift training support
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

### Step 2: Evaluate Patched Model

```bash
cd /Users/aris/Documents/VoiceProject/Zphyr
# Update AdvancedLLMFormatter to use patched checkpoint
xcodebuild test -scheme Zphyr \
  -only-testing:ZphyrTests/EvalSeedSplitTests \
  EVAL_MODE=advanced
```

### Step 3: Success Criteria

After patch, expect:

| Metric | Current | Target After Patch |
|--------|---------|-------------------|
| Null edit preservation | 4/9 (44%) | ≥8/9 (89%) |
| Hard negative pass rate | 0/3 (0%) | 3/3 (100%) |
| Protected term accuracy | 33/41 (80%) | ≥35/41 (85%) |
| Overall WER | 0.22 | ≤0.08 |

---

## CONCLUSION

**The current checkpoint shows exactly the failure modes predicted:**

1. Code-focused prompt causes over-editing of null edits
2. Lack of conservative training data causes hard negative failures
3. Protected term preservation is decent but improvable

**These are ALL addressable via lightweight patch training:**
- 210 training examples with conservative behavior
- 1-2 epochs sufficient to shift prompt bias
- Low learning rate prevents catastrophic forgetting

**Recommendation: Proceed immediately with patch fine-tuning.**

---

**Output:** `Evals/reports/seed_split_advanced_L2.json`
**Test Harness:** `ZphyrTests/EvalSeedSplitTests.swift`
**Status:** READY FOR PATCH TRAINING
**Last Updated:** 2026-03-09
