# Zphyr Split Baseline Report

- Split: `v2_validated_val`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_baseline_v2_validated_val_advanced_L2.json`
- Total examples: `167`
- WER: `0.2457`
- CER: `0.1072`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `78/78` (`100.0%`)
- Hard negative pass rate: `0/16` (`0.0%`)
- Translation violations: `0`
- Rewrite stage ran: `0/167` (`0.0%`)
- Mean latency: `1.1 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.1627 | 0.0278 | 24 |
| corrections | 0.2939 | 0.1314 | 24 |
| lists | 0.3859 | 0.2387 | 21 |
| multilingual | 0.1384 | 0.0263 | 24 |
| prose | 0.1907 | 0.0415 | 20 |
| short | 0.4271 | 0.2896 | 24 |
| technical | 0.1526 | 0.0221 | 30 |

## Sample Failures

- `zphyr-commands-amb-001` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe dans ce document.`
  output:   `Ajoute le dernier paragraphe dans ce document`
- `zphyr-commands-amb-003` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe à la fin.`
  output:   `Ajoute le dernier paragraphe à la fin`
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
  output:   `Ajoute la note tout de suite`
- `zphyr-commands-amb-028` `commands/ambiguous_command_content`
  expected: `Ajoute la note dans la sidebar.`
  output:   `Ajoute la note dans la sidebar`
- `zphyr-commands-amb-031` `commands/ambiguous_command_content`
  expected: `Ajoute le fichier à la fin.`
  output:   `Ajoute le fichier à la fin`
- `zphyr-commands-fmt-002` `commands/formatting_commands`
  expected: `Supprime le titre dans la page actuelle.`
  output:   `Supprime le titre dans la page actuelle`

