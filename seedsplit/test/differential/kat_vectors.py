#!/usr/bin/env python3
"""Known-answer vectors for the GF(256) core of the second (Python) implementation.

The differential tests (diff_test.py) prove the bash and Python implementations
agree with EACH OTHER. This file anchors the shared arithmetic to PUBLISHED,
EXTERNAL sources, so that "both implementations carry the same mistake" for the
field core would also have to mean "FIPS-197 is wrong":

  * Multiplication — FIPS-197 (Advanced Encryption Standard), §4.2 and §4.2.1:
    {57}·{83}={c1}, {57}·{13}={fe}, and the xtime chain
    {57}·{02}={ae}, {57}·{04}={47}, {57}·{08}={8e}, {57}·{10}={07}.
    https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197.pdf
  * Inversion — FIPS-197 §5.1.1 (SubBytes construction): the multiplicative
    inverse of {53} is {ca}; plus inv(1)=1 and a full a·inv(a)=1 sweep.
  * log/antilog tables — the generator-3 antilog table published in
    Daemen & Rijmen, "The Design of Rijndael" (the standard AES log tables):
    the first sixteen antilog entries are 01 03 05 0f 11 33 55 ff
    1a 2e 72 96 a1 f8 13 35.
  * Lagrange interpolation at zero — the frozen SSS2 share-set that has shipped
    in this repository's test suite since v0.3.0 (test/shamir.bats "frozen SSS2
    share-set"): a vector generated years before this file existed, decoded here
    by the Python implementation. This one is an internal (repo-frozen) anchor,
    not an external publication — stated plainly.

Run:  python3 test/differential/kat_vectors.py   (from the seedsplit directory)
Exit code 0 = every vector matches.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from independent_sss import EXP, LOG, combine, gf_inv, gf_mul  # noqa: E402

failures = 0


def check(name, got, want):
    global failures
    if got != want:
        print(f"FAIL {name}: got {got!r}, want {want!r}", file=sys.stderr)
        failures += 1
    else:
        print(f"ok {name}")


# --- FIPS-197 §4.2 / §4.2.1: multiplication ---
check("FIPS-197 {57}*{83}", gf_mul(0x57, 0x83), 0xC1)
check("FIPS-197 {57}*{13}", gf_mul(0x57, 0x13), 0xFE)
check("FIPS-197 xtime {57}*{02}", gf_mul(0x57, 0x02), 0xAE)
check("FIPS-197 xtime {57}*{04}", gf_mul(0x57, 0x04), 0x47)
check("FIPS-197 xtime {57}*{08}", gf_mul(0x57, 0x08), 0x8E)
check("FIPS-197 xtime {57}*{10}", gf_mul(0x57, 0x10), 0x07)

# --- FIPS-197 §5.1.1: inversion ---
check("FIPS-197 inv({53})", gf_inv(0x53), 0xCA)
check("inv(1)=1", gf_inv(1), 1)
check("a*inv(a)=1 for all 255 nonzero a",
      all(gf_mul(a, gf_inv(a)) == 1 for a in range(1, 256)), True)

# --- Daemen & Rijmen: generator-3 antilog table, first 16 entries ---
check("Rijndael antilog[0..15]", EXP[:16],
      [0x01, 0x03, 0x05, 0x0F, 0x11, 0x33, 0x55, 0xFF,
       0x1A, 0x2E, 0x72, 0x96, 0xA1, 0xF8, 0x13, 0x35])
check("log/antilog are mutually inverse",
      all(LOG[EXP[i]] == i for i in range(255)), True)

# --- Lagrange at zero: the repo-frozen v0.3.0 share-set (internal anchor) ---
_FROZEN = [
    "SSS2-c8854057-2-1-7f68df20a655723629706e8be2e0741a33c4df7ac2ca982951c438ff3f707f6c15ce9b9c50-f201",
    "SSS2-c8854057-2-2-01d0939d945693f9fd4f70984f6f53a81109f5a1cfa0b44e7dbc279aa76b64da2932a07193-49a0",
    "SSS2-c8854057-2-3-2bb85ef67357ccbcb15a7a60dde34ec60fbb1ae83d86599a9094dbb926626d413d66402ad2-8ca1",
]
for a, b in ((0, 1), (0, 2), (1, 2)):
    check(f"frozen v0.3.0 shares {a+1}+{b+1}",
          combine([_FROZEN[a], _FROZEN[b]]), b"KAT-seedsplit-v030")

if failures:
    print(f"\n{failures} vector(s) FAILED", file=sys.stderr)
    sys.exit(1)
print("\nAll known-answer vectors match.")
