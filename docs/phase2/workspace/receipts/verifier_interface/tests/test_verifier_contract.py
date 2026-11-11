"""Verifier boundary tests (test doubles only). Run: python3 -m unittest -v test_verifier_contract.py"""
import sys, os, unittest
from datetime import datetime, timedelta, timezone
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from verifier_contract import verify_production, verify_test_double, VerificationFailClosed

NOW = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
GOOD = {"key_id": "test-key-1", "alg": "TEST-ALG-1", "audience": "governance_adapter", "canonicalization_version": "receipt-canon-v1",
        "not_before": NOW - timedelta(minutes=1), "expires_at": NOW + timedelta(minutes=5), "test_signature_ok": True}
TRUSTED = ["test-key-1"]; ALLOW = ["TEST-ALG-1"]; AUD = "governance_adapter"

def check(a, **over):
    kw = dict(trusted_keys=TRUSTED, algorithm_allowlist=ALLOW, audience=AUD, now=NOW)
    kw.update(over); return verify_test_double(a, **kw)

class ProductionIsFailClosed(unittest.TestCase):
    def test_production_refuses_everything(self):
        with self.assertRaises(VerificationFailClosed):
            verify_production(GOOD, trusted_key_resolver=None, algorithm_allowlist=None, audience=AUD, now=NOW)

class TestDoubleRules(unittest.TestCase):
    def test_accepts_when_all_rules_pass(self):
        self.assertEqual(check(GOOD).reason, "accepted")
    def test_unknown_or_revoked_key_rejected(self):
        self.assertEqual(check({**GOOD, "key_id": "rotated-out"}).reason, "unknown_or_revoked_key")
    def test_disallowed_algorithm_rejected(self):
        self.assertEqual(check({**GOOD, "alg": "none"}).reason, "algorithm_not_allowlisted")
    def test_empty_allowlist_rejects_everything(self):
        self.assertEqual(check(GOOD, algorithm_allowlist=[]).reason, "algorithm_not_allowlisted")
    def test_audience_mismatch_rejected(self):
        self.assertEqual(check({**GOOD, "audience": "worker"}).reason, "audience_mismatch")
    def test_not_yet_valid_rejected(self):
        self.assertEqual(check({**GOOD, "not_before": NOW + timedelta(minutes=1)}).reason, "not_yet_valid")
    def test_expired_rejected(self):
        self.assertEqual(check({**GOOD, "expires_at": NOW}).reason, "expired")
    def test_invalid_signature_rejected(self):
        self.assertEqual(check({**GOOD, "test_signature_ok": False}).reason, "invalid_signature")
    def test_missing_signature_result_is_not_accepted(self):
        bad = {k: v for k, v in GOOD.items() if k != "test_signature_ok"}
        self.assertEqual(check(bad).reason, "invalid_signature")

class CanonicalBindingInVerifier(unittest.TestCase):
    PAYLOAD = {"role_key": "counselor"}
    def base(self, **kw):
        from canonical_v1 import payload_digest_v1 as d
        a = {**GOOD, "canonicalization_version": "receipt-canon-v1", "payload": self.PAYLOAD,
             "payload_digest": d(self.PAYLOAD)}
        a.update(kw); return a
    def test_matching_payload_digest_accepted(self):
        self.assertEqual(check(self.base()).reason, "accepted")
    def test_unknown_canonicalization_version_rejected(self):
        self.assertEqual(check(self.base(canonicalization_version="receipt-canon-v2")).reason, "unsupported_canonicalization_version")
    def test_missing_canonicalization_version_rejected(self):
        a = self.base(); a.pop("canonicalization_version")
        self.assertEqual(check(a).reason, "unsupported_canonicalization_version")
    def test_altered_payload_digest_rejected(self):
        self.assertEqual(check(self.base(payload={"role_key": "admin"})).reason, "payload_digest_mismatch")
    def test_inadmissible_payload_rejected(self):
        self.assertEqual(check(self.base(payload={"x": 1.5})).reason, "payload_not_canonicalizable")

if __name__ == "__main__":
    unittest.main(verbosity=2)
