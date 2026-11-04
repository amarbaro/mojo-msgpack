#!/usr/bin/env bash
# tests/bench.mojo vs tools/bench_oracle.py, same records, 3 runs each: each prints its own timed work in ms;
# peak RSS of the whole process from getrusage. The Mojo decode builds a flat node table, Python builds objects.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work
.venv/bin/mojo build -I src tests/bench.mojo -o .work/bench 2>.work/build.err || { echo "FAIL build: tests/bench.mojo"; cat .work/build.err; exit 1; }
run() {
  systemd-run --user --scope -q -p MemoryMax=4G -p MemorySwapMax=0 .venv/bin/python -I -c 'import resource, subprocess, sys
out = subprocess.run(sys.argv[2:], capture_output=True, text=True, check=True).stdout.strip()
print("%-7s %s, peak RSS %d MB" % (sys.argv[1], out, resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss // 1024))' "$@" \
    || { echo "FAIL run: $1"; exit 1; }
}
for i in 1 2 3; do run mojo .work/bench; run python .venv/bin/python -I tools/bench_oracle.py; done
