# API

`from msgpack import ...`. Every function that can fail is marked `raises`; errors read `msgpack: <what> at byte <n>`.

## Encoder

`struct Encoder(Movable)`: append-only, the bytes are `buf: List[UInt8]`.

| Call | Does | Raises |
|---|---|---|
| `Encoder(capacity: Int = 0)` | empty buffer, optional reserve | no |
| `nil()` | `c0` | no |
| `bool(v: Bool)` | `c2` or `c3` | no |
| `int(v: Int)` | shortest form; non-negative ones unsigned, as Python | no |
| `uint(v: UInt64)` | shortest unsigned form up to 2^64-1 | no |
| `f32(v: Float32)`, `f64(v: Float64)` | `ca` / `cb`, bits kept | no |
| `str(s: StringSlice)` | shortest str header + bytes | length above 2^32-1 |
| `bin(b: Span[UInt8])` | shortest bin header + bytes | length above 2^32-1 |
| `array(n: Int)`, `map(n: Int)` | header for n items / n pairs; you then write them (a map: key, value, key, value) | n above 2^32-1 |
| `ext(typ: Int8, b: Span[UInt8])` | fixext for 1, 2, 4, 8, 16 bytes, else ext 8/16/32 | length above 2^32-1 |
| `timestamp(sec: Int, nsec: Int = 0)` | ext -1 in the 32, 64 or 96 bit form | nsec outside 0..999999999 |

## Parser

`parse(data: Span[UInt8]) raises -> Doc`: exactly one value. Raises on truncated input, a length or count that
overruns the input, invalid UTF-8 in a str, byte `c1`, trailing bytes, nesting past `MAX_DEPTH` (1024, the
innermost array or map included).

`struct Doc(Movable)`: `nodes: List[Node]` in preorder, node 0 the root. The input must outlive the Doc and be
kept alive past its last use (hold it in a variable and touch it after, as `examples/quickstart.mojo` does).

| Call | Returns |
|---|---|
| `bytes(i)` | `Span[UInt8]` view of a STR, BIN or EXT payload |
| `str(i)` | `StringSlice` view of a STR |
| `int(i)` | `Int` of an INT; a UINT above Int64 max wraps, read `nodes[i].v` |
| `f64(i)` | `Float64` of an F32 (widened) or F64 |
| `timestamp(i) raises` | `(seconds, nanoseconds)` of an ext -1 with 4, 8 or 12 bytes; raises otherwise or on nanoseconds above 999999999 |

`struct Node` (16 bytes): `kind`, `v`, `n`, `size`, `ext`.

| `kind` | `v` | `n` |
|---|---|---|
| `NIL` | 0 | 0 |
| `BOOL` | 0 or 1 | 0 |
| `INT` | Int64 bits | 0 |
| `UINT` | UInt64, above Int64 max | 0 |
| `F32`, `F64` | Float64 bits | 0 |
| `STR`, `BIN`, `EXT` | offset into the input (`ext` holds the type) | byte length |
| `ARR`, `MAP` | 0 | children (a map has 2n nodes below it) |

`size` = nodes in the subtree, itself included: the next sibling of node `i` is `i + nodes[i].size`.

## Example

```mojo
from msgpack import Encoder, parse, ARR


def main() raises:
    var e = Encoder()
    e.array(3)
    e.int(-5); e.bin(Span("ab".as_bytes())); e.nil()
    var d = parse(e.buf)
    var second = 1 + Int(d.nodes[1].size)  # skip the first child
    print(d.nodes[0].kind == ARR, d.int(1), len(d.bytes(second)), second)
    _ = len(e.buf)
```
