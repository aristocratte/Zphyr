# Zphyr Split Baseline Report

- Split: `v2_validated_smoke_test`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_smoke_postft_v2_validated_smoke_test_advanced_L2.json`
- Total examples: `14`
- WER: `0.2791`
- CER: `0.0648`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `4/6` (`66.7%`)
- Hard negative pass rate: `0/2` (`0.0%`)
- Translation violations: `0`
- Reasoning tag contamination: `0`
- Rewrite stage ran: `14/14` (`100.0%`)
- Mean latency: `327.0 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.1548 | 0.0220 | 2 |
| corrections | 0.1833 | 0.0345 | 2 |
| lists | 0.6250 | 0.2175 | 2 |
| multilingual | 0.1429 | 0.0275 | 2 |
| prose | 0.2019 | 0.0303 | 2 |
| short | 0.5000 | 0.1000 | 2 |
| technical | 0.1458 | 0.0214 | 2 |

## Sample Failures

- `zphyr-commands-amb-005` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe avant d'envoyer.`
  output:   `ajoute le dernier paragraphe avant d'envoyer`
- `zphyr-commands-amb-008` `commands/ambiguous_command_content`
  expected: `Ajoute la section conclusion dans ce document.`
  output:   `Ajoute la section conclusion dans ce document`
- `zphyr-corrections-fil-003` `corrections/filler_removal`
  expected: `Il faut redémarrer le service.`
  output:   `il faut redémarrer le service`
- `zphyr-corrections-fil-006` `corrections/filler_removal`
  expected: `Je note ça dans le document.`
  output:   `Je note ça dans le document`
- `zphyr-lists-bul-001` `lists/bulleted_spoken`
  expected: `- Frontend
- Backend
- Infra`
  output:   `frontend, backend, infra`
- `zphyr-lists-inl-001` `lists/inline_enumeration`
  expected: `À faire : mettre à jour le README, taguer la release, puis prévenir l'équipe.`
  output:   `Mettre à jour le README puis taguer la release puis prévenir l'équipe`
- `zphyr-multilingual-fren-001` `multilingual/fr_primary_en_terms`
  expected: `On garde deploy et build comme ça.`
  output:   `on garde deploy et build comme ça`
- `zphyr-multilingual-fren-004` `multilingual/fr_primary_en_terms`
  expected: `On garde deploy et validation comme ça.`
  output:   `on garde deploy et validation comme ça`
- `zphyr-prose-ema-126` `prose/email_body`
  expected: `Bonjour, Madame Leroy je serai disponible demain matin pour en discuter merci.`
  output:   `Bonjour Madame Leroy, je serai disponible demain matin pour en discuter. Merci.`
- `zphyr-prose-ema-127` `prose/email_body`
  expected: `Bonjour, Madame Leroy je serai disponible demain matin pour en discuter bien cordialement.`
  output:   `Bonjour Madame Leroy, je serai disponible demain matin pour en discuter bien cordialement.`

