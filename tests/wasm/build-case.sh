#!/bin/sh
# ============================================================
# tests/wasm/build-case.sh <ridgunc> <executable> [build arguments...]
# Builds a program for wasm32 (<executable>.wasm), then turns it into an
# executable of this machine with host-build.sh. tests/run.ridgun uses it
# for --wasm, so one command builds a case and its output is one stream.
# ============================================================
set -e
here=$(cd "$(dirname "$0")" && pwd)
ridgunc=$1
exe=$2
shift 2
"$ridgunc" build "$@" -o "$exe.wasm" --target wasm32
sh "$here/host-build.sh" "$exe.wasm" "$exe"
