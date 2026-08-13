#!/usr/bin/env python3
"""Независимая реализация схемы долей seedsplit (SSS2/SSS3) для differential-тестов.

НЕ порт bash-кода: та же математика, написанная заново по спецификации формата —
GF(256) с приводящим многочленом 0x11b (как в AES), генератор поля 0x03,
Shamir по каждому байту payload, интерполяция Лагранжа в нуле.

Payload: 0x55 | len(2B BE) | secret | tag(16B = первые 16 байт sha256(предыдущего)).
Доля SSS2: SSS2-<setid8hex>-<T>-<x>-<hexY>-<chk4>
Доля SSS3: SSS3-<setid8hex>-<T>-<x>-<hexY>-<par>-<chk4>
chk4 — первые 4 hex-символа sha256 тела доли без -<chk4>.

Смысл файла: если bash-реализация и эта сходятся на случайных векторах в обе
стороны (bash split → python combine, python split → bash combine), ошибка
должна быть ОБЩЕЙ для двух независимых реализаций — класс «опечатка в таблице
логарифмов / кривой Горнер» так не выживает.
"""
import hashlib
import re
import secrets

# --- GF(256), 0x11b, генератор 3 ---
EXP = [0] * 255
LOG = [0] * 256
_x = 1
for _i in range(255):
    EXP[_i] = _x
    LOG[_x] = _i
    _t = (_x << 1) & 0xFF
    if _x & 0x80:
        _t ^= 0x1B
    _x = _t ^ _x  # x *= 3


def gf_mul(a: int, b: int) -> int:
    if a == 0 or b == 0:
        return 0
    return EXP[(LOG[a] + LOG[b]) % 255]


def gf_inv(a: int) -> int:
    if a == 0:
        raise ZeroDivisionError("inverse of 0 in GF(256)")
    return EXP[(255 - LOG[a]) % 255]


def wrap_payload(secret: bytes) -> bytes:
    core = b"\x55" + len(secret).to_bytes(2, "big") + secret
    return core + hashlib.sha256(core).digest()[:16]


def unwrap_payload(payload: bytes) -> bytes:
    if len(payload) < 20 or payload[0] != 0x55:
        raise ValueError("bad payload envelope")
    ln = int.from_bytes(payload[1:3], "big")
    if len(payload) != ln + 19:
        raise ValueError("bad payload length")
    core, tag = payload[: ln + 3], payload[ln + 3 :]
    if hashlib.sha256(core).digest()[:16] != tag:
        raise ValueError("payload tag mismatch")
    return core[3:]


def chk4(body: str) -> str:
    return hashlib.sha256(body.encode()).hexdigest()[:4]


def split_sss2(secret: bytes, n: int, t: int) -> list[str]:
    """Независимый split в формате SSS2 (без RS-parity — её bash дочитывает как legacy)."""
    payload = wrap_payload(secret)
    setid = secrets.token_bytes(4).hex()
    ys = {x: bytearray() for x in range(1, n + 1)}
    for byte in payload:
        coeffs = [byte] + [secrets.randbelow(256) for _ in range(t - 1)]
        for x in range(1, n + 1):
            acc = 0
            for c in reversed(coeffs):  # Горнер
                acc = gf_mul(acc, x) ^ c
            ys[x].append(acc)
    out = []
    for x in range(1, n + 1):
        body = f"SSS2-{setid}-{t}-{x}-{ys[x].hex()}"
        out.append(f"{body}-{chk4(body)}")
    return out


_SSS_RE = re.compile(
    r"^SSS(?P<v>[23])-(?P<sid>[0-9a-f]{8})-(?P<t>[0-9]+)-(?P<x>[0-9]+)-(?P<y>[0-9a-f]+)"
    r"(?:-(?P<par>[0-9a-f]+))?-(?P<chk>[0-9a-f]{4})$"
)


def combine(lines: list[str]) -> bytes:
    """Независимый combine: парсинг долей + Лагранж в нуле + проверка обёртки."""
    xs: list[int] = []
    ys: list[bytes] = []
    sid_seen = None
    t_decl = None
    for line in lines:
        m = _SSS_RE.match(line.strip())
        if not m:
            raise ValueError(f"not a share: {line!r}")
        if m["v"] == "3":
            body = f"SSS3-{m['sid']}-{m['t']}-{m['x']}-{m['y']}-{m['par']}"
        else:
            body = f"SSS2-{m['sid']}-{m['t']}-{m['x']}-{m['y']}"
        if chk4(body) != m["chk"]:
            raise ValueError(f"chk4 mismatch on x={m['x']}")
        if sid_seen is None:
            sid_seen = m["sid"]
        elif m["sid"] != sid_seen:
            raise ValueError("mixed share sets")
        if t_decl is None:
            t_decl = int(m["t"])
        elif int(m["t"]) != t_decl:
            raise ValueError("inconsistent thresholds")
        xs.append(int(m["x"]))
        ys.append(bytes.fromhex(m["y"]))
    if t_decl is None or len(xs) < t_decl:
        raise ValueError("below threshold")
    if len(set(xs)) != len(xs):
        raise ValueError("duplicate x")
    # Веса Лагранжа в нуле: w_i = prod_{j!=i} x_j / (x_i ^ x_j)
    ws = []
    for i, xi in enumerate(xs):
        w = 1
        for j, xj in enumerate(xs):
            if i == j:
                continue
            w = gf_mul(w, gf_mul(xj, gf_inv(xi ^ xj)))
        ws.append(w)
    payload = bytearray()
    for p in range(len(ys[0])):
        acc = 0
        for i in range(len(xs)):
            acc ^= gf_mul(ys[i][p], ws[i])
        payload.append(acc)
    return unwrap_payload(bytes(payload))
