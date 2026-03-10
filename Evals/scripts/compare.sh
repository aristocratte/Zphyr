#!/usr/bin/env bash
# compare.sh  —  Compare two evaluation runs per-category and per-metric.
#
# Usage:
#   ./Evals/scripts/compare.sh BASELINE_JSON CURRENT_METRICS_JSON
#
# Both arguments should be metrics JSON files produced by:
#   python Evals/metrics/zphyr_eval.py run --run ...
#
# Exit codes:
#   0  — clean (no regressions)
#   1  — warnings (regressions present but not blocking)
#   2  — blocking (hard failure count increased or entity preservation dropped)
#
# Example:
#   ./Evals/scripts/compare.sh \
#     Evals/baselines/locked_baseline.json \
#     Evals/reports/metrics_current_run_trigger_technical_L2.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="$(cd "$SCRIPT_DIR/../metrics" && pwd)"

BASELINE="${1:-}"
CURRENT="${2:-}"

if [[ -z "$BASELINE" || -z "$CURRENT" ]]; then
  echo "Usage: compare.sh <baseline.json> <current_metrics.json>"
  exit 1
fi

python3 "$METRICS_DIR/zphyr_eval.py" compare \
  --baseline "$BASELINE" \
  --run      "$CURRENT"
