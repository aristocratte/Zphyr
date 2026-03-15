# Zphyr Training Dataset v1 — Category Taxonomy

## Quick Reference

| Category | Rewrite Level | Severity Default | Null Edit Target |
|----------|--------------|-----------------|------------------|
| `prose` | `light_polish` | low–medium | 5% |
| `short` | `punctuation_only` or `no_edit` | medium | 25% |
| `multilingual` | `punctuation_only` | critical | 20% |
| `lists` | `light_polish` | medium | 5% |
| `technical` | `punctuation_only` | critical | 10% |
| `corrections` | `light_polish` | low–high | 5% |
| `commands` | `punctuation_only` | medium–critical | 5% |
| `null_edits` | `no_edit` | medium–critical | 100% |

---

## CAT-1: `prose`

**What the model does**: Sentence capitalization, sentence-final punctuation, filler removal. Nothing else.

**Failure risks**:
- Adding words not in raw
- Paraphrasing or synonym substitution
- Over-punctuating mid-sentence
- "Improving" a sentence that was already correct

**Rewrite level**: `light_polish` (allows filler removal + punctuation). Never `full_rewrite`.

| Subcategory | Description | Example signal |
|-------------|-------------|----------------|
| `email_body` | Multi-sentence email content | Formal register, salutation present |
| `chat` | Short conversational messages | Informal, may have slang |
| `notes` | Unstructured personal notes | Fragment-like, terse |
| `long_form` | Extended dictation, 3+ sentences | Multiple clause boundaries |
| `prompt_query` | Dictating a query to an LLM interface | Often ends with `?` |
| `informal` | Very informal, slang acceptable | Social media tone |

---

## CAT-2: `short`

**What the model does**: Minimal punctuation at most. Aggressive restraint. Model must resist the urge to edit.

**Failure risks**:
- Expanding the utterance ("envoie" → "Tu dois envoyer")
- Adding anything when nothing is needed
- Translating ("ok" → "d'accord")
- Capitalizing mid-sentence words unnecessarily

**Rewrite level**: `punctuation_only` or `no_edit`. **Never `light_polish`.**

A 5-word input that is already correct must produce a 5-word (or near-identical) output. The model adds at most a capital letter and a period.

| Subcategory | Description | Example |
|-------------|-------------|---------|
| `short_sentence` | Complete sentence, ≤10 words | "envoie le fichier à sophie" |
| `single_word_phrase` | Single word or short compound | "annulé" / "en cours" |
| `title` | Document or section title | "rapport mensuel mars 2026" |
| `filename_tag` | Filename, label, tag | "config_backup_v2" |
| `near_empty` | 1–2 word utterance | "ok" / "d'accord" / "oui" |

---

## CAT-3: `multilingual`

**What the model does**: Sentence punctuation and capitalization only. **Never translates anything.**

**Failure risks**:
- Translating the minority-language portion
- Normalizing foreign words (removing accents, anglicizing)
- Silently dropping a foreign-language word
- Changing case of English technical terms embedded in French sentences

**Rewrite level**: `punctuation_only`. No exceptions.

All examples: `no_translation: true`. All examples: `language: "mixed"`. Protected terms must include any technical token regardless of language.

| Subcategory | Description | Example |
|-------------|-------------|---------|
| `fr_primary_en_terms` | French sentence with English technical terms | "j'ai besoin d'un endpoint" |
| `en_primary_fr_terms` | English sentence with French phrases | "the report is ready, merci de le relire" |
| `code_switching` | Language switches mid-sentence at clause boundary | "je pense que le best approach c'est Redis" |
| `quoted_foreign` | One language explicitly quoting another | French sentence with quoted English term |
| `other_pairs` | Other Zphyr UI language pairs (es, ja, zh, ru + en) | Spanish with English tech terms |

---

## CAT-4: `lists`

**What the model does**: Detect spoken list structure from explicit markers, format as numbered or bulleted list. Item content must be preserved verbatim.

**Failure risks**:
- Detecting list structure where none was intended (see `no_list_ambiguous`)
- Paraphrasing list items while formatting them
- Reordering items
- Merging two items into one
- Adding items not in the raw text

**Rewrite level**: `light_polish` for structure detection, but `no_edit` on item content. Never paraphrase items.

| Subcategory | Description | Signal |
|-------------|-------------|--------|
| `numbered_spoken` | Explicit ordinals: premièrement/deuxièmement/first/second | Ordinal words at item starts |
| `bulleted_spoken` | Repeated conjunction pattern | "et puis... et puis..." / "and then... and then..." |
| `structured_outline` | Hierarchical list, nesting implied | "first category: A, B, C; second category: D, E" |
| `inline_enumeration` | Inline list that becomes bulleted | "I need three things: X, Y, and Z" |
| `no_list_ambiguous` | Two related ideas connected by "et" — NOT a list | "nous devons améliorer X et aussi Y" |

`no_list_ambiguous` is a **negative example** category. The expected output is a single sentence (no list). These examples teach the model to require explicit signals before creating list structure.

---

## CAT-5: `technical`

**What the model does**: Punctuation and capitalization at sentence level only. Preserves all technical tokens exactly. The model's job in this category is primarily **to do nothing** to technical content.

**Failure risks**:
- Normalizing camelCase to plain words
- Removing or altering package name hyphens
- Changing env var case (UPPER → lower)
- Altering version numbers
- Translating technical terms to French equivalents
- Adding punctuation inside technical strings

**Rewrite level**: `punctuation_only`. Almost never `light_polish`.

**Every example must have `protected_terms` populated.** If you cannot identify protected terms, the example does not belong in this category.

| Subcategory | Description | Protected term examples |
|-------------|-------------|------------------------|
| `code_identifiers` | Function/method/variable names | `getUserById`, `parse_config`, `myVar` |
| `terminal_commands` | Shell commands and flags | `npm run build`, `git push origin main` |
| `urls_paths` | URLs, file paths, routes | `/api/v2/users`, `https://zphyr.app` |
| `package_names` | npm/pip/brew package names | `react-query`, `@anthropic-ai/sdk`, `axios` |
| `config_env_vars` | Environment variables, config keys | `NODE_ENV`, `DATABASE_URL`, `NEXT_PUBLIC_*` |
| `version_numbers` | Semver, version strings | `v20.11.0`, `3.14.1`, `Node.js v20` |
| `data_values` | Port numbers, IDs, timestamps | `3000`, `user_id: 42` |

---

## CAT-6: `corrections`

**What the model does**: Remove unambiguous ASR artifacts. Preserve intentional repetition. When in doubt, do nothing.

**Failure risks**:
- Removing intentional emphasis repetition ("vraiment vraiment", "no no")
- Over-cleaning spoken restarts that should be preserved
- Removing content words mistaken for fillers
- Producing a different sentence than what was intended

**Rewrite level**: `light_polish` for clear artifacts. `punctuation_only` or `no_edit` when ambiguous.

| Subcategory | Description | Rule |
|-------------|-------------|------|
| `filler_removal` | `um`, `uh`, `euh`, `hm` at utterance boundaries | Safe to remove at start/end only |
| `word_repetition` | ASR artifact repeating a word (`le le`, `that that`) | Safe to collapse if clearly artifactual |
| `spoken_restart` | Explicit self-correction ("no wait actually") | Collapse the restart |
| `filler_and_repetition` | Both filler and repetition present | Remove both where safe |
| `intentional_repetition` | Repeated word that is emphatic, not artifactual | **Must preserve** — critical negative example |

`intentional_repetition` examples are high-severity negative examples. A model that removes `vraiment vraiment` is broken. These examples must exist in the dataset to prevent this behavior.

---

## CAT-7: `commands`

**What the model does**: Correctly execute or preserve spoken commands depending on context.

**Failure risks**:
- Executing a command that was content ("à la ligne" in prose context → should not insert newline)
- Preserving a command word that should be replaced ("virgule" → should become `,`)
- Executing a command in the wrong position
- Confusing trigger-mode commands with advanced-mode punctuation commands

**Rewrite level**: `punctuation_only` (the "edit" is a substitution, not a free rewrite).

| Subcategory | Description | Example |
|-------------|-------------|---------|
| `spoken_punctuation` | Spoken punct word → punctuation character | `virgule` → `,` / `point` → `.` |
| `trigger_mode` | Trigger-mode code style commands | `camel get user profile` → `getUserProfile` |
| `formatting_commands` | Structural commands | `new paragraph` → `\n\n` / `bullet point` → `-` |
| `navigation_commands` | Commands that should not appear in output | `undo`, `delete that` → empty / no-op |
| `ambiguous_command_content` | Formatting phrase that is prose content | "dis-lui d'aller à la ligne" — content, not command |

`ambiguous_command_content` is a critical negative example category: the spoken phrase sounds like a command but is actually content. The model must output the phrase verbatim.

---

## CAT-8: `null_edits`

**What the model does**: Nothing. Output = input exactly.

**Failure risks**: Any edit at all. This category exists to calibrate model restraint. Without sufficient null edits in training, the model learns that its job is always to change something.

**Rewrite level**: `no_edit`. Always. Every example in this category has `is_null_edit: true`.

**Target**: 12–15% of total training set. 20% of seed set (for early restraint calibration).

| Subcategory | Description | Notes |
|-------------|-------------|-------|
| `already_correct` | Whisper produced perfectly formatted prose | Sentence-final punct present, casing correct |
| `short_passthrough` | Short utterance already correct or requiring no edit | Often 1–5 words |
| `technical_passthrough` | Technical content with protected terms, already correct | All technical tokens verified verbatim |
| `multilingual_passthrough` | Mixed-language content, already correctly formatted | Protected terms verified; `no_translation: true` |

For `technical_passthrough` and `multilingual_passthrough`, the raw text must include sentence-final punctuation (these are already-correct examples from a realistic scenario where Whisper produced good output). Verify with a diff tool that raw == expected byte-for-byte.
