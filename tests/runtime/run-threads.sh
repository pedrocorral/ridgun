#!/bin/sh
# Builds the Linux x86-64 runtime object and the thread tests (threads.ll),
# links them as an executable and runs it ROUNDS times (default 20): a race
# that shows once in a few runs is found by repetition.
# Run from the repository root: sh tests/runtime/run-threads.sh [rounds]
set -eu
rounds=${1:-20}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sh src/main/runtime/build-linux-x86_64.sh "$tmp/rt.o" >/dev/null
llc -O2 -filetype=obj tests/runtime/threads.ll -o "$tmp/threads.o"
cat > "$tmp/lds" <<'LDS'
ENTRY(_start)
PHDRS { all PT_LOAD FILEHDR PHDRS FLAGS(7); }
SECTIONS {
  . = 0x400080;
  .rg_page0 : { KEEP(*(.rg_page0)) } :all
  . = 0x401000;
  .text : ALIGN(16) { *(.text .text.*) } :all
  .rodata : ALIGN(16) { *(.rodata .rodata.*) } :all
  .data : ALIGN(16) { *(.data .data.*) } :all
  .bss : ALIGN(16) { *(.bss .bss.* COMMON) } :all
  /DISCARD/ : { *(.note*) *(.eh_frame*) *(.comment*) }
}
LDS
ld -n --no-warn-rwx-segments -T "$tmp/lds" "$tmp/threads.o" "$tmp/rt.o" -o "$tmp/threads"
i=1
while [ "$i" -le "$rounds" ]; do
  out=$(timeout 120 "$tmp/threads" 2>&1) || { echo "round $i failed:"; echo "$out"; exit 1; }
  i=$((i + 1))
done
echo "$out"
echo "$rounds rounds passed"
