# Zphyr Split Baseline Report

- Split: `v2_validated_smoke_test_10`
- Source artifact: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/reports/seed_split_smoke_postft_v2_round3_v2_validated_smoke_test_10_advanced_L2.json`
- Total examples: `10`
- WER: `0.3118`
- CER: `0.1859`

## Core Metrics

- Null edit preservation: `0/0` (`0.0%`)
- Protected term accuracy: `2/3` (`66.7%`)
- Hard negative pass rate: `0/4` (`0.0%`)
- Translation violations: `0`
- Reasoning tag contamination: `0`
- Rewrite stage ran: `10/10` (`100.0%`)
- Mean latency: `228.3 ms`

## Category Breakdown

| Category | WER | CER | Count |
| --- | ---: | ---: | ---: |
| commands | 0.1667 | 0.0222 | 1 |
| corrections | 0.4208 | 0.3838 | 4 |
| lists | 0.7500 | 0.2143 | 1 |
| multilingual | 0.1429 | 0.0294 | 1 |
| prose | 0.2500 | 0.0385 | 1 |
| short | 0.0000 | 0.0000 | 1 |
| technical | 0.1250 | 0.0200 | 1 |

## Sample Failures

- `zphyr-commands-amb-005` `commands/ambiguous_command_content`
  expected: `Ajoute le dernier paragraphe avant d'envoyer.`
  output:   `Ajoute le dernier paragraphe avant d'envoyer`
- `zphyr-corrections-fil-003` `corrections/filler_removal`
  expected: `Il faut redémarrer le service.`
  output:   `il faut redémarrer le service`
- `zphyr-lists-bul-001` `lists/bulleted_spoken`
  expected: `- Frontend
- Backend
- Infra`
  output:   `frontend, backend, infra`
- `zphyr-multilingual-fren-001` `multilingual/fr_primary_en_terms`
  expected: `On garde deploy et build comme ça.`
  output:   `on garde deploy et build comme ça`
- `zphyr-prose-ema-126` `prose/email_body`
  expected: `Bonjour, Madame Leroy je serai disponible demain matin pour en discuter merci.`
  output:   `Bonjour Madame Leroy, je serai disponible demain matin pour en discuter. Merci.`
- `zphyr-technical-cfg-002` `technical/config_env_vars`
  expected: `Il faut vérifier JWT_SECRET dans la sortie finale.`
  output:   `Il faut vérifier jwt_secret dans la sortie finale`
- `zphyr-corrections-irep-001` `corrections/intentional_repetition`
  expected: `Vraiment vraiment c'est important.`
  output:   `c'est important`
- `zphyr-corrections-irep-003` `corrections/intentional_repetition`
  expected: `Vraiment vraiment il faut attendre.`
  output:   `Il faut attendre.`
- `zphyr-corrections-irep-006` `corrections/intentional_repetition`
  expected: `Vraiment vraiment on lance le déploiement.`
  output:   `On lance le déploiement.`

