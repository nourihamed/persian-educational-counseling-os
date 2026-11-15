#!/usr/bin/env python3
"""REPOSITORY CHECK — NOT an implementation test.

The Supervisor brief's Batch 7 requires "no secret or key material in source code, logs, or Git". The
database half of that is asserted in SQL (CID-01..CID-05). This script covers the repository half: it
scans tracked files, and optionally the whole Git history, for things that must never be committed.

It is a repository/documentation check and must NOT be counted as implementation test evidence.

WHAT IT LOOKS FOR, AND WHY EACH PATTERN IS HERE
  * plaintext contacts — Iranian mobile numbers and generic E.164. This project treats a contact as an
    identity, encrypts it and indexes only a keyed fingerprint; a real number in a fixture would defeat
    all of that, and D-014 forbids real data outright.
  * key material — long hex or base64 blobs assigned to a key-, secret- or token-shaped name.
  * private keys and credential files — PEM blocks, .env and key files.

WHAT IT DELIBERATELY DOES NOT FLAG
  Synthetic test values of the shape repeat('aa',32) or decode('c1c2c3..','hex'), and identifiers like
  freeze_token='freeze-1'. Those are fixtures, they are obviously not secrets, and flagging them would
  train a reader to ignore this check — which is worse than not having it.

LIMITATION, stated rather than implied: a pattern scan cannot prove the absence of a secret. It proves
the absence of the shapes listed here. Real assurance needs a secret-scanning service on the repository,
which is an operational control and is outside this repository.
"""
import re
import subprocess
import sys

# (name, compiled pattern, why it matters)
PATTERNS = [
    ("iranian-mobile", re.compile(r"(?<![0-9])(?:\+98|0)9\d{9}(?![0-9])"),
     "a real Iranian mobile number; contacts are identities here and D-014 forbids real data"),
    ("e164", re.compile(r"(?<![0-9+])\+[1-9]\d{9,14}(?![0-9])"),
     "a real-looking E.164 number"),
    ("assigned-secret", re.compile(
        r"""(?ix) (?:secret|hmac_key|cipher_key|private_key|api[_-]?key|passwd|password|bearer)
            \s* (?:=|:=|:) \s* ['"] (?![\s'"]) [A-Za-z0-9+/=_\-]{16,} ['"]"""),
     "a long literal assigned to a secret-shaped name"),
    ("pem", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----"),
     "a private key block"),
]

# Synthetic shapes this project uses everywhere; flagging them would be noise.
ALLOW = [
    re.compile(r"repeat\('[0-9a-f]{1,2}',\s*\d+\)"),
    re.compile(r"decode\('[0-9a-f]+',\s*'hex'\)"),
    re.compile(r"sha256\(convert_to\("),
    re.compile(r"gen_random_uuid\(\)"),
    re.compile(r"\bsynthetic\b", re.I),
]

SKIP_PATH = re.compile(r"(^|/)(\.git/|\.github/workflows/.*\.ya?ml$)")
BINARY_EXT = re.compile(r"\.(png|jpg|jpeg|gif|pdf|zip|gz|tar|ico|woff2?)$", re.I)
CREDENTIAL_FILE = re.compile(r"(^|/)(\.env(\..*)?|id_rsa|id_ed25519|.*\.pem|.*\.p12|.*\.pfx|.*\.jks)$")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=False).stdout


def scan_text(path, text, findings):
    for lineno, line in enumerate(text.splitlines(), start=1):
        if any(a.search(line) for a in ALLOW):
            continue
        for name, pat, why in PATTERNS:
            m = pat.search(line)
            if m:
                findings.append((path, lineno, name, why, m.group(0)[:24]))


def main():
    findings = []

    files = [f for f in git("ls-files").splitlines() if f]
    if not files:
        print("FAIL SEC-REPO-01 `git ls-files` returned nothing; this is not a Git working tree")
        return 1

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

    # Git history: a secret removed from the working tree is still in the history.
    hist = git("log", "--all", "--diff-filter=A", "--name-only", "--pretty=format:")
    hist_files = {h for h in hist.splitlines() if h}
    for h in sorted(hist_files):
        if CREDENTIAL_FILE.search(h):
            findings.append((h, 0, "credential-file-history",
                             "a credential or key file was committed at some point in the history", h))
    print(f"PASS SEC-REPO-02 checked {len(hist_files)} paths ever added in the Git history "
          f"for credential-file names")

    if findings:
        print(f"\nFAIL SEC-REPO: {len(findings)} finding(s)")
        for path, lineno, name, why, sample in findings[:40]:
            where = f"{path}:{lineno}" if lineno else path
            print(f"  {where}  [{name}]  {why}  -> {sample!r}")
        return 1

    print("\nNO SECRET OR KEY MATERIAL FOUND IN TRACKED FILES OR IN COMMITTED FILE NAMES")
    print("Reminder: a pattern scan proves the absence of these SHAPES, not the absence of secrets. "
          "Real assurance needs a secret-scanning service on the repository (operational, outside it).")
    print("REPOSITORY CHECK COMPLETED (not implementation evidence)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
