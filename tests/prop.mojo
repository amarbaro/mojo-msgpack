# Property smoke step: encode then parse gives the values back, for random Int arrays (whole Int64 range) and string arrays.
from proptest import check, Lists, Strings, Ints
from msgpack import Encoder, parse


def ints(xs: List[Int]) raises -> Bool:
    var e = Encoder()
    e.array(len(xs))
    for x in xs:
        e.int(x)
    var d = parse(e.buf)
    for i in range(len(xs)):
        if d.int(i + 1) != xs[i]:
            return False
    return len(d.nodes) == len(xs) + 1


def strs(xs: List[String]) raises -> Bool:
    var e = Encoder()
    e.array(len(xs))
    for s in xs:
        e.str(s)
    var d = parse(e.buf)
    for i in range(len(xs)):
        if d.str(i + 1) != xs[i]:
            return False
    _ = len(e.buf)   # str views point into e.buf: e must outlive d
    return len(d.nodes) == len(xs) + 1


def main() raises:
    check(Lists(Ints(Int.MIN, Int.MAX), 20), ints, n=3000)
    check(Lists(Strings(40), 20), strs, n=3000)
    print("prop: ok")
