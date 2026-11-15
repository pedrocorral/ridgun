#!/bin/sh
# ============================================================
# tests/wasm/run-wasm.sh <program.wasm>
# Runs a wasm32 program built by ridgunc on this machine (see
# host-build.sh). Exit status: the program's.
# ============================================================
set -e
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sh "$here/host-build.sh" "$1" "$tmp/prog"
set +e
"$tmp/prog"
