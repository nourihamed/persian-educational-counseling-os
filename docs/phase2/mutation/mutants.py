# Mutant definitions for post_credit_transaction(). Each (id, description, old, new, expected_failing_test_prefix).
# old must occur EXACTLY ONCE in the canonical schema; otherwise the mutant is not generated.
import sys
MUTANTS = [
 ("AUTH-1", "binding check disabled (tenant not verified)",
  "IF NOT EXISTS (SELECT 1 FROM public.tenant_role_bindings b",
  "IF FALSE AND NOT EXISTS (SELECT 1 FROM public.tenant_role_bindings b"),
 ("AUTH-2", "permission check disabled (any role may perform any kind)",
  "IF NOT EXISTS (SELECT 1 FROM public.credit_role_permissions p",
  "IF FALSE AND NOT EXISTS (SELECT 1 FROM public.credit_role_permissions p"),
 ("AUTH-3", "identity uses current_user (owner inside SECURITY DEFINER) instead of session_user",
  "WHERE b.role_name = session_user AND b.tenant_id = p_tenant",
  "WHERE b.role_name = current_user AND b.tenant_id = p_tenant"),
 ("AUTH-4", "permission lookup uses current_user instead of session_user",
  "WHERE p.role_name = session_user AND p.kind = p_kind",
  "WHERE p.role_name = current_user AND p.kind = p_kind"),
 ("IDEM-kind", "replay ignores kind",
  "IF v_existing.kind = p_kind",
  "IF v_existing.kind IS NOT NULL"),
 ("IDEM-amount", "replay ignores amount",
  "AND v_existing.amount = p_amount",
  "AND v_existing.amount IS NOT NULL"),
 ("IDEM-student", "replay ignores student_id",
  "AND v_existing.student_id IS NOT DISTINCT FROM p_student",
  "AND TRUE"),
 ("IDEM-order", "replay ignores order_id",
  "AND v_existing.order_id   IS NOT DISTINCT FROM p_order",
  "AND TRUE"),
 ("IDEM-actor", "replay ignores actor_id",
  "AND v_existing.actor_id   IS NOT DISTINCT FROM p_actor",
  "AND TRUE"),
 ("H02-insert-only", "enrollment version check runs on INSERT only (pre-H-02 behaviour)",
  "BEFORE INSERT OR UPDATE OF tenant_id, program_version_id ON student_program_enrollments",
  "BEFORE INSERT ON student_program_enrollments"),
 ("IDEM-reason", "replay ignores reason",
  "AND v_existing.reason     IS NOT DISTINCT FROM p_reason THEN",
  "AND TRUE THEN"),
]

def make(canonical_path, out_dir):
    src = open(canonical_path, encoding="utf-8").read()
    made = []
    for mid, desc, old, new in MUTANTS:
        n = src.count(old)
        if n != 1:
            print(f"SKIP {mid}: target occurs {n} times (need exactly 1)", file=sys.stderr)
            continue
        path = f"{out_dir}/{mid}.sql"
        open(path, "w", encoding="utf-8").write(src.replace(old, new))
        made.append((mid, desc, path))
    return made

if __name__ == "__main__":
    made = make(sys.argv[1], sys.argv[2])
    # Refuse silently-shrunk mutant sets: every defined mutant must be generated.
    if len(made) != len(MUTANTS):
        print(f"GENERATION INCOMPLETE: {len(made)} of {len(MUTANTS)} mutants generated", file=sys.stderr)
        sys.exit(3)
    for mid, desc, path in made:
        print(f"{mid}\t{desc}\t{path}")
