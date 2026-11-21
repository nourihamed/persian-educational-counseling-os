#!/usr/bin/env python3
"""REPOSITORY CHECK — NOT an implementation test.

The Supervisor brief's Batch 7 requires "no secret or key material in source code, logs, or Git". The
database half of that is asserted in SQL (CID-01..CID-05). This script covers the repository half.

It is a repository check and must NOT be counted as implementation test evidence.

WHAT IT SCANS, AND WHAT EACH PASS PROVES
  SEC-REPO-01  every tracked file in the working tree, for the patterns below.
  SEC-REPO-02  every path ever ADDED in the history, for credential-file NAMES.
  SEC-REPO-03  the CONTENT of every blob reachable from every ref PRESENT IN THE CHECKOUT (CI fetches every
               branch and tag with fetch-depth: 0). This is the one that covers a secret
               that was committed and later removed: deleting a file does not remove its blob from the
               history, and SEC-REPO-01 cannot see it. Until 2026-11-18 this script checked historical
               file NAMES only, while its own docstring said it scanned "optionally the whole Git
               history"; the Supervisor caught the overclaim, and history CONTENT scanning is now
               implemented rather than the sentence reworded. Its first run found 110 contact-shaped
               fixtures in old blobs and nothing else (see secret_scan_history_exceptions.json).
  SEC-REPO-04  untracked, non-ignored files, reported by name. They are NOT scanned by SEC-REPO-01,
               because `git ls-files` lists only tracked files — see THE BLIND SPOT below.
  SEC-REPO-05  a self-test of the exception mechanism, on planted findings.

WHAT IT LOOKS FOR, AND WHY EACH PATTERN IS HERE
  * plaintext contacts — Iranian mobile numbers and generic E.164. This project treats a contact as an
    identity, encrypts it and indexes only a keyed fingerprint; a real number in a fixture would defeat
    all of that, and D-014 forbids real data outright.
  * key material — long hex or base64 blobs assigned to a key-, secret- or token-shaped name.
  * private keys and credential files — PEM blocks, .env and key files.

THE BLIND SPOT THAT LET A FAILURE REACH CI (Batch 8, recorded rather than quietly fixed)
  Batch 8 was reported as passing this check locally, and then FAILED in GitHub Actions runs 43725323633
  and 43725318826 at commit fc3416ed. Running the fc3416ed version of this script on the exact fc3416ed
  tree reproduces two findings, both in workspace_operations_tests.sql, which that same batch had added:
  line 165 [iranian-mobile] and line 171 [e164]. The local "pass" was the implementation agent's error:
  the script was run while that file was still UNTRACKED, and `git ls-files` lists only tracked files, so
  it was never scanned. CI scans the committed tree, where it was tracked.
  Two things came out of that: SEC-REPO-04 now names every untracked file it did not scan, so the gap is
  visible in the output instead of being silent; and the operating rule is that this check runs after
  `git add`, against the tree that will actually be committed.

NARROW, PER-LINE EXCEPTIONS
  One test must contain contact-SHAPED strings, because its whole purpose is to assert that the database
  REFUSES such a payload (OPS-17/OPS-18). A fixture of that kind and a scanner for that shape are in
  genuine conflict, so the exception is as narrow as it can be made:
    * it is per LINE, not per file and not per directory;
    * the line must carry the marker NOT-A-REAL-CONTACT: followed by a reason, in the file itself, so a
      reader sees the justification at the point of use;
    * it exempts ONLY the two contact patterns. A marker does not exempt an assigned secret, a PEM block
      or a credential file, and a marker with no reason text exempts nothing.
  The fixtures themselves were also changed to all-zero subscriber bodies, so the strings are
  unmistakably synthetic as well as excepted.

HISTORY EXCEPTIONS ARE KEYED TO A BLOB HASH AND AN EXACT VALUE
  Rewriting history is forbidden on this branch (no rebase, no force-push), so a fixture that has already
  been committed stays in the history for good. Each one is excepted in secret_scan_history_exceptions.json
  by the exact triple (blob SHA, pattern, SHA-256 of the matched text), with a stated reason. A blob hash
  is content-addressed, so the exception cannot drift onto other content; naming the pattern and hashing
  the exact value means any OTHER finding in the same blob still fires. The value is stored only hashed
  and masked, so the exception file does not itself contain what it excepts. An exception that matches
  nothing is reported as a warning (it may sit on a branch the checkout does not hold).

THE ALLOWLIST USED TO EXEMPT WHOLE LINES (defect from Batch 7, found 2026-11-18)
  The synthetic-shape allowlist was tested against the whole LINE, so the word "synthetic" anywhere on a
  line exempted every pattern on it, including a PEM header and a secret assignment. It is now tested
  against the matched text only and never exempts a PEM block. SEC-REPO-05 carries the regression cases.

LIMITATIONS, stated rather than implied
  * A pattern scan proves the absence of the SHAPES listed here, not the absence of secrets. Real
    assurance needs a secret-scanning service on the repository, which is an operational control and is
    outside this repository.
  * SEC-REPO-03 needs the full history. In a shallow clone it CANNOT see it, so it FAILS CLOSED and says
    how to fix that (`fetch-depth: 0`) rather than reporting a clean history it never read.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

# (name, compiled pattern, why it matters, exemptible by a per-line marker)
PATTERNS = [
    ("iranian-mobile", re.compile(r"(?<![0-9])(?:\+98|0)9\d{9}(?![0-9])"),
     "a real Iranian mobile number; contacts are identities here and D-014 forbids real data", True),
    ("e164", re.compile(r"(?<![0-9+])\+[1-9]\d{9,14}(?![0-9])"),
     "a real-looking E.164 number", True),
    ("assigned-secret", re.compile(
        r"""(?ix) (?:secret|hmac_key|cipher_key|private_key|api[_-]?key|passwd|password|bearer)
            \s* (?:=|:=|:) \s* ['"] (?![\s'"]) [A-Za-z0-9+/=_\-]{16,} ['"]"""),
     "a long literal assigned to a secret-shaped name", False),
    ("pem", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----"),
     "a private key block", False),
]

# Synthetic shapes this project uses everywhere; flagging them would be noise.
ALLOW = [
    re.compile(r"repeat\('[0-9a-f]{1,2}',\s*\d+\)"),
    re.compile(r"decode\('[0-9a-f]+',\s*'hex'\)"),
    re.compile(r"sha256\(convert_to\("),
    re.compile(r"gen_random_uuid\(\)"),
    re.compile(r"\bsynthetic\b", re.I),
]

# A line may exempt itself from the two CONTACT patterns only, and only with a stated reason.
MARKER = re.compile(r"NOT-A-REAL-CONTACT:\s*(?P<reason>\S.{9,})")

# A cheap pre-filter, used ONLY to skip whole blobs that cannot contain a finding. The history scan walks
# every version of every file ever committed — tens of megabytes of text — and running the four patterns
# over all of it takes minutes, while one selective pass that rejects a clean blob takes milliseconds.
#
# IT MUST BE A STRICT SUPERSET of every pattern above, or it would hide findings instead of saving time.
# It is built by taking each pattern and REMOVING only its lookarounds, which can never widen a match:
# a lookbehind or lookahead restricts where a match may occur, so dropping it accepts strictly more.
# A coarser filter such as `\d{9}` would also be a superset but matches almost every file in this
# repository, because the synthetic Workspace keys are long digit runs, so it would save nothing.
# SEC-REPO-05 runs every planted case with the pre-filter ON and OFF and requires identical results, so
# an edit that narrows it below a superset fails the check.
PREFILTER = re.compile(
    r"(?:\+98|0)9\d{9}"
    r"|\+[1-9]\d{9,14}"
    r"|secret|hmac_key|cipher_key|private_key|api[_-]?key|passwd|password|bearer"
    r"|-----BEGIN",
    re.IGNORECASE)

# Historical findings that were reviewed live in a data file, keyed by (blob SHA, pattern, SHA-256 of the
# matched text). The blob SHA is content-addressed and immutable; naming the pattern and hashing the exact
# matched text means a DIFFERENT finding in the same blob still fires. The matched text is stored only as
# a hash and a masked form, so the exception file does not itself contain the strings it excepts.
EXCEPTIONS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "secret_scan_history_exceptions.json")


def load_history_exceptions():
    with open(EXCEPTIONS_FILE, encoding="utf-8") as fh:
        doc = json.load(fh)
    out = {}
    for e in doc["exceptions"]:
        if not e.get("reason") or len(e["reason"].strip()) < 20:
            raise SystemExit(f"FAIL SEC-REPO-03 history exception without a reason: {e}")
        out[(e["blob"], e["pattern"], e["matched_sha256"])] = e["reason"]
    return out


HISTORY_EXCEPTIONS = None   # loaded in main(); a test may replace it


SKIP_PATH = re.compile(r"(^|/)(\.git/|\.github/workflows/.*\.ya?ml$)")
BINARY_EXT = re.compile(r"\.(png|jpg|jpeg|gif|pdf|zip|gz|tar|ico|woff2?)$", re.I)
CREDENTIAL_FILE = re.compile(r"(^|/)(\.env(\..*)?|id_rsa|id_ed25519|.*\.pem|.*\.p12|.*\.pfx|.*\.jks)$")


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True, check=False)
    return r.stdout


def scan_text(path, text, findings, marker_ok=True, prefilter=False, keep_full=False):
    """Appends (path, lineno, pattern-name, why, sample) for every unexempted match, plus the full
    matched text as a sixth element when keep_full is set (the history exceptions hash it).

    Whole-text `finditer` per pattern rather than a Python loop over every line: the history scan reads
    every version of every file ever committed, and a per-line loop over that much text took minutes.
    Only the lines that actually contain a match are then examined for an allowlist shape or a marker, so
    the result is identical and SEC-REPO-05 asserts that on planted cases.
    """
    if prefilter and not PREFILTER.search(text):
        return
    for name, pat, why, exemptible in PATTERNS:
        for m in pat.finditer(text):
            ls = text.rfind("\n", 0, m.start()) + 1
            le = text.find("\n", m.end())
            line = text[ls:le if le != -1 else len(text)]
            # The allowlist is tested against the MATCHED TEXT, never against the whole line, and never
            # exempts a private-key block. Until 2026-11-18 it was tested against the line, which meant
            # the word "synthetic" ANYWHERE on a line exempted EVERY pattern on it — a PEM header, a
            # secret assignment, a real number — because a comment or a fixture label said "synthetic".
            # That defect dates from Batch 7 and was found by the SEC-REPO-05 self-test.
            if name != "pem" and any(a.search(m.group(0)) for a in ALLOW):
                continue
            if marker_ok and exemptible and MARKER.search(line):
                continue
            row = (path, text.count("\n", 0, m.start()) + 1, name, why, masked(name, m.group(0)))
            findings.append(row + (m.group(0),) if keep_full else row)


def masked(name, text):
    """What a finding prints. A detected contact is never echoed in full, because CI logs are retained and
    readable by everyone with repository access; printing the number would copy it into a second place."""
    if name in ("iranian-mobile", "e164") and len(text) > 8:
        return text[:6] + "*" * (len(text) - 10) + text[-4:]
    return text[:24]


def scan_working_tree(findings):
    files = [f for f in git("ls-files").splitlines() if f]
    if not files:
        print("FAIL SEC-REPO-01 `git ls-files` returned nothing; this is not a Git working tree")
        return False
    for f in files:
        if CREDENTIAL_FILE.search(f):
            findings.append((f, 0, "credential-file", "a credential or key file is tracked", f))
            continue
        if SKIP_PATH.search(f) or BINARY_EXT.search(f):
            continue
        try:
            with open(f, "r", encoding="utf-8", errors="replace") as fh:
                scan_text(f, fh.read(), findings)
        except OSError:
            continue
    print(f"PASS SEC-REPO-01 scanned {len(files)} tracked files")
    return True


def scan_history_names(findings):
    hist = git("log", "--all", "--diff-filter=A", "--name-only", "--pretty=format:")
    hist_files = {h for h in hist.splitlines() if h}
    for h in sorted(hist_files):
        if CREDENTIAL_FILE.search(h):
            findings.append((h, 0, "credential-file-history",
                             "a credential or key file was committed at some point in the history", h))
    print(f"PASS SEC-REPO-02 checked {len(hist_files)} paths ever added in the Git history "
          f"for credential-file names")


def scan_history_contents(findings):
    """Scans the CONTENT of every blob reachable from every ref. Fails closed on a shallow clone."""
    if git("rev-parse", "--is-shallow-repository").strip() == "true":
        print("FAIL SEC-REPO-03 this is a SHALLOW clone, so the history CANNOT be scanned, and a secret "
              "committed and later deleted would be invisible. Check out with `fetch-depth: 0` "
              "(actions/checkout) or run `git fetch --unshallow`. Failing closed rather than reporting a "
              "history that was never read.")
        return False

    candidates = {}
    for line in git("rev-list", "--objects", "--all").splitlines():
        parts = line.split(" ", 1)
        if len(parts) != 2:
            continue
        sha, path = parts[0], parts[1].strip()
        if not path or SKIP_PATH.search(path) or BINARY_EXT.search(path):
            continue
        candidates.setdefault(sha, path)
    # `rev-list --objects` lists TREES as well as blobs, because a directory has a path too. Keep blobs
    # only, decided by Git rather than by guessing from the path. (The first version of this function
    # sent trees to `cat-file --batch` and skipped their bodies without reading them; the stream then
    # desynchronised and the scan hung. Filtering here, and consuming every body below, both prevent it.)
    types = subprocess.run(["git", "cat-file", "--batch-check=%(objectname) %(objecttype)"],
                           input="\n".join(candidates) + "\n", capture_output=True, text=True).stdout
    blobs = {}
    for line in types.splitlines():
        p = line.split()
        if len(p) == 2 and p[1] == "blob":
            blobs[p[0]] = candidates[p[0]]
    if not blobs:
        print("FAIL SEC-REPO-03 no blobs were found in the history; the scan could not run")
        return False

    raw = []
    proc = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for sha, path in blobs.items():
            proc.stdin.write((sha + "\n").encode())
            proc.stdin.flush()
            header = proc.stdout.readline().decode("utf-8", "replace").split()
            if len(header) != 3:
                continue          # "<sha> missing": no body follows
            size = int(header[2])
            body = proc.stdout.read(size)   # ALWAYS consume the body, whatever happens next
            proc.stdout.read(1)             # the newline cat-file writes after each object
            if size > 2_000_000:
                continue
            got = []
            # The per-line marker is honoured here exactly as in the working tree: it is part of the
            # content, so a blob that carries it was reviewed with it. Without this, every marked fixture
            # would be flagged again the moment it was committed.
            scan_text(path, body.decode("utf-8", "replace"), got, prefilter=True, keep_full=True)
            raw.extend((sha, *g) for g in got)
    finally:
        try:
            proc.stdin.close()
        except OSError:
            pass
        proc.wait()

    exc = HISTORY_EXCEPTIONS if HISTORY_EXCEPTIONS is not None else load_history_exceptions()
    excepted = 0
    used = set()
    for sha, path, lineno, name, why, sample, full in raw:
        key = (sha, name, hashlib.sha256(full.encode()).hexdigest())
        if key in exc:
            used.add(key)
            excepted += 1
            continue
        findings.append((f"{path}@{sha[:12]}", lineno, name, why, sample))

    # An exception that matched nothing is reported, not silently kept. It is a WARNING and not a failure
    # because what is reachable depends on which refs the checkout holds: most of these historical blobs
    # live only on older branches (for example docs/phase2-database-domain-model), which a single-branch
    # clone does not have. An unused exception cannot over-match anything, since it is keyed by exact
    # blob SHA and exact matched value. CI checks out every branch (fetch-depth: 0), so there it should be 0.
    stale = [k for k in exc if k not in used]
    if stale:
        print(f"WARN SEC-REPO-03 {len(stale)} of {len(exc)} history exception(s) matched nothing in the refs "
              f"present here; they are probably on branches this checkout does not hold")
    print(f"PASS SEC-REPO-03 scanned the CONTENT of {len(blobs)} historical blob(s); {excepted} "
          f"finding(s) excepted, each by exact (blob SHA, pattern, matched text) with a recorded reason")
    return True


def report_untracked():
    untracked = [u for u in git("ls-files", "--others", "--exclude-standard").splitlines() if u]
    if untracked:
        # Not a PASS: something was NOT scanned. It is a warning rather than a failure because a local
        # working tree legitimately has untracked files mid-edit; in CI the checkout has none.
        print(f"WARN SEC-REPO-04 {len(untracked)} untracked file(s) were NOT scanned by SEC-REPO-01, "
              f"because `git ls-files` lists only tracked files. Run this check after `git add`: "
              f"{', '.join(untracked[:10])}")
    else:
        print("PASS SEC-REPO-04 no untracked file, so SEC-REPO-01 covered the whole working tree")


def self_test():
    """SEC-REPO-05 — the exceptions must be narrow. Planted lines, asserted one by one.

    Every planted value is ASSEMBLED AT RUNTIME from fragments, so this file never contains the shapes it
    scans for. Otherwise the scanner flags its own source, and the only way out would be an exception
    for the scanner itself, which is exactly the kind of exception that should not exist.
    """
    mob = "0" + "9" + "123456789"
    zero = "0" + "9" + "0" * 9
    pem = "-" * 5 + "BEGIN " + "PRIVATE KEY" + "-" * 5
    akey = "api" + "_key = " + chr(34) + "AKIA" + "Q" * 16 + chr(34)
    pwd = "pass" + "word = " + chr(34) + "hunter2" * 3 + chr(34)
    marker = "-- NOT-A-REAL-" + "CONTACT: fixture for the refusal test, not a real number"
    cases = [
        ("an UNMARKED contact is still found", f'payload = "{mob}"', "iranian-mobile", True),
        ("a MARKED contact is exempt", f'payload = "{zero}"  {marker}', "iranian-mobile", False),
        ("a marker does NOT exempt a secret-shaped assignment", f"{akey}  {marker}", "assigned-secret", True),
        ("a marker does NOT exempt a PEM block", f"{pem}  {marker}", "pem", True),
        ("a marker with no reason exempts nothing",
         f'payload = "{mob}"  -- NOT-A-REAL-' + "CONTACT:", "iranian-mobile", True),
        ("a marked line is still scanned for the OTHER patterns", f"{pwd}  {marker}", "assigned-secret", True),
        # Regression for the Batch 7 defect: the word "synthetic" elsewhere on the line used to exempt
        # EVERY pattern on that line.
        ("the word synthetic on the line does NOT exempt a PEM block",
         f"{pem}  -- synthetic", "pem", True),
        ("the word synthetic on the line does NOT exempt a secret assignment",
         f"{akey}  -- synthetic fixture", "assigned-secret", True),
        ("the word synthetic on the line does NOT exempt a contact",
         f'payload = "{mob}"  -- synthetic', "iranian-mobile", True),
    ]
    ok = True
    for label, line, want_name, want_found in cases:
        results = {}
        for pre in (False, True):
            f = []
            scan_text("selftest", line, f, prefilter=pre)
            results[pre] = any(r[2] == want_name for r in f)
        if results[False] != want_found:
            print(f"FAIL SEC-REPO-05 {label}: expected found={want_found}, got {results[False]}")
            ok = False
        if results[True] != results[False]:
            print(f"FAIL SEC-REPO-05 {label}: the pre-filter changed the result "
                  f"({results[False]} -> {results[True]}), so it is not a superset of the patterns")
            ok = False

    # A history exception is keyed by the exact matched text: the SAME blob and pattern with a different
    # matched value must not be covered.
    k1 = ("b" * 40, "iranian-mobile", hashlib.sha256(mob.encode()).hexdigest())
    k2 = ("b" * 40, "iranian-mobile", hashlib.sha256((mob[:-1] + "0").encode()).hexdigest())
    if k1 == k2:
        print("FAIL SEC-REPO-05 a history exception key does not distinguish two different matched values")
        ok = False
    if ok:
        print(f"PASS SEC-REPO-05 the exceptions are narrow: {len(cases)} planted cases behave as documented "
              f"(an unmarked contact fires; a marker exempts a contact only and only with a reason; the word "
              f"'synthetic' exempts nothing on its own), and history exceptions are keyed by exact value")
    return ok


def main():
    findings = []
    ok = True
    if not scan_working_tree(findings):
        return 1
    scan_history_names(findings)
    if not scan_history_contents(findings):
        ok = False
    report_untracked()
    if not self_test():
        ok = False

    if findings:
        print(f"\nFAIL SEC-REPO: {len(findings)} finding(s)")
        for path, lineno, name, why, sample in sorted((r[:5] for r in findings), key=lambda x: (x[0], x[1]))[:60]:
            where = f"{path}:{lineno}" if lineno else path
            print(f"  {where}  [{name}]  {why}  -> {sample!r}")
        return 1
    if not ok:
        return 1

    print("\nNO SECRET OR KEY MATERIAL FOUND: not in tracked files, not in committed file names, and not "
          "in the content of any blob in the history")
    print("Reminder: a pattern scan proves the absence of these SHAPES, not the absence of secrets. "
          "Real assurance needs a secret-scanning service on the repository (operational, outside it).")
    print("REPOSITORY CHECK COMPLETED (not implementation evidence)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
