# Zphyr v2 Validated Split Report

- Dataset subset: `zphyr_v2_validated_ft`
- Seed: `42`
- Ratios: train `0.70` / val `0.15` / test `0.15`
- Near-duplicate grouping: Jaccard `0.7` on `3`-grams

## Source

- Included files: technical.jsonl, multilingual.jsonl, commands.jsonl, corrections.jsonl, short.jsonl, prose.jsonl, lists.jsonl
- Excluded files: null_edits.jsonl
- Frozen merged file: `/Users/aris/Documents/VoiceProject/Zphyr/Evals/datasets/frozen/v2/zphyr_v2_validated_ft.jsonl`
- Frozen row count: `1115`

## Split Sizes

| Split | Rows |
| --- | ---: |
| train | 781 |
| val | 167 |
| test | 167 |

## Verification

- Total rows preserved: `True`
- Group leakage clean: `True`
- Duplicate IDs across splits: `0`

## Category Counts

| Category | Train | Val | Test | Total |
| --- | ---: | ---: | ---: | ---: |
| commands | 105 | 24 | 21 | 150 |
| corrections | 109 | 24 | 22 | 155 |
| lists | 98 | 21 | 21 | 140 |
| multilingual | 112 | 24 | 24 | 160 |
| prose | 105 | 20 | 25 | 150 |
| short | 112 | 24 | 24 | 160 |
| technical | 140 | 30 | 30 | 200 |

## Near-Duplicate Groups

- Non-singleton groups: `36`
- Pair edges over threshold: `296`

- `ndg-001` -> `train` (10 rows): zphyr-prose-ema-001, zphyr-prose-ema-002, zphyr-prose-ema-003, zphyr-prose-ema-004, zphyr-prose-ema-005, zphyr-prose-ema-041, zphyr-prose-ema-042, zphyr-prose-ema-043, zphyr-prose-ema-044, zphyr-prose-ema-045
- `ndg-002` -> `train` (10 rows): zphyr-prose-ema-011, zphyr-prose-ema-012, zphyr-prose-ema-013, zphyr-prose-ema-014, zphyr-prose-ema-015, zphyr-prose-ema-051, zphyr-prose-ema-052, zphyr-prose-ema-053, zphyr-prose-ema-054, zphyr-prose-ema-055
- `ndg-003` -> `train` (10 rows): zphyr-prose-ema-016, zphyr-prose-ema-017, zphyr-prose-ema-018, zphyr-prose-ema-019, zphyr-prose-ema-020, zphyr-prose-ema-056, zphyr-prose-ema-057, zphyr-prose-ema-058, zphyr-prose-ema-059, zphyr-prose-ema-060
- `ndg-004` -> `train` (10 rows): zphyr-prose-ema-021, zphyr-prose-ema-022, zphyr-prose-ema-023, zphyr-prose-ema-024, zphyr-prose-ema-025, zphyr-prose-ema-061, zphyr-prose-ema-062, zphyr-prose-ema-063, zphyr-prose-ema-064, zphyr-prose-ema-065
- `ndg-005` -> `train` (6 rows): zphyr-corrections-fil-007, zphyr-corrections-fil-015, zphyr-corrections-fil-023, zphyr-corrections-fil-039, zphyr-corrections-fil-047, zphyr-corrections-fil-055
- `ndg-006` -> `train` (6 rows): zphyr-corrections-fil-008, zphyr-corrections-fil-016, zphyr-corrections-fil-024, zphyr-corrections-fil-040, zphyr-corrections-fil-048, zphyr-corrections-fil-056
- `ndg-007` -> `train` (5 rows): zphyr-prose-ema-006, zphyr-prose-ema-007, zphyr-prose-ema-008, zphyr-prose-ema-009, zphyr-prose-ema-010
- `ndg-008` -> `train` (5 rows): zphyr-prose-ema-026, zphyr-prose-ema-027, zphyr-prose-ema-028, zphyr-prose-ema-029, zphyr-prose-ema-030
- `ndg-009` -> `train` (5 rows): zphyr-prose-ema-031, zphyr-prose-ema-032, zphyr-prose-ema-033, zphyr-prose-ema-034, zphyr-prose-ema-035
- `ndg-010` -> `train` (5 rows): zphyr-prose-ema-036, zphyr-prose-ema-037, zphyr-prose-ema-038, zphyr-prose-ema-039, zphyr-prose-ema-040
- `ndg-011` -> `train` (5 rows): zphyr-prose-ema-046, zphyr-prose-ema-047, zphyr-prose-ema-048, zphyr-prose-ema-049, zphyr-prose-ema-050
- `ndg-012` -> `train` (5 rows): zphyr-prose-ema-066, zphyr-prose-ema-067, zphyr-prose-ema-068, zphyr-prose-ema-069, zphyr-prose-ema-070
- `ndg-013` -> `train` (5 rows): zphyr-prose-ema-071, zphyr-prose-ema-072, zphyr-prose-ema-073, zphyr-prose-ema-074, zphyr-prose-ema-075
- `ndg-014` -> `train` (5 rows): zphyr-prose-ema-076, zphyr-prose-ema-077, zphyr-prose-ema-078, zphyr-prose-ema-079, zphyr-prose-ema-080
- `ndg-015` -> `train` (5 rows): zphyr-prose-ema-081, zphyr-prose-ema-082, zphyr-prose-ema-083, zphyr-prose-ema-084, zphyr-prose-ema-085
- `ndg-016` -> `train` (5 rows): zphyr-prose-ema-086, zphyr-prose-ema-087, zphyr-prose-ema-088, zphyr-prose-ema-089, zphyr-prose-ema-090
- `ndg-017` -> `train` (5 rows): zphyr-prose-ema-091, zphyr-prose-ema-092, zphyr-prose-ema-093, zphyr-prose-ema-094, zphyr-prose-ema-095
- `ndg-018` -> `train` (5 rows): zphyr-prose-ema-096, zphyr-prose-ema-097, zphyr-prose-ema-098, zphyr-prose-ema-099, zphyr-prose-ema-100
- `ndg-019` -> `train` (5 rows): zphyr-prose-ema-101, zphyr-prose-ema-102, zphyr-prose-ema-103, zphyr-prose-ema-104, zphyr-prose-ema-105
- `ndg-020` -> `val` (5 rows): zphyr-prose-ema-106, zphyr-prose-ema-107, zphyr-prose-ema-108, zphyr-prose-ema-109, zphyr-prose-ema-110
- ... `16` additional groups omitted in Markdown; see JSON manifest.

