# Zphyr Split Baseline Report

- Split: `v2_validated_val`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_postft_v2_round1_v2_validated_val_advanced_L2.json`
- Total examples: `167`
- WER: `0.2527`
- CER: `0.0993`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `59/78` (`75.6%`)
- Hard negative pass rate: `2/16` (`12.5%`)
- Translation violations: `0`
- Reasoning tag contamination: `0`
- Rewrite stage ran: `166/167` (`99.4%`)
- Mean latency: `334.6 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.1627 | 0.0279 | 24 |
| corrections | 0.2718 | 0.1324 | 24 |
| lists | 0.4330 | 0.2894 | 21 |
| multilingual | 0.1384 | 0.0263 | 24 |
| prose | 0.2809 | 0.0692 | 20 |
| short | 0.3472 | 0.1496 | 24 |
| technical | 0.1805 | 0.0353 | 30 |

## Sample Failures

- `zphyr-commands-amb-001` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe dans ce document.`
  output:   `ajoute le dernier paragraphe dans ce document`
- `zphyr-commands-amb-003` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe à la fin.`
  output:   `ajoute le dernier paragraphe à la fin`
- `zphyr-commands-amb-010` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion à la fin.`
  output:   `Ajoute la section conclusion à la fin`
- `zphyr-commands-amb-013` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion dans le formulaire.`
  output:   `Ajoute la section conclusion dans le formulaire`
- `zphyr-commands-amb-022` `commands/ambiguous_command_content`
  expected: `Ajoute la note dans ce document.`
  output:   `ajoute la note dans ce document`
- `zphyr-commands-amb-025` `commands/ambiguous_command_content`
  expected: `Ajoute la note tout de suite.`
  output:   `ajoute la note tout de suite`
- `zphyr-commands-amb-028` `commands/ambiguous_command_content`
  expected: `Ajoute la note dans la sidebar.`
  output:   `ajoute la note dans la sidebar`
- `zphyr-commands-amb-031` `commands/ambiguous_command_content`
  expected: `Ajoute le fichier à la fin.`
  output:   `ajoute le fichier à la fin`
- `zphyr-commands-fmt-002` `commands/formatting_commands`
  expected: `Supprime le titre dans la page actuelle.`
  output:   `supprime le titre dans la page actuelle`
- `zphyr-commands-fmt-004` `commands/formatting_commands`
  expected: `Supprime le titre en haut.`
  output:   `supprime le titre en haut`

