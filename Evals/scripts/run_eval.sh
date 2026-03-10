#!/usr/bin/env bash
# run_eval.sh  —  Main evaluation runner for Zphyr
#
# Usage:
#   ./Evals/scripts/run_eval.sh [options]
#
# Options:
#   --mode    trigger|advanced          (default: trigger)
#   --category all|prose|technical|commands|lists|multilingual|corrections|short
#   --semantic                          Enable sentence-transformer scoring (optional)
#   --only-swift                        Only run Swift tests, skip Python metrics
#   --only-python                       Only run Python metrics on existing JSON
#   --help
#
# Example:
#   ./Evals/scripts/run_eval.sh --mode trigger --category technical

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/Evals"
METRICS_DIR="$EVALS_DIR/metrics"
REPORTS_DIR="$EVALS_DIR/reports"
PYTHON_VENV_DIR="$METRICS_DIR/.venv"
PYTHON_BIN="$PYTHON_VENV_DIR/bin/python"
PIP_BIN="$PYTHON_VENV_DIR/bin/pip"
EVAL_CONFIG_FILE="$REPORTS_DIR/current_eval_config.json"

# ── Defaults ─────────────────────────────────────────────────────────────────
MODE="trigger"
CATEGORY="all"
SEMANTIC_FLAG=""
ONLY_SWIFT=false
ONLY_PYTHON=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)      MODE="$2"; shift 2 ;;
    --category)  CATEGORY="$2"; shift 2 ;;
    --semantic)  SEMANTIC_FLAG="--semantic"; shift ;;
    --only-swift)  ONLY_SWIFT=true; shift ;;
    --only-python) ONLY_PYTHON=true; shift ;;
    --help)
      sed -n '/^#/p' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ZPHYR EVALUATION HARNESS                               ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Mode:     $MODE"
echo "║  Category: $CATEGORY"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$REPORTS_DIR"
cat >"$EVAL_CONFIG_FILE" <<EOF
{"mode":"$MODE","category":"$CATEGORY"}
EOF

CATEGORY_SUFFIX=""
if [[ "$CATEGORY" != "all" ]]; then
  CATEGORY_SUFFIX="_$CATEGORY"
fi
RUN_STEM="current_run_${MODE}${CATEGORY_SUFFIX}_L2"
RUN_FILE="$REPORTS_DIR/${RUN_STEM}.json"
METRICS_FILE="$REPORTS_DIR/metrics_${RUN_STEM}.json"
REPORT_FILE="$REPORTS_DIR/report_${RUN_STEM}.md"
SWIFT_LOG="$REPORTS_DIR/xcodebuild_${RUN_STEM}.log"
SWIFT_FAILED=false

# ── Phase 1: Swift XCTest runner (L2 pipeline) ────────────────────────────────
if ! $ONLY_PYTHON; then
  echo "▶  Running Swift eval runner (L2 tests)…"
  echo ""

  XCODE_PROJECT="$REPO_ROOT/Zphyr.xcodeproj"

  if ! EVAL_MODE="$MODE" EVAL_CATEGORY="$CATEGORY" xcodebuild test \
    -project "$XCODE_PROJECT" \
    -scheme Zphyr \
    -destination 'platform=macOS' \
    -only-testing:ZphyrTests/EvalL2Tests/testL2_AllCategories \
    >"$SWIFT_LOG" 2>&1; then
    tail -n 40 "$SWIFT_LOG" || true
    if [[ ! -f "$RUN_FILE" ]]; then
      echo ""
      echo "Swift L2 run failed before producing a run artifact. Full log: $SWIFT_LOG"
      exit 1
    fi
    echo ""
    echo "Swift L2 assertions failed, but the run artifact was produced. Continuing to Python metrics."
    SWIFT_FAILED=true
  fi

  grep -E "(passed|failed|FAIL|error:|EvalL2)" "$SWIFT_LOG" | tail -40 || true

  echo ""
  echo "Swift L2 run complete."
fi

# ── Phase 2: Python metrics engine ────────────────────────────────────────────
if ! $ONLY_SWIFT; then
  if [[ ! -f "$RUN_FILE" ]]; then
    echo "ERROR: Run file not found: $RUN_FILE"
    echo "       Run Swift tests first (omit --only-python)."
    exit 1
  fi

  # Check Python deps
  if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "Creating local Python venv for eval metrics…"
    python3 -m venv "$PYTHON_VENV_DIR"
  fi
  if ! "$PYTHON_BIN" -c "import jiwer, rich, tabulate" 2>/dev/null; then
    echo "Installing core Python dependencies into local venv…"
    "$PIP_BIN" install -q -r "$METRICS_DIR/requirements.txt"
  fi

  echo "▶  Running Python metrics engine…"
  echo ""

  CATEGORY_ARGS=()
  if [[ "$CATEGORY" != "all" ]]; then
    CATEGORY_ARGS+=(--category "$CATEGORY")
  fi

  "$PYTHON_BIN" "$METRICS_DIR/zphyr_eval.py" run \
    --run "$RUN_FILE" \
    "${CATEGORY_ARGS[@]}" \
    $SEMANTIC_FLAG

  echo ""
  echo "▶  Comparing to locked baseline…"
  BASELINE="$EVALS_DIR/baselines/locked_baseline.json"
  if [[ -f "$BASELINE" ]]; then
    "$PYTHON_BIN" "$METRICS_DIR/zphyr_eval.py" compare \
      --baseline "$BASELINE" \
      --run "$METRICS_FILE" || true
  else
    echo "  (No baseline found — skipping comparison. Run 'lock' after review to create one.)"
  fi
fi

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Report: $REPORT_FILE"
echo "══════════════════════════════════════════════════════════"

if $SWIFT_FAILED; then
  exit 1
fi
