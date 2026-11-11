"""Test-only REFERENCE implementation of the canonical payload contract receipt-canon-v1.

Contract: docs/phase2/workspace/receipts/CANONICALIZATION_CONTRACT.md. The SQL draft
(receipt_00_canonical_payload_draft.sql) must produce identical canonical text and digests
for every vector in test_vectors_v1.py. This is a fingerprint of bytes, not a signature and
not production cryptographic approval. Synthetic data only.
"""
import hashlib

CANON_VERSION = "receipt-canon-v1"
MAX_SAFE = 9007199254740991


class CanonicalizationError(ValueError):
    pass


def _escape(s: str) -> str:
    out = ['"']
    for ch in s:
        o = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\b":
            out.append("\\b")
        elif ch == "\f":
            out.append("\\f")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif o < 0x20:
            out.append("\\u%04x" % o)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def canonical_text(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        if abs(value) > MAX_SAFE:
            raise CanonicalizationError("integer outside the admissible domain")
        return str(value)  # -0 cannot exist as a Python int; it normalises to 0
    if isinstance(value, float):
        raise CanonicalizationError("floats are not admissible in receipt-canon-v1")
    if isinstance(value, str):
        return _escape(value)
    if isinstance(value, list):
        return "[" + ",".join(canonical_text(v) for v in value) + "]"
    if isinstance(value, dict):
        for k in value:
            if not isinstance(k, str):
                raise CanonicalizationError("object keys must be strings")
        items = sorted(value.items(), key=lambda kv: kv[0])  # code-point order
        return "{" + ",".join(_escape(k) + ":" + canonical_text(v) for k, v in items) + "}"
    raise CanonicalizationError("unsupported type %s" % type(value).__name__)


def payload_digest_v1(value) -> str:
    """Hex SHA-256 over the UTF-8 bytes of the canonical text (fingerprint, not a signature)."""
    return hashlib.sha256(canonical_text(value).encode("utf-8")).hexdigest()
