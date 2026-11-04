# One operation per run, printing what tools/oracle.py prints for the same arguments:
#   encode SPECFILE -> per line the hex of the encoded bytes
#   decode HEXFILE  -> per line the decoded tree as tokens, or ERR
from std.sys import argv
from msgpack import *

comptime HEXD = "0123456789abcdef"


def nib(c: UInt8) -> UInt8:
    return c - 48 if c < 58 else c - 87


def be(b: List[UInt8]) -> UInt64:
    var v = UInt64(0)
    for x in b:
        v = (v << 8) | UInt64(x)
    return v


def unhex(s: StringSlice) -> List[UInt8]:
    var o = List[UInt8]()
    if s == "-":
        return o^
    var b = s.as_bytes()
    for i in range(0, len(b), 2):
        o.append(nib(b[i]) * 16 + nib(b[i + 1]))
    return o^


def hx(b: Span[UInt8, _], mut out: String):
    if len(b) == 0:
        out += "-"
    for x in b:
        out += chr(Int(HEXD.as_bytes()[Int(x >> 4)]))
        out += chr(Int(HEXD.as_bytes()[Int(x & 15)]))


def num(s: StringSlice) -> Int:  # decimal, may be negative or up to 2^64-1 (wraps)
    var neg = s.startswith("-")
    var v = UInt64(0)
    for c in s.as_bytes():
        if c != 45:
            v = v * 10 + UInt64(Int(c) - 48)
    return Int(0 - v) if neg else Int(v)


def encode(line: String) raises -> String:
    var t = line.split()
    var e = Encoder()
    var i = 0
    while i < len(t):
        var k = t[i]
        i += 1
        if k == "n":
            e.nil()
        elif k == "t" or k == "f":
            e.bool(k == "t")
        elif k == "i":
            if t[i].startswith("-") or t[i].byte_length() < 19:
                e.int(num(t[i]))
            else:  # above Int64 max: unsigned
                e.uint(UInt64(num(t[i])))
            i += 1
        elif k == "d":
            var b = unhex(t[i])
            e.f64(bitcast[DType.float64](be(b)))
            i += 1
        elif k == "F":
            var b = unhex(t[i])
            e.f32(bitcast[DType.float32](UInt32(be(b))))
            i += 1
        elif k == "s":
            var b = unhex(t[i])
            e.str(StringSlice(unsafe_from_utf8=Span(b)))
            i += 1
        elif k == "b":
            e.bin(Span(unhex(t[i])))
            i += 1
        elif k == "a":
            e.array(num(t[i]))
            i += 1
        elif k == "m":
            e.map(num(t[i]))
            i += 1
        elif k == "x":
            e.ext(Int8(num(t[i])), Span(unhex(t[i + 1])))
            i += 2
        else:
            e.timestamp(num(t[i]), num(t[i + 1]))
            i += 2
    var o = String()
    hx(e.buf, o)
    return o^


def dump(d: Doc, i: Int, mut o: String) raises:
    var k = d.nodes[i]
    if k.kind == NIL:
        o += "n"
    elif k.kind == BOOL:
        o += "t" if k.v == 1 else "f"
    elif k.kind == INT:
        o += "i " + String(d.int(i))
    elif k.kind == UINT:
        o += "i " + String(k.v)
    elif k.kind == F32 or k.kind == F64:
        o += "d "
        var w = List[UInt8]()
        for j in range(8):
            w.append(UInt8((k.v >> UInt64(56 - 8 * j)) & 255))
        hx(w, o)
    elif k.kind == STR or k.kind == BIN:
        o += "s " if k.kind == STR else "b "
        hx(d.bytes(i), o)
    elif k.kind == EXT:
        if k.ext == -1:
            var ts = d.timestamp(i)
            o += "T " + String(ts[0]) + " " + String(ts[1])
        else:
            o += "x " + String(Int(k.ext)) + " "
            hx(d.bytes(i), o)
    else:
        o += ("a " if k.kind == ARR else "m ") + String(Int(k.n))
        var c = i + 1
        for _ in range(Int(k.n) * (2 if k.kind == MAP else 1)):
            o += " "
            dump(d, c, o)
            c += Int(d.nodes[c].size)


def decode(line: String) -> String:
    try:
        var b = unhex(line)
        var d = parse(b)
        var o = String()
        dump(d, 0, o)
        _ = len(b)  # Doc points into b: keep it alive past the last use
        return o^
    except:
        return "ERR"


def main() raises:
    var a = argv()
    var enc = String(a[1]) == "encode"
    var out = String()
    with open(String(a[2]), "r") as f:
        for line in f.read().splitlines():
            out += encode(String(line)) if enc else decode(String(line))
            out += "\n"
    print(out, end="")
