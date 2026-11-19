#!/bin/sh
# Programs of several files: what a module sees of the others (FR-COMP-032).
# The case suite builds one file at a time, so these projects are written here,
# each in its own folder, and built with the compiler under test. A case says
# the output of the program, or a text the build error must have.
# Run from the repository root: sh tests/runtime/run-modules.sh
set -u
ridgunc=${RIDGUNC:-bin/ridgunc}
case "$ridgunc" in /*) ;; *) ridgunc="$PWD/$ridgunc" ;; esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=0

# new <case>: an empty folder for the case, and the shell is left in it.
new() {
  name=$1
  rm -rf "${tmp:?}/$name"
  mkdir -p "$tmp/$name"
  cd "$tmp/$name" || exit 1
}

# runs <text>: main.ridgun builds and prints exactly <text>.
runs() {
  if ! "$ridgunc" build main.ridgun -o prog --quiet > build.log 2>&1; then
    echo "FAIL  $name: the build failed"
    cat build.log
    failed=1
    return
  fi
  got=$(./prog 2>&1)
  if [ "$got" = "$1" ]; then
    echo "ok    $name"
  else
    echo "FAIL  $name: printed '$got', expected '$1'"
    failed=1
  fi
}

# refuses <text>: main.ridgun does not build and the error has <text>.
refuses() {
  if "$ridgunc" build main.ridgun -o prog --quiet > build.log 2>&1; then
    echo "FAIL  $name: it built, and the build should stop"
    failed=1
  elif grep -qF "$1" build.log; then
    echo "ok    $name"
  else
    echo "FAIL  $name: the error does not say '$1'"
    cat build.log
    failed=1
  fi
}

# ── What an import brings ────────────────────────────────────

new import_does_not_bring_what_the_module_imports
cat > inner.ridgun <<'EOF'
fn :: inner value Int => Int
      inner value n =  n + 1
EOF
cat > facade.ridgun <<'EOF'
import inner

fn :: facade value Int => Int
      facade value n =  inner value n
EOF
cat > main.ridgun <<'EOF'
import facade

fn :: main => ()
      main =  echo (inner value 1)
EOF
refuses "'inner_value' is in a module this one does not import"

new export_offers_an_imported_module
cat > inner.ridgun <<'EOF'
fn :: inner value Int => Int
      inner value n =  n + 1
EOF
cat > facade.ridgun <<'EOF'
import inner
export inner
EOF
cat > main.ridgun <<'EOF'
import facade

fn :: main => ()
      main =  echo (inner value 41)
EOF
runs "42"

new export_of_a_module_in_a_folder
mkdir web
cat > web/router.ridgun <<'EOF'
fn :: admin addon Int => Int
      admin addon n =  n + 1
EOF
cat > admin.ridgun <<'EOF'
import web/router
export web/router
EOF
cat > main.ridgun <<'EOF'
import admin

fn :: main => ()
      main =  echo (admin addon 41)
EOF
runs "42"

new one_name_in_two_imported_modules_must_say_the_module
cat > left.ridgun <<'EOF'
type TableDef = TableDef Int
EOF
cat > right.ridgun <<'EOF'
type TableDef = TableDef String
EOF
cat > main.ridgun <<'EOF'
import left
import right

fn :: size of TableDef => Int
      size of (TableDef n) =  n

fn :: main => ()
      main =  echo (size of (TableDef 3))
EOF
refuses "is in more than one of the modules this one uses"

# ── Two files of one base name ───────────────────────────────

new two_files_of_one_name_in_two_folders_are_two_modules
mkdir px2 vk
cat > px2/db.ridgun <<'EOF'
module :: mm

fn :: px two Int => Int
      px two n   =  n + 1
EOF
cat > vault.ridgun <<'EOF'
type Sealed = sl_key: String, sl_n: Int

fn :: sealed text Sealed => String
      sealed text s =  sl_key s
EOF
cat > px2/one.ridgun <<'EOF'
module :: mm

import px2/db
import vault

fn :: px text Sealed => String
      px text s      =  sealed text s
EOF
cat > vk/db.ridgun <<'EOF'
module :: vk

type Sealed = Sealed Int

fn :: vk open Int => Sealed
      vk open n =  Sealed n
EOF
cat > adapter.ridgun <<'EOF'
import vk/db

fn :: adapter size Int => Int
      adapter size n =  n
EOF
cat > main.ridgun <<'EOF'
import adapter
import px2/one
import vault

fn :: main => ()
      main =  echo (px text (Sealed "k" (px two (adapter size 1))))
EOF
runs "k"

# ── A function and a record field of one name ────────────────

new function_wins_over_a_field_of_a_module_not_imported
cat > aa.ridgun <<'EOF'
module :: aa

type Tok = TkWord String | TkEnd

fn :: tk_name Tok        => String
      tk_name (TkWord w) =  w
      tk_name _          =  ""

fn :: first name [Tok] => String
      first name []    =  ""
      first name (t:_) =  tk_name t
EOF
cat > bb.ridgun <<'EOF'
module :: bb

type Task = tk_name: String, tk_size: Int

fn :: task label Task => String
      task label t    =  tk_name t
EOF
cat > main.ridgun <<'EOF'
import aa
import bb

fn :: main => ()
      main =  echo (first name [TkWord "word"]) (task label (Task "task" 1))
EOF
runs "word task"

new two_words_are_not_a_field_with_an_underscore
cat > ga.ridgun <<'EOF'
module :: ga

type Srv = v_n: Int, v_now: Int, v_name: String

fn :: srv count Srv => Int
      srv count s =  v_n s
EOF
cat > gb.ridgun <<'EOF'
module :: gb

type Big = Big Int

fn :: big one => Big
      big one =  Big 1

fn :: big int Big => Int
      big int (Big n) =  n

fn :: geometric Big Int Int Big Big => Big
      geometric v n i a b
        | i >= n = v
        | otherwise = geometric v n (i + 1) a b

fn :: list values Big Int => Big
      list values v   n   =  geometric v n 0 big one big one
EOF
cat > main.ridgun <<'EOF'
import ga
import gb

fn :: main => ()
      main =  echo (big int (list values (Big 3) 2)) (srv count (Srv 1 2 "x"))
EOF
runs "3 1"

new words_of_a_name_among_arguments_stay_one_name
cat > ab.ridgun <<'EOF'
module :: ab

type Pool = backend: String, capabilities: Int, workers: [Int], size: Int, next: Int

fn :: new session String Int [Int] => Int
      new session name caps ags =  caps
EOF
cat > va.ridgun <<'EOF'
module :: va

import ab

fn :: vkd capabilities => Int
      vkd capabilities =  7

fn :: vkd pool Int => Pool
      vkd pool sz
        | sz <= 0   = Pool "vonkeep" vkd capabilities [] 0 0
        | otherwise = Pool "vonkeep" vkd capabilities [sz] sz 0

fn :: vkd pool caps Int => Int
      vkd pool caps sz =  capabilities (vkd pool sz)

fn :: vkd session Int => Int
      vkd session ag =  new session "vonkeep" vkd capabilities [ag]
EOF
cat > main.ridgun <<'EOF'
import va

fn :: capabilities => String
      capabilities =  "mine"

fn :: main => ()
      main =  echo (vkd session 1) (vkd pool caps 2) capabilities
EOF
runs "7 7 mine"

# ── A library bundle that has a name of the prelude ──────────

new bundle_with_a_prelude_name_leaves_the_prelude_whole
mkdir -p .stable/deps
cat > .stable/deps/abstract.ridgunlib <<'EOF'
module :: abstract

fn :: list len [A]    => Int
      list len []     =  0
      list len (_:xs) =  10 + (list len xs)
EOF
cat > main.ridgun <<'EOF'
import abstract

fn :: main => ()
      main =  echo (list len [1, 2, 3])
EOF
runs "30"

cd /
[ "$failed" -eq 0 ] && echo "all module cases hold"
exit "$failed"
