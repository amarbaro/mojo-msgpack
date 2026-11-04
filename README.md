# mojo-msgpack

MessagePack for Mojo, pure Mojo: `Encoder` writes builtins straight into one buffer, `parse` reads a
`Span[UInt8]` into a flat node table whose str, bin and ext values are views of the input (nothing copied).
305 lines, no dependencies. Every encode and decode result is checked against Python `msgpack`
on 2503 trees and 9475 byte strings, including truncated, mutated, oversized-length and too-deep input.

```mojo
from msgpack import Encoder, parse


def main() raises:
    var e = Encoder()
    e.map(2)
    e.str("name"); e.str("héllo")
    e.str("when"); e.timestamp(1700000000, 5)
    var d = parse(e.buf)  # str and bin are views into e.buf: e must outlive d
    print(len(d.nodes), d.str(2), d.timestamp(4)[0])
    _ = len(e.buf)
```

## Install

Requires Mojo 1.2.

| Way | Command |
|---|---|
| Source path | `mojo run -I path/to/mojo-msgpack/src app.mojo` |
| Precompiled | `mojo precompile src/msgpack -o msgpack.mojoc` |
| Vendor | copy `src/msgpack/` into your project |

## What you get

- `Encoder`: `nil bool int uint f32 f64 str bin array map ext timestamp`, shortest form for every length and
  integer, byte-identical to Python `msgpack.packb(use_bin_type=True)`. `array(n)` and `map(n)` write the header;
  you then write the items.
- `parse(data)`: one value, raises on truncated input, a length or count that overruns the input (nothing is
  allocated for it), invalid UTF-8 in a str, byte `0xc1`, trailing bytes, nesting past 1024.
- `Doc`: `nodes` in preorder (16 bytes each, `size` jumps to the next sibling), `str(i)`, `bytes(i)`, `int(i)`,
  `f64(i)`, `timestamp(i)`.
- Errors start with `msgpack: ` and name the byte.

## Performance

`scripts/bench.sh` (`tests/bench.mojo` vs `tools/bench_oracle.py`, 100 000 records, 4.86 MB, 3 runs):

| | Mojo | Python msgpack (C ext) |
|---|---|---|
| encode | 5 to 6 ms | 33 to 34 ms |
| decode x5 | 110 to 119 ms | 308 to 320 ms |
| peak RSS | 81 MB | 139 MB |

The Mojo decode builds the node table; Python builds objects.

## Checks

| Script | What |
|---|---|
| `scripts/check.sh` | encode of 2503 trees and decode of 9475 byte strings identical to `tools/oracle.py`; API errors; every run capped at 4 GB |
| `scripts/selfcheck.sh` | 6 mutants (boundary, depth, UTF-8, trailing bytes, timestamp form, length) all rejected |
| `scripts/bench.sh` | the numbers above |
| `scripts/ci.sh` | install and gate, same on GitHub and a local VM |

Not covered by the oracle: extension codes below -1 (Python refuses them, `tests/api.mojo` checks one) and
lengths above 2^32-1 on encode.

## License

Apache-2.0.
