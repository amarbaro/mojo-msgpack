# Behaviour the oracle diff cannot show: errors are raised, extension codes below -1, the shortest forms.
from msgpack import *


def bad(h: List[UInt8], what: String) raises:
    try:
        _ = parse(h)
    except e:
        if String(e).startswith("msgpack: "):
            return
    raise Error("api: " + what + " did not raise msgpack: ...")


def main() raises:
    bad([UInt8(0x92), 0xC0], "truncated array")
    bad([UInt8(0xDD), 0xFF, 0xFF, 0xFF, 0xFF], "4G-item array in 5 bytes")
    bad([UInt8(0xC1)], "reserved byte")
    bad([UInt8(0xC0), 0xC0], "trailing byte")
    bad([UInt8(0xA1), 0xFF], "invalid UTF-8")
    bad(List[UInt8](), "empty input")
    var deep = List[UInt8](length=1026, fill=0x91)
    deep[1025] = 0xC0
    bad(deep, "1025 nested arrays")
    var e = Encoder()
    var three: List[UInt8] = [1, 2, 3]
    e.ext(-100, three)
    e.uint(UInt64.MAX)
    e.int(-33)
    e.int(Int.MIN)
    var d = parse(e.buf[0:6])
    if d.nodes[0].ext != -100 or d.nodes[0].kind != EXT or len(d.bytes(0)) != 3:
        raise Error("api: ext -100 round trip")
    var u = parse(e.buf[6:15])
    if u.nodes[0].kind != UINT or u.nodes[0].v != UInt64.MAX:
        raise Error("api: UInt64 max round trip")
    if e.buf[15] != 0xD0 or e.buf[16] != 0xDF or e.buf[17] != 0xD3:
        raise Error("api: -33 and Int.MIN not in the shortest signed form")
    var t = Encoder()
    t.timestamp(-1, 999999999)
    var ts = parse(t.buf)
    var sec = ts.timestamp(0)[0]
    _ = len(t.buf)  # the Doc points into t.buf: keep it alive past the last use of the Doc
    if sec != -1:
        raise Error("api: negative-second timestamp")
    print("api: ok")
