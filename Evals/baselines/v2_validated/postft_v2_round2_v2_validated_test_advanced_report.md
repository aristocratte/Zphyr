# Zphyr Split Baseline Report

- Split: `v2_validated_test`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_postft_v2_round2_v2_validated_test_advanced_L2.json`
- Total examples: `167`
- WER: `0.2575`
- CER: `0.1104`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `59/78` (`75.6%`)
- Hard negative pass rate: `3/14` (`21.4%`)
- Translation violations: `0`
- Reasoning tag contamination: `0`
- Rewrite stage ran: `167/167` (`100.0%`)
- Mean latency: `279.8 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.2011 | 0.0635 | 21 |
| corrections | 0.2864 | 0.1462 | 22 |
| lists | 0.4556 | 0.3179 | 21 |
| multilingual | 0.1391 | 0.0263 | 24 |
| prose | 0.1905 | 0.0320 | 25 |
| short | 0.3229 | 0.1578 | 24 |
| technical | 0.2355 | 0.0663 | 30 |

## Sample Failures

- `zphyr-commands-amb-005` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe avant d'envoyer.`
  output:   `Ajoute le dernier paragraphe avant d'envoyer`
- `zphyr-commands-amb-019` `commands/ambiguous_command_content`
  expected: `Ajoute le bloc de code avant d'envoyer.`
  output:   `const result = await fetch api url .`
- `zphyr-commands-amb-024` `commands/ambiguous_command_content`
  expected: `Ajoute la note à la fin.`
  output:   `Ajoute la note à la fin`
- `zphyr-commands-amb-027` `commands/ambiguous_command_content`
  expected: `Ajoute la note dans le formulaire.`
  output:   `Ajoute la note dans le formulaire`
- `zphyr-commands-amb-030` `commands/ambiguous_command_content`
  expected: `Ajoute le fichier dans la page actuelle.`
  output:   `ajoute le fichier dans la page actuelle`
- `zphyr-commands-amb-033` `commands/ambiguous_command_content`
  expected: `Ajoute le fichier avant d'envoyer.`
  output:   `ajoute le fichier avant d'envoyer`
- `zphyr-commands-fmt-001` `commands/formatting_commands`
  expected: `Supprime le titre dans ce document.`
  output:   `supprime le titre dans ce document`
- `zphyr-commands-fmt-003` `commands/formatting_commands`
  expected: `Supprime le titre à la fin.`
  output:   `supprime le titre à la fin`
- `zphyr-commands-fmt-005` `commands/formatting_commands`
  expected: `Supprime le titre tout de suite.`
  output:   `supprime le titre tout de suite`
- `zphyr-commands-fmt-007` `commands/formatting_commands`
  expected: `Supprime le titre dans le formulaire.`
  output:   `supprime le titre dans le formulaire`

