# Round5 Targeted Patch Dataset Summary

## Final Counts by Bucket
- hard_negatives_and_ambiguity: 900
- intentional_repetition_preservation: 700
- protected_terms_verbatim: 600
- spoken_lists_and_structuring: 450
- email_prose_punctuation: 350

## Final Counts by Subcategory
- ambiguous_command_content: 150
- no_list_ambiguous: 150
- navigation_ambiguity: 150
- formatting_scope_ambiguity: 150
- spoken_restart_hard_negative: 150
- anti_overrewrite: 150
- intentional_repetition: 140
- emphasis_repetition: 140
- spoken_emphasis: 140
- contrastive_repetition: 140
- rhetorical_repetition: 140
- config_env_vars: 75
- package_names: 75
- terminal_commands: 75
- framework_names: 75
- product_names: 75
- version_numbers: 75
- filenames_and_paths: 75
- mixed_fr_en_terms: 75
- bulleted_spoken: 75
- numbered_spoken: 75
- inline_enumeration: 75
- no_list_control: 75
- task_sequence: 75
- list_vs_sentence_disambiguation: 75
- email_body: 70
- short_sentence: 50
- filler_removal: 60
- spoken_restart: 60
- comma_and_clause_control: 55
- polite_formulation: 55

## QA Checks Performed
- JSON parsing across all 3000 lines
- Exact 7-key schema validation on every row
- Required key presence and no extra-key validation
- `category="round5_patch"` validation on every row
- Allowed subcategory validation by bucket
- `language="fr"` validation on every row
- Empty `raw` / `expected` / `notes` rejection
- `<think>` / `</think>` contamination scan on `raw` and `expected`
- ID uniqueness validation across the merged dataset
- Exact duplicate `(subcategory, raw, expected)` validation across the merged dataset
- Strict near-duplicate heuristic review via Sub-agent F report
- Exact final count validation (= 3000)

## Duplicate Count Removed
- exact duplicates removed: 0
- near-duplicates removed: 0

## Assumptions Made
- The shard-local ordering and IDs were kept as generated because cross-shard QA found no collisions or count mismatches.
- No rows were removed or regenerated after QA because both exact-duplicate checks and the strict near-duplicate heuristic returned zero risky candidates.
- The sub-agent shards were treated as final content after merged validation confirmed schema compliance and the required bucket totals.
