"""Same work as tests/bench.mojo with Python msgpack (C extension): build the records untimed, time pack, then unpackb x5."""
import msgpack, time
N = 100_000
recs = [{"id": i, "name": "user%d" % i, "score": i * 0.5, "tags": [i % 7, "x", True, None]} for i in range(N)]
t0 = time.perf_counter()
b = msgpack.packb(recs, use_bin_type=True)
t1 = time.perf_counter()
for _ in range(5):
    o = msgpack.unpackb(b, raw=False)
t2 = time.perf_counter()
print("encode %d B %d ms; decode %d nodes x5 %d ms" % (len(b), (t1 - t0) * 1000, N * 13 + 1, (t2 - t1) * 1000))
