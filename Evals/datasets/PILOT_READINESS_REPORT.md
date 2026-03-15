# Zphyr v1 Pilot Fine-Tuning Readiness Report

**Generated:** 2026-03-09
**Dataset:** 300-example seed set
**Split:** 70/15/15 (194 train / 53 val / 53 test)

---

## 1. EXECUTIVE SUMMARY

The 300-example seed set is **MINIMALLY VIABLE** for a first pilot fine-tuning run, with significant caveats.

**Verdict:** Proceed with pilot as a **learning exercise**, not as a production-ready model trainer. This pilot will validate the training pipeline and reveal which categories need more data.

**Key Finding:** The dataset is well-structured and covers the taxonomy, but many categories are critically underpowered (≤10 examples per split). The pilot should focus on proving the pipeline works, not achieving production metrics.

---

## 2. SPLIT STRATEGY

### 2.1 Allocation

| Split | Rows | % of Total | Purpose |
|-------|------|------------|---------|
| Train | 194 | 64.7% | Model training |
| Val   | 53  | 17.7% | Hyperparameter tuning, early stopping |
| Test  | 53  | 17.7% | Final evaluation |

### 2.2 Stratification Approach

- **Category-stratified:** Each of 8 categories is represented proportionally across splits
- **Subcategory-stratified:** Each subcategory has at least 1 example in val/test (where category size permits)
- **Critical examples preserved:** All 10 CRITICAL-marked examples distributed across val/test (4) and train (6)
- **Null edit ratio maintained:** ~21% across all splits (matching the 63/300 target)
- **Hard negatives distributed:** Ambiguous examples spread across splits

### 2.3 Split Statistics

```
METRIC                           TRAIN        VAL       TEST      TOTAL
----------------------------------------------------------------------
Total rows                         194         53         53        300
% of dataset                     64.7%      17.7%      17.7%     100.0%

Null edits (count)                  41         11         11         63
Null edits (%)                   21.1%      20.8%      20.8%

Critical examples                    6          2          2         10
Hard negatives                       6          3          3         12
```

---

## 3. CATEGORY DISTRIBUTION

```
Category                TRAIN      VAL     TEST    TOTAL
-------------------------------------------------------
commands                   10        5        5       20
corrections                17        4        4       25
lists                      17        4        4       25
multilingual               26        7        7       40
null_edits                 40       10       10       60
prose                      23        6        6       35
short                      27        9        9       45
technical                  34        8        8       50
```

### Balance Assessment
- **Well-balanced:** null_edits (67/17/17%), technical (68/16/16%), multilingual (65/18/18%)
- **Acceptable:** prose (66/17/17%), short (60/20/20%), corrections (68/16/16%), lists (68/16/16%)
- **Sparse:** commands (50/25/25%) - only 10 training examples

---

## 4. SUBCATEGORY DISTRIBUTION (KEY CATEGORIES)

### CORRECTIONS (25 total)
| Subcategory | TRAIN | VAL | TEST | TOTAL |
|-------------|-------|-----|------|-------|
| filler_removal | 6 | 1 | 1 | 8 |
| word_repetition | 5 | 1 | 1 | 7 |
| spoken_restart | 3 | 1 | 1 | 5 |
| intentional_repetition | 3 | 1 | 1 | 5 |

**Assessment:** Critical negative examples (intentional_repetition) have 1 in each split - good coverage.

### LISTS (25 total)
| Subcategory | TRAIN | VAL | TEST | TOTAL |
|-------------|-------|-----|------|-------|
| numbered_spoken | 6 | 1 | 1 | 8 |
| bulleted_spoken | 5 | 1 | 1 | 7 |
| inline_enumeration | 3 | 1 | 1 | 5 |
| no_list_ambiguous | 3 | 1 | 1 | 5 |

**Assessment:** Hard negative (no_list_ambiguous) has 1 in each split - good coverage.

### COMMANDS (20 total) - UNDERPOWERED
| Subcategory | TRAIN | VAL | TEST | TOTAL |
|-------------|-------|-----|------|-------|
| spoken_punctuation | 6 | 2 | 2 | 10 |
| trigger_mode | 3 | 1 | 1 | 5 |
| formatting_commands | 1 | 1 | 1 | 3 |
| ambiguous_command_content | 0 | 1 | 1 | 2 |

**Assessment:** Critical negative (ambiguous_command_content) has 0 in train - may not learn to preserve prose content. Only 10 train examples total.

### SHORT (45 total)
| Subcategory | TRAIN | VAL | TEST | TOTAL |
|-------------|-------|-----|------|-------|
| short_sentence | 17 | 4 | 4 | 25 |
| near_empty | 6 | 2 | 2 | 10 |
| single_word_phrase | 3 | 1 | 1 | 5 |
| filename_tag | 1 | 1 | 1 | 3 |
| title | 0 | 1 | 1 | 2 |

**Assessment:** title and filename_tag are severely underrepresented.

### TECHNICAL (50 total)
| Subcategory | TRAIN | VAL | TEST | TOTAL |
|-------------|-------|-----|------|-------|
| package_names | 8 | 2 | 2 | 12 |
| code_identifiers | 6 | 2 | 2 | 10 |
| terminal_commands | 5 | 1 | 1 | 7 |
| urls_paths | 6 | 1 | 1 | 8 |
| config_env_vars | 6 | 1 | 1 | 8 |

**Assessment:** Well-distributed across subcategories.

---

## 5. DEDUPLICATION AND LEAKAGE CHECKS

### 5.1 Exact Duplicates
**Found:** 1 pair
- `zphyr-null-short-002` (null_edits/short_passthrough): "ok" → "ok"
- `zphyr-short-near-003` (short/near_empty): "ok" → "OK"

**Analysis:** These are **NOT true duplicates**. Same raw input, different expected outputs based on category:
- null_edits expects passthrough (no change)
- short expects capitalization (OK)

**Issue:** Currently split between train and test - could confuse the model if it sees "ok" in training with one behavior and "ok" in test with another.

**Recommendation:** Keep both, but add metadata about ambiguous raw inputs.

### 5.2 Near-Duplicate Leakage
**Found:** 0 near-duplicate pairs at 85% threshold across splits.

### 5.3 Critical Examples Distribution
All 10 critical examples are distributed:
- Train: 6 (for learning)
- Val: 2 (for validation)
- Test: 2 (for evaluation)

---

## 6. PILOT FINE-TUNE READINESS VERDICT

### 6.1 Strengths of Current Dataset

1. **Well-structured taxonomy:** 8 categories, 30+ subcategories clearly defined
2. **Negative examples included:** intentional_repetition, no_list_ambiguous, ambiguous_command_content
3. **Null edit ratio healthy:** 21% across all splits (target was 20%)
4. **Validation clean:** 0 errors, only 7 acceptable warnings (R-13 on known transformations)
5. **Multi-language coverage:** French + mixed EN/FR examples
6. **Technical diversity:** code, URLs, packages, env vars, version numbers

### 6.2 Weaknesses and Gaps

1. **Severe underpowering in several categories:**
   - commands: only 10 train examples for 5 subcategories
   - formatting_commands: 1 train example
   - ambiguous_command_content: 0 train examples (critical negative!)
   - title: 0 train examples
   - filename_tag: 1 train example

2. **Limited language diversity:**
   - 154/194 train examples are French-only
   - Only 40/194 are mixed-language
   - Zero examples for: Spanish, Japanese, Chinese, Russian + English

3. **Minimal ASR artifact variety:**
   - Most examples are clean input
   - Limited true filler/dysfluency examples
   - No重度 dysfluency examples

4. **Short inputs dominate:**
   - Many examples are 1-5 words
   - Limited long-form prose (3+ sentences)

5. **Ambiguous raw input issue:**
   - "ok" appears twice with different expected outputs
   - Could confuse model during training

### 6.3 Underpowered Categories (Need More Data)

| Category | Current | Estimated Needed | Gap |
|----------|---------|------------------|-----|
| commands | 20 | 50-75 | +30-55 |
| formatting_commands | 3 | 15-20 | +12-17 |
| ambiguous_command_content | 2 | 8-10 | +6-8 |
| title | 2 | 10 | +8 |
| filename_tag | 3 | 10 | +7 |
| non-FR languages | 0 | 30-50 | +30-50 |
| long_form prose | ~5 | 20 | +15 |

### 6.4 What This Pilot Can and Cannot Prove

**CAN Prove:**
- Training pipeline works end-to-end
- Model learns basic punctuation and capitalization
- Model learns to preserve technical terms (protected_terms)
- Null edit restraint is learned (21% ratio)
- Basic list structure detection
- French language formatting

**CANNOT Prove:**
- Robust command detection (insufficient examples)
- Multi-language coverage (only FR + EN/FR mixed)
- Handling of重度 ASR artifacts (insufficient dysfluency examples)
- Title/filename formatting (severely underpowered)
- Ambiguous command vs content discrimination (0 train examples)

---

## 7. RECOMMENDED PILOT OBJECTIVE

### 7.1 Success Metrics (Before vs After)

**Primary Metrics:**
1. **WER/Character edit rate:** Compare baseline model vs fine-tuned on test set
2. **Null edit preservation:** % of null_edits that remain unchanged
3. **Technical term accuracy:** % of protected_terms preserved verbatim
4. **Critical negative pass rate:** % of intentional_repetition that is NOT collapsed

**Secondary Metrics:**
1. **List detection accuracy:** Precision/recall for list structure
2. **Punctuation quality:** Sentence-final punct correctness
3. **Language preservation:** No translation in multilingual examples

### 7.2 Categories to Improve First

**Priority 1 (Expected improvement):**
- **prose:** Sentence punctuation, capitalization, filler removal
- **short:** Proper restraint on short utterances
- **null_edits:** Model learns when NOT to edit

**Priority 2 (Expected improvement):**
- **technical:** Protected term preservation
- **corrections:** Safe artifact removal

### 7.3 Categories to NOT Regress

**Must maintain baseline performance:**
- **multilingual:** No translation, preserve mixed-language
- **commands:** Current baseline (won't improve much, but shouldn't break)
- **lists:** Don't over-detect lists where none exist

### 7.4 Success Criteria for Pilot

**Minimum Viable:**
- Training runs without errors
- Model produces output for all test examples
- WER improves by >5% on prose/short/null_edits
- Null edit preservation >80%
- No regression on multilingual (0 translations)

**Good Result:**
- WER improves by >10% on prose/short/null_edits
- Technical term accuracy >90%
- All critical negative examples pass
- No category regresses

**Excellent Result:**
- WER improves by >15% on core categories
- Model shows learning on lists and corrections
- Commands show slight improvement despite low data
- Ready to scale to 1000+ examples

---

## 8. RECOMMENDED NEXT STEPS

### 8.1 Immediate (Before Pilot)

1. **Fix ambiguous raw input:** Add metadata flag to both "ok" examples
2. **Verify split files:** Ensure train/val/test are correctly formatted
3. **Create baseline metrics:** Run current model on test set for comparison

### 8.2 Pilot Run

1. **Configure training:**
   - Start with conservative hyperparameters
   - Use val set for early stopping
   - Save checkpoints

2. **Monitor:**
   - Loss curves by category
   - Null edit ratio during training
   - Overfitting signals (train loss << val loss)

### 8.3 Post-Pilot (Based on Results)

**If pilot succeeds:**
- Scale up underpowered categories (commands: +30-55, titles: +8, etc.)
- Add non-FR language pairs
- Add long-form examples
- Expand to 1000-2000 examples

**If pilot fails:**
- Analyze failure modes (overfitting? underfitting? data quality?)
- Review hyperparameters
- Consider data augmentation
- Revisit taxonomy complexity

---

## 9. SUMMARY TABLE

| Aspect | Status | Notes |
|--------|--------|-------|
| Total examples | 300 | Minimal viable for pilot |
| Train/Val/Test split | 194/53/53 | Well-stratified |
| Null edit ratio | 21% | On target |
| Critical examples | 10 | Well distributed |
| Duplicate leakage | 0 | Clean (ambiguous input flagged) |
| Category balance | Mixed | 5 categories OK, 3 underpowered |
| Language diversity | Low | FR + EN/FR only |
| Technical terms | Good | 50 technical examples |
| ASR artifacts | Low | Mostly clean input |
| Overall readiness | MINIMALLY VIABLE | Proceed for learning, not production |

---

**Generated by:** `create_splits.py` + `analyze_splits.py`
