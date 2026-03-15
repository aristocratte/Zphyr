# Zphyr Split Baseline Report

- Split: `v2_validated_val`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_smoke_nomodel_v2_validated_val_advanced_L2.json`
- Total examples: `167`
- WER: `0.1869`
- CER: `0.0959`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `65/78` (`83.3%`)
- Hard negative pass rate: `8/16` (`50.0%`)
- Translation violations: `0`
- Rewrite stage ran: `163/167` (`97.6%`)
- Mean latency: `641.0 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.0317 | 0.0072 | 24 |
| corrections | 0.2951 | 0.2240 | 24 |
| lists | 0.3994 | 0.1987 | 21 |
| multilingual | 0.0000 | 0.0000 | 24 |
| prose | 0.2424 | 0.0517 | 20 |
| short | 0.3021 | 0.1760 | 24 |
| technical | 0.0958 | 0.0347 | 30 |

## Sample Failures

- `zphyr-commands-amb-001` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe dans ce document.`
  output:   `Ajoutez le dernier paragraphe dans ce document.`
- `zphyr-commands-amb-013` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion dans le formulaire.`
  output:   `Ajoute la section 'Conclusion' dans le formulaire.`
- `zphyr-commands-amb-025` `commands/ambiguous_command_content`
  expected: `Ajoute la note tout de suite.`
  output:   `Ajoute la note 'tout de suite'`
- `zphyr-commands-nav-015` `commands/navigation_commands`
  expected: `Supprime la section conclusion dans le formulaire.`
  output:   `Supprime la section 'Conclusion' dans le formulaire.`
- `zphyr-corrections-fil-004` `corrections/filler_removal`
  expected: `La réunion commence à dix heures.`
  output:   `La réunion commence à 10 heures.`
- `zphyr-corrections-fil-012` `corrections/filler_removal`
  expected: `La réunion commence à dix heures.`
  output:   `La réunion commence à 10 heures.`
- `zphyr-corrections-fil-017` `corrections/filler_removal`
  expected: `On valide le ticket demain.`
  output:   `Bon, on valide le ticket demain.`
- `zphyr-corrections-fil-020` `corrections/filler_removal`
  expected: `La réunion commence à dix heures.`
  output:   `Le débriefing se déroule à 10h.`
- `zphyr-corrections-fil-025` `corrections/filler_removal`
  expected: `On valide le ticket demain.`
  output:   `Du coup on valide le ticket demain.`
- `zphyr-corrections-irep-002` `corrections/intentional_repetition`
  expected: `Vraiment vraiment on garde cette version.`
  output:   `On garde cette version.`

