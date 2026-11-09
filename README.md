# mojo-msgpack

<!-- badges -->
[![ci](https://github.com/amarbaro/mojo-msgpack/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/amarbaro/mojo-msgpack/actions/workflows/ci.yml) [![latest release](https://img.shields.io/github/v/release/amarbaro/mojo-msgpack)](https://github.com/amarbaro/mojo-msgpack/releases/latest) [![license](https://img.shields.io/github/license/amarbaro/mojo-msgpack)](https://github.com/amarbaro/mojo-msgpack/blob/main/LICENSE) [![checks](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/amarbaro/mojo-msgpack/badges/checks.json)](https://github.com/amarbaro/mojo-msgpack/actions/workflows/ci.yml)
<!-- /badges -->

<!-- install -->
Install: `pixi workspace channel add https://conda.modular.com/max https://prefix.dev/amarbaro/amarbaro`, then `pixi add mojo-msgpack` (import `msgpack`). From source: `git clone https://github.com/amarbaro/mojo-msgpack`, then `mojo run -I mojo-msgpack/src app.mojo`.
Toolchains: Mojo 1.2 stable, and the nightly 1.3.0.dev2026110805 in the weekly [mojo-libs](https://github.com/amarbaro/mojo-libs) matrix (36 libraries on stable, 35 on nightly).

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
<!-- /install -->

MessagePack for Mojo, pure Mojo: `Encoder` writes builtins straight into one buffer, `parse` reads a
`Span[UInt8]` into a flat node table whose str, bin and ext values are views of the input (nothing copied).
305 lines, no dependencies. Every encode and decode result is checked against Python `msgpack`
on 2503 trees and 9475 byte strings, including truncated, mutated, oversized-length and too-deep input.

Requires Mojo 1.2.

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

Docs: [api](docs/api.md), [design](docs/design.md), [perf](docs/perf.md). The example above is
`examples/quickstart.mojo` and the one in the API doc is `tests/docs.mojo`; the gate runs both.

**Limits:** No streaming parse, no map-key lookup helper, no owned value tree; nesting is capped at depth 1024 (Python msgpack's limit). A `Doc` points into the input and does not own it: use the input after the Doc's last use (`_ = len(buf)`). Decoding takes 16 bytes per node besides the input.

## Checks

| Script | What |
|---|---|
| `scripts/check.sh` | encode of 2503 trees and decode of 9475 byte strings identical to `tools/oracle.py`; API errors; the doc examples; every run capped at 4 GB |
| `scripts/selfcheck.sh` | 6 mutants (boundary, depth, UTF-8, trailing bytes, timestamp form, length) all rejected |
| `scripts/bench.sh` | the numbers above |
| `scripts/ci.sh` | install and gate, same on GitHub and a local VM |

Not covered by the oracle: extension codes below -1 (Python refuses them, `tests/api.mojo` checks one) and
lengths above 2^32-1 on encode.

## License

Apache-2.0.
