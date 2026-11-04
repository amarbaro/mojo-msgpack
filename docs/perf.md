# Performance

Rerun: `scripts/bench.sh` (builds `tests/bench.mojo`, runs it and `tools/bench_oracle.py` three times each,
4 GB cap, peak RSS from `getrusage`). Input: 100 000 records `{id, name, score, tags[4]}`, 4 857 439 bytes,
both sides produce the same byte count. Mojo 1.2.0, Python 3.14 with msgpack C extension, 7800X3D.

| | Mojo | Python msgpack |
|---|---|---|
| encode | 5 to 6 ms | 33 to 34 ms |
| decode x5 (1 300 001 nodes) | 110 to 119 ms | 308 to 320 ms |
| peak RSS | 81 MB | 139 MB |

Source `.work/mojo-msgpack-bench.txt` (3 runs). Python builds its records untimed; the Mojo decode makes a node
table, Python makes objects, so the decode ratio compares a table with a tree.

LOC: `src/msgpack/__init__.mojo` 305 lines, 269 without comments and blanks. `wc -l src/msgpack/*.mojo`.

One tuning: reserving the node table at `len(data)/4` cut decode from 181 ms to 115 ms and RSS from 112 to 81 MB.
