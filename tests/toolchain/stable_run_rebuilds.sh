#!/usr/bin/env bash
# Toolchain check for FR-TOOL-002 (stable run): `stable run` builds when the sources changed since the last
# build, also when they change in the same second, and does not build when nothing changed.
# Usage: stable_run_rebuilds.sh <stable binary> <work dir>
# Prints FIRST_OK, REBUILT_OK and CACHED_OK; exits non-zero on the first broken rule.
set -e
S="$1"; O="$2/runrebuild"
rm -rf "$O"; mkdir -p "$O/src/main/ridgun/demo"; cd "$O"
printf 'fn :: project name => String\n      project name =  "demo"\nfn :: main entry => String\n      main entry =  "src/main/ridgun/demo/main.rg"\n' > build.rg
M=src/main/ridgun/demo/main.rg
printf 'fn :: main => ()\n      main =  echo "uno"\n' > "$M"
"$S" run > out1.txt 2>&1
grep -q "^uno$" out1.txt && echo FIRST_OK
printf 'fn :: main => ()\n      main =  echo "dos"\n' > "$M"
"$S" run > out2.txt 2>&1
grep -q "^dos$" out2.txt && grep -q "Building" out2.txt && echo REBUILT_OK
"$S" run > out3.txt 2>&1
grep -q "^dos$" out3.txt && ! grep -q "Building" out3.txt && echo CACHED_OK
