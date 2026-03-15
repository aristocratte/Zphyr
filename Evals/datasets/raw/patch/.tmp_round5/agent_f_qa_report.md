# Round5 QA Report

## Summary
- Total rows: 3000
- Expected total rows: 3000
- QA pass: yes

## Per-shard Counts
- agent_a_hard_negatives_and_ambiguity: 900
- agent_b_intentional_repetition_preservation: 700
- agent_c_protected_terms_verbatim: 600
- agent_d_spoken_lists_and_structuring: 450
- agent_e_email_prose_punctuation: 350

## Counts by Subcategory
- ambiguous_command_content: 150
- anti_overrewrite: 150
- bulleted_spoken: 75
- comma_and_clause_control: 55
- config_env_vars: 75
- contrastive_repetition: 140
- email_body: 70
- emphasis_repetition: 140
- filenames_and_paths: 75
- filler_removal: 60
- formatting_scope_ambiguity: 150
- framework_names: 75
- inline_enumeration: 75
- intentional_repetition: 140
- list_vs_sentence_disambiguation: 75
- mixed_fr_en_terms: 75
- navigation_ambiguity: 150
- no_list_ambiguous: 150
- no_list_control: 75
- numbered_spoken: 75
- package_names: 75
- polite_formulation: 55
- product_names: 75
- rhetorical_repetition: 140
- short_sentence: 50
- spoken_emphasis: 140
- spoken_restart: 60
- spoken_restart_hard_negative: 150
- task_sequence: 75
- terminal_commands: 75
- version_numbers: 75

## QA Checks
- JSON parse errors: 0
- Schema mismatches: 0
- Missing or extra key issues: 0
- Non-fr language rows: 0
- `<think>` contamination rows: 0
- Empty raw/expected/notes rows: 0
- Duplicate IDs: 0
- Exact duplicate `(subcategory, raw, expected)` rows: 0
- Near-duplicate candidates (strict heuristic): 0
- Exact final count check (=3000): pass

## Exact Duplicate Detection
- No exact duplicate rows detected.

## Near-Duplicate Review
- No risky near-duplicate pairs were flagged by the strict heuristic (same subcategory, shared opening tokens, raw/expected similarity >= 0.975, token diff <= 5).

## Issues To Fix
- None.
