#!/usr/bin/env python3
"""
test_hard_metrics.py  —  Unit tests for hard_metrics.py

Run: python -m pytest Evals/metrics/tests/test_hard_metrics.py -v
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import pytest
from hard_metrics import (
    check_protected_terms,
    check_url_integrity,
    check_email_integrity,
    check_numeric_integrity,
    check_command_accuracy,
    check_rewrite_gate,
    run_hard_checks,
    hard_failure_summary,
    HardCheckResult,
)


# ── check_protected_terms ─────────────────────────────────────────────────────


class TestProtectedTerms:
    def test_term_present_passes(self):
        assert check_protected_terms("x", "getUserProfile", ["getUserProfile"]) == []

    def test_term_missing_fails(self):
        failures = check_protected_terms("x", "something else", ["getUserProfile"])
        assert "protectedTermMissing" in failures[0]

    def test_term_case_corrupted(self):
        failures = check_protected_terms("x", "getuserprofile here", ["getUserProfile"])
        assert "protectedTermCaseCorruption" in failures[0]

    def test_multiple_terms_all_present(self):
        result = check_protected_terms(
            "x", "REST API JSON HTTPS", ["REST", "API", "JSON", "HTTPS"]
        )
        assert result == []

    def test_multiple_terms_one_missing(self):
        failures = check_protected_terms(
            "x", "REST API JSON", ["REST", "API", "JSON", "HTTPS"]
        )
        assert any("HTTPS" in f for f in failures)

    def test_empty_term_ignored(self):
        assert check_protected_terms("x", "hello", [""]) == []

    def test_overlapping_terms_both_checked(self):
        # 'getUserProfile' contains 'Profile'; both are checked independently
        failures = check_protected_terms("x", "getUser", ["getUserProfile", "Profile"])
        # getUserProfile missing, Profile missing
        assert len(failures) == 2

    def test_term_is_substring_of_another(self):
        # 'user' is substring of 'getUserProfile'; must check both separately
        result = check_protected_terms(
            "x", "getUserProfile and user data", ["getUserProfile", "user"]
        )
        assert result == []


# ── check_url_integrity ───────────────────────────────────────────────────────


class TestURLIntegrity:
    def test_url_present_passes(self):
        url = "https://api.example.com/v2/users/me"
        assert check_url_integrity("x", f"endpoint is {url}", [url]) == []

    def test_url_missing_fails(self):
        url = "https://api.example.com/v2/users/me"
        failures = check_url_integrity("x", "endpoint is something else", [url])
        assert any("malformedURL" in f for f in failures)

    def test_non_url_term_ignored(self):
        # Terms not starting with http are not checked as URLs
        assert check_url_integrity("x", "hello world", ["getUserProfile"]) == []

    def test_partial_url_fails(self):
        url = "https://api.example.com/v2/users/me"
        # Only first part of URL present — missing path
        failures = check_url_integrity("x", "https://api.example.com", [url])
        assert any("malformedURL" in f for f in failures)

    def test_https_acronym_is_not_treated_as_url(self):
        assert check_url_integrity("x", "REST API over HTTPS", ["HTTPS"]) == []


# ── check_email_integrity ─────────────────────────────────────────────────────


class TestEmailIntegrity:
    def test_email_present_passes(self):
        email = "alice.smith@company.io"
        assert check_email_integrity("x", f"send to {email}", [email]) == []

    def test_email_missing_fails(self):
        email = "alice.smith@company.io"
        failures = check_email_integrity("x", "send to someone@else.com", [email])
        assert any("malformedEmail" in f for f in failures)

    def test_decorator_at_symbol_ignored(self):
        # @MainActor is not an email
        assert check_email_integrity("x", "@MainActor is cool", ["@MainActor"]) == []

    def test_email_case_sensitive(self):
        email = "Alice.Smith@Company.IO"
        # Different case in output
        failures = check_email_integrity("x", "alice.smith@company.io text", [email])
        assert any("malformedEmail" in f for f in failures)

    def test_git_remote_with_email_prefix_passes(self):
        remote = "git@github.com:myorg/repo.git"
        assert check_email_integrity("x", f"clone {remote}", [remote]) == []


# ── check_numeric_integrity ───────────────────────────────────────────────────


class TestNumericIntegrity:
    def test_technical_context_number_present(self):
        assert (
            check_numeric_integrity(
                "x", "version 3.14.1", "version 3.14.1", "technical"
            )
            == []
        )

    def test_technical_context_number_missing(self):
        failures = check_numeric_integrity(
            "x", "version 3.14.1", "version X.Y.Z", "technical"
        )
        assert any("numericCorruption" in f for f in failures)

    def test_prose_context_skip(self):
        # In prose context, numeric check is alerting only, not hard
        assert (
            check_numeric_integrity("x", "version 3.14.1", "version X.Y.Z", "prose")
            == []
        )

    def test_thousand_separator_allowed(self):
        # 30000 reformatted as 30,000 should not fail
        assert (
            check_numeric_integrity(
                "x", "timeout 30000ms", "timeout 30,000ms", "technical"
            )
            == []
        )

    def test_correction_context_enforced(self):
        failures = check_numeric_integrity(
            "x", "meant 3.2 not 2.3", "meant 3.2 not 2.4", "correction"
        )
        assert any("numericCorruption" in f for f in failures)


# ── check_command_accuracy ────────────────────────────────────────────────────


class TestCommandAccuracy:
    def test_expected_none_actual_none_passes(self):
        assert check_command_accuracy("x", None, "none") == []

    def test_spurious_command(self):
        failures = check_command_accuracy("x", None, "cancelLast")
        assert any("spuriousCommand" in f for f in failures)

    def test_correct_command(self):
        assert check_command_accuracy("x", "cancelLast", "cancelLast") == []

    def test_wrong_command_type(self):
        failures = check_command_accuracy("x", "cancelLast", "copyOnly")
        assert any("commandMismatch" in f for f in failures)

    def test_expected_command_not_extracted(self):
        failures = check_command_accuracy("x", "newParagraph", "none")
        assert any("commandMismatch" in f for f in failures)

    def test_empty_string_treated_as_none(self):
        assert check_command_accuracy("x", None, "") == []
        assert check_command_accuracy("x", None, None) == []


# ── check_rewrite_gate ────────────────────────────────────────────────────────


class TestRewriteGate:
    def test_level_none_no_change_passes(self):
        result = check_rewrite_gate(
            "x", "the meeting is Friday", "The meeting is Friday.", "none"
        )
        assert result == []  # capitalisation + period = allowed

    def test_level_none_filler_removal_passes(self):
        result = check_rewrite_gate(
            "x", "uh the meeting is Friday", "The meeting is Friday.", "none"
        )
        assert result == []  # filler removal = allowed

    def test_level_none_content_insertion_fails(self):
        result = check_rewrite_gate(
            "x", "the meeting is Friday", "The important meeting is Friday.", "none"
        )
        assert any("forbiddenRewrite" in f for f in result)

    def test_level_light_allows_insertion(self):
        result = check_rewrite_gate(
            "x", "the meeting is Friday", "The important meeting is Friday.", "light"
        )
        assert result == []  # light level: gate not applied

    def test_level_full_allows_all(self):
        result = check_rewrite_gate(
            "x",
            "meeting friday",
            "The quarterly meeting is scheduled for Friday.",
            "full",
        )
        assert result == []


# ── run_hard_checks (integration) ────────────────────────────────────────────


class TestRunHardChecks:
    def _make_record(self, **kwargs):
        base = {
            "caseID": "test-001",
            "rawAsrText": "call getUserProfile with userId",
            "finalText": "call getUserProfile with userId",
            "protectedTerms": ["getUserProfile", "userId"],
            "contextType": "technical",
            "expectedCommand": None,
            "actualCommand": "none",
            "rewriteAllowedLevel": "none",
        }
        base.update(kwargs)
        return base

    def test_clean_record_passes(self):
        result = run_hard_checks(self._make_record())
        assert result.passed

    def test_missing_protected_term_fails(self):
        result = run_hard_checks(
            self._make_record(finalText="call getUser with userId")
        )
        assert not result.passed
        assert any("protectedTerm" in f for f in result.hard_failures)

    def test_spurious_command_fails(self):
        result = run_hard_checks(self._make_record(actualCommand="cancelLast"))
        assert not result.passed
        assert "spuriousCommand" in result.hard_failures

    def test_case_corrupted_term_fails(self):
        result = run_hard_checks(
            self._make_record(finalText="call getuserprofile with userid")
        )
        assert not result.passed
        assert any("protectedTermCaseCorruption" in f for f in result.hard_failures)


# ── hard_failure_summary ──────────────────────────────────────────────────────


class TestHardFailureSummary:
    def test_empty_results(self):
        summary = hard_failure_summary([])
        assert summary["total_cases"] == 0
        assert summary["hard_failure_count"] == 0

    def test_all_passed(self):
        results = [HardCheckResult(case_id=f"c-{i}") for i in range(5)]
        summary = hard_failure_summary(results)
        assert summary["hard_failure_count"] == 0
        assert summary["hard_failure_rate"] == 0.0

    def test_some_failed(self):
        r1 = HardCheckResult(case_id="ok-1")
        r2 = HardCheckResult(case_id="fail-1", hard_failures=["protectedTermMissing"])
        r3 = HardCheckResult(
            case_id="fail-2", hard_failures=["spuriousCommand", "protectedTermMissing"]
        )
        summary = hard_failure_summary([r1, r2, r3])
        assert summary["hard_failure_count"] == 2
        assert summary["failure_types"]["protectedTermMissing"] == 2
        assert summary["failure_types"]["spuriousCommand"] == 1
