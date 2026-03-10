#!/usr/bin/env python3
"""
report_generator.py  —  Generates diagnostic Markdown reports from eval results.

Report structure (diagnostic-first, not dashboard-first):
  1. Hard Failures         (always first — the most important section)
  2. Alerting Metrics      (warnings, never blocking)
  3. Layer Summaries       (L1a, L2 per-category, L3 composite)
  4. Stage Latency         (mean/p50/p95 vs. baseline)
  5. Protected Term Log    (every term that was corrupted or missing)
  6. Command Accuracy      (confusion matrix)
  7. Regression vs. Baseline
  8. "Must Never Regress" Subsets
  9. Human Review Queue    (top-10 cases to manually inspect)
  10. Informational Score  (clearly labeled as non-gate)
"""

from __future__ import annotations
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


def canonical_category(name: Optional[str]) -> str:
    if not name:
        return "unknown"
    mapping = {
        "command": "commands",
        "commands": "commands",
        "list": "lists",
        "lists": "lists",
        "correction": "corrections",
        "corrections": "corrections",
    }
    lowered = name.lower()
    return mapping.get(lowered, lowered)


def record_category(record: dict) -> str:
    return canonical_category(record.get("contextType"))


def generate_markdown_report(
    metrics: dict,
    records: list[dict],
    hard_results,        # list[HardCheckResult]
    alerting_results,    # list[AlertingResult]
    output_path: Path,
) -> None:
    lines: list[str] = []

    # ── Header ─────────────────────────────────────────────────────────────
    run_date = metrics.get("run_date", datetime.now(timezone.utc).isoformat())[:10]
    mode     = records[0].get("formattingMode", "unknown") if records else "unknown"
    lines += [
        f"# Zphyr Eval Report — {run_date} — `{mode}`",
        "",
        f"> {len(records)} cases evaluated  |  "
        f"Hard failures: **{metrics['hard_metrics']['hard_failure_count']}**  |  "
        f"WER (L2): `{metrics['wer_l2_overall'].get('wer', 'n/a')}`",
        "",
    ]

    # ── 1. Hard Failures ───────────────────────────────────────────────────
    lines += ["## ⛔ Hard Failures", ""]
    hard_failed = [r for r in hard_results if not r.passed]
    if not hard_failed:
        lines += ["> ✅ No hard failures detected in this run.", ""]
    else:
        lines += [
            f"> **{len(hard_failed)} case(s) failed hard correctness checks.**  ",
            "> These must be fixed before any baseline update is considered.",
            "",
            "| Case ID | Category | Failure Type(s) | Detail |",
            "|---------|----------|-----------------|--------|",
        ]
        # Match records by case_id for category
        cat_map = {r["caseID"]: record_category(r) for r in records}
        for res in hard_failed:
            failures = ", ".join(set(res.hard_failures))
            details = "; ".join(f"{k}={v}" for k, v in list(res.details.items())[:2])
            cat = cat_map.get(res.case_id, "?")
            lines.append(f"| `{res.case_id}` | {cat} | `{failures}` | {details[:80]} |")
        lines.append("")

    # ── 2. Alerting Metrics ────────────────────────────────────────────────
    lines += ["## ⚠️ Alerting Metrics", ""]
    alert_sum = metrics.get("alerting", {})
    lines += [
        f"- Total warnings: **{alert_sum.get('total_warnings', 0)}**  ",
        f"- Cases with warnings: {alert_sum.get('cases_with_warnings', 0)}",
        "",
        "> ℹ️ Alerting metrics are warnings only — they never block a run.",
        "",
    ]
    type_counts = alert_sum.get("alert_type_counts", {})
    if type_counts:
        lines += ["| Alert Type | Count |", "|-----------|-------|"]
        for atype, cnt in sorted(type_counts.items(), key=lambda x: -x[1]):
            lines.append(f"| `{atype}` | {cnt} |")
        lines.append("")
    else:
        lines += ["> ✅ No alerting warnings raised.", ""]

    # ── 3. Layer Summaries ─────────────────────────────────────────────────
    lines += ["## 📊 Layer Summaries", ""]

    # L1a
    lines += [
        "### L1a — Raw ASR Quality (transcript-only)",
        "",
        "> ℹ️ L1b (audio-backed) is not implemented in v1.",
        "> L1a compares `raw_asr_text` to `literal_reference` via WER/CER.",
        "> Precise WER uses jiwer; per-category breakdown available with `--category` flag.",
        "",
    ]

    # L2 per-category
    lines += ["### L2 — Post-ASR Formatting Quality (per category)", ""]
    lines += [
        "| Category | Cases | WER | CER | Hard Failures |",
        "|----------|-------|-----|-----|---------------|",
    ]
    categories = metrics.get("categories", {})
    for cat in sorted(categories.keys()):
        l2 = categories.get(cat, {}).get("L2", {})
        wer_v = f"`{l2.get('wer', 'n/a')}`"
        cer_v = f"`{l2.get('cer', 'n/a')}`"
        hard_n = l2.get("hard_failures", 0)
        flag = " ⛔" if hard_n > 0 else ""
        case_count = sum(1 for record in records if record_category(record) == cat)
        lines.append(f"| {cat} | {case_count} | {wer_v} | {cer_v} | {hard_n}{flag} |")
    lines.append("")

    # L3
    comp = metrics.get("composite", {})
    lines += [
        "### L3 — End-to-End",
        "",
        f"| Metric | Value |",
        f"|--------|-------|",
        f"| Entity preservation | `{metrics.get('entity_preservation_rate', 'n/a'):.1%}` |",
        f"| Command accuracy | `{metrics.get('command_accuracy', {}).get('command_accuracy', 'n/a'):.1%}` |",
        f"| Formatting score | `{metrics.get('formatting', {}).get('mean_formatting_score', 0):.1%}` |",
        "",
    ]

    # ── 4. Stage Latency ───────────────────────────────────────────────────
    lines += ["## ⏱ Stage Latency Breakdown", ""]
    latency = metrics.get("latency", {})
    total_lat = latency.get("total", {})
    if total_lat:
        lines += [
            f"**Total**: mean={total_lat.get('mean', 0):.1f}ms  "
            f"p50={total_lat.get('p50', 0):.1f}ms  "
            f"p95={total_lat.get('p95', 0):.1f}ms",
            "",
            "| Stage | Mean (ms) | p50 (ms) | p95 (ms) |",
            "|-------|-----------|----------|----------|",
        ]
        for stage, st in latency.get("stages", {}).items():
            lines.append(
                f"| {stage} | {st.get('mean', 0):.1f} | {st.get('p50', 0):.1f} | {st.get('p95', 0):.1f} |"
            )
        lines.append("")
    else:
        lines += ["> No latency data available.", ""]

    # ── 5. Protected Term Damage Log ───────────────────────────────────────
    lines += ["## 🔒 Protected Term Damage Log", ""]
    term_failures = [r for r in hard_results if any("protectedTerm" in f for f in r.hard_failures)]
    if not term_failures:
        lines += ["> ✅ All protected terms preserved in this run.", ""]
    else:
        lines += [
            f"> **{len(term_failures)} case(s)** had protected term failures.",
            "",
            "| Case ID | Failure | Detail |",
            "|---------|---------|--------|",
        ]
        for res in term_failures:
            pt_fails = [f for f in res.hard_failures if "protectedTerm" in f]
            detail = res.details.get("protected_terms", "")
            lines.append(f"| `{res.case_id}` | `{', '.join(pt_fails)}` | {detail[:80]} |")
        lines.append("")

    # ── 6. Command Accuracy ────────────────────────────────────────────────
    lines += ["## 🎙 Command Accuracy", ""]
    cmd = metrics.get("command_accuracy", {})
    lines += [
        f"**Accuracy: {cmd.get('command_accuracy', 0):.1%}** "
        f"({cmd.get('correct', 0)}/{cmd.get('total', 0)} correct)",
        "",
        "**Confusion matrix** (row=expected, col=actual):",
        "",
    ]
    confusion = cmd.get("confusion_matrix", {})
    all_vals = sorted({v for row in confusion.values() for v in row} | set(confusion.keys()))
    if confusion:
        header = "| Expected \\ Actual | " + " | ".join(all_vals) + " |"
        sep    = "|" + "---|" * (len(all_vals) + 1)
        lines += [header, sep]
        for exp in sorted(confusion.keys()):
            row_vals = [str(confusion[exp].get(a, 0)) for a in all_vals]
            lines.append(f"| `{exp}` | " + " | ".join(row_vals) + " |")
        lines.append("")

    # ── 7. "Must Never Regress" Subsets ────────────────────────────────────
    lines += ["## 🚨 \"Must Never Regress\" Subsets", ""]
    mnr_cats = {"technical", "commands"}
    mnr_records = [r for r in records if record_category(r) in mnr_cats]
    mnr_fails = [
        res for res in hard_results
        if not res.passed and any(record.get("caseID") == res.case_id and record_category(record) in mnr_cats for record in records)
    ]
    lines += [
        f"Tracking {len(mnr_records)} cases in sensitive subsets (`technical`, `commands`).",
        "",
        f"Hard failures in these subsets: **{len(mnr_fails)}**",
        "",
    ]
    if mnr_fails:
        lines += ["> ⛔ Failures in must-never-regress subsets require immediate review.", ""]
    else:
        lines += ["> ✅ All must-never-regress cases passed.", ""]

    # ── 8. Human Review Queue ──────────────────────────────────────────────
    lines += ["## 👁 Human Review Queue (Top 10)", ""]
    lines += [
        "Ranked by: hard failure → alerting warnings → WER → correction burden.",
        "",
        "| Rank | Case ID | Category | Issue |",
        "|------|---------|----------|-------|",
    ]
    hard_case_ids = {r.case_id for r in hard_results if not r.passed}
    warn_case_ids = {r.case_id for r in alerting_results if r.has_warnings}

    queue = []
    for r in records:
        cid = r.get("caseID", "")
        score = 0
        issue = []
        if cid in hard_case_ids: score += 100; issue.append("hard_failure")
        if cid in warn_case_ids: score += 10;  issue.append("alert")
        queue.append((score, cid, r.get("contextType", "?"), ", ".join(issue) or "review"))

    queue.sort(key=lambda x: -x[0])
    for i, (sc, cid, cat, iss) in enumerate(queue[:10], 1):
        lines.append(f"| {i} | `{cid}` | {cat} | {iss} |")
    lines.append("")

    # ── 9. Informational Score ─────────────────────────────────────────────
    lines += [
        "## 📈 Informational Score",
        "",
        "> **This score is for dashboards only. It is NOT a release gate.**  ",
        "> Hard failures override it. Never use this score to approve a change.",
        "",
        f"**Score: {comp.get('informational_score', 0)}/100**",
        "",
        "| Component | Contribution |",
        "|-----------|-------------|",
    ]
    for k, v in comp.get("components", {}).items():
        lines.append(f"| {k.replace('_', ' ').title()} | {v}/100 |")
    lines.append("")

    # ── Write ──────────────────────────────────────────────────────────────
    output_path.write_text("\n".join(lines), encoding="utf-8")
