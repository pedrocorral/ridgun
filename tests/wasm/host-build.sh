#!/bin/sh
# ============================================================
# tests/wasm/host-build.sh <program.wasm> <executable>
# Turns a wasm32 program built by ridgunc into an executable for this
# machine: wasm2c translates it to C, and cc builds it with
# tests/wasm/wasi-host.c. The executable runs the program with the
# caller's standard input and output; its exit status is the program's.
# Linear memory is plain heap memory with bounds checks (no 8 GB
# reservation), so it runs under the test runner's address-space limit.
# Tail calls are wasm return_call (WebAssembly 3.0), so wasm2c runs with
# --enable-tail-call. Needs wabt 1.0.36 (wasm2c and its runtime sources in
# /usr/src/wasm2c) and cc.
# ============================================================
set -e
here=$(cd "$(dirname "$0")" && pwd)
rt=/usr/src/wasm2c
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
wasm2c --enable-tail-call "$1" -n ridgun -o "$tmp/prog.c"
# Two wabt 1.0.36 bugs in the C of tail calls, patched here:
# - the tail-call handlers of imported functions pass the parameter struct
#   by value to memcpy, which needs its address;
# - a return_call from a plain function starts the trampoline with an
#   instance pointer that is never set, so the callee reads garbage.
sed -i -e 's/wasm_rt_memcpy(params, tail_call_stack/wasm_rt_memcpy(\&params, tail_call_stack/' \
  -e 's/void \*instance_ptr_storage;/void *instance_ptr_storage = instance;/' "$tmp/prog.c"
cc -O1 -w -DWASM_RT_USE_MMAP=0 -DWASM_RT_STACK_DEPTH_COUNT=1 \
  -DWASM_RT_MAX_CALL_STACK_DEPTH=4000000 -I"$tmp" -I"$rt" \
  "$here/wasi-host.c" "$tmp/prog.c" "$rt/wasm-rt-impl.c" \
  "$rt/wasm-rt-mem-impl.c" "$rt/wasm-rt-exceptions-impl.c" -lm -lpthread -o "$2"
