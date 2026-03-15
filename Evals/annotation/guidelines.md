# Zphyr Training Dataset v1 — Annotation Guidelines

> **Core principle**: When uncertain, produce no edit. Under-formatting is always preferred over over-formatting. The no-edit output is always acceptable. An unnecessary edit is never acceptable.

---

## 1. What This Dataset Is

This dataset trains the Qwen LLM to perform **constrained post-ASR transformation**: take raw Whisper output and produce final text ready for clipboard insertion.

This is **not** a general text generation task. The model applies a small, safe, auditable set of edits. The ideal delta between input and output is minimal.

This dataset covers `formatting_mode: advanced_llm` only. It does not cover trigger-mode code formatting (that is deterministic, not LLM-based).

---

## 2. Annotation Workflow

```
DRAFT  →  automated validate.py  →  REVIEW  →  APPROVED
                                              ↘  REJECTED  (move to annotation/rejected/)
                                              ↘  NEEDS_REVIEW  (annotation_confidence: low)
```

**Before writing `final_expected_text`**: set `rewrite_allowed_level` first. This forces you to decide what you are allowed to do before you do it. Do not set the level to match what you already wrote.

**Before saving a draft**:
1. Every item in `protected_terms` appears character-identically in both raw and expected
2. No word in `final_expected_text` is a translation of a word in `raw_asr_text`
3. `is_null_edit` is correct (`true` iff raw == expected, exactly)
4. `annotation_confidence` honestly reflects your certainty

**Review gap**: Do not review a row you drafted the same day. Minimum 24-hour gap for self-review.

**Null edit target**: At least 1 in 8 examples you write should be a null edit. If your ratio falls below 10%, stop and write more.

---

## 3. Field Reference

| Field | Type | Values | Notes |
|-------|------|--------|-------|
| `id` | string | `zphyr-{cat}-{sub}-{NNN}` | Unique, stable, never reused |
| `raw_asr_text` | string | — | Exact Whisper output; no punctuation at sentence ends |
| `final_expected_text` | string | — | Gold output; only safe edits applied |
| `category` | enum | see taxonomy | Top-level category |
| `subcategory` | enum | see taxonomy | Must match category |
| `language` | enum | `fr en es zh ja ru mixed` | Primary language; `mixed` for code-switching |
| `rewrite_allowed_level` | enum | `no_edit punctuation_only light_polish` | Set BEFORE writing expected |
| `is_null_edit` | bool | — | `true` iff raw == expected exactly |
| `difficulty` | enum | `easy medium hard` | Based on annotation effort, not ASR quality |
| `severity_if_wrong` | enum | `low medium high critical` | See §8 for defaults |
| `source_type` | enum | `hand_written semi_synthetic synthetic eval_derived` | |
| `protected_terms` | string[] | — | Required for `technical` and any row with technical tokens |
| `no_translation` | bool | default `true` | Explicit `false` only for future translation category |
| `has_asr_artifact` | bool | — | |
| `asr_artifact_types` | string[] | `filler_word repetition split_word wrong_number hallucination` | |
| `constraint_ids` | string[] | `CONSTRAINT-01` … `CONSTRAINT-10` | Recommended for high-severity rows |
| `notes` | string | — | Concise annotation rationale |
| `annotation_confidence` | enum | `high medium low` | |
| `acceptable_variants` | string[] | max 3 | Only truly correct alternatives |
| `review_status` | enum | `draft approved rejected needs_review` | |

---

## 4. Operation Rules

### 4.1 Punctuation

**Always allowed (`punctuation_only` and above)**:
- Sentence-final period when sentence clearly ends and none is present
- Question mark when syntax is interrogative
- Comma before a coordinating conjunction joining two independent clauses, when clearly missing

**Never allowed (any level)**:
- Comma insertion mid-clause where not clearly required
- Semicolons (too ambiguous)
- Ellipses (only preserve if already present in raw)
- Any punctuation inside `protected_terms` or technical strings
- Period after a very short utterance (1–3 words) unless it is clearly a complete sentence

**Spoken punctuation commands (`commands/spoken_punctuation`)**:
- `virgule` → `,` (French)
- `point` or `point final` → `.` (French)
- `point d'interrogation` → `?` (French)
- `period` / `comma` → `.` / `,` (English)
- The spoken command word must **not** appear in the output

### 4.2 Capitalization

**Always allowed**:
- First word of a sentence
- `I` (first person singular, English)
- Proper nouns you can identify with certainty (established names, cities, brands)

**Never allowed**:
- Mid-sentence capitalization because a word "seems important"
- Changing case of any item in `protected_terms`
- Changing case of camelCase, snake_case, UPPER_CASE identifiers
- ALL_CAPS for emphasis (unless already present)

**Borderline — prefer no change**:
- First word after a colon: only capitalize if it begins a complete sentence

### 4.3 Filler Words

**Safe to remove (`light_polish` only)**:
- `um`, `uh` at utterance start or utterance end
- `euh`, `hm` in French at utterance boundaries
- Exact duplicate word where repetition is a clear ASR artifact (not semantic)

**Never remove**:
- `like` (usually semantic in informal speech)
- `well` at utterance start (discourse marker)
- Repetition that could be intentional emphasis: `vraiment vraiment`, `no no`, `think think` are often emphatic — do NOT clean unless context makes artifactual nature unambiguous
- Any filler that falls inside a technical phrase

**Rule**: When in doubt, keep the filler. Write a null-edit example instead.

### 4.4 Numbers

**Normalize only when**:
- The subcategory is `data_values` and context is clearly numeric
- The number is a year in an unambiguous date phrase and you are certain

**Never normalize**:
- Spelled-out numbers that could be stylistic ("chapter two", "act three")
- Version numbers without explicit context
- Phone numbers, IDs, codes
- Numbers inside technical identifiers
- Port numbers unless subcategory explicitly tests this

**Default**: `preserve_numbers: true` behavior unless the example is specifically testing normalization.

### 4.5 Language Preservation

This is the highest-priority rule after null edits.

If the raw text contains a word in language X, the expected output must contain that word in language X. No exceptions.

- Do not translate `endpoint` to `point de terminaison`
- Do not translate `merci` to `thanks`
- Do not normalize a French accent (`élève` must not become `eleve`)
- Do not drop a foreign-language word from the output

Every multilingual example has `no_translation: true` and must be verified against this rule.

### 4.6 Technical Tokens

Any token where a character-level change creates an error is a protected term. Add it to `protected_terms`.

Protected term types:
- Function/method names: `getUserById`, `parse_config`
- Package names: `react-query`, `@anthropic-ai/sdk`
- Environment variables: `NODE_ENV`, `DATABASE_URL`
- URLs: any substring of a URL
- File paths: any path component including dots and slashes
- Semver: `v20.11.0`, `3.14.1`
- Proper case names: `GitHub`, `Node.js`, `TypeScript`

Verification: after writing the expected text, check every item in `protected_terms` character-by-character against both raw and expected.

### 4.7 Lists

**Detect list structure only when signal is explicit**:
- Ordinal markers: `premièrement`, `deuxièmement`, `first`, `second`, `third`
- Repeated conjunction pattern: `et puis... et puis... et puis...`
- Explicit numbering: `un virgule... deux virgule...`

**Never detect list structure from**:
- Two related sentences ("nous devons améliorer X et aussi Y")
- Items connected by `and` / `et` alone
- Any ambiguous sequence

**When you detect a list**: list items must be preserved verbatim; only the structural markers change.

---

## 5. When to Write a Null Edit

Write `is_null_edit: true` when:
- The Whisper output is already correctly formatted
- The edit you are considering is borderline or stylistic
- The example is technical or multilingual and you cannot guarantee every protected term survives
- The utterance is short (CAT-2) and no edit is clearly mandated
- You are uncertain whether an edit is correct

For null edits: `raw_asr_text` and `final_expected_text` must be byte-identical. Use a diff tool to verify.

---

## 6. Acceptable Variants

`acceptable_variants` is for eval tolerance only, not for training. Rules:

- A variant must be as correct as `final_expected_text`. Not just plausible — actually correct.
- A variant differs from `final_expected_text` in at most 2 ways: number format, punctuation style, list marker style
- A variant must not change meaning
- A variant must not be identical to `raw_asr_text` (unless `is_null_edit: true`)
- Maximum 3 variants. If you have more than 3 acceptable outputs, the example is too ambiguous — simplify or reject.

---

## 7. Severity Defaults

| Condition | Severity |
|-----------|----------|
| `category: technical` with any `protected_terms` | `critical` |
| `category: multilingual` (all subcategories) | `critical` |
| `null_edits/technical_passthrough` | `critical` |
| `null_edits/multilingual_passthrough` | `critical` |
| `commands/ambiguous_command_content` | `critical` |
| `corrections/intentional_repetition` | `high` |
| `commands/spoken_punctuation` | `medium` |
| `prose`, `corrections` general | `low` to `medium` |

---

## 8. Hard Constraints Reference

| ID | Rule |
|----|------|
| CONSTRAINT-01 | Never translate any content, even a single word |
| CONSTRAINT-02 | Never corrupt protected terms — character-level changes are critical failures |
| CONSTRAINT-03 | Never modify URLs, emails, paths, package names, API names |
| CONSTRAINT-04 | Never collapse list structure when list is indicated |
| CONSTRAINT-05 | Never alter numbers, versions, dates unless example explicitly tests normalization |
| CONSTRAINT-06 | Never expand short utterances — output word count ≤ input word count (except punctuation tokens) |
| CONSTRAINT-07 | Spoken formatting commands must execute — command word must not appear in output |
| CONSTRAINT-08 | Content that mentions formatting must not trigger formatting — preserve it verbatim |
| CONSTRAINT-09 | Never infer list structure unless explicit spoken markers are present |
| CONSTRAINT-10 | When uncertain, produce no change — the no-edit output is always acceptable |

---

## 9. Common Rejection Reasons

| Reason | Example |
|--------|---------|
| Paraphrase | "je crois" → "je pense" — word substitution is not a formatting operation |
| Added words | Expected contains words not in raw (not structural tokens) |
| Translation | `endpoint` → `point de terminaison` |
| Protected term corrupted | `react-query` → `react query` or `ReactQuery` |
| Over-capitalization | Capitalizing a mid-sentence word that is not a proper noun |
| Ambiguous expected output | More than 3 valid outputs exist — example needs to be simplified |
| Raw already has terminal punct but is_null_edit=false | Verify Whisper really produced this; if so, make it a null edit |
| Rewrite level too high | `light_polish` set but only punctuation was changed — use `punctuation_only` |
| Null edit mismatch | `is_null_edit: true` but raw ≠ expected |
| annotation_confidence: low in a completed row | Must resolve or reject before inclusion |
