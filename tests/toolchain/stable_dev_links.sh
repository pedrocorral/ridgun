#!/usr/bin/env bash
# Toolchain check for FR-TOOL-002 AC5 / ADR-0005: stable developer links.
# Usage: stable_dev_links.sh <stable binary> <work dir>
# Prints LINK_OK, REFUSE_OK and UNLINK_OK; exits non-zero on the first broken rule.
set -e
S="$1"; O="$2/devlinks"
rm -rf "$O"; mkdir -p "$O/home" "$O/pkg/src/main/ridgun/lib" "$O/app/src/main/ridgun"
export HOME="$O/home"
printf 'fn :: project name => String\n      project name =  "pkg"\nfn :: project kind => String\n      project kind =  "lib"\n' > "$O/pkg/build.ridgun"
printf 'fn :: pkg one => Int\n      pkg one =  1\n' > "$O/pkg/src/main/ridgun/lib/pkg.ridgun"
cd "$O/app"
printf 'fn :: project name => String\n      project name =  "app"\nfn :: main entry => String\n      main entry =  "main.ridgun"\nfn :: dependencies => [String]\n      dependencies =  ["pkg"]\n' > build.ridgun
printf 'fn :: main => ()\n      main =  echo 1\n' > src/main/ridgun/main.ridgun
# No link by default: the name must come from omni.
if "$S" deps >/dev/null 2>&1; then exit 1; fi
[ ! -e "$HOME/.stable/dev-links" ]
# A valid link is used, with a warning.
"$S" dev link pkg "$O/pkg" >/dev/null
"$S" deps > deps.out
grep -q "Developer link" deps.out
[ -f .stable/deps/pkg/src/main/ridgun/lib/pkg.ridgun ]
grep -q "dependencies =  \[\"pkg\"\]" build.ridgun
echo LINK_OK
# Invalid links are refused: another project, a path as name, a shell character in the folder.
if "$S" dev link app "$O/pkg" >/dev/null 2>&1; then exit 1; fi
if "$S" dev link ../pkg "$O/pkg" >/dev/null 2>&1; then exit 1; fi
mkdir -p "$O/a\$(touch pwned)"; cp "$O/pkg/build.ridgun" "$O/a\$(touch pwned)/"
if "$S" dev link pkg "$O/a\$(touch pwned)" >/dev/null 2>&1; then exit 1; fi
# A link edited by hand to an invalid folder stops the build; it never falls back silently.
printf 'pkg|/nonexistent\n' > "$HOME/.stable/dev-links"
if "$S" deps >/dev/null 2>&1; then exit 1; fi
[ ! -e pwned ]
echo REFUSE_OK
"$S" dev unlink pkg >/dev/null
if "$S" deps >/dev/null 2>&1; then exit 1; fi
echo UNLINK_OK
