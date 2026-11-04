---
name: mojo-msgpack
description: "MessagePack encode and decode in pure Mojo: an Encoder and a zero-copy parse into a flat node table. Use when a Mojo program reads or writes msgpack bytes, byte-identical with Python msgpack.packb(use_bin_type=True)."
metadata:
  short-description: "MessagePack for Mojo: Encoder plus zero-copy parse into a flat node table"
---

# mojo-msgpack

One file, `src/msgpack/__init__.mojo`, Mojo 1.2, no dependencies. Every call is in `docs/api.md`.

## When to use

Write or read MessagePack (RPC, cache files, interchange with Python `msgpack`).
Not for streaming parse or an owned object tree.

## Install

`mojo run -I src app.mojo` from a clone, or copy `src/msgpack/`.

## The calls

```mojo
from msgpack import Encoder, parse, MAP

def main() raises:
    var e = Encoder()                      # the bytes are e.buf
    e.map(2)                               # array(n) / map(n) write the header, you write the items
    e.str("k"); e.int(-1)
    e.str("t"); e.timestamp(1700000000, 5)   # also nil bool uint f32 f64 bin ext
    var d = parse(e.buf)                   # one value; raises on any malformed input
    print(d.nodes[0].kind == MAP, d.str(1), d.int(2), d.timestamp(4)[0])
    # flat preorder table: the next sibling of node i is i + d.nodes[i].size
    _ = len(e.buf)                         # keep the input alive past the last use of d
```

## Gotchas

- **The `Doc` does not own its input.** `str`, `bytes` and `timestamp` read the buffer you parsed. Mojo frees a
  variable after its last use, so bind the input and end with `_ = len(b)`.
- `parse` raises on malformed input and on nesting past `MAX_DEPTH` (1024); catch it for untrusted bytes.
- `array(n)` and `map(n)` only write the header: a map takes `2n` items (key, value, ...).
- `d.nodes[i].size` counts the node itself and all descendants; use it to skip a subtree.
- `Encoder.str` and `bin` raise past the 4 GiB format limit.

## Gate

`scripts/check.sh` from the repo: oracle diff against Python `msgpack` over generated trees and decode inputs,
API test, doc examples. `scripts/selfcheck.sh` (mutants must fail it), `scripts/bench.sh`.
