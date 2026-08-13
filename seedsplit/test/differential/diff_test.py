#!/usr/bin/env python3
"""Differential- и property-тесты seedsplit против независимой реализации.

Запуск:  python3 test/differential/diff_test.py            (из каталога seedsplit)
         SEEDSPLIT_DIFF_VECTORS=500 python3 ...            (больше векторов локально)

Направления:
  A. bash split → независимый python combine + сверка RS-parity каждой доли
     с независимым RS-кодером (математика генерации, включая parity);
  B. python split (SSS3 и legacy SSS2 попеременно) → bash combine
     (математика восстановления обоих форматов);
  C. свойства: k-1 долей — отказ; любые k из n — успех; смешение сплитов — отказ;
     ≤2 опечаток в теле доли чинится RS, опечатка в самом parity тоже; большее —
     честный отказ; повторный split того же секрета даёт другие доли.

Все вызовы bash-стороны идут через сам скрипт `./seedsplit` (secret через stdin,
как в реальном использовании). Падение любого пункта = ненулевой exit.
"""
import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from independent_sss import combine as py_combine  # noqa: E402
from independent_sss import rs_parity  # noqa: E402
from independent_sss import split_sss2, split_sss3  # noqa: E402

SEEDSPLIT = os.environ.get("SEEDSPLIT_BIN", "./seedsplit")
VECTORS = int(os.environ.get("SEEDSPLIT_DIFF_VECTORS", "60"))
rng = random.Random(0xC0FFEE)  # ДЕТЕРМИНИРОВАННО: прогон воспроизводим по seed —
# это тест эквивалентности реализаций, а не источник ключей

passed = 0


def ok(name: str) -> None:
    global passed
    passed += 1
    print(f"ok {passed} {name}")


def fail(name: str, detail: str = "") -> None:
    print(f"FAIL {name}: {detail}", file=sys.stderr)
    sys.exit(1)


def bash_split(secret: bytes, n: int, t: int) -> list[str]:
    r = subprocess.run(
        [SEEDSPLIT, "split", "-n", str(n), "-t", str(t)],
        input=secret, capture_output=True,
    )
    if r.returncode != 0:
        fail("bash split", r.stderr.decode(errors="replace"))
    return r.stdout.decode().strip().splitlines()


def bash_combine(lines: list[str]) -> tuple[int, bytes, str]:
    r = subprocess.run(
        [SEEDSPLIT, "combine"],
        input="\n".join(lines).encode() + b"\n", capture_output=True,
    )
    return r.returncode, r.stdout, r.stderr.decode(errors="replace")


def random_secret() -> bytes:
    # Байты без 0x00 и без 0x0a: секрет подаётся строкой через stdin (как сид-фраза);
    # NUL bash не хранит в переменной, а перевод строки завершил бы ввод раньше.
    ln = rng.randint(4, 96)
    return bytes(rng.choice([b for b in range(1, 256) if b != 0x0A]) for _ in range(ln))


def corrupt_field(line: str, field: int, nbytes: int) -> str:
    """Испортить nbytes разных байтов в поле доли (4=hexY, 5=parity); chk4 не
    пересчитываем — это модель опечатки при переписывании с бумаги."""
    parts = line.split("-")
    y = bytearray(bytes.fromhex(parts[field]))
    for pos in rng.sample(range(len(y)), nbytes):
        y[pos] ^= rng.randint(1, 255)
    parts[field] = y.hex()
    return "-".join(parts)


# --- A: bash split → python combine (+ дифференциальная сверка RS-parity) ---
for _ in range(VECTORS):
    sec = random_secret()
    n = rng.randint(2, 9)
    t = rng.randint(2, n)
    shares = bash_split(sec, n, t)
    for line in shares:
        parts = line.split("-")
        want_par = rs_parity(bytes.fromhex(parts[4])).hex()
        if parts[5] != want_par:
            fail("A rs-parity", f"x={parts[3]}: bash par={parts[5]} independent={want_par}")
    got = py_combine(rng.sample(shares, t))
    if got != sec:
        fail("A bash→py", f"n={n} t={t} sec={sec.hex()} got={got.hex()}")
ok(f"A: bash split → independent combine + RS parity cross-check, {VECTORS} vectors")

# --- B: python split (SSS3 и legacy SSS2) → bash combine ---
for i in range(VECTORS):
    sec = random_secret()
    n = rng.randint(2, 9)
    t = rng.randint(2, n)
    shares = (split_sss3 if i % 2 == 0 else split_sss2)(sec, n, t)
    rc, out, err = bash_combine(rng.sample(shares, t))
    # bash combine печатает сырые байты секрета (без завершающего \n)
    if rc != 0 or out != sec:
        fail("B py→bash", f"n={n} t={t} rc={rc} err={err}")
ok(f"B: independent split (SSS3/SSS2 alternating) → bash combine, {VECTORS} vectors")

# --- C: свойства ---
sec = random_secret()
shares = bash_split(sec, 5, 3)

rc, _, _ = bash_combine(rng.sample(shares, 2))
rc == 0 and fail("C below-threshold", "2 of t=3 combined")
ok("C: t-1 shares are refused")

import itertools  # noqa: E402
for subset in itertools.combinations(shares, 3):
    rc, out, err = bash_combine(list(subset))
    if rc != 0 or out != sec:
        fail("C any-k-of-n", f"subset={subset} rc={rc} err={err}")
ok("C: every 3-of-5 subset reconstructs the secret")

other = bash_split(sec, 5, 3)
rc, _, err = bash_combine([shares[0], other[1], other[2]])
rc == 0 and fail("C mixed-sets", "shares from different splits combined")
ok("C: mixing shares from two splits is refused deterministically")

for nb in (1, 2):
    dam = [corrupt_field(shares[0], 4, nb)] + shares[1:3]
    rc, out, err = bash_combine(dam)
    if rc != 0 or out != sec:
        fail(f"C rs-repair-{nb}", f"rc={rc} err={err}")
    if "x=1" not in err:
        fail(f"C rs-repair-{nb}", f"no repair notice in stderr: {err}")
ok("C: RS parity repairs 1- and 2-byte typos in a share body, with a notice")

dam = [corrupt_field(shares[0], 5, 1)] + shares[1:3]
rc, out, err = bash_combine(dam)
if rc != 0 or out != sec:
    fail("C rs-repair-parity", f"typo in the parity field not repaired: rc={rc} err={err}")
ok("C: a typo in the parity field itself is repaired too")

dam = [corrupt_field(shares[0], 4, 3)] + shares[1:3]
rc, _, _ = bash_combine(dam)
rc == 0 and fail("C rs-overload", "3 typos silently accepted")
ok("C: 3 typos in one share are an honest failure, not a wrong secret")

a, b = bash_split(sec, 3, 2), bash_split(sec, 3, 2)
if a == b:
    fail("C randomness", "two splits of the same secret are identical")
ok("C: repeated splits of one secret differ (fresh set-id and coefficients)")

print(f"\nAll {passed} groups passed "
      f"({VECTORS}×2 differential vectors + property checks).")
