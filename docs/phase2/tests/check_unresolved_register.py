#!/usr/bin/env python3
"""DOCUMENTATION CONSISTENCY CHECK — NOT an implementation test.

This script proves nothing about the database, the schema or any security property. It only checks that the
two halves of the unresolved-item register cannot drift apart:

  docs/phase2/unresolved_items.json       (machine-readable)
  docs/phase2/UNRESOLVED_ITEM_REGISTER.md (human-readable)

It is counted as a documentation check and must never be reported as test evidence for an implementation
claim. It exists because a register that is maintained in two places silently diverges otherwise, and a
reviewer reading one half would be reading something the other half contradicts.

Checks:
  1. The JSON parses and every item has every required field.
  2. The mandatory item list from the Supervisor brief is fully covered.
  3. Every JSON item id appears in the Markdown.
  4. No item is recorded as RESOLVED, because the implementation cannot resolve any of them.
  5. Every item states whether safe implementation may continue, and if so under what condition.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
JSON_PATH = ROOT / "docs/phase2/unresolved_items.json"
MD_PATH = ROOT / "docs/phase2/UNRESOLVED_ITEM_REGISTER.md"

# The list the Supervisor brief requires the register to cover, verbatim in spirit.
MANDATORY = [
    "Q-007", "Q-020",
    "OQ-CRD-2", "OQ-CRD-3",
    "OQ-SAGA-1", "OQ-SAGA-2",
    "OQ-ASM-1",
    "OQ-D", "OQ-E",
    "PS-1", "PS-2", "PS-3", "PS-4", "PS-5", "PS-6", "PS-7", "PS-8",
    "M-05", "M-06",
    "WS-DOM-02",
    "TRANSFER-EXC-AUTH",
    "PR-8-11-DISPOSITION",
    "BRANCH-SYNC",
    # Added 2026-11-18 on Supervisor instruction: a core product security requirement, BLOCKING.
    "WS-ISO-01",
]

REQUIRED_FIELDS = [
    "id", "title", "status", "why_unresolved", "security_impact",
    "implementation_may_continue", "decision_owner", "options",
    "recommended_option", "rationale",
    # Classification fields, required since 2026-11-18 (Supervisor instruction E).
    "item_class", "code_can_resolve", "code_resolution_note", "recommended_gate_impact", "closure_evidence",
]

ALLOWED_CLASS = {"PRODUCT_OWNER_DECISION", "PLATFORM_SECURITY_DECISION", "SUPERVISOR_FINDING",
                 "IMPLEMENTATION_DEFECT", "LATER_OPERATIONAL_DEPENDENCY"}
ALLOWED_CODE = {"yes", "partly", "no"}
ALLOWED_GATE = {"BLOCKING", "NON_BLOCKING_FAIL_CLOSED", "LATER_PHASE", "UNKNOWN_UNTIL_DEFINED"}

ALLOWED_STATUS = {"OPEN", "PARTIALLY_DECIDED", "DEFERRED", "RESOLVED", "FACTUALLY_CORRECTED"}

failures = []


def fail(msg):
    failures.append(msg)
    print(f"FAIL REG: {msg}")


def main():
    try:
        data = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - any parse problem is a failure to report
        print(f"FAIL REG-01 {JSON_PATH} does not parse: {exc}")
        return 1
    print("PASS REG-01 the machine-readable register parses")

    md = MD_PATH.read_text(encoding="utf-8")
    items = data.get("items", [])
    ids = [it.get("id") for it in items]

    for it in items:
        missing = [f for f in REQUIRED_FIELDS if f not in it or it[f] in (None, "", [])]
        if missing:
            fail(f"REG-02 item {it.get('id')!r} is missing required field(s): {', '.join(missing)}")
        if it.get("status") not in ALLOWED_STATUS:
            fail(f"REG-02 item {it.get('id')!r} has status {it.get('status')!r}, "
                 f"which is not one of {sorted(ALLOWED_STATUS)}")
        if it.get("status") == "RESOLVED":
            fail(f"REG-05 item {it.get('id')!r} is marked RESOLVED. The implementation cannot resolve a "
                 f"register item; only its named decision owner can.")
        cls = it.get("item_class") or []
        if not isinstance(cls, list) or not cls or any(c not in ALLOWED_CLASS for c in cls):
            fail(f"REG-07 item {it.get('id')!r} has item_class {cls!r}; each must be one of {sorted(ALLOWED_CLASS)}")
        if it.get("code_can_resolve") not in ALLOWED_CODE:
            fail(f"REG-07 item {it.get('id')!r} has code_can_resolve {it.get('code_can_resolve')!r}")
        if it.get("recommended_gate_impact") not in ALLOWED_GATE:
            fail(f"REG-07 item {it.get('id')!r} has recommended_gate_impact {it.get('recommended_gate_impact')!r}")
        if it.get("implementation_may_continue") is True and not it.get("continue_conditions"):
            fail(f"REG-06 item {it.get('id')!r} says implementation may continue but states no fail-closed "
                 f"condition. 'May continue' without a condition is how an open question becomes an "
                 f"implicit decision.")
    if not any(f.startswith("FAIL REG-02") for f in failures):
        print(f"PASS REG-02 all {len(items)} items carry every required field and a valid status")

    for want in MANDATORY:
        if want not in ids:
            fail(f"REG-03 mandatory item {want} is absent from the register")
    if not any("REG-03" in f for f in failures):
        print(f"PASS REG-03 all {len(MANDATORY)} mandatory items are covered")

    for i in ids:
        if i and i not in md:
            fail(f"REG-04 item {i} is in the JSON but not in {MD_PATH.name}; the two halves have drifted")
    if not any("REG-04" in f for f in failures):
        print("PASS REG-04 every machine-readable item appears in the human-readable register")

    if not any("REG-07" in f for f in failures):
        print(f"PASS REG-07 every item is classified (kind, code-resolvable, gate impact, closure evidence)")

    # REG-08: the Markdown classification table must AGREE with the JSON row by row, not merely mention
    # each id. This is what makes "the two halves agree" a checked statement.
    rows = {}
    in_table = False
    for line in md.splitlines():
        if line.startswith("## 6. Classification of every item"):
            in_table = True
            continue
        if in_table and line.startswith("## "):
            break
        if in_table and line.startswith("| ") and not line.startswith("| ID ") and not line.startswith("|---"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 4:
                rows[cells[0]] = cells
    for it in items:
        r = rows.get(it.get("id"))
        if r is None:
            fail(f"REG-08 item {it.get('id')} has no row in the Markdown classification table")
            continue
        want = [it["id"], ", ".join(it.get("item_class", [])), it.get("code_can_resolve"),
                it.get("recommended_gate_impact")]
        if r[:4] != want:
            fail(f"REG-08 item {it.get('id')} disagrees between JSON {want} and Markdown {r[:4]}")
    extra = set(rows) - set(ids)
    if extra:
        fail(f"REG-08 the Markdown classification table has rows for unknown items: {sorted(extra)}")
    if not any("REG-08" in f for f in failures):
        print(f"PASS REG-08 the Markdown classification table agrees with the JSON for all {len(items)} items")

    blocking = [it["id"] for it in items if it.get("recommended_gate_impact") == "BLOCKING"]
    print(f"NOTE REG blocking items recommended to the Supervisor: {', '.join(blocking) or 'none'}")

    if not any("REG-05" in f for f in failures):
        print("PASS REG-05 no item is recorded as RESOLVED by the implementation")
    if not any("REG-06" in f for f in failures):
        print("PASS REG-06 every continuable item states its fail-closed condition")

    if failures:
        print(f"\nREGISTER CONSISTENCY CHECK FAILED with {len(failures)} problem(s)")
        return 1
    print("\nREGISTER CONSISTENCY CHECK COMPLETED (documentation check only; not implementation evidence)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
