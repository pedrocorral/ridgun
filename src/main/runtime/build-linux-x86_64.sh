#!/bin/sh
# Builds the Ridgun runtime for Linux on x86-64 (ADR-0013, TASK-0096) as one
# position-independent object: core + the Linux PAL + the entry points of the
# LLVM backend's helpers. Needs llvm-link, opt and llc (LLVM 19).
# Run from the repository root:
#   sh src/main/runtime/build-linux-x86_64.sh [out.o]
set -eu
here=$(dirname "$0")
out=${1:-/tmp/ridgun-rt-linux-x86_64.o}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
llvm-link "$here"/core/*.ll "$here"/abi/llvm.ll "$here"/pal/linux-x86_64.ll -o "$tmp/rt.bc"
opt -O2 -mtriple=x86_64-unknown-linux-gnu "$tmp/rt.bc" -o "$tmp/rt.opt.bc"
llc -O2 -mtriple=x86_64-unknown-linux-gnu -relocation-model=pic -filetype=obj "$tmp/rt.opt.bc" -o "$out"
echo "wrote $out"
