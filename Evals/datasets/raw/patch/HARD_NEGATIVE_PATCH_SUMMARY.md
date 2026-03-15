# Hard Negative Patch Dataset — Executive Summary

**Dataset:** Zphyr Hard Negative Patch v1
**Date:** 2026-03-09
**Total Examples:** 150
**Status:** READY FOR TRAINING

---

## Purpose

This is a **targeted hard-negative correction dataset** designed to fix specific conservative policy failures in the current `zphyr_qwen_v1-MLX-4bit` checkpoint. Unlike general coverage datasets, this patch focuses exclusively on teaching the model what **NOT to do**.

### Current Model Issues Addressed

| Issue | Current Model Behavior | Target Behavior |
|-------|------------------------|-----------------|
| **Intentional repetition collapse** | "vraiment vraiment" → "vraiment" | Preserve all emphatic repetition |
| **False list creation** | "et aussi" → bullet points | Keep as prose when not explicit list |
| **Command over-extraction** | Talking ABOUT commands → command extraction | Only extract direct commands TO system |

---

## Dataset Composition

```
┌─────────────────────────────────────┐
│  TOTAL: 150 examples                │
├─────────────────────────────────────┤
│  intentional_repetition: 60 (40%)   │  ← Emphatic repetition patterns
│  no_list_ambiguous:      45 (30%)   │  ← "et aussi" NOT a list
│  ambiguous_command_content:45 (30%) │  ← Talking ABOUT ≠ TO
└─────────────────────────────────────┘
```

### By Subcategory

| Subcategory | Count | Failure Corrected | What Model Must Learn |
|-------------|-------|-------------------|----------------------|
| **intentional_repetition** | 60 | Stops collapsing emphatic words | When uncertain, preserve repetition |
| **no_list_ambiguous** | 45 | Stops creating false lists | "et" alone ≠ list signal |
| **ambiguous_command_content** | 45 | Stops extracting indirect commands | Distinguish talk vs. command |

---

## Hard Negative Design Logic

### 1. intentional_repetition (60 examples)

**Failure it corrects:** Model collapses "vraiment vraiment" to "vraiment"
**What the model must learn:** Emphatic repetition is intentional, not stutter
**What the model must stop doing:** NOT deduplicating repeated words
**Contrastive logic:**
- `word_repetition` (seed): "je je vais" → "je vais" (stutter, remove)
- `intentional_repetition` (patch): "vraiment vraiment" → "vraiment vraiment" (emphasis, KEEP)

**Pattern types covered:**
- Double adverbs: "très très", "vraiment vraiment"
- Double adjectives: "belle belle", "génial génial"
- Double nouns: "bruit bruit", "attention attention"
- Double verbs: "je comprends je comprends"
- Emotional emphasis: "je t'aime je t'aime", "je pleure je pleure"
- Colloquial patterns: "ça marche ça marche", "t'inquiète t'inquiète"

### 2. no_list_ambiguous (45 examples)

**Failure it corrects:** Model creates bullet lists from simple "et" connections
**What the model must learn:** Single "et" ≠ list enumeration
**What the model must stop doing:** NOT bulleting "X et Y" compounds
**Contrastive logic:**
- `numbered_spoken` (seed): "premièrement X, deuxièmement Y" → list (explicit, DO list)
- `no_list_ambiguous` (patch): "X et aussi Y" → prose (implicit, DON'T list)

**Pattern types covered:**
- Two verbs with "et": "rechercher et trier"
- Two adjectives with "et": "épuré et intuitif"
- "et aussi": "améliorer et aussi réduire"
- "et en même temps": concessive, not list
- "et ensuite": temporal, not enumeration
- Technical I/O pairs: "lit et écrit", "envoie et reçoit"

### 3. ambiguous_command_content (45 examples)

**Failure it corrects:** Model extracts commands when people are just TALKING about commands
**What the model must learn:** Indirect speech ≠ direct command
**What the model must stop doing:** NOT extracting reported commands
**Contrastive logic:**
- `terminal_commands` (seed): "supprime le fichier" → copyOnly (direct, DO extract)
- `ambiguous_command_content` (patch): "elle m'a dit de supprimer" → prose (indirect, DON'T extract)

**Pattern types covered:**
- Reported speech: "elle a demandé de..."
- Advice attribution: "mon collègue m'a dit de..."
- Questions about capability: "est-ce qu'on peut..."
- Tentative suggestions: "tu pourrais..."
- Capability descriptions: "ce logiciel permet de..."
- Uncertainty expressions: "je ne sais pas si..."

---

## Reviewer Notes

### intentional_repetition Examples

All examples follow the pattern: **repeated word(s) are intentional emphasis, not stutter**

| Pattern | Example | Why NOT collapse |
|---------|---------|------------------|
| Double degree adverb | "très très bien" | Emphatic degree modification |
| Double adjective | "belle belle" | Appreciative emphasis |
| Double emotional word | "je t'aime je t'aime" | Romantic/emphatic declaration |
| Double action verb | "je comprends je comprends" | Active listening marker |
| Reassuring pattern | "t'inquiète t'inquiète" | Conversational reassurance |

**Key insight:** French uses word repetition for emphasis much more than English. The model's current "stutter removal" training is over-aggressive.

### no_list_ambiguous Examples

All examples follow: **single "et" connecting related items is prose, NOT a list**

| Connector | Example | Why NOT list |
|-----------|---------|--------------|
| "et aussi" | "améliorer et aussi réduire" | Compound goal, not enumerated items |
| "et en même temps" | "épuré et en même temps intuitif" | Concessive relationship |
| "et ensuite" | "analyser et ensuite présenter" | Temporal sequence |
| Simple "et" | "rechercher et trier" | Compound verb phrase |

**Key insight:** List creation requires EXPLICIT enumeration signals (premièrement/deuxièmement, numbered, bulleted). Simple "et" is insufficient.

### ambiguous_command_content Examples

All examples follow: **talking ABOUT commands ≠ giving a command**

| Frame | Example | Why NOT extract |
|-------|---------|----------------|
| Reported speech | "elle a demandé de supprimer" | Narrative about past request |
| Attribution | "mon père m'a dit de sauvegarder" | Quoting received advice |
| Question | "est-ce qu'on peut annuler" | Inquiry about capability |
| Tentative | "tu pourrais essayer" | Suggestion, not directive |
| Description | "le bouton permet de copier" | Feature description |

**Key insight:** Commands TO the system are direct imperatives. Indirect speech about commands is prose.

---

## Validation Summary

```
┌─────────────────────────────────────────────────────────────┐
│  VALIDATION RESULTS                                        │
├─────────────────────────────────────────────────────────────┤
│  Total examples:        150                                │
│  Unique IDs:            150                                │
│  review_status:         150/150 approved                   │
│  annotation_confidence: 150/150 high                       │
│  no_translation:        150/150 true                       │
│  duplicates with seed:  0                                  │
├─────────────────────────────────────────────────────────────┤
│  intentional_repetition: 60/150 (40%)                      │
│  no_list_ambiguous:      45/150 (30%)                      │
│  ambiguous_command_content: 45/150 (30%)                   │
└─────────────────────────────────────────────────────────────┘
```

### Duplicate Check: PASS ✓
- 0 overlapping `raw_asr_text` with existing seed data
- All 150 examples are novel additions

### Schema Compliance: PASS ✓
- All fields present and correctly typed
- Follows approved Zphyr dataset v1 schema exactly
- Required fields populated: `review_status`, `annotation_confidence`

### Contrastive Coverage: PASS ✓
- Each patch example has corresponding positive example in seed
- Clear distinction between "do this" (seed) and "don't do this" (patch)

---

## Final Counts and Rationale

| Subcategory | Count | Rationale |
|-------------|-------|-----------|
| **intentional_repetition** | 60 | Highest diversity needed: 12 distinct repetition pattern types × 5 variations each |
| **no_list_ambiguous** | 45 | Medium diversity: 9 connector patterns × 5 variations each |
| **ambiguous_command_content** | 45 | Medium diversity: 9 indirect speech frames × 5 variations each |

**Total: 150 examples** — Focused, targeted correction dataset

### Why These Counts?

1. **intentional_repetition (60 = 40%)**: Highest priority because current model fails ALL 3 test hard negatives. This is the most severe failure mode.

2. **no_list_ambiguous (45 = 30%)**: Medium priority. Model creates false lists but issue is less catastrophic than repetition collapse.

3. **ambiguous_command_content (45 = 30%)**: Medium priority. Command over-extraction is annoying but less frequent than other issues.

---

## Usage Instructions

### For Training

```bash
# Convert to Qwen chat format
cd Evals/training
python prepare_qwen_dataset.py \
  --input ../datasets/raw/patch/hard_negative_patch.jsonl \
  --output qwen_format/patch.jsonl \
  --patch-mode
```

### For Validation

```bash
# Run against existing validation harness
cd /Users/aris/Documents/VoiceProject/Zphyr
xcodebuild test -scheme Zphyr \
  -only-testing:ZphyrTests/EvalSeedSplitTests \
  EVAL_MODE=advanced
```

### Expected Impact

| Metric | Before Patch | After Patch (Target) |
|--------|-------------|---------------------|
| Null edit preservation | 44% | ≥89% |
| Hard negative pass rate | 0% | 100% |
| Overall WER | 0.22 | ≤0.08 |

---

## File Location

```
Evals/datasets/raw/patch/hard_negative_patch.jsonl
```

**Size:** 150 lines, ~47 KB
**Format:** JSONL (one JSON object per line)
**Encoding:** UTF-8

---

**Status:** ✅ READY FOR PATCH TRAINING
**Last Updated:** 2026-03-09
**Contact:** Zphyr ML Team
