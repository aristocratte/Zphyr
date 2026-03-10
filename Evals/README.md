# Zphyr Evaluation Harness

A rigorous local evaluation harness for the Zphyr dictation pipeline.

## Structure

```
Evals/
├── datasets/           # JSONL test cases
│   ├── schema.json     # Full 13-field dataset schema
│   ├── technical.jsonl # 25 cases — code identifiers, URLs, acronyms
│   ├── commands.jsonl  # 25 cases — commands + false-positive tests
│   ├── prose.jsonl     # 30 cases — workplace, filler, numbers, multilingual
│   ├── short.jsonl     # 20 cases — single words, pure fillers, edge cases
│   ├── lists.jsonl     # 15 cases — ordinal triggers, false positives
│   ├── multilingual.jsonl  # 20 cases — EN/FR/ZH/RU/ES/DE code-switch
│   └── corrections.jsonl   # 10 cases — self-corrections, numeric corrections
│
├── metrics/            # Python metrics engine
│   ├── zphyr_eval.py   # Main CLI (run / compare / lock)
│   ├── hard_metrics.py # Hard correctness checks (binary pass/fail)
│   ├── formatting_scorer.py  # Structure-aware formatting score
│   ├── alerting_metrics.py   # Alerting/warning metrics (non-blocking)
│   ├── report_generator.py   # JSON → diagnostic Markdown report
│   └── requirements.txt      # jiwer, rich, tabulate (no model downloads)
│
├── scripts/
│   ├── run_eval.sh     # Full eval run (Swift + Python)
│   └── compare.sh      # Regression comparison wrapper
│
├── reports/            # Generated per run (gitignored)
├── baselines/
│   └── locked_baseline.json  # Per-category, per-metric baseline
└── README.md
```

## Three Evaluation Layers

| Layer | Evaluates | Status |
|-------|-----------|--------|
| **L1a** | `raw_asr_text` vs `literal_reference` — transcript quality only | v1 (transcript-only, no audio) |
| **L2** | `raw_asr_text` → pipeline → vs `final_expected_text` — formatting quality | **Primary (v1 core)** |
| **L3** | Aggregate L2 results — end-to-end composite | Informational only |

> L1b (audio-backed ASR evaluation) is not implemented in v1.

## Quick Start

### 1. Install Python dependencies

```bash
./Evals/scripts/run_eval.sh --mode trigger --category technical

# Optional manual setup:
python3 -m venv Evals/metrics/.venv
Evals/metrics/.venv/bin/pip install -r Evals/metrics/requirements.txt

# Optional: cosine similarity (requires ~90MB model download)
Evals/metrics/.venv/bin/pip install sentence-transformers numpy
```

### 2. Run the full harness

```bash
# Runs Swift L2 tests, then Python metrics, then comparison
./Evals/scripts/run_eval.sh --mode trigger

# Category-specific run
./Evals/scripts/run_eval.sh --mode trigger --category technical

# Enable semantic scoring
./Evals/scripts/run_eval.sh --semantic
```

### 3. Run Swift tests directly (via Xcode or CLI)

```bash
mkdir -p Evals/reports
printf '{"mode":"trigger","category":"technical"}\n' > Evals/reports/current_eval_config.json
xcodebuild test -scheme Zphyr \
  -only-testing:ZphyrTests/EvalL2Tests/testL2_AllCategories
```

### 4. Run Python metrics on existing output

```bash
python Evals/metrics/zphyr_eval.py run \
  --run Evals/reports/current_run_trigger_technical_L2.json

# With Markdown report
python Evals/metrics/zphyr_eval.py run \
  --run Evals/reports/current_run_trigger_technical_L2.json \
  --md Evals/reports/my_report.md
```

### 5. Compare to baseline

```bash
python Evals/metrics/zphyr_eval.py compare \
  --baseline Evals/baselines/locked_baseline.json \
  --run Evals/reports/metrics_current_run_trigger_technical_L2.json
# Exit: 0 = clean, 1 = warnings, 2 = blocking
```

### 6. Lock baseline after human review

```bash
python Evals/metrics/zphyr_eval.py lock \
  --run Evals/reports/metrics_current_run_trigger_technical_L2.json \
  --confirm-reviewed \
  --review-notes "Initial baseline after first clean run on 2026-03-10"
```

## Hard Metrics (Binary Pass/Fail)

These are **blocking** — a failure here cannot be compensated by any composite score.

| Check | Hard Failure Type | Contexts |
|-------|-------------------|---------|
| Protected term present (exact, case-sensitive) | `protectedTermMissing` | All |
| Protected term case preserved | `protectedTermCaseCorruption` | All |
| URL structurally valid in output | `malformedURL` | All |
| Email structurally valid in output | `malformedEmail` | All |
| No command when none expected | `spuriousCommand` | All (must-never-regress) |
| Correct command type extracted | `commandMismatch` | All (must-never-regress) |
| No content-changing insertion when `rewrite_allowed_level=none` | `forbiddenRewrite` | All |
| Numbers/versions in output match input | `numericCorruption` | technical, correction, command |

## Alerting Metrics (Warnings Only)

These **never block** a run. They surface for investigation.

- Token drop rate >5% (non-filler content words)
- Acronym casing changed (unprotected terms)
- Number/date drift in non-hard-check contexts
- Latency >50% above baseline
- Cosine similarity <0.85 (`--semantic` only, skip for technical/short/command/multilingual)

## Must-Never-Regress Subsets

Hard failures in these subsets get prominently flagged in reports:

- All cases where `context_type = "technical"`
- All cases where `context_type = "command"`
- All cases where `protected_terms` contains a URL or email
- All cases where `protected_terms` contains an all-caps token (acronym)

## Baseline Locking Policy

**Baselines are NEVER updated automatically.**

The `lock` command requires:
1. `--confirm-reviewed` flag — confirms a human reviewed the run
2. `--review-notes` — required string summarizing the review

Previous baselines are automatically backed up with a timestamp.

## Adding New Test Cases

1. Add a JSONL line to the appropriate `datasets/*.jsonl` file
2. Assign a unique ID using the format `{category_prefix}-{NNN}` (e.g. `tech-026`)
3. Fill all required fields per `datasets/schema.json`
4. Run the harness to verify the new case passes hard checks

## Runtime Dimensions

Formatting mode is the real runtime dimension in v1 L2. This harness is transcript-only and does not switch live ASR backends.

| Env Var | Values | Default |
|---------|--------|---------|
| `EVAL_MODE` | `trigger`, `advanced` | `trigger` |
| `EVAL_CATEGORY` | `all`, `prose`, `technical`, `commands`, `lists`, `multilingual`, `corrections`, `short` | `all` |

`EVAL_CATEGORY` uses dataset categories; the harness normalizes these to their runtime context labels (`commands` → `command`, `lists` → `list`, `corrections` → `correction`).

## Informational Composite Score

The harness computes a 0–100 composite score for dashboard display.

> ⚠️ **This score is NOT a release gate and NOT a substitute for hard checks.**
> It is labelled `INFORMATIONAL — not a release gate` in all outputs.

Weights: WER 30% · Entity 20% · Formatting 20% · Alerting 15% · Command 10% · Latency 5%
