#!/usr/bin/env python3
"""
alerting_metrics.py  —  Alerting (non-blocking) metrics for the Zphyr eval harness.

These metrics raise WARNINGS, not failures.
They inform investigation but NEVER act as release gates.

Core alerts (always run, no model downloads):
  - Rule-based semantic drift: token drop, acronym shape change
  - Number/date/version drift (outside hard-check contexts)
  - Latency trend (per-stage vs. baseline)

Optional (requires --semantic flag and sentence-transformers install):
  - Cosine similarity via MiniLM-L6

WARNING: Cosine similarity is UNRELIABLE for:
  - Short utterances (<5 words)
  - Technical identifiers and acronyms
  - Commands
  - Multilingual / code-switch text
It is supplementary to rule-based alerts only.
"""

from __future__ import annotations
import re
from dataclasses import dataclass, field
from typing import Optional


# ── Result types ──────────────────────────────────────────────────────────────

@dataclass
class AlertEntry:
    case_id: str
    alert_type: str      # e.g. "token_drop", "acronym_shape", "latency_spike"
    severity: str        # "WARNING" | "INFO"
    detail: str          # human-readable detail


@dataclass
class AlertingResult:
    case_id: str
    alerts: list[AlertEntry] = field(default_factory=list)

    @property
    def has_warnings(self) -> bool:
        return any(a.severity == "WARNING" for a in self.alerts)


# ── Token drop rate ───────────────────────────────────────────────────────────

_FILLER_TOKENS = frozenset({
    "uh", "um", "er", "ah", "euh", "voilà", "alors", "bah",
    "like", "so", "basically", "you", "know",
})


def _content_tokens(text: str) -> list[str]:
    """Lowercase alphanum tokens, excluding fillers."""
    tokens = re.findall(r'[a-z0-9]+', text.lower())
    return [t for t in tokens if t not in _FILLER_TOKENS]


def check_token_drop(record: dict, threshold: float = 0.05) -> list[AlertEntry]:
    """
    Alert if more than `threshold` fraction of content tokens from raw_asr_text
    are missing in final_text. Filler words excluded from the denominator.
    """
    case_id   = record.get("caseID", "unknown")
    raw_text  = record.get("rawAsrText", "")
    final_text = record.get("finalText", "")

    raw_tokens   = _content_tokens(raw_text)
    final_tokens = set(_content_tokens(final_text))

    if not raw_tokens:
        return []

    dropped = [t for t in raw_tokens if t not in final_tokens]
    drop_rate = len(dropped) / len(raw_tokens)

    if drop_rate > threshold:
        return [AlertEntry(
            case_id=case_id,
            alert_type="token_drop",
            severity="WARNING",
            detail=f"drop_rate={drop_rate:.2%} dropped={dropped[:10]}",
        )]
    return []


# ── Acronym shape check ───────────────────────────────────────────────────────

_ACRONYM_RE = re.compile(r'\b[A-Z]{2,}\b')


def check_acronym_shape(record: dict) -> list[AlertEntry]:
    """
    All-caps tokens in raw_asr_text must appear with the same casing in final_text.
    If they appear lowercased → alert (this may also be caught by protected_terms
    hard check, but this catches unprotected acronyms too).
    """
    case_id   = record.get("caseID", "unknown")
    raw_text  = record.get("rawAsrText", "")
    final_text = record.get("finalText", "")

    raw_acronyms = set(_ACRONYM_RE.findall(raw_text))
    alerts = []
    for acronym in raw_acronyms:
        if acronym not in final_text:
            if acronym.lower() in final_text.lower():
                alerts.append(AlertEntry(
                    case_id=case_id,
                    alert_type="acronym_shape",
                    severity="WARNING",
                    detail=f"acronym={acronym!r} case changed in output",
                ))
    return alerts


# ── Number / date drift (alert for non-hard-check contexts) ──────────────────

_NUMBER_RE = re.compile(r'\b\d+(?:[.,]\d+)*\b')
_HARD_CONTEXTS = frozenset({"technical", "correction", "command"})


def check_number_drift(record: dict) -> list[AlertEntry]:
    """
    For contexts NOT covered by hard numeric check, alert on any numeric discrepancy.
    """
    case_id   = record.get("caseID", "unknown")
    raw_text  = record.get("rawAsrText", "")
    final_text = record.get("finalText", "")
    ctx_type  = record.get("contextType", "")

    if ctx_type in _HARD_CONTEXTS:
        return []  # already covered as hard check

    def _nums(text: str) -> set[str]:
        raw = set(_NUMBER_RE.findall(text))
        return raw | {re.sub(r'[,.]', '', n) for n in raw}

    raw_nums   = _nums(raw_text)
    final_nums = _nums(final_text)
    missing = raw_nums - final_nums

    if missing:
        return [AlertEntry(
            case_id=case_id,
            alert_type="number_drift",
            severity="WARNING",
            detail=f"numbers_missing_or_changed={sorted(missing)}",
        )]
    return []


# ── Latency trend ─────────────────────────────────────────────────────────────

def check_latency(
    record: dict,
    baseline_total_ms: Optional[float] = None,
    baseline_stage_ms: Optional[dict] = None,
    threshold_pct: float = 0.50,
) -> list[AlertEntry]:
    """
    Alert if total duration or per-stage duration is > threshold_pct above baseline.
    If no baseline provided, alerts only if total > 2000ms (absolute ceiling).
    """
    case_id      = record.get("caseID", "unknown")
    total_ms     = record.get("totalDurationMs", 0.0)
    stage_traces = record.get("stageTraces", [])
    alerts = []

    if baseline_total_ms is not None:
        if total_ms > baseline_total_ms * (1 + threshold_pct):
            alerts.append(AlertEntry(
                case_id=case_id,
                alert_type="latency_total",
                severity="WARNING",
                detail=f"total={total_ms:.1f}ms baseline={baseline_total_ms:.1f}ms ({(total_ms/baseline_total_ms-1)*100:.0f}% slower)",
            ))
    elif total_ms > 2000:
        alerts.append(AlertEntry(
            case_id=case_id,
            alert_type="latency_total",
            severity="INFO",
            detail=f"total={total_ms:.1f}ms (no baseline; exceeds 2000ms ceiling)",
        ))

    if baseline_stage_ms:
        for trace in stage_traces:
            stage     = trace.get("stageName", "")
            stage_dur = trace.get("durationMs", 0.0)
            base_dur  = baseline_stage_ms.get(stage)
            if base_dur and stage_dur > base_dur * (1 + threshold_pct):
                alerts.append(AlertEntry(
                    case_id=case_id,
                    alert_type=f"latency_stage:{stage}",
                    severity="WARNING",
                    detail=f"{stage}={stage_dur:.1f}ms baseline={base_dur:.1f}ms",
                ))
    return alerts


# ── Optional: cosine similarity (gated on sentence-transformers) ──────────────

def check_semantic_similarity(
    record: dict,
    model,           # sentence_transformers.SentenceTransformer instance
    threshold: float = 0.85,
) -> list[AlertEntry]:
    """
    Optional semantic similarity check. Requires --semantic flag.
    UNRELIABLE for: short utterances, technical content, commands, multilingual text.
    Use as supplementary signal only — never as a gate.
    """
    case_id    = record.get("caseID", "unknown")
    raw_text   = record.get("rawAsrText", "")
    final_text = record.get("finalText", "")
    ctx_type   = record.get("contextType", "")

    # Skip unreliable contexts
    _UNRELIABLE = {"command", "technical", "short", "multilingual"}
    if ctx_type in _UNRELIABLE:
        return [AlertEntry(
            case_id=case_id,
            alert_type="semantic_similarity_skipped",
            severity="INFO",
            detail=f"Skipped for context_type={ctx_type!r} (unreliable for cosine similarity)",
        )]

    # Skip very short utterances
    if len(raw_text.split()) < 5:
        return [AlertEntry(
            case_id=case_id,
            alert_type="semantic_similarity_skipped",
            severity="INFO",
            detail="Skipped: utterance < 5 words (unreliable for cosine similarity)",
        )]

    embeddings = model.encode([raw_text, final_text], convert_to_tensor=False)
    # Cosine similarity
    import numpy as np
    a, b = embeddings[0], embeddings[1]
    cos_sim = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-9))

    if cos_sim < threshold:
        return [AlertEntry(
            case_id=case_id,
            alert_type="semantic_drift",
            severity="WARNING",
            detail=f"cosine_similarity={cos_sim:.3f} (threshold={threshold})",
        )]
    return [AlertEntry(
        case_id=case_id,
        alert_type="semantic_similarity",
        severity="INFO",
        detail=f"cosine_similarity={cos_sim:.3f}",
    )]


# ── Main alerting runner ──────────────────────────────────────────────────────

def run_alerting(
    record: dict,
    baseline_total_ms: Optional[float] = None,
    baseline_stage_ms: Optional[dict] = None,
    semantic_model=None,
) -> AlertingResult:
    case_id = record.get("caseID", "unknown")
    result  = AlertingResult(case_id=case_id)

    result.alerts += check_token_drop(record)
    result.alerts += check_acronym_shape(record)
    result.alerts += check_number_drift(record)
    result.alerts += check_latency(record, baseline_total_ms, baseline_stage_ms)

    if semantic_model is not None:
        result.alerts += check_semantic_similarity(record, semantic_model)

    return result


def run_all_alerting(
    records: list[dict],
    baseline: Optional[dict] = None,
    semantic_model=None,
) -> list[AlertingResult]:
    """Run alerting over all records. Baseline is the locked_baseline.json dict."""
    bl_total = None
    bl_stage = None
    if baseline:
        # Extract mean total latency from baseline if available
        cat_data = baseline.get("categories", {})
        all_totals = [
            v.get("L2", {}).get("mean_duration_ms")
            for v in cat_data.values()
            if v.get("L2", {}).get("mean_duration_ms") is not None
        ]
        bl_total = sum(all_totals) / len(all_totals) if all_totals else None

    return [
        run_alerting(r, bl_total, bl_stage, semantic_model)
        for r in records
    ]


def alerting_summary(results: list[AlertingResult]) -> dict:
    from collections import Counter
    warnings = [a for r in results for a in r.alerts if a.severity == "WARNING"]
    infos    = [a for r in results for a in r.alerts if a.severity == "INFO"]
    type_counts = Counter(a.alert_type.split(":")[0] for a in warnings)
    return {
        "total_warnings": len(warnings),
        "total_infos": len(infos),
        "cases_with_warnings": sum(1 for r in results if r.has_warnings),
        "alert_type_counts": dict(type_counts),
    }
