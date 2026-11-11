"""Deterministic vectors for receipt-canon-v1. The same expected strings are asserted by the SQL test
receipt_30_canonical_tests.sql. A divergence in either implementation fails its suite."""
import sys, os, unittest
sys.path.insert(0, os.path.dirname(__file__))
from canonical_v1 import canonical_text, payload_digest_v1, CanonicalizationError

VECTORS = [
  # (name, input, expected canonical text)
  ("key_order_independent_a", {"b": 1, "a": 2}, '{"a":2,"b":1}'),
  ("key_order_independent_b", {"a": 2, "b": 1}, '{"a":2,"b":1}'),
  ("unicode_keys_and_values", {"name": "محمد", "k": "é"}, '{"k":"é","name":"محمد"}'),
  ("nested_objects_arrays", {"z": [{"y": 1, "x": [True, False, None]}], "a": {}}, '{"a":{},"z":[{"x":[true,false,null],"y":1}]}'),
  ("string_escapes", 'a"b\\c\n', '"a\\"b\\\\c\\n"'),
  ("integer_1000", 1000, "1000"),
  ("integer_max_safe", 9007199254740991, "9007199254740991"),
  ("empty_array", [], "[]"),
  ("empty_object", {}, "{}"),
]
REJECTS = [
  ("float_rejected", 1.5),
  ("integer_above_safe_range_rejected", 9007199254740992),
  ("non_string_key_rejected", {1: "x"}),
]

class VectorsV1(unittest.TestCase):
    def test_canonical_text_vectors(self):
        for name, value, expected in VECTORS:
            with self.subTest(name=name):
                self.assertEqual(canonical_text(value), expected)
    def test_key_order_does_not_change_digest(self):
        self.assertEqual(payload_digest_v1({"b": 1, "a": 2}), payload_digest_v1({"a": 2, "b": 1}))
    def test_changed_value_changes_digest(self):
        self.assertNotEqual(payload_digest_v1({"role_key": "counselor"}), payload_digest_v1({"role_key": "admin"}))
    def test_unicode_is_hashed_as_utf8_bytes_not_normalised(self):
        import hashlib
        s = canonical_text({"k": "é"})
        self.assertEqual(payload_digest_v1({"k": "é"}), hashlib.sha256(s.encode("utf-8")).hexdigest())
    def test_inadmissible_inputs_fail_closed(self):
        for name, value in REJECTS:
            with self.subTest(name=name):
                with self.assertRaises(CanonicalizationError):
                    canonical_text(value)
    def test_fixed_digest_of_reference_vector(self):
        # Digest of the canonical text '{"a":2,"b":1}' (cross-checked with the SQL draft).
        import hashlib
        self.assertEqual(payload_digest_v1({"a": 2, "b": 1}),
                         hashlib.sha256(b'{"a":2,"b":1}').hexdigest())

if __name__ == "__main__":
    unittest.main(verbosity=2)
