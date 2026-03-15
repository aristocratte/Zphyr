# Zphyr Split Baseline Report

- Split: `v2_validated_val`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_postft_v2_round5_v2_validated_val_advanced_L2.json`
- Total examples: `167`
- WER: `0.2602`
- CER: `0.1024`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `59/78` (`75.6%`)
- Hard negative pass rate: `1/16` (`6.2%`)
- Translation violations: `0`
- Reasoning tag contamination: `0`
- Rewrite stage ran: `167/167` (`100.0%`)
- Mean latency: `239.3 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.1687 | 0.0288 | 24 |
| corrections | 0.2787 | 0.1336 | 24 |
| lists | 0.4286 | 0.2879 | 21 |
| multilingual | 0.1384 | 0.0263 | 24 |
| prose | 0.2809 | 0.0692 | 20 |
| short | 0.3576 | 0.1548 | 24 |
| technical | 0.2062 | 0.0476 | 30 |

## Sample Failures

- `zphyr-commands-amb-001` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe dans ce document.`
  output:   `ajoute le dernier paragraphe dans ce document`
- `zphyr-commands-amb-003` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe à la fin.`
  output:   `ajoute le dernier paragraphe à la fin`
- `zphyr-commands-amb-006` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe dans le formulaire.`
  output:   `Ajoute le dernier paragraphe dans le formulaire`
- `zphyr-commands-amb-010` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion à la fin.`
  output:   `Ajoute la section conclusion à la fin`
- `zphyr-commands-amb-013` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion dans le formulaire.`
  output:   `Ajoute la section conclusion dans le formulaire`
- `zphyr-commands-amb-022` `commands/ambiguous_command_content`
  expected: `Ajoute la note dans ce document.`
  output:   `Ajoute la note dans ce document`
- `zphyr-commands-amb-025` `commands/ambiguous_command_content`
  expected: `Ajoute la note tout de suite.`
  output:   `ajoute la note tout de suite`
- `zphyr-commands-amb-028` `commands/ambiguous_command_content`
  expected: `Ajoute la note dans la sidebar.`
  output:   `Ajoute la note dans la sidebar`
- `zphyr-commands-amb-031` `commands/ambiguous_command_content`
  expected: `Ajoute le fichier à la fin.`
  output:   `ajoute le fichier à la fin`
- `zphyr-commands-fmt-002` `commands/formatting_commands`
  expected: `Supprime le titre dans la page actuelle.`
  output:   `Supprime le titre dans la page actuelle`

