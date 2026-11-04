#!/usr/bin/env bash
# Print the path of mojo-proptest's src/ for the property smoke step: $PROPTEST, else the sibling checkout,
# else a fetch of the pinned commit into .work/deps (what CI does: it checks out this repo only).
set -euo pipefail
cd "$(dirname "$0")/.."
sha=8f9fe35ea718dd67d8677052e12f30463915cbeb
if [[ -n ${PROPTEST:-} ]]; then echo "$PROPTEST"; exit 0; fi
if [[ -d ../mojo-proptest/src ]]; then echo "$(cd ../mojo-proptest/src && pwd)"; exit 0; fi
d=.work/deps/mojo-proptest
if [[ $(git -C "$d" rev-parse HEAD 2>/dev/null) != "$sha" ]]; then
  rm -rf "$d" && git init -q "$d"
  { git -C "$d" fetch -q --depth 1 https://github.com/amarbaro/mojo-proptest "$sha" && git -C "$d" checkout -q FETCH_HEAD; } >&2 \
    || { echo "FAIL setup: fetch mojo-proptest $sha" >&2; exit 1; }
fi
echo "$PWD/$d/src"
