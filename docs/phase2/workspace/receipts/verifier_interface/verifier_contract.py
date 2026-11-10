"""Verifier interface contract for governance proof assertions (Issue #13, decisions A1/B3/C).

THIS MODULE DOES NOT PERFORM PRODUCTION CRYPTOGRAPHIC VERIFICATION.
- verify_production() is fail-closed: it always refuses until Platform Security approves the
  signature algorithm, algorithm allowlist, issuer-key registry, key provisioning/rotation/revocation,
  clock-skew allowance and the trust-store / certificate design (Decision C, deferred).
- verify_test_double() is TEST ONLY. It checks the NON-cryptographic rules (key known, algorithm allowlisted,
  audience, validity window) and accepts an explicit test flag for the signature result. A passing test
  double proves nothing about production cryptographic security.
Synthetic data only (D-014). No key material, certificate or secret is defined here.
"""
from dataclasses import dataclass
from datetime import datetime
from typing import Iterable, Mapping, Optional


class VerificationFailClosed(Exception):
    """Raised when production verification is not approved. Callers must treat it as a refusal."""


@dataclass(frozen=True)
class Verdict:
    accepted: bool
    reason: str  # 'accepted' or a stable rejection code


def verify_production(assertion: Mapping, *, trusted_key_resolver, algorithm_allowlist: Optional[Iterable[str]],
                      audience: str, now: datetime) -> Verdict:
    """Production verifier. Fail-closed until Decision C is approved by Platform Security / Product Owner."""
    raise VerificationFailClosed(
        "production cryptographic verification is not approved (Decision C deferred): refusing all assertions")


def verify_test_double(assertion: Mapping, *, trusted_keys: Iterable[str], algorithm_allowlist: Iterable[str],
                       audience: str, now: datetime) -> Verdict:
    """TEST ONLY. Non-cryptographic rule checks. 'test_signature_ok' is a test-supplied flag, not a verification."""
    if assertion.get("key_id") not in set(trusted_keys):
        return Verdict(False, "unknown_or_revoked_key")
    if assertion.get("alg") not in set(algorithm_allowlist):
        return Verdict(False, "algorithm_not_allowlisted")
    if assertion.get("audience") != audience:
        return Verdict(False, "audience_mismatch")
    if now < assertion["not_before"]:
        return Verdict(False, "not_yet_valid")
    if now >= assertion["expires_at"]:
        return Verdict(False, "expired")
    if assertion.get("test_signature_ok") is not True:
        return Verdict(False, "invalid_signature")
    return Verdict(True, "accepted")
