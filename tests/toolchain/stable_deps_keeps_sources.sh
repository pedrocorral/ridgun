#!/usr/bin/env bash
# Toolchain check for FR-TOOL-002 AC7: `stable deps` keeps a package under .stable/deps and writes nothing into
# the project's own sources; a program that imports the package's module still builds and runs.
# Usage: stable_deps_keeps_sources.sh <stable binary> <work dir>
# Prints SOURCES_CLEAN_OK and IMPORT_OK; exits non-zero on the first broken rule.
set -e
S="$1"; O="$2/depsclean"
rm -rf "$O"; mkdir -p "$O/pkg/src/main/ridgun/lib" "$O/app/src/main/ridgun"
printf 'fn :: project name => String\n      project name =  "pkg"\nfn :: project kind => String\n      project kind =  "lib"\n' > "$O/pkg/build.rg"
printf 'fn :: pkg one => Int\n      pkg one =  41\n' > "$O/pkg/src/main/ridgun/lib/pkg.rg"
printf 'fn :: pkg wire => Int\n      pkg wire =  1\n' > "$O/pkg/src/main/ridgun/lib/pkg_wire.rg"
cd "$O/app"
printf 'fn :: project name => String\n      project name =  "app"\nfn :: main entry => String\n      main entry =  "src/main/ridgun/main.rg"\nfn :: dependencies => [String]\n      dependencies =  ["pkg"]\n' > build.rg
printf 'fn :: locked packages => [String]\n      locked packages =  ["pkg|pkg||0.1.0||%s"]\n' "$O/pkg" > omni.lock
printf 'import pkg\n\nfn :: main => ()\n      main =  echo ((pkg one) + 1)\n' > src/main/ridgun/main.rg
"$S" deps > deps.out 2>&1
[ -f .stable/deps/pkg/src/main/ridgun/lib/pkg.rg ]
[ -f .stable/deps/pkg/src/main/ridgun/lib/pkg_wire.rg ]
[ "$(find src -type f | sort | tr '\n' ' ')" = "src/main/ridgun/main.rg " ]
echo SOURCES_CLEAN_OK
"$S" run > run.out 2>&1
grep -q "^42$" run.out
echo IMPORT_OK
