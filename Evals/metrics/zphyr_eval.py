#!/usr/bin/env python3
"""
zphyr_eval.py  —  Main CLI entry point for the Zphyr evaluation harness.

Usage:
  python zphyr_eval.py run  --run PATH           Compute all metrics from a run JSON
  python zphyr_eval.py compare --baseline B --run R  Compare run to baseline
  python zphyr_eval.py lock   --run PATH --confirm-reviewed --review-notes "..."
                                                  Lock run as new baseline (never automatic)
  python zphyr_eval.py report --run PATH [--md OUTPUT]  Generate Markdown report

Flags:
  --semantic    Enable optional sentence-transformer cosine similarity (needs extra install)
  --category    Filter to a dataset category (prose, technical, commands, etc.)

Example:
  python zphyr_eval.py run \\
    --run ../../Evals/reports/current_run_trigger_technical_L2.json

  python zphyr_eval.py compare \\
    --baseline ../../Evals/baselines/locked_baseline.json \\
    --run ../../Evals/reports/metrics_current_run_trigger_technical_L2.json
"""

from __future__ import annotations
import argparse
import json
import sys
from pathlib import Path
from datetime import datetime, timezone

# ── Dependency check ──────────────────────────────────────────────────────────

def _require(pkg: str, install_hint: str = "") -> bool:
    import importlib
    try:
        importlib.import_module(pkg)
        return True
    except ImportError:
        return False


HAS_JIWER = _require("jiwer")
HAS_RICH  = _require("rich")
HAS_TABULATE = _require("tabulate")
HAS_ST    = False  # sentence-transformers, checked only if --semantic

# ── Local imports ─────────────────────────────────────────────────────────────

sys.path.insert(0, str(Path(__file__).parent))
from hard_metrics import run_all_hard_checks, hard_failure_summary
from formatting_scorer import score_all_formatting, formatting_summary
from alerting_metrics import run_all_alerting, alerting_summary
from report_generator import generate_markdown_report

_CATEGORY_ALIASES = {
    "command": "commands",
    "commands": "commands",
    "list": "lists",
    "lists": "lists",
    "correction": "corrections",
    "corrections": "corrections",
    "technical": "technical",
    "prose": "prose",
    "short": "short",
    "multilingual": "multilingual",
}


def canonical_category(name: str | None) -> str:
    if not name:
        return "unknown"
    return _CATEGORY_ALIASES.get(name.lower(), name.lower())


def record_category(record: dict) -> str:
    return canonical_category(record.get("contextType", "unknown"))


# ── WER / CER (jiwer) ─────────────────────────────────────────────────────────

def compute_wer_cer(records: list[dict], layer: str = "L2") -> dict:
    """
    Compute WER and CER for a given layer.
    L1a: raw_asr_text vs literal_reference
    L2/L3: final_text vs final_expected_text
    """
    if not HAS_JIWER:
        return {"error": "jiwer not installed — run: pip install jiwer"}

    import jiwer
    refs, hyps = [], []
    for r in records:
        if layer == "L1a":
            ref  = r.get("literalReference", "")
            hyp  = r.get("rawAsrText", "")
        else:
            ref  = r.get("finalExpectedText", "")
            hyp  = r.get("finalText", "")
        if ref.strip() and hyp.strip():
            refs.append(ref)
            hyps.append(hyp)

    if not refs:
        return {"wer": None, "cer": None, "note": "No valid pairs"}

    wer = jiwer.wer(refs, hyps)
    cer = jiwer.cer(refs, hyps)
    return {"wer": round(wer, 4), "cer": round(cer, 4), "pair_count": len(refs)}


def compute_wer_per_category(records: list[dict]) -> dict[str, dict]:
    cats: dict[str, list[dict]] = {}
    for r in records:
        c = record_category(r)
        cats.setdefault(c, []).append(r)
    return {cat: compute_wer_cer(recs) for cat, recs in cats.items()}


# ── Composite score (INFORMATIONAL ONLY) ─────────────────────────────────────

def compute_informational_score(
    wer: float,
    entity_rate: float,
    formatting_score: float,
    alert_pass_rate: float,
    command_accuracy: float,
    mean_latency_ms: float,
) -> dict:
    """
    Composite score for dashboards ONLY.
    NOT a release gate. NOT a substitute for hard correctness metrics.
    Always labelled 'informational'.
    """
    latency_score = max(0.0, 1.0 - max(0.0, mean_latency_ms - 500) / 2500)
    score = (
        0.30 * (1.0 - min(wer, 1.0))
      + 0.20 * entity_rate
      + 0.20 * formatting_score
      + 0.15 * alert_pass_rate
      + 0.10 * command_accuracy
      + 0.05 * latency_score
    )
    return {
        "informational_score": round(score * 100, 1),
        "label": "INFORMATIONAL — not a release gate",
        "components": {
            "wer_contribution":       round(0.30 * (1.0 - min(wer, 1.0)) * 100, 1),
            "entity_contribution":    round(0.20 * entity_rate * 100, 1),
            "formatting_contribution": round(0.20 * formatting_score * 100, 1),
            "alert_contribution":     round(0.15 * alert_pass_rate * 100, 1),
            "command_contribution":   round(0.10 * command_accuracy * 100, 1),
            "latency_contribution":   round(0.05 * latency_score * 100, 1),
        },
    }


# ── Command accuracy ──────────────────────────────────────────────────────────

def compute_command_accuracy(records: list[dict]) -> dict:
    total, correct = 0, 0
    confusion: dict[str, dict[str, int]] = {}
    for r in records:
        expected = r.get("expectedCommand")
        actual_raw = r.get("actualCommand", "none")
        actual = None if actual_raw in ("none", "null", "", None) else actual_raw

        exp_key = expected or "none"
        act_key = actual or "none"
        confusion.setdefault(exp_key, {})
        confusion[exp_key][act_key] = confusion[exp_key].get(act_key, 0) + 1

        total += 1
        if expected == actual:
            correct += 1

    return {
        "command_accuracy": round(correct / max(total, 1), 4),
        "correct": correct,
        "total": total,
        "confusion_matrix": confusion,
    }


# ── Latency breakdown ──────────────────────────────────────────────────────────

def compute_latency_breakdown(records: list[dict]) -> dict:
    """Per-stage mean, p50, p95 latency."""
    import statistics
    stage_times: dict[str, list[float]] = {}
    total_times: list[float] = []

    for r in records:
        total_times.append(r.get("totalDurationMs", 0.0))
        for trace in r.get("stageTraces", []):
            name = trace.get("stageName", "unknown")
            stage_times.setdefault(name, []).append(trace.get("durationMs", 0.0))

    def stats(vals: list[float]) -> dict:
        if not vals:
            return {}
        sorted_v = sorted(vals)
        return {
            "mean": round(statistics.mean(sorted_v), 1),
            "p50":  round(sorted_v[int(len(sorted_v) * 0.50)], 1),
            "p95":  round(sorted_v[int(len(sorted_v) * 0.95)], 1),
        }

    return {
        "total": stats(total_times),
        "stages": {name: stats(times) for name, times in stage_times.items()},
    }


def compute_category_summary(
    records: list[dict],
    hard_results,
    formatting_scores,
) -> dict[str, dict]:
    formatting_by_case = {score.case_id: score.score for score in formatting_scores}
    hard_by_case = {result.case_id: result for result in hard_results}

    categories: dict[str, dict] = {}
    grouped_records: dict[str, list[dict]] = {}
    for record in records:
        grouped_records.setdefault(record_category(record), []).append(record)

    for category, category_records in grouped_records.items():
        case_ids = {record.get("caseID") for record in category_records}
        category_hard_results = [
            result for result in hard_results
            if result.case_id in case_ids
        ]
        hard_failures = sum(1 for result in category_hard_results if not result.passed)

        total_term_checks = sum(len(record.get("protectedTerms", [])) for record in category_records)
        failed_term_checks = sum(
            len([failure for failure in result.hard_failures if "protectedTerm" in failure])
            for result in category_hard_results
        )
        entity_rate = 1.0 - (failed_term_checks / max(total_term_checks, 1))

        formatting_values = [
            formatting_by_case[case_id]
            for case_id in case_ids
            if case_id in formatting_by_case
        ]
        formatting_mean = (
            sum(formatting_values) / len(formatting_values)
            if formatting_values else 0.0
        )

        mean_duration_ms = (
            sum(record.get("totalDurationMs", 0.0) for record in category_records) / len(category_records)
            if category_records else 0.0
        )

        command_accuracy = compute_command_accuracy(category_records)["command_accuracy"]
        wer_data = compute_wer_cer(category_records, "L2")

        categories[category] = {
            "L2": {
                "wer": wer_data.get("wer"),
                "cer": wer_data.get("cer"),
                "entity_preservation": round(entity_rate, 4),
                "hard_failures": hard_failures,
                "formatting_score": round(formatting_mean, 4),
                "command_accuracy": round(command_accuracy, 4),
                "mean_duration_ms": round(mean_duration_ms, 1),
            }
        }

    return categories


# ── Main run command ──────────────────────────────────────────────────────────

def cmd_run(args: argparse.Namespace) -> dict:
    run_path = Path(args.run)
    if not run_path.exists():
        print(f"ERROR: Run file not found: {run_path}", file=sys.stderr)
        sys.exit(1)

    with open(run_path) as f:
        records: list[dict] = json.load(f)

    if args.category:
        target_category = canonical_category(args.category)
        records = [r for r in records if record_category(r) == target_category]

    if not records:
        print("No records found (check --category filter).")
        sys.exit(1)

    print(f"Evaluating {len(records)} records from {run_path.name}…")

    # ── Load baseline for alerting ────────────────────────────────────────
    baseline = None
    baseline_path = Path(args.run).parent.parent / "baselines" / "locked_baseline.json"
    if baseline_path.exists():
        with open(baseline_path) as f:
            baseline = json.load(f)

    # ── Semantic model (optional) ─────────────────────────────────────────
    semantic_model = None
    if getattr(args, "semantic", False):
        try:
            from sentence_transformers import SentenceTransformer
            print("Loading MiniLM-L6 (one-time download if not cached)…")
            semantic_model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
        except ImportError:
            print("WARNING: sentence-transformers not installed. Run: pip install sentence-transformers")

    # ── Run all metrics ───────────────────────────────────────────────────
    hard_results     = run_all_hard_checks(records)
    formatting_scores = score_all_formatting(records)
    alerting_results = run_all_alerting(records, baseline, semantic_model)

    hard_sum     = hard_failure_summary(hard_results)
    format_sum   = formatting_summary(formatting_scores)
    alert_sum    = alerting_summary(alerting_results)
    wer_overall  = compute_wer_cer(records, "L2")
    wer_per_cat  = compute_wer_per_category(records)
    cmd_accuracy = compute_command_accuracy(records)
    latency      = compute_latency_breakdown(records)
    categories   = compute_category_summary(records, hard_results, formatting_scores)

    # ── Entity preservation rate ──────────────────────────────────────────
    total_term_checks = sum(len(r.get("protectedTerms", [])) for r in records)
    failed_term_checks = sum(
        len([f for f in res.hard_failures if "protectedTerm" in f])
        for res in hard_results
    )
    entity_rate = 1.0 - (failed_term_checks / max(total_term_checks, 1))

    # ── Alerting pass rate ────────────────────────────────────────────────
    alert_pass_rate = 1.0 - (
        alert_sum["cases_with_warnings"] / max(len(records), 1)
    )

    # ── Informational composite score ─────────────────────────────────────
    mean_lat = latency["total"].get("mean", 999.0) if latency.get("total") else 999.0
    informational = compute_informational_score(
        wer=wer_overall.get("wer") or 0.0,
        entity_rate=entity_rate,
        formatting_score=format_sum.get("mean_formatting_score", 0.0),
        alert_pass_rate=alert_pass_rate,
        command_accuracy=cmd_accuracy["command_accuracy"],
        mean_latency_ms=mean_lat,
    )

    result = {
        "run_date": datetime.now(timezone.utc).isoformat(),
        "run_file": str(run_path),
        "category_filter": getattr(args, "category", None),
        "total_cases": len(records),

        # ── Hard correctness (always first) ───────────────────────────────
        "hard_metrics": hard_sum,
        "entity_preservation_rate": round(entity_rate, 4),
        "command_accuracy": cmd_accuracy,

        # ── Layer-specific WER ────────────────────────────────────────────
        "wer_l2_overall": wer_overall,
        "wer_l2_per_category": wer_per_cat,
        "categories": categories,

        # ── Formatting ────────────────────────────────────────────────────
        "formatting": format_sum,

        # ── Alerting ──────────────────────────────────────────────────────
        "alerting": alert_sum,

        # ── Latency ───────────────────────────────────────────────────────
        "latency": latency,

        # ── Informational composite (NOT a gate) ──────────────────────────
        "composite": informational,
    }

    # ── Print summary ─────────────────────────────────────────────────────
    _print_summary(result)

    # ── Write metrics JSON ────────────────────────────────────────────────
    out_path = run_path.parent / f"metrics_{run_path.stem}.json"
    out_path.write_text(json.dumps(result, indent=2))
    print(f"\nMetrics written to: {out_path}")

    # ── Generate Markdown report ──────────────────────────────────────────
    md_path = getattr(args, "md", None)
    if md_path:
        report_path = Path(md_path)
    else:
        report_path = run_path.parent / f"report_{run_path.stem}.md"

    generate_markdown_report(result, records, hard_results, alerting_results, report_path)
    print(f"Report written to: {report_path}")

    return result


def _print_summary(result: dict) -> None:
    hard = result["hard_metrics"]
    wer  = result["wer_l2_overall"]
    fmt  = result["formatting"]
    cmd  = result["command_accuracy"]
    comp = result["composite"]

    print("\n" + "─" * 62)
    print("  ZPHYR EVAL SUMMARY")
    print("─" * 62)
    print(f"  Cases evaluated:           {result['total_cases']}")
    hard_n = hard['hard_failure_count']
    print(f"  ⛔ Hard failures:           {hard_n}  {'← blocking' if hard_n > 0 else '✓ clean'}")
    if hard.get("failure_types"):
        for k, v in hard["failure_types"].items():
            print(f"      {k}: {v}")
    print(f"  Entity preservation:       {result['entity_preservation_rate']:.1%}")
    print(f"  Command accuracy:          {cmd['command_accuracy']:.1%}")
    print(f"  WER (L2):                  {wer.get('wer', 'n/a')}")
    print(f"  CER (L2):                  {wer.get('cer', 'n/a')}")
    print(f"  Formatting score:          {fmt.get('mean_formatting_score', 0.0):.1%}")
    print(f"  Alerting warnings:         {result['alerting']['total_warnings']}")
    print(f"  ──────────────────────────────────────────────────────")
    print(f"  {comp['label']}")
    print(f"  Informational score:       {comp['informational_score']}/100")
    print("─" * 62)


# ── Compare command ────────────────────────────────────────────────────────────

def cmd_compare(args: argparse.Namespace) -> None:
    baseline_path = Path(args.baseline)
    run_path      = Path(args.run)

    if not baseline_path.exists():
        print(f"ERROR: Baseline not found: {baseline_path}", file=sys.stderr); sys.exit(1)
    if not run_path.exists():
        print(f"ERROR: Run metrics not found: {run_path}", file=sys.stderr); sys.exit(1)

    with open(baseline_path) as f:
        baseline: dict = json.load(f)
    with open(run_path) as f:
        current: dict = json.load(f)

    if not baseline.get("locked_date"):
        print("Baseline is not locked yet; skipping comparison.")
        sys.exit(0)

    print("\n" + "═" * 62)
    print("  REGRESSION COMPARISON")
    print("  Baseline: " + str(baseline_path.name))
    print("  Current:  " + str(run_path.name))
    print("═" * 62)

    blocking = False
    warnings_list = []

    # ── Per-category comparison ───────────────────────────────────────────
    bl_cats  = baseline.get("categories", {})
    cur_cats = current.get("categories", {})

    for cat, bl_data in bl_cats.items():
        bl_l2  = bl_data.get("L2", {})
        cur_l2 = cur_cats.get(cat, {}).get("L2", {})

        # Hard failures: ANY increase is blocking
        bl_fails  = bl_l2.get("hard_failures", 0)
        cur_fails = cur_l2.get("hard_failures", 0)
        bl_wer = bl_l2.get("wer")
        cur_wer = cur_l2.get("wer")
        bl_entity = bl_l2.get("entity_preservation")
        cur_entity = cur_l2.get("entity_preservation")

        if cur_wer is not None and bl_wer is not None:
            wer_delta = cur_wer - bl_wer
            if wer_delta > 0.03:
                warnings_list.append(f"⚠  [{cat}] WER increased {wer_delta:+.3f} (baseline={bl_wer:.3f} → current={cur_wer:.3f})")

        if bl_entity is not None and cur_entity is not None and cur_entity < bl_entity - 0.001:
            if cat in ("technical", "commands"):
                print(f"⛔ BLOCKING [{cat}] Entity preservation dropped: {bl_entity:.3f} → {cur_entity:.3f}")
                blocking = True
            else:
                warnings_list.append(f"⚠  [{cat}] Entity preservation dropped: {bl_entity:.3f} → {cur_entity:.3f}")

        if bl_fails is not None and cur_fails > bl_fails:
            print(f"⛔ BLOCKING [{cat}] Hard failures increased: {bl_fails} → {cur_fails}")
            blocking = True

    # ── Hard failure global check ─────────────────────────────────────────
    cur_total_hard = current.get("hard_metrics", {}).get("hard_failure_count", 0)
    bl_hard_sum    = sum(v.get("L2", {}).get("hard_failures", 0) for v in bl_cats.values())
    if cur_total_hard > bl_hard_sum:
        print(f"⛔ BLOCKING: Hard failure count increased {bl_hard_sum} → {cur_total_hard}")
        blocking = True

    # ── Formatting ────────────────────────────────────────────────────────
    bl_fmt  = baseline.get("formatting_score", 0.0)
    cur_fmt = current.get("formatting", {}).get("mean_formatting_score", 0.0)
    if bl_fmt and cur_fmt < bl_fmt - 0.05:
        warnings_list.append(f"⚠  Formatting score dropped {bl_fmt:.3f} → {cur_fmt:.3f}")

    # ── Print warnings ────────────────────────────────────────────────────
    for w in warnings_list:
        print(w)
    if not blocking and not warnings_list:
        print("✓  No regressions detected.")

    if blocking:
        print("\n⛔ RESULT: BLOCKING regressions detected. Do not accept this run.")
        sys.exit(2)
    elif warnings_list:
        print(f"\n⚠  RESULT: {len(warnings_list)} warning(s). Review before accepting.")
        sys.exit(1)
    else:
        print("\n✓  RESULT: Clean — no regressions.")
        sys.exit(0)


# ── Lock command ──────────────────────────────────────────────────────────────

def cmd_lock(args: argparse.Namespace) -> None:
    """
    Lock a run as a new baseline. REQUIRES explicit --confirm-reviewed and --review-notes.
    Baseline updates are NEVER automatic. This is a deliberate product decision.
    """
    if not getattr(args, "confirm_reviewed", False):
        print("ERROR: Baseline locking requires --confirm-reviewed flag.", file=sys.stderr)
        print("       Baselines must be reviewed by a human before locking.", file=sys.stderr)
        sys.exit(1)
    if not getattr(args, "review_notes", "").strip():
        print("ERROR: --review-notes is required when locking a baseline.", file=sys.stderr)
        sys.exit(1)

    metrics_path = Path(args.run)
    if not metrics_path.exists():
        print(f"ERROR: Metrics file not found: {metrics_path}", file=sys.stderr)
        sys.exit(1)

    with open(metrics_path) as f:
        metrics: dict = json.load(f)

    baseline_dir = metrics_path.parent.parent / "baselines"
    baseline_dir.mkdir(parents=True, exist_ok=True)

    # Write baseline with per-category structure
    baseline = {
        "version": "1.0",
        "locked_date": datetime.now(timezone.utc).isoformat(),
        "review_notes": args.review_notes,
        "source_metrics_file": str(metrics_path),
        "formatting_score": metrics.get("formatting", {}).get("mean_formatting_score"),
        "global_hard_failures": metrics.get("hard_metrics", {}).get("hard_failure_count", 0),
        "categories": metrics.get("categories", {}),
    }

    baseline_path = baseline_dir / "locked_baseline.json"
    backup_path   = baseline_dir / f"baseline_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"

    # Keep previous as backup
    if baseline_path.exists():
        import shutil
        shutil.copy(baseline_path, backup_path)
        print(f"Previous baseline backed up to: {backup_path.name}")

    baseline_path.write_text(json.dumps(baseline, indent=2))
    print(f"✓ Baseline locked: {baseline_path}")
    print(f"  Review notes: {args.review_notes}")


# ── Argument parser ───────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Zphyr evaluation harness — offline metrics engine")
    sub = parser.add_subparsers(dest="command", required=True)

    # run
    p_run = sub.add_parser("run", help="Compute metrics from a run JSON file")
    p_run.add_argument("--run",      required=True, help="Path to EvalRunRecord JSON")
    p_run.add_argument("--category", help="Filter to specific context_type")
    p_run.add_argument("--semantic", action="store_true",
                       help="Enable sentence-transformer cosine similarity (requires extra install)")
    p_run.add_argument("--md",       help="Path for Markdown report output")

    # compare
    p_cmp = sub.add_parser("compare", help="Compare current run to locked baseline")
    p_cmp.add_argument("--baseline", required=True, help="Path to locked_baseline.json")
    p_cmp.add_argument("--run",      required=True, help="Path to current metrics JSON")

    # lock
    p_lock = sub.add_parser("lock", help="Lock current run as new baseline (requires review)")
    p_lock.add_argument("--run",             required=True, help="Path to metrics JSON")
    p_lock.add_argument("--confirm-reviewed", dest="confirm_reviewed", action="store_true",
                        help="REQUIRED: confirms human review was done before locking")
    p_lock.add_argument("--review-notes",    dest="review_notes", default="",
                        help="REQUIRED: notes from the human reviewer")

    args = parser.parse_args()

    if args.command == "run":
        cmd_run(args)
    elif args.command == "compare":
        cmd_compare(args)
    elif args.command == "lock":
        cmd_lock(args)


if __name__ == "__main__":
    main()
