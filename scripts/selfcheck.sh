#!/usr/bin/env bash
# Proves the gate rejects wrong code: each mutant is applied to a copy of the tree and scripts/check.sh must FAIL
# on it. Then the oracle as its own implementation must pass the oracle part.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
export PROPTEST=${PROPTEST:-$ROOT/../mojo-proptest/src}   # mutant trees live in .work/, so the sibling path must be absolute
F=src/msgpack/__init__.mojo
mutants=(
  "$F|        elif v >= -32:|        elif v >= -31:|negative fixint boundary"
  "$F|(kind == ARR or kind == MAP) and len(open) >= MAX_DEPTH|(kind == ARR or kind == MAP) and len(open) > MAX_DEPTH|depth limit off by one"
  "$F|            if kind == STR and not _is_valid_utf8(data[p : p + ln]):|            if False:|UTF-8 not checked"
  "$F|                if p != n:|                if False:|trailing bytes accepted"
  "$F|        elif d >> 32 == 0:|        elif d >> 33 == 0:|timestamp 32 bit form too wide"
  "$F|            self._tb[2](t16, UInt64(n))|            self._tb[2](t16, UInt64(n + 1))|16 bit length wrong"
)
for m in "${mutants[@]}"; do
  IFS='|' read -r file from to why <<< "$m"
  d=$ROOT/.work/mutant; rm -rf "$d"; mkdir -p "$d/.work"
  cp -r src tests tools scripts examples "$d"; ln -s "$ROOT/.venv" "$d/.venv"; ln -s "$ROOT/.work/fx" "$d/.work/fx"
  .venv/bin/python -I -c 'import sys; p,a,b=sys.argv[1:]; s=open(p).read(); assert a in s, "mutant does not apply: "+a; open(p,"w").write(s.replace(a,b,1))' "$d/$file" "$from" "$to" \
    || { echo "FAIL selfcheck: mutant does not apply ($why)"; exit 1; }
  if "$d/scripts/check.sh" > "$d.log" 2>&1; then echo "FAIL selfcheck: gate passed a mutant ($why)"; exit 1; fi
  echo "selfcheck: rejected ($why): $(grep -m1 FAIL "$d.log" | cut -c1-110)"
done
CASES=oracle scripts/check.sh > .work/oracle-self.log 2>&1 || { echo "FAIL selfcheck: oracle fails its own gate"; tail -3 .work/oracle-self.log; exit 1; }
echo "PASS selfcheck"
