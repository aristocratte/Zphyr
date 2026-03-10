#!/usr/bin/env bash
# Run the split-based Swift evaluation harness on an arbitrary split file, then
# aggregate the results into normalized JSONL / metrics / Markdown artifacts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALS_DIR="$REPO_ROOT/Evals"
BASELINES_DIR="$EVALS_DIR/baselines"
REPORTS_DIR="$EVALS_DIR/reports"

MODE="advanced"
LABEL="baseline"
SPLIT_FILE=""
SPLIT_NAME=""
MODEL_PATH=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --split-file) SPLIT_FILE="$2"; shift 2 ;;
    --split-name) SPLIT_NAME="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --model-path) MODEL_PATH="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --help)
      cat <<'EOF'
Usage:
  ./Evals/scripts/run_split_baseline.sh \
    --split-file /abs/path/to/test.jsonl \
    --split-name v2_validated_test \
    [--mode advanced] \
    [--label baseline] \
    [--model-path /abs/path/to/fused/model] \
    [--output-dir /abs/path/to/output]

Notes:
  - `--model-path` is optional. When set, it is forwarded to
    `ZPHYR_FORMATTER_MODEL_PATH` so XCTest uses that model directory instead of
    the default local cache.
  - Artifacts are written to:
      * Evals/reports/<swift run json>
      * Evals/baselines/<output dir>/<normalized outputs, metrics, report>
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SPLIT_FILE" ]]; then
  echo "ERROR: --split-file is required." >&2
  exit 1
fi

if [[ -z "$SPLIT_NAME" ]]; then
  SPLIT_NAME="$(basename "$SPLIT_FILE" .jsonl)"
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$BASELINES_DIR/v2_validated"
fi

mkdir -p "$OUTPUT_DIR" "$REPORTS_DIR"

if [[ ! -f "$SPLIT_FILE" ]]; then
  echo "ERROR: Split file not found: $SPLIT_FILE" >&2
  exit 1
fi

if [[ -n "$MODEL_PATH" ]]; then
  if [[ ! -d "$MODEL_PATH" ]]; then
    echo "ERROR: Model path is not a directory: $MODEL_PATH" >&2
    exit 1
  fi
  for required in config.json tokenizer.json tokenizer_config.json; do
    if [[ ! -f "$MODEL_PATH/$required" ]]; then
      echo "ERROR: Model path is missing $required: $MODEL_PATH" >&2
      exit 1
    fi
  done
  if ! find "$MODEL_PATH" -maxdepth 1 -type f -name '*.safetensors' | grep -q .; then
    echo "ERROR: Model path has no .safetensors weights: $MODEL_PATH" >&2
    exit 1
  fi
fi

SANITIZED_LABEL="$(printf '%s' "$LABEL" | tr -cs 'A-Za-z0-9._-' '_')"
SANITIZED_SPLIT="$(printf '%s' "$SPLIT_NAME" | tr -cs 'A-Za-z0-9._-' '_')"
RUN_FILE="$REPORTS_DIR/seed_split_${SANITIZED_LABEL}_${SANITIZED_SPLIT}_${MODE}_L2.json"
RUN_BASENAME="$(basename "$RUN_FILE")"
XCODE_LOG="$OUTPUT_DIR/${SANITIZED_LABEL}_${SANITIZED_SPLIT}_${MODE}_xcodebuild.log"
OUTPUT_JSONL="$OUTPUT_DIR/${SANITIZED_LABEL}_${SANITIZED_SPLIT}_${MODE}_outputs.jsonl"
METRICS_JSON="$OUTPUT_DIR/${SANITIZED_LABEL}_${SANITIZED_SPLIT}_${MODE}_metrics.json"
REPORT_MD="$OUTPUT_DIR/${SANITIZED_LABEL}_${SANITIZED_SPLIT}_${MODE}_report.md"
CONFIG_JSON="$REPORTS_DIR/current_seed_split_config.json"

echo "Running split baseline:"
echo "  split:  $SPLIT_FILE"
echo "  name:   $SPLIT_NAME"
echo "  mode:   $MODE"
echo "  label:  $LABEL"
if [[ -n "$MODEL_PATH" ]]; then
  echo "  model:  $MODEL_PATH"
fi
echo "  config: $CONFIG_JSON"
echo ""

python3 - "$CONFIG_JSON" "$MODE" "$SPLIT_FILE" "$SANITIZED_SPLIT" "$RUN_BASENAME" "$MODEL_PATH" <<'PY'
import json
import sys

payload = {
    "mode": sys.argv[2],
    "split_path": sys.argv[3],
    "split_name": sys.argv[4],
    "output_file": sys.argv[5],
    "model_path": sys.argv[6],
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
    handle.write("\n")
PY

rm -f "$RUN_FILE"

if ! xcodebuild test \
  -project "$REPO_ROOT/Zphyr.xcodeproj" \
  -scheme Zphyr \
  -destination 'platform=macOS' \
  -only-testing:ZphyrTests/EvalSeedSplitTests/testSeedSplitEvaluation \
  >"$XCODE_LOG" 2>&1; then
  tail -n 40 "$XCODE_LOG" || true
  if [[ ! -f "$RUN_FILE" ]]; then
    echo ""
    echo "Swift split evaluation failed before producing $RUN_FILE" >&2
    echo "Full log: $XCODE_LOG" >&2
    exit 1
  fi
  echo ""
  echo "Swift split evaluation reported a failure, but the run artifact exists. Aggregating anyway."
fi

if [[ ! -f "$RUN_FILE" ]]; then
  echo "ERROR: Expected run artifact missing after XCTest: $RUN_FILE" >&2
  echo "Full log: $XCODE_LOG" >&2
  exit 1
fi

python3 "$SCRIPT_DIR/evaluate_baseline.py" \
  --run-file "$RUN_FILE" \
  --split-name "$SPLIT_NAME" \
  --output-file "$OUTPUT_JSONL" \
  --metrics-file "$METRICS_JSON" \
  --report-file "$REPORT_MD"

echo ""
echo "Artifacts:"
echo "  Swift run:  $RUN_FILE"
echo "  Outputs:    $OUTPUT_JSONL"
echo "  Metrics:    $METRICS_JSON"
echo "  Report:     $REPORT_MD"
echo "  Xcode log:  $XCODE_LOG"
