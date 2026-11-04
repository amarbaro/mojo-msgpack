# Design

## Why pure Mojo, no system library
MessagePack is a few dozen tag bytes and big-endian integers. A C library would add a loader, a dependency and
a copy at the boundary for no gain. The whole library is one file, 305 lines.

## Encoder
- One `List[UInt8]`, append only. No intermediate tree: you call `array(n)` and write n values.
- Shortest form everywhere (`_head` picks fix, 8, 16 or 32 bit length), so output equals Python
  `packb(use_bin_type=True)`; the gate diffs 2503 trees byte for byte.
- Every header size is a comptime parameter (`_be[n]`, `_tb[n]`), so the byte loops unroll.

## Parser
- One pass, one `List[Node]`, no recursion: open containers sit in two small lists (`open`, `rest`), so depth
  costs 16 bytes of stack-free bookkeeping, and the 1024 limit (Python msgpack's) is a counter check.
- `Node` is 16 bytes: kind, a 64-bit payload, a count/length, and the subtree `size` that makes skipping a
  subtree O(1). str, bin and ext store an offset into the input, not a copy.
- Every length is checked against the bytes left before anything is reserved, so `dd ffffffff` (4 billion items
  in 5 bytes) raises at once. The node table is reserved at `len(data)/4`, which is at most 4x the input.
- UTF-8 of every str is validated (`std` `_is_valid_utf8`), as Python does; bin and ext are not.

## Memory model
- The Doc holds a raw pointer to the input and does not own it. Mojo destroys a variable after its last use, so
  if the input is not used after the Doc's last use it may be freed early. Touch the input last
  (`_ = len(buf)`); `examples/quickstart.mojo` and the tests do.
- Decode of 4.86 MB peaks at 81 MB (1.3 M nodes, 16 bytes each, plus the input and the encoder buffer).

## Not done on purpose
- No `Value` tree of owned objects (each would copy); the node table is the value type.
- No streaming parse, no map-key lookup helper, no timestamp check at parse time (`timestamp(i)` checks).
