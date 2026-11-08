#!/usr/bin/env bash
# The gate. Fixtures from tools/oracle.py gen (seeded): 2503 trees and 9475 byte strings to decode. Our encode of
# every tree must equal Python msgpack's bytes; our decode of every byte string (valid, every prefix of 150 valid
# documents, 2000 mutants, length bombs, depth 1023 to 1100) must equal Python's tree or its error.
# Every run is capped at 4 GB. CASES="oracle" (the oracle as its own implementation) proves the gate; selfcheck.sh
# proves it fails on wrong code.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work
M=${MOJO:-.venv/bin/mojo}; PY=".venv/bin/python -I"
if systemd-run --user --scope -q true 2>/dev/null; then
  cap() { systemd-run --user --scope -q -p MemoryMax=4G -p MemorySwapMax=0 timeout 120 "$@"; }
else
  cap() { (ulimit -v 4194304; timeout 120 "$@"); }
fi
CASES=${CASES:-.work/cases}
if [[ $CASES == .work/cases ]]; then
  $M build -I src tests/cases.mojo -o .work/cases 2>.work/build.err || { echo "FAIL build: tests/cases.mojo"; cat .work/build.err; exit 1; }
else
  CASES="$PY tools/oracle.py"
fi
F=.work/fx
mkdir -p $F
[[ -f $F/trees.spec && -f $F/dec.hex ]] || cap $PY tools/oracle.py gen $F >/dev/null || { echo "FAIL setup: fixtures"; exit 1; }
for op in encode decode; do
  in=$F/trees.spec; [[ $op == decode ]] && in=$F/dec.hex
  rc=0; cap $CASES $op $in > .work/m.$op 2>.work/m.err || rc=$?
  (( rc == 0 )) || { echo "FAIL oracle: $op exit $rc (137 = over the 4 GB cap): $(head -c 300 .work/m.err)"; exit 1; }
  cap $PY tools/oracle.py $op $in > .work/o.$op || { echo "FAIL oracle: python $op"; exit 1; }
  cmp -s .work/m.$op .work/o.$op || { echo "FAIL oracle: $op line $(cmp .work/m.$op .work/o.$op | sed 's/.*line //') differs"; exit 1; }
  echo "oracle: $op $(wc -l < $in) inputs identical"
done
if [[ $CASES == .work/cases ]]; then
  cap $M run -I src tests/api.mojo || { echo "FAIL api: tests/api.mojo"; exit 1; }
  for t in examples/quickstart tests/docs; do
    [[ -f $t.mojo ]] && { cap $M run -I src $t.mojo > /dev/null || { echo "FAIL example: $t.mojo"; exit 1; }; }
  done
  # property smoke step: mojo-proptest from $PROPTEST, the sibling checkout, or a pinned fetch
  PT=$(scripts/proptest.sh)
  cap $M run -I src -I "$PT" tests/prop.mojo > /dev/null || { echo "FAIL prop: tests/prop.mojo"; exit 1; }
fi
echo "PASS all"
