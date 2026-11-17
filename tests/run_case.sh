#!/usr/bin/env bash
# tests/run_case.sh: runs one built acceptance case for tests/run.ridgun and measures it.
# Usage: run_case.sh WORK_DIR TIMEOUT_S OUT_FILE TIME_FILE RSS_FILE EXE
#   OUT_FILE   standard output and standard error of EXE
#   TIME_FILE  "USER_MS SYS_MS": CPU that EXE used (all its threads)
#   RSS_FILE   "PEAK_KB": the highest VmHWM read from /proc/<pid>/status while EXE ran
# Exits with the exit status of EXE, or 124 when EXE ran past TIMEOUT_S (as timeout(1)).
# EXE runs with at most 4 GB of address space. Pure Bash: no /usr/bin/time, no forks while EXE runs.
# The poller samples every 2 ms, so growth in the last 2 ms before EXE exits can go unseen.
set -u
export LC_ALL=C
work=$1 timeout_s=$2 out_f=$3 time_f=$4 rss_f=$5 exe=$6
cd "$work" || exit 1
ulimit -v 4000000

exec {sleep_fd}<> <(:)  # a pipe that never delivers data: `read -t` on it sleeps without a fork
peak_kb=0
running=1

# Reads State and VmHWM of process $1; clears `running` when it has exited (zombie or reaped).
# The file is read whole (mapfile) and split without `read`: a `read` loop left at
# VmHWM kept the rest of the file in Bash's read buffer, and under load those lines
# (RssAnon: ...) came out of the next `read` of the times file, which stopped the script with status 1.
sample() {
  local line state=""
  local -a st_lines=() f=()
  { mapfile -t st_lines < "/proc/$1/status"; } 2>/dev/null
  if (( ${#st_lines[@]} == 0 )); then
    running=0
    return
  fi
  for line in "${st_lines[@]}"; do
    case $line in
      State:*) f=($line); state=${f[1]:-} ;;
      VmHWM:*) f=($line); (( ${f[1]:-0} > peak_kb )) && peak_kb=${f[1]}; break ;;
    esac
  done
  [[ $state == Z || -z $state ]] && running=0
}

# Sets `ms` from a `times` field such as 1m2.345s.
to_ms() {
  local t=$1 min sec
  min=${t%%m*}; sec=${t#*m}; sec=${sec%s}
  ms=$(( (10#$min * 60 + 10#${sec%.*}) * 1000 + 10#${sec#*.} ))
}

# Sets `user_ms` and `sys_ms` from the children line of a `times` snapshot file.
children_cpu() {
  local -a tl=() f=()
  mapfile -t tl < "$1"
  f=(${tl[1]:-0m0.000s 0m0.000s})
  to_ms "${f[0]}"; user_ms=$ms
  to_ms "${f[1]}"; sys_ms=$ms
}

times > "$work/.times0"
"$exe" > "$out_f" 2>&1 &
pid=$!
now_us=${EPOCHREALTIME/./}
deadline_us=$(( now_us + timeout_s * 1000000 ))
timed_out=0
while (( running )); do
  sample "$pid"
  (( running )) || break
  now_us=${EPOCHREALTIME/./}
  if (( now_us >= deadline_us )); then
    if (( timed_out )); then
      kill -KILL "$pid" 2>/dev/null
    else
      kill -TERM "$pid" 2>/dev/null
      timed_out=1
      deadline_us=$(( now_us + 2000000 ))
    fi
  fi
  read -t 0.002 -u "$sleep_fd" _
done
wait "$pid"
code=$?
times > "$work/.times1"

children_cpu "$work/.times0"; u0=$user_ms; s0=$sys_ms
children_cpu "$work/.times1"
printf '%d %d\n' $(( user_ms - u0 )) $(( sys_ms - s0 )) > "$time_f"
printf '%d\n' "$peak_kb" > "$rss_f"
(( timed_out )) && exit 124
exit "$code"
