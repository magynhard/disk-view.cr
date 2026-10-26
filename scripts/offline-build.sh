#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
prefix="${1:-/usr}"
patch --forward --batch -p1 -d lib/gi-crystal < packaging/patches/gi-crystal-offline-version.patch
for directory in lib/*/; do
    ln -sfn .. "${directory}lib"
done
mkdir -p bin
export CRYSTAL_LIBRARY_PATH="$(pkg-config --variable=libdir bdw-gc)"
(cd lib/gi-crystal && crystal build src/generator/main.cr --no-debug -o ../../bin/gi-crystal)
./bin/gi-crystal
crystal tool format --check src/ spec/
make test
cpu=x86-64
if [[ "$(uname -m)" == aarch64 ]]; then cpu=generic; fi
make install PREFIX="$prefix" CRYSTAL_FLAGS="--release --no-debug --mcpu $cpu"
python3 scripts/packaging.py licenses "${DESTDIR:-}$prefix"
