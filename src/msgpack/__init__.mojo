"""MessagePack for Mojo, pure Mojo. `Encoder` writes builtins straight into one buffer; `parse` reads a
Span into a flat `Doc` (nodes in preorder, str/bin/ext are views of the input, nothing is copied)."""
from std.bit import count_trailing_zeros
from std.memory import bitcast
from std.collections.string._utf8 import _is_valid_utf8

comptime NIL: UInt8 = 0
comptime BOOL: UInt8 = 1  # Node.v is 0 or 1
comptime INT: UInt8 = 2  # Node.v is the Int64 bits (negative, or up to Int64 max)
comptime UINT: UInt8 = 3  # Node.v is a UInt64 above Int64 max
comptime F32: UInt8 = 4  # Node.v is the Float64 bits (widened)
comptime F64: UInt8 = 5
comptime STR: UInt8 = 6  # Node.v is the offset into the input, Node.n the byte length
comptime BIN: UInt8 = 7
comptime EXT: UInt8 = 8  # as BIN, Node.ext is the type
comptime ARR: UInt8 = 9  # Node.n children follow; a MAP has 2n (key, value, ...)
comptime MAP: UInt8 = 10
comptime MAX_DEPTH = 1024  # arrays and maps on one path, the innermost included; Python msgpack's limit
comptime _Src = Span[UInt8, ImmUntrackedOrigin]


@always_inline
def _rd[n: Int](s: Span[UInt8, _], i: Int) -> UInt64:
    var v = UInt64(0)
    comptime for k in range(n):
        v = (v << 8) | UInt64(s[i + k])
    return v


struct Encoder(Movable):
    """Append-only; `buf` holds the bytes. Integers use the shortest form (non-negative ones unsigned,
    as Python msgpack), strings and bins the shortest header. Lengths above 2^32-1 raise."""

    var buf: List[UInt8]

    def __init__(out self, capacity: Int = 0):
        self.buf = List[UInt8](capacity=capacity)

    @always_inline
    def _be[n: Int](mut self, v: UInt64):
        comptime for i in range(n):
            self.buf.append(UInt8((v >> UInt64((n - 1 - i) * 8)) & 0xFF))

    @always_inline
    def _tb[n: Int](mut self, tag: UInt8, v: UInt64):
        self.buf.append(tag)
        self._be[n](v)

    def nil(mut self):
        self.buf.append(0xC0)

    def bool(mut self, v: Bool):
        self.buf.append(UInt8(0xC3) if v else UInt8(0xC2))

    def uint(mut self, v: UInt64):
        if v < 128:
            self.buf.append(UInt8(v))
        elif v < 1 << 8:
            self._tb[1](0xCC, v)
        elif v < 1 << 16:
            self._tb[2](0xCD, v)
        elif v < 1 << 32:
            self._tb[4](0xCE, v)
        else:
            self._tb[8](0xCF, v)

    def int(mut self, v: Int):
        if v >= 0:
            self.uint(UInt64(v))
        elif v >= -32:
            self.buf.append(UInt8(v & 0xFF))
        elif v >= -128:
            self._tb[1](0xD0, UInt64(v))
        elif v >= -32768:
            self._tb[2](0xD1, UInt64(v))
        elif v >= -2147483648:
            self._tb[4](0xD2, UInt64(v))
        else:
            self._tb[8](0xD3, UInt64(v))

    def f32(mut self, v: Float32):
        self._tb[4](0xCA, UInt64(bitcast[DType.uint32](v)))

    def f64(mut self, v: Float64):
        self._tb[8](0xCB, bitcast[DType.uint64](v))

    def _head(mut self, n: Int, fix: UInt8, t8: UInt8, t16: UInt8, t32: UInt8, lim: Int) raises:
        """Header with the shortest length form: fix|n below lim, else tag t8 (0 = none), t16, t32."""
        if n < lim:
            self.buf.append(fix | UInt8(n))
        elif t8 != 0 and n < 1 << 8:
            self._tb[1](t8, UInt64(n))
        elif n < 1 << 16:
            self._tb[2](t16, UInt64(n))
        elif n < 1 << 32:
            self._tb[4](t32, UInt64(n))
        else:
            raise Error("msgpack: length ", n, " exceeds 2^32-1")

    def str(mut self, s: StringSlice) raises:
        self._head(s.byte_length(), 0xA0, 0xD9, 0xDA, 0xDB, 32)
        self.buf.extend(s.as_bytes())

    def bin(mut self, b: Span[UInt8, _]) raises:
        self._head(len(b), 0, 0xC4, 0xC5, 0xC6, 0)
        self.buf.extend(b)

    def array(mut self, n: Int) raises:
        """Header for n items; the caller then writes n values."""
        self._head(n, 0x90, 0, 0xDC, 0xDD, 16)

    def map(mut self, n: Int) raises:
        """Header for n pairs; the caller then writes n keys and values, alternating."""
        self._head(n, 0x80, 0, 0xDE, 0xDF, 16)

    def ext(mut self, typ: Int8, b: Span[UInt8, _]) raises:
        var n = len(b)
        if n == 1 or n == 2 or n == 4 or n == 8 or n == 16:
            self.buf.append(UInt8(0xD4 + count_trailing_zeros(n)))
        else:
            self._head(n, 0, 0xC7, 0xC8, 0xC9, 0)
        self.buf.append(UInt8(Int(typ) & 0xFF))
        self.buf.extend(b)

    def timestamp(mut self, sec: Int, nsec: Int = 0) raises:
        """Ext -1 in the shortest of the 32, 64 and 96 bit forms."""
        if nsec < 0 or nsec > 999999999:
            raise Error("msgpack: nanoseconds ", nsec, " out of range")
        var d = (UInt64(nsec) << 34) | UInt64(sec)
        if sec >> 34 != 0:
            self.buf.append(0xC7)
            self.buf.append(0x0C)
            self._tb[4](0xFF, UInt64(nsec))
            self._be[8](UInt64(sec))
        elif d >> 32 == 0:
            self.buf.append(0xD6)
            self._tb[4](0xFF, d)
        else:
            self.buf.append(0xD7)
            self._tb[8](0xFF, d)


@fieldwise_init
struct Node(TrivialRegisterPassable):
    """16 bytes. `n` is the byte length of a STR, BIN or EXT, the child count of an ARR or MAP."""

    var v: UInt64
    var n: UInt32
    var size: UInt32  # nodes in this subtree, itself included: the next sibling is at i + size
    var kind: UInt8
    var ext: Int8


struct Doc(Movable):
    """A parsed document: `nodes` in preorder, node 0 the root, a map's children alternating key, value.
    The input must outlive the Doc; STR, BIN and EXT point into it."""

    var nodes: List[Node]
    var src: _Src

    def __init__(out self, src: _Src):
        self.nodes = List[Node]()
        self.src = src

    def bytes(self, i: Int) -> _Src:
        var k = self.nodes[i]
        return _Src(unsafe_ptr=self.src.unsafe_ptr().unsafe_offset(Int(k.v)), length=Int(k.n))

    def str(self, i: Int) -> StringSlice[ImmUntrackedOrigin]:
        return StringSlice(unsafe_from_utf8=self.bytes(i))

    def int(self, i: Int) -> Int:
        """An INT; a UINT above Int64 max wraps, read `nodes[i].v` for it."""
        return Int(self.nodes[i].v)

    def f64(self, i: Int) -> Float64:
        return bitcast[DType.float64](self.nodes[i].v)

    def timestamp(self, i: Int) raises -> Tuple[Int, Int]:
        """(seconds, nanoseconds) of an ext -1 of 4, 8 or 12 bytes."""
        var k = self.nodes[i]
        var b = self.bytes(i)
        if k.kind != EXT or k.ext != -1 or (k.n != 4 and k.n != 8 and k.n != 12):
            raise Error("msgpack: node ", i, " is not a timestamp")
        var sec = Int(_rd[4](b, 0))
        var nsec = 0
        if k.n == 8:
            var d = _rd[8](b, 0)
            sec = Int(d & ((1 << 34) - 1))
            nsec = Int(d >> 34)
        elif k.n == 12:
            nsec = sec
            sec = Int(_rd[8](b, 4))
        if nsec > 999999999:
            raise Error("msgpack: timestamp nanoseconds ", nsec, " out of range")
        return (sec, nsec)


def parse(data: Span[UInt8, _]) raises -> Doc:
    """Reads exactly one value. Raises on truncated input, a length that overruns it, invalid UTF-8 in a
    str, the reserved byte 0xc1, nesting past MAX_DEPTH and trailing bytes. Nothing is allocated for a
    length the input cannot hold."""
    var n = len(data)
    var d = Doc(_Src(unsafe_ptr=Pointer[UInt8, ImmUntrackedOrigin](unsafe_from_address=Int(data.unsafe_ptr())), length=n))
    d.nodes.reserve(n // 4 + 1)
    var open = List[Int]()  # node index of each open container
    var rest = List[Int]()  # its parent's items left, counting it
    var left = 1
    var p = 0
    while True:
        if p >= n:
            raise Error("msgpack: truncated at byte ", p)
        var t = data[p]
        p += 1
        var kind = INT
        var v = UInt64(0)
        var ln = 0
        var ext = Int8(0)
        if t < 0x80:
            v = UInt64(t)
        elif t >= 0xE0:
            v = UInt64(Int(t) - 256)
        elif t < 0xA0:
            kind = MAP if t < 0x90 else ARR
            ln = Int(t & 15)
        elif t < 0xC0:
            kind = STR
            ln = Int(t & 31)
        elif t < 0xC4:
            if t == 0xC1:
                raise Error("msgpack: reserved byte 0xc1 at ", p - 1)
            kind = NIL if t == 0xC0 else BOOL
            v = UInt64(t & 1)
        else:
            var w = 0  # bytes of length or value that follow the tag
            if t <= 0xC9:
                kind = BIN if t < 0xC7 else EXT
                w = 1 << Int((t - 0xC4) % 3)
            elif t <= 0xCB:
                kind = F32 if t == 0xCA else F64
                w = 4 if t == 0xCA else 8
            elif t <= 0xCF:
                kind = UINT
                w = 1 << Int(t - 0xCC)
            elif t <= 0xD3:
                w = 1 << Int(t - 0xD0)
            elif t <= 0xD8:
                kind = EXT
                ln = 1 << Int(t - 0xD4)
            elif t <= 0xDB:
                kind = STR
                w = 1 << Int(t - 0xD9)
            else:
                kind = ARR if t < 0xDE else MAP
                w = 2 if t & 1 == 0 else 4
            if w > n - p:
                raise Error("msgpack: truncated at byte ", n)
            var x = UInt64(0)
            for k in range(w):
                x = (x << 8) | UInt64(data[p + k])
            p += w
            if kind == INT:
                var sh = 64 - 8 * w
                v = UInt64(Int(x << UInt64(sh)) >> sh)
            elif kind == UINT:
                v = x
                kind = UINT if x >> 63 != 0 else INT
            elif kind == F32:
                v = bitcast[DType.uint64](Float64(bitcast[DType.float32](UInt32(x))))
            elif kind == F64:
                v = x
            elif w != 0:
                ln = Int(x)
        if kind == EXT:
            if p >= n:
                raise Error("msgpack: truncated at byte ", p)
            ext = Int8(Int(data[p]) - (256 if data[p] > 127 else 0))
            p += 1
        if kind == STR or kind == BIN or kind == EXT:
            if ln > n - p:
                raise Error("msgpack: length ", ln, " at byte ", p, " overruns the input")
            if kind == STR and not _is_valid_utf8(data[p : p + ln]):
                raise Error("msgpack: invalid UTF-8 in str at byte ", p)
            v = UInt64(p)
            p += ln
        elif kind == ARR or kind == MAP:
            if ln * (2 if kind == MAP else 1) > n - p:
                raise Error("msgpack: count ", ln, " at byte ", p, " overruns the input")
        d.nodes.append(Node(v, UInt32(ln), 1, kind, ext))
        if (kind == ARR or kind == MAP) and len(open) >= MAX_DEPTH:  # an empty one counts, as in Python msgpack
            raise Error("msgpack: nesting deeper than ", MAX_DEPTH)
        if (kind == ARR or kind == MAP) and ln > 0:
            open.append(len(d.nodes) - 1)
            rest.append(left)
            left = ln * (2 if kind == MAP else 1)
            continue
        left -= 1
        while left == 0:
            if len(open) == 0:
                if p != n:
                    raise Error("msgpack: ", n - p, " trailing bytes at ", p)
                return d^
            var j = open.pop()
            d.nodes[j].size = UInt32(len(d.nodes) - j)
            left = rest.pop() - 1
