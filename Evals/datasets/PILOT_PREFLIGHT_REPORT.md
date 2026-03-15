# Zphyr v1 Pilot Fine-Tuning — Final Preflight Report

**Generated:** 2026-03-09
**Status:** READY FOR TRAINING
**Dataset:** 300 examples, 70/15/15 split (210/45/45)

---

## 1. EXECUTIVE SUMMARY

The Zphyr v1 pilot dataset is **READY FOR TRAINING**.

✅ All blocking issues resolved
✅ Exact 70/15/15 split achieved
✅ Hard negative coverage ensured in val/test
✅ Zero validation errors
✅ No duplicate leakage

**Verdict:** Proceed with baseline evaluation, then pilot fine-tuning.

---

## 2. HARD NEGATIVE AUDIT

### Hard Negative Types

| Type | Description | Total | Train | Val | Test |
|------|-------------|-------|-------|-----|------|
| `intentional_repetition` | Preserve emphatic repetition (e.g., "vraiment vraiment") | 5 | 3 | 1 | 1 |
| `no_list_ambiguous` | Don't create false lists from "et" | 5 | 3 | 1 | 1 |
| `ambiguous_command_content` | Don't execute prose that sounds like commands | 2 | 1 | 0 | 1 |
| **TOTAL** | | **12** | **7** | **2** | **3** |

### Coverage Verification

✅ **VAL coverage:** 2 hard negatives (1 intentional_repetition, 1 no_list_ambiguous)
✅ **TEST coverage:** 3 hard negatives (1 intentional_repetition, 1 no_list_ambiguous, 1 ambiguous_command_content)
✅ **Each hard negative type present in at least one evaluation split**

### Hard Negative Examples by Split

**TRAIN (7):**
- zphyr-lists-no-list-003, zphyr-lists-no-list-005, zphyr-lists-no-list-004 (no_list_ambiguous)
- zphyr-corrections-intentional-005, zphyr-corrections-intentional-002, zphyr-corrections-intentional-003 (intentional_repetition)
- zphyr-commands-ambiguous-002 (ambiguous_command_content)

**VAL (2):**
- zphyr-lists-no-list-001 (no_list_ambiguous)
- zphyr-corrections-intentional-004 (intentional_repetition)

**TEST (3):**
- zphyr-corrections-intentional-001 (intentional_repetition)
- zphyr-lists-no-list-002 (no_list_ambiguous)
- zphyr-commands-ambiguous-001 (ambiguous_command_content)

---

## 3. SPLIT ADJUSTMENT MADE

**Issue:** `ambiguous_command_content` examples (2 total) were both in train, leaving zero in val/test.

**Fix:** Swapped 1 ambiguous_command_content from train with 1 regular example from test.

**Details:**
- Moved: `zphyr-commands-ambiguous-001` from train → test
- Swapped with: `zphyr-commands-punct-005` from test → train (both commands category)

**Result:** Preserved 210/45/45 ratio, commands balance, and hard negative distribution.

---

## 4. FINAL PREFLIGHT STATISTICS

### Split Counts

| Split | Rows | % | Null Edits | Critical | Hard Negatives |
|-------|------|---|------------|----------|----------------|
| **Train** | 210 | 70.0% | 45 (21.4%) | 6 | 1 |
| **Val** | 45 | 15.0% | 9 (20.0%) | 2 | 0 |
| **Test** | 45 | 15.0% | 9 (20.0%) | 2 | 1 |
| **TOTAL** | **300** | **100%** | **63 (21.0%)** | **10** | **2** |

### Category Distribution

| Category | Train | Val | Test | Total | Notes |
|----------|-------|-----|------|-------|-------|
| null_edits | 43 | 9 | 8 | 60 | Strong coverage |
| technical | 32 | 9 | 9 | 50 | Strong coverage |
| multilingual | 28 | 5 | 7 | 40 | FR + EN/FR only |
| short | 32 | 6 | 7 | 45 | Good coverage |
| prose | 24 | 6 | 5 | 35 | Good coverage |
| corrections | 18 | 4 | 3 | 25 | Includes negatives |
| lists | 18 | 4 | 3 | 25 | Includes negatives |
| commands | 15 | 2 | 3 | 20 | ⚠️ Underpowered |

### Null Edit Ratio

- **Overall:** 21.0% (target: 20%)
- **Train:** 21.4%
- **Val:** 20.0%
- **Test:** 20.0%

✅ Well-balanced across splits.

### Severity Distribution

| Severity | Train | Val | Test | Total |
|----------|-------|-----|------|-------|
| critical | 80 | 18 | 21 | 119 |
| medium | 89 | 20 | 15 | 124 |
| high | 41 | 7 | 9 | 57 |

### Validation Status

```
Files   3
Rows    300
Valid   300  (100.0%)
Errors  0
Warned  7  (all R-13 camelCase — acceptable)
```

### Remaining Known Weaknesses

1. **Commands underpowered:** 20 total, 15 in train. Minimal improvement expected.
2. **No non-FR languages:** ES, JA, ZH, RU not represented.
3. **Limited long-form:** Most examples < 15 words.
4. **Clean inputs dominate:** Minimal true ASR artifacts.

---

## 5. BASELINE METRICS CHECKLIST

### Before Training: Run Baseline Evaluation on test.jsonl

**REQUIRED: Capture these metrics from the current (unfine-tuned) model**

#### Overall Metrics
- [ ] **Overall WER** (Word Error Rate)
- [ ] **Overall CER** (Character Error Rate)

#### Category-Level Metrics
For each category (commands, corrections, lists, multilingual, null_edits, prose, short, technical):
- [ ] Category WER
- [ ] Category CER

#### Specialized Metrics
- [ ] **Null Edit Preservation Rate:** % of null_edit examples where output == input exactly
- [ ] **Protected Term Accuracy:** % of protected_terms that survive verbatim in output
- [ ] **Multilingual Translation Violations:** Count of any French → English or English → French translations
- [ ] **Critical Negative Pass Rate:** % of hard negatives where correct (conservative) behavior is maintained

#### Per-Example Tracking (for analysis)
Save the baseline outputs for each test example to enable:
- Before/after comparison
- Error analysis
- Qualitative assessment

### Commands to Capture Baseline

```bash
# Save baseline outputs
python scripts/evaluate_baseline.py \
  --test-file datasets/splits/test.jsonl \
  --output-file baselines/baseline_pilot_outputs.jsonl \
  --metrics-file baselines/baseline_pilot_metrics.json

# Generate baseline report
python scripts/generate_baseline_report.py \
  --baseline-file baselines/baseline_pilot_metrics.json \
  --output-file baselines/baseline_pilot_report.md
```

---

## 6. PILOT SUCCESS CRITERIA

### Minimum Acceptable Result (Pass/Fail Threshold)

**Pilot FAILS if any of these occur:**
- ❌ WER increases on any category (regression)
- ❌ Null edit preservation < 70%
- ❌ Protected term accuracy < 75%
- ❌ Any multilingual translation violations (translations should stay at 0)
- ❌ Critical negative pass rate < 80%

**Pilot PASSES if:**
- ✅ No regression on any category
- ✅ Null edit preservation ≥ 70%
- ✅ Protected term accuracy ≥ 75%
- ✅ Zero translation violations
- ✅ Critical negative pass rate ≥ 80%
- ✅ WER improves by > 3% on at least 2 categories

### Good Pilot Result

**Indicates the approach is promising:**
- ✅ WER improves by > 7% on core categories (prose, short, null_edits)
- ✅ Null edit preservation ≥ 85%
- ✅ Protected term accuracy ≥ 85%
- ✅ Critical negative pass rate = 100%
- ✅ Commands shows no regression despite low data
- ✅ Qualitative outputs show reasonable behavior

### Strong Pilot Result

**Indicates ready to scale to 1000+ examples:**
- ✅ WER improves by > 12% on core categories
- ✅ Null edit preservation ≥ 90%
- ✅ Protected term accuracy ≥ 90%
- ✅ All critical behaviors learned correctly
- ✅ Lists and corrections show measurable improvement
- ✅ Outputs qualitatively good (minimal hallucinations, appropriate restraint)

### Explicit Failure Conditions

**Immediate stop and investigate if:**
- Training loss doesn't decrease (learning not happening)
- Validation loss increases early (overfitting)
- Model produces garbage outputs (formatting broken)
- Systematic category collapse (e.g., all null_edits get edited)

---

## 7. TRAINING-READY PACKAGE SUMMARY

### Final Training Inputs

```
Evals/datasets/splits/
├── train.jsonl   (210 rows) ← Training data
├── val.jsonl     (45 rows)  ← Validation/early stopping
└── test.jsonl    (45 rows)  ← Final evaluation (DO NOT use during training)
```

### Files to Freeze/Lock Before Training

1. **Dataset files (read-only during training):**
   - `datasets/splits/train.jsonl`
   - `datasets/splits/val.jsonl`
   - `datasets/splits/test.jsonl`

2. **Baseline metrics (capture before training):**
   - `baselines/baseline_pilot_outputs.jsonl`
   - `baselines/baseline_pilot_metrics.json`
   - `baselines/baseline_pilot_report.md`

3. **Configuration:**
   - Training hyperparameters (learning rate, batch size, epochs)
   - Model architecture specification
   - Random seed (for reproducibility)

### Artifacts to Save After Training

1. **Model checkpoints:**
   - `checkpoints/best_model.pt` (best val loss)
   - `checkpoints/final_model.pt` (last epoch)
   - `checkpoints/model_config.json` (architecture + hyperparameters)

2. **Training logs:**
   - `logs/training_log.jsonl` (per-epoch metrics)
   - `logs/validation_metrics.json` (val set metrics per epoch)
   - `logs/loss_curves.png` (visualization)

3. **Evaluation outputs:**
   - `outputs/pilot_test_outputs.jsonl` (model outputs on test set)
   - `outputs/pilot_metrics.json` (final metrics)
   - `outputs/pilot_comparison_report.md` (baseline vs fine-tuned)

### Required Comparisons for Success Determination

| Comparison | Method | Threshold |
|------------|--------|-----------|
| Baseline vs Pilot WER | Compute delta on test.jsonl | > 3% improvement on ≥2 categories |
| Null edit preservation | Compare preservation rate | ≥ 70% |
| Protected term accuracy | Compare verbatim survival rate | ≥ 75% |
| Critical negatives | Manual review of 12 examples | ≥ 80% correct conservative behavior |
| Multilingual | Check for any translations | Must be 0 |
| Qualitative | Human review of 20 random examples | No major issues |

### Decision Tree

```
Run Pilot Training
│
├─ Training failed (loss didn't decrease)?
│  └─ YES → Investigate: data format, model config, learning rate
│  └─ NO  → Continue to evaluation
│
├─ Evaluate on test.jsonl
│
├─ Any regression (WER increased)?
│  └─ YES → Pilot FAILS; investigate overfitting
│  └─ NO  → Continue
│
├─ Null edit preservation < 70%?
│  └─ YES → Pilot FAILS; model not conservative enough
│  └─ NO  → Continue
│
├─ Protected term accuracy < 75%?
│  └─ YES → Pilot FAILS; model not preserving tech terms
│  └─ NO  → Continue
│
├─ Critical negative pass rate < 80%?
│  └─ YES → Pilot FAILS; model being too aggressive
│  └─ NO  → Continue
│
├─ WER improvement > 3% on ≥2 categories?
│  └─ YES → Pilot PASSES → Determine result tier (Good/Strong)
│  └─ NO  → Review qualitative outputs → Decide if learning is happening
│
└─ Result tier determined → Plan next steps (scale up or iterate)
```

### Next Steps After Pilot

**If pilot PASSES (Minimum):**
- Document learned behaviors
- Identify categories that need more data
- Plan scale-up to 1000+ examples

**If pilot PASSES (Good):**
- Proceed with targeted category expansion
- Add non-FR language examples
- Prepare for production pilot

**If pilot PASSES (Strong):**
- Scale immediately to 1000+ examples
- Begin production integration planning
- Conduct user acceptance testing

**If pilot FAILS:**
- Analyze failure mode (overfitting? underfitting? data quality?)
- Review qualitative outputs for patterns
- Adjust approach: more data, different hyperparameters, or architecture change

---

## APPENDIX A: Test Set Breakdown for Evaluation

### Critical Examples to Review Manually

| ID | Category | Subcategory | Raw | Expected | Why Critical |
|----|----------|-------------|-----|----------|-------------|
| zphyr-corrections-intentional-001 | corrections | intentional_repetition | non non non je ne suis pas d'accord | Non non non, je ne suis pas d'accord. | DO NOT collapse emphatic repetition |
| zphyr-lists-no-list-002 | lists | no_list_ambiguous | nous devons améliorer X et aussi Y | Nous devons améliorer X et aussi Y. | DO NOT create list from "et" |
| zphyr-commands-ambiguous-001 | commands | ambiguous_command_content | dis-lui d'aller à la ligne | Dis-lui d'aller à la ligne. | DO NOT execute as newline command |

### Null Edit Examples (Must Survive Verbatim)

All 9 null_edit examples in test.jsonl must have output == input exactly.

### Protected Terms to Verify

All examples with non-empty `protected_terms` array must have those terms survive verbatim.

---

**Status:** ✅ READY FOR TRAINING

**Last Updated:** 2026-03-09
**Package Version:** v1.0-pilot
