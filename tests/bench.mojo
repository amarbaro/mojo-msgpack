# Encode 100k records {id, name, score, tags[4]} (about 5 MB), decode them 5 times. Same work as tools/bench_oracle.py.
from std.sys import argv
from std.time import perf_counter_ns
from msgpack import *

comptime N = 100_000


def main() raises:
    var t0 = perf_counter_ns()
    var e = Encoder(capacity=6_000_000)
    e.array(N)
    for i in range(N):
        e.map(4)
        e.str("id"); e.int(i)
        e.str("name"); e.str("user" + String(i))
        e.str("score"); e.f64(Float64(i) * 0.5)
        e.str("tags"); e.array(4); e.int(i % 7); e.str("x"); e.bool(True); e.nil()
    var t1 = perf_counter_ns()
    var nodes = 0
    for _ in range(5):
        nodes += len(parse(e.buf).nodes)
    var t2 = perf_counter_ns()
    print("encode", len(e.buf), "B", (t1 - t0) // 1_000_000, "ms; decode", nodes // 5, "nodes x5", (t2 - t1) // 1_000_000, "ms")
