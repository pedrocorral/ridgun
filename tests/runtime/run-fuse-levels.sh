#!/bin/sh
# A fused element-wise loop is in the program three times: for the plain
# x86-64 instructions, for AVX2 and for AVX-512 (FR-COMP-031). The case suite
# runs the widest one this machine has. This builds the fused cases and runs
# them at each level the machine has (RIDGUN_CPU=2 and RIDGUN_CPU=3 keep the
# level down): the output must be the one the case promises.
# Run from the repository root: sh tests/runtime/run-fuse-levels.sh
set -eu
ridgunc=${RIDGUNC:-bin/ridgunc}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0
for case in fused_elementwise_expressions packed_u16_and_u32_tensors_wrap_at_their_width fused_statements_share_one_loop; do
  src=tests/cases/tensors/$case.ridgun
  sed -n '/^-- expect-output:/,/^$/p' "$src" | sed -e '1d' -e '/^$/d' -e 's/^--   //' > "$tmp/want"
  "$ridgunc" build "$src" -o "$tmp/prog" --quiet
  for level in 2 3 4; do
    RIDGUN_CPU=$level "$tmp/prog" > "$tmp/got" 2>&1 || true
    if cmp -s "$tmp/want" "$tmp/got"; then
      echo "ok    $case at level $level"
    else
      echo "FAIL  $case at level $level"
      diff "$tmp/want" "$tmp/got" | head -20
      failed=1
    fi
  done
done
[ "$failed" -eq 0 ] && echo "all levels give the promised output"
exit "$failed"
