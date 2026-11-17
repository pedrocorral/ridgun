#!/bin/sh
# Runs the groups of tests/cases one by one and keeps the whole log of each.
# Run from the repository root:
#   sh tests/run-groups.sh                      every group, native backends
#   sh tests/run-groups.sh agents names         some groups
#   RIDGUNC=/path/to/ridgunc sh tests/run-groups.sh
#   LOGS=/some/dir sh tests/run-groups.sh       where the logs go (default: a new folder in /tmp)
#   FLAGS=--wasm sh tests/run-groups.sh         flags for tests/run.ridgun (default --no-toolchain)
# One line per group. For a group that fails, every FAIL line with the reason the
# runner printed under it, and the path of the log. Nothing is cut: a failure that is
# seen once must leave its reason behind.
# Do not run it under `nice`: cases with a time limit then fail on a loaded machine.
# Exit status 0 only when every group passed.
set -u
ridgunc=${RIDGUNC:-bin/ridgunc}
flags=${FLAGS:---no-toolchain}
logs=${LOGS:-$(mktemp -d /tmp/ridgun-groups.XXXXXX)}
mkdir -p "$logs"
if [ $# -eq 0 ]; then set -- $(ls tests/cases); fi
failed=0
for g in "$@"; do
  log="$logs/$g.log"
  start=$(date +%s)
  RIDGUNC=$ridgunc timeout 600 "$ridgunc" run tests/run.ridgun $flags "$g/" > "$log" 2>&1
  rc=$?
  secs=$(( $(date +%s) - start ))
  summary=$(grep "promised behaviours passed" "$log" | head -1)
  if [ "$rc" -eq 0 ] && ! grep -q "^FAIL" "$log" && [ -n "$summary" ]; then
    echo "PASS  $g: ${summary%% promised*} (${secs}s)"
  else
    failed=1
    echo "FAIL  $g: ${summary:-no summary, exit $rc} (${secs}s, load $(cut -d' ' -f1 /proc/loadavg)) log: $log"
    awk '/^FAIL/ {p=1; print "      " $0; next} p && /^       / {print "      " $0; next} {p=0}' "$log"
  fi
done
echo "logs: $logs"
exit $failed
