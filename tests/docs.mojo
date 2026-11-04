# The example in docs/api.md, with its output checked.
from msgpack import Encoder, parse, ARR


def main() raises:
    var e = Encoder()
    e.array(3)
    e.int(-5); e.bin(Span("ab".as_bytes())); e.nil()
    var d = parse(e.buf)
    var second = 1 + Int(d.nodes[1].size)  # skip the first child
    if not (d.nodes[0].kind == ARR and d.int(1) == -5 and len(d.bytes(second)) == 2 and second == 2):
        raise Error("docs: api.md example output changed")
    _ = len(e.buf)
