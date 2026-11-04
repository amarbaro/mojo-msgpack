"""Reference for the gate: Python msgpack (use_bin_type=True) is the oracle, never imported by the library.

  oracle.py gen DIR     write fixtures: trees.spec (random trees, one token line each), dec.hex (bytes to decode)
  oracle.py encode F    per spec line: hex of msgpack's bytes
  oracle.py decode F    per hex line: the decoded tree as tokens, or ERR

Tokens: n | t | f | i DEC | d HEX64 (float64) | F HEX32 (float32) | s HEX | b HEX | a N | m N | x TYPE HEX | T SEC NSEC.
Containers announce a count and their children follow. "-" stands for empty hex."""
import random, struct, sys
import msgpack
from msgpack import ExtType, Timestamp

sys.setrecursionlimit(20000)
D, S = msgpack.Packer(use_bin_type=True), msgpack.Packer(use_bin_type=True, use_single_float=True)


def unhex(s):
    return b"" if s == "-" else bytes.fromhex(s)


def hx(b):
    return b.hex() or "-"


def encode(line):
    t, i, out = line.split(), 0, []
    while i < len(t):
        k = t[i]
        i += 1
        if k in "ntf":
            out.append(D.pack({"n": None, "t": True, "f": False}[k]))
        elif k == "i":
            out.append(D.pack(int(t[i]))); i += 1
        elif k == "d":
            out.append(D.pack(struct.unpack(">d", bytes.fromhex(t[i]))[0])); i += 1
        elif k == "F":
            out.append(S.pack(struct.unpack(">f", bytes.fromhex(t[i]))[0])); i += 1
        elif k == "s":
            out.append(D.pack(unhex(t[i]).decode())); i += 1
        elif k == "b":
            out.append(D.pack(unhex(t[i]))); i += 1
        elif k == "a":
            out.append(D.pack_array_header(int(t[i]))); i += 1
        elif k == "m":
            out.append(D.pack_map_header(int(t[i]))); i += 1
        elif k == "x":
            out.append(D.pack(ExtType(int(t[i]), unhex(t[i + 1])))); i += 2
        elif k == "T":
            out.append(D.pack(Timestamp(int(t[i]), int(t[i + 1])))); i += 2
        else:
            raise SystemExit("bad token " + k)
    return b"".join(out).hex()


class Pairs(list):
    pass


class Ext:  # any type -128..127 (msgpack.ExtType refuses negative codes)
    def __init__(self, code, data):
        self.code, self.data = code, data


def dump(o, out):
    if o is None: out.append("n")
    elif o is True: out.append("t")
    elif o is False: out.append("f")
    elif isinstance(o, int): out += ["i", str(o)]
    elif isinstance(o, float): out += ["d", struct.pack(">d", o).hex()]
    elif isinstance(o, str): out += ["s", hx(o.encode())]
    elif isinstance(o, bytes): out += ["b", hx(o)]
    elif isinstance(o, Timestamp): out += ["T", str(o.seconds), str(o.nanoseconds)]
    elif isinstance(o, Ext): out += ["x", str(o.code), hx(o.data)]
    elif isinstance(o, Pairs):
        out += ["m", str(len(o))]
        for k, v in o:
            dump(k, out); dump(v, out)
    else:
        out += ["a", str(len(o))]
        for v in o:
            dump(v, out)


def decode(h):
    try:
        o = msgpack.unpackb(unhex(h), raw=False, strict_map_key=False, timestamp=0, ext_hook=Ext, object_pairs_hook=Pairs)
        out = []
        dump(o, out)
        return " ".join(out)
    except Exception:
        return "ERR"


INTS = [0, 1, -1, 31, 32, -32, -33, 127, 128, -128, -129, 255, 256, 32767, 32768, -32768, -32769, 65535, 65536,
        2**31 - 1, 2**31, -2**31, -2**31 - 1, 2**32 - 1, 2**32, 2**63 - 1, 2**63, 2**64 - 1, -2**63]
FLOATS = [0.0, -0.0, 1.5, -2.25, 1e300, 5e-324, float("inf"), float("-inf"), 3.141592653589793, 1e-45, 3.4028234663852886e38]
F32S = [0.0, -0.0, 1.5, -2.25, float("inf"), float("-inf"), 1e-45, 3.4028234663852886e38]
LENS = [0, 1, 2, 4, 8, 16, 30, 31, 32, 33, 255, 256, 257, 65535, 65536]


def rstr(r, n):  # str of about n UTF-8 bytes, mixed 1 to 4 byte characters
    out, size = [], 0
    while size < n:
        c = r.choice("a" * 6 + "é€𝄞\u0000\n\"")
        out.append(c)
        size += len(c.encode())
    return "".join(out)


MAX_TOKENS = 300  # per tree: containers stop growing past this, so a spec stays small


def tree(r, depth, out):
    k = r.random()
    if depth == 0 or k < 0.55 or len(out) > MAX_TOKENS:
        k = r.randrange(10)
        if k == 0: out.append("n")
        elif k == 1: out.append(r.choice("tf"))
        elif k < 4:
            v = r.choice(INTS) if r.random() < 0.5 else r.choice([-1, 1]) * (2 ** r.randint(0, 63) + r.randint(-2, 2))
            out += ["i", str(max(-2**63, min(2**64 - 1, v)))]
        elif k == 4: out += ["d", struct.pack(">d", r.choice(FLOATS) if r.random() < 0.5 else r.uniform(-1e9, 1e9)).hex()]
        elif k == 5: out += ["F", struct.pack(">f", r.choice(F32S + [r.uniform(-1e6, 1e6)])).hex()]
        elif k == 6: out += ["s", hx(rstr(r, r.choice(LENS[:-2])).encode())]
        elif k == 7: out += ["b", hx(r.randbytes(r.choice(LENS[:-2])))]
        elif k == 8: out += ["x", str(r.choice([0, 1, 5, 127, 100])), hx(r.randbytes(r.choice(LENS[:-2])))]
        else: out += ["T", str(r.choice([0, 1, 2**32 - 1, 2**32, 2**34 - 1, 2**34, -1, -2**40, 2**40, 1700000000, 2**62])),
                      str(r.choice([0, 1, 999999999, 500000000, 123456789]))]
        return
    n = r.choice([0, 1, 2, 3, 5, 15, 16, 17])
    if k < 0.8:
        out += ["a", str(n)]
        for _ in range(n): tree(r, depth - 1, out)
    else:
        out += ["m", str(n)]
        for _ in range(n):
            tree(r, 0, out); tree(r, depth - 1, out)


def gen(d, seed=20261104, n=2400):
    r = random.Random(seed)
    specs = []
    for _ in range(n):
        out = []
        tree(r, r.randint(1, 5), out)
        specs.append(" ".join(out))
    specs += ["a 65535 " + "n " * 65535, "a 65536 " + "n " * 65536, "m 65536 " + "i 1 n " * 65536, "a 16 " + "t " * 16, "m 15 " + "n n " * 15]
    specs += [f"i {v}" for v in INTS] + [f"s {hx(rstr(r, k).encode())}" for k in LENS] + [f"b {hx(r.randbytes(k))}" for k in LENS]
    specs += [f"x 3 {hx(r.randbytes(k))}" for k in LENS] + [f"T {s} {ns}" for s in (0, 2**32 - 1, 2**32, 2**34 - 1, 2**34, -1, 2**63 - 1, -2**63) for ns in (0, 1, 999999999)]
    with open(d + "/trees.spec", "w") as f:
        f.writelines(s + "\n" for s in specs)
    enc = [bytes.fromhex(encode(s)) for s in specs]
    dec = [e for e in enc]
    for e in [e for e in enc[:400] if len(e) <= 300][:150]:  # every proper prefix of a valid document is truncated, so it must raise
        dec += [e[:k] for k in range(len(e))]
    for e in [e for e in enc if len(e) <= 4096][:2000]:  # mutations: any outcome the oracle gives, the library must give
        b = bytearray(e)
        for _ in range(r.choice([1, 1, 2])):
            if b: b[r.randrange(len(b))] = r.choice([r.randrange(256), 0xC1, 0xC1, 0xFF, 0x00])
        dec.append(bytes(b))
    dec += [e + b"\x00" for e in enc[:50] if len(e) <= 4096]  # trailing bytes
    big = bytes.fromhex
    dec += [big(x) for x in (
        "dd" "ffffffff", "dd" "ffffffff" "c0", "df" "ffffffff", "df" "7fffffff" "c0c0", "db" "ffffffff", "c6" "ffffffff" "00",
        "c9" "ffffffff" "05", "c5" "ffff", "dc" "ffff" "c0", "de" "ffff" "c0c0", "da" "ffff" "41", "d9" "05" "4142", "c4" "01",
        "c1", "", "c7", "c7" "02", "d4", "d4" "01", "ca" "00", "cb" "000000", "cc", "d3" "00",
        "a1ff", "a2c080", "a3eda080", "a4f4908080", "a2c3", "a3e282", "a2c328", "a1" "80", "a4f0908080", "a4f08f8080", "a3e08080",
        "ca7fc00000", "caff800000", "cb7ff8000000000000", "cb7ff0000000000000", "ca00000001",
        "d6ff00000000", "d7ff0000000000000000", "c70cff" "000000000000000000000000", "c70cff" "3b9aca00" "0000000000000000", "d7ff" "ffffffff00000000",
        "c703ff000000", "d5ff0000", "c700ff", "c70500" "0102030405", "d4ff00", "d8800102030405060708090a0b0c0d0e0f10",
        "9190", "92" "c0", "81" "c0", "81" "c0c0", "80", "90", "dc0000", "de0000", "deffff", "c200", "00" "00",
    )]
    for depth in (1023, 1024, 1025, 1100):
        dec += [b"\x91" * depth + leaf for leaf in (b"\xc0", b"\x90", b"\x80")]
        dec.append(b"\x81\xc0" * depth + b"\xc0")  # maps nested as values
        dec.append((b"\x91\x81\xc0") * (depth // 2) + b"\xc0")  # alternating
    with open(d + "/dec.hex", "w") as f:
        f.writelines(hx(b) + "\n" for b in dec)
    print(len(specs), "trees", len(dec), "decode inputs")


if __name__ == "__main__":
    op = sys.argv[1]
    if op == "gen":
        gen(sys.argv[2])
    else:
        f = {"encode": encode, "decode": decode}[op]
        sys.stdout.write("".join(f(l.rstrip("\n")) + "\n" for l in open(sys.argv[2])))
