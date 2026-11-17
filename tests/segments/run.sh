#!/bin/sh
# Short tests by segment, each with a time limit (docs/etc/testing_in_segments.md).
# Run from the repository root:
#   sh tests/segments/run.sh                 every quick segment
#   sh tests/segments/run.sh runtime-threads one segment
#   sh tests/segments/run.sh cases-lists     one folder of tests/cases
# One line per segment: PASS, FAIL or TIMEOUT and the seconds taken. The exit
# status is 0 only when every segment passed.
set -u
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# run NAME LIMIT_SECONDS COMMAND...
run() {
  name=$1; limit=$2; shift 2
  start=$(date +%s)
  if [ "$1" = "seg" ]; then
    timeout "$limit" sh "$0" __inner "$2" > "$tmp/$name.log" 2>&1
  else
    timeout "$limit" "$@" > "$tmp/$name.log" 2>&1
  fi
  rc=$?
  secs=$(( $(date +%s) - start ))
  if [ "$rc" -eq 0 ]; then
    echo "PASS    $name (${secs}s)"
    tail -1 "$tmp/$name.log" | grep -E "ms|CPU" | sed 's/^/        /'; true
  elif [ "$rc" -eq 124 ]; then
    echo "TIMEOUT $name (limit ${limit}s)"; failed=1
  else
    echo "FAIL    $name (${secs}s, exit $rc)"; tail -5 "$tmp/$name.log" | sed 's/^/        /'; failed=1
  fi
}

seg_runtime_build() {
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  sh src/main/runtime/build-linux-x86_64.sh "$tmp/rt.o" || return 1
  cp src/main/ridgun/lib/wasmrt.ridgun "$tmp/wasmrt.before"
  sh src/main/runtime/build-wasm32.sh || return 1
  cp "$tmp/wasmrt.before" src/main/ridgun/lib/wasmrt.ridgun
}

seg_runtime_scaling() {
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  "${RIDGUNC:-bin/ridgunc}" build tests/segments/four_agents.ridgun -o "$tmp/fa" --quiet || { echo "the benchmark does not build"; return 1; }
  # user CPU time of the whole run, in ms (bash's time keyword; there is no /usr/bin/time here)
  bash -c 'TIMEFORMAT=%U; time "$0" > "$1"' "$tmp/fa" "$tmp/fa.out" 2> "$tmp/cpu" || { echo "the benchmark fails"; return 1; }
  one=$(sed -n 's/^one thread: *\([0-9]*\) ms.*/\1/p' "$tmp/fa.out")
  four=$(sed -n 's/^four agents: *\([0-9]*\) ms.*/\1/p' "$tmp/fa.out")
  cpu_ms=$(awk -v c="$(tail -1 "$tmp/cpu")" 'BEGIN{printf "%d", c*1000}')
  # the whole run is the one-thread phase plus the four-agent phase: the CPU
  # of the second must stay under about 3 times the first, so the total stays
  # under 4 times the one-thread phase
  limit=$(( one * 4 ))
  echo "one thread ${one} ms, four agents ${four} ms, total user CPU ${cpu_ms} ms, limit ${limit} ms"
  [ "$cpu_ms" -lt "$limit" ] || { echo "the four agents cost too much CPU: threads share a cache line or a lock"; return 1; }
}

# A program of n small functions, to time the compiler on inputs of growing size.
gen_program() {
  awk -v n="$1" 'BEGIN {
    for (i = 0; i < n; i++) {
      printf "fn :: f%d Int => Int\n      f%d x =  (x + %d) * 2 - 1\n\n", i, i, i
    }
    printf "fn :: main => ()\n      main =\n"
    for (i = 0; i < n; i++) printf "        echo (f%d %d)\n", i, i
  }'
}

# ms taken by a command (the command is the arguments)
ms_of() {
  s=$(date +%s%N); "$@" > /dev/null 2>&1; rc=$?; e=$(date +%s%N)
  echo $(( (e - s) / 1000000 ))
  return $rc
}

# scaling NAME COMMAND-PREFIX: time the compiler command on n and 2n functions;
# the ratio stays under 3 (twice as much work: about 2 is linear, about 4 is quadratic)
scaling() {
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  gen_program "$2" > "$tmp/a.ridgun"; gen_program "$(( $2 * 2 ))" > "$tmp/b.ridgun"
  cmd=$1
  ta=$($cmd "$tmp/a.ridgun" "$tmp/a.bin") || { echo "fails on $2 functions"; return 1; }
  tb=$($cmd "$tmp/b.ridgun" "$tmp/b.bin") || { echo "fails on $(( $2 * 2 )) functions"; return 1; }
  # a floor of 50 ms keeps the ratio meaningful when both are small
  base=$(( ta > 50 ? ta : 50 ))
  ratio_x10=$(( tb * 10 / base ))
  echo "$2 functions ${ta} ms, $(( $2 * 2 )) functions ${tb} ms, ratio $(( ratio_x10 / 10 )).$(( ratio_x10 % 10 )) (limit 3.0)"
  [ "$ratio_x10" -lt 30 ] || { echo "the time more than doubles with twice the input: a phase is not linear"; return 1; }
}

check_cmd() { ms_of "${RIDGUNC:-bin/ridgunc}" check "$1"; }
build_cmd() { ms_of "${RIDGUNC:-bin/ridgunc}" build "$1" -o "$2" --quiet; }

# front end: lexer, parser, analyzer and type checker (`check`)
seg_compiler_frontend() { scaling check_cmd 1500; }
# the whole pipeline: front end, lowering, LLVM IR, opt, llc, ld (`build`)
seg_compiler_build() { scaling build_cmd 300; }

if [ "${1:-}" = "__inner" ]; then
  "$2"
  exit $?
fi

quick() {
  run runtime-build 120 seg seg_runtime_build
  run runtime-threads 180 sh tests/runtime/run-threads.sh 10
  run runtime-scaling 120 seg seg_runtime_scaling
  run compiler-frontend 120 seg seg_compiler_frontend
  run compiler-build 240 seg seg_compiler_build
}

case "${1:-all}" in
  all) quick ;;
  runtime-build) run runtime-build 120 seg seg_runtime_build ;;
  runtime-threads) run runtime-threads 180 sh tests/runtime/run-threads.sh 10 ;;
  runtime-scaling) run runtime-scaling 120 seg seg_runtime_scaling ;;
  compiler-frontend) run compiler-frontend 120 seg seg_compiler_frontend ;;
  compiler-build) run compiler-build 240 seg seg_compiler_build ;;
  cases-*) g=${1#cases-}; run "$1" 300 bin/ridgunc run tests/run.ridgun --no-toolchain "$g/" ;;
  *) echo "unknown segment: $1"; exit 2 ;;
esac
exit "$failed"
