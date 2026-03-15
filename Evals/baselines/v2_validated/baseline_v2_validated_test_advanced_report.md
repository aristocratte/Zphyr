# Zphyr Split Baseline Report

- Split: `v2_validated_test`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_baseline_v2_validated_test_advanced_L2.json`
- Total examples: `167`
- WER: `0.2330`
- CER: `0.0986`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `78/78` (`100.0%`)
- Hard negative pass rate: `0/14` (`0.0%`)
- Translation violations: `0`
- Rewrite stage ran: `0/167` (`0.0%`)
- Mean latency: `1.1 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.1603 | 0.0279 | 21 |
| corrections | 0.2587 | 0.1266 | 22 |
| lists | 0.4072 | 0.2556 | 21 |
| multilingual | 0.1391 | 0.0263 | 24 |
| prose | 0.1380 | 0.0223 | 25 |
| short | 0.4097 | 0.2444 | 24 |
| technical | 0.1560 | 0.0223 | 30 |

## Sample Failures

- `zphyr-commands-amb-005` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe avant d'envoyer.`
  output:   `Ajoute le dernier paragraphe avant d'envoyer`
- `zphyr-commands-amb-008` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion dans ce document.`
  output:   `Ajoute la section conclusion dans ce document`
- `zphyr-commands-amb-012` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion avant d'envoyer.`
  output:   `Ajoute la section conclusion avant d'envoyer`
- `zphyr-commands-amb-019` `commands/ambiguous_command_content`
  expected: `Ajoute le bloc de code avant d'envoyer.`
  output:   `Ajoute le bloc de code avant d'envoyer`
- `zphyr-commands-amb-024` `commands/ambiguous_command_content`
  expected: `Ajoute la note à la fin.`
  output:   `Ajoute la note à la fin`
- `zphyr-commands-amb-027` `commands/ambiguous_command_content`
  expected: `Ajoute la note dans le formulaire.`
  output:   `Ajoute la note dans le formulaire`
- `zphyr-commands-amb-030` `commands/ambiguous_command_content`
  expected: `Ajoute le fichier dans la page actuelle.`
  output:   `Ajoute le fichier dans la page actuelle`
- `zphyr-commands-amb-033` `commands/ambiguous_command_content`
  expected: `Ajoute le fichier avant d'envoyer.`
  output:   `Ajoute le fichier avant d'envoyer`
- `zphyr-commands-fmt-001` `commands/formatting_commands`
  expected: `Supprime le titre dans ce document.`
  output:   `Supprime le titre dans ce document`
- `zphyr-commands-fmt-003` `commands/formatting_commands`
  expected: `Supprime le titre à la fin.`
  output:   `Supprime le titre à la fin`

