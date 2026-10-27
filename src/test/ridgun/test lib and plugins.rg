-- ============================================================
-- src/test/ridgun/test lib and plugins.rg
-- Automated Verification of Library Compilation (.rglib & ELF64 .so)
-- and Comprehensive `stable` Build System, Scaffolding, Deps,
-- Formatting, Compile, Clean, Custom Tasks & Plugins
-- @tests FR-COMP-006
-- @tests FR-COMP-007
-- @tests FR-TOOL-001
-- @tests FR-TOOL-002
-- @tests FR-TOOL-003
-- ============================================================
import test
import str
import "io.rglib"

fn :: byte at [Int]  Int => Int
      byte at []     _   =  -1
      byte at (b:_)  0   =  b
      byte at (_:bs) idx =  byte at bs (idx - 1)

fn :: os path sep SysOs   => String
      os path sep Linux   =  "/"
      os path sep MacOS   =  "/"
      os path sep Windows =  "\\"

fn :: arch word bits SysArch => Int
      arch word bits X86_64  =  64
      arch word bits Arm64   =  64

fn :: resolve stable bin => String
      resolve stable bin
        | is file "target/stable_candidate" = "target/stable_candidate"
        | is file "target/stable"           = "target/stable"
        | otherwise                         = "bin/stable"

fn :: resolve ridgunc bin => String
      resolve ridgunc bin
        | is file "target/ridgunc_candidate" = "target/ridgunc_candidate"
        | is file "target/ridgunc"           = "target/ridgunc"
        | otherwise                          = "bin/ridgunc"

fn :: tuple fst (Int Int) => Int
      tuple fst (a, _)    =  a

fn :: tuple snd (Int Int) => Int
      tuple snd (_, b)    =  b

fn :: wait child exit Int => Int Int
      wait child exit 0 =
        sys exit 42
        (0, 0)
      wait child exit pid =  sys waitpid pid 0

fn :: run pal timeout block String   => Int
      run pal timeout block pal_file =
        with timeout 500_ms do
          dl_outer = sys deadline ms
          rem_outer = sys remaining ms
          assert true (dl_outer > 0)
          assert true (rem_outer > 0 and rem_outer <= 500)
          -- Inner longer timeout (2_s) must clamp to outer deadline (`dl_inner == dl_outer`)
          inner_dl = with timeout 2_s do sys deadline ms
          assert equals inner_dl dl_outer
          -- Poll readable regular file (events = 1 = POLLIN)
          pfd = sys open mode pal_file "r"
          pr = sys poll pfd 1 (0 - 1)
          sys close pfd
          assert true (pr > 0)
          42

fn :: main => ()
      main =
        root_dir = sys getcwd
        stable_bin = root_dir + "/" + (resolve stable bin)
        ridgunc_bin = root_dir + "/" + (resolve ridgunc bin)
        echo "=== FR-COMP-006: Reusable Library Compilation (.rglib & ELF64 ET_DYN .so) ==="
        shell exec "rm -rf target/test_lib_work && mkdir -p target/test_lib_work"
        lib_src = "-- Reusable math & shape library (no main function)\ntype Shape = Circle Int | Rect Int Int\n\nfn :: math cube Int => Int\n      math cube x   =  x * x * x\n\nfn :: shape area Shape        => Int\n      shape area (Circle r)   =  3 * r * r\n      shape area (Rect   w h) =  w * h\n"
        write file "target/test_lib_work/geom_lib.rg" lib_src
        st_lib = shell exec ("\"" + ridgunc_bin + "\" build --lib target/test_lib_work/geom_lib.rg -o target/test_lib_work/geom_lib")
        assert int equals st_lib 0 "ridgunc build --lib geom_lib"
        rglib_text = read file "target/test_lib_work/geom_lib.rglib"
        assert ok (str starts with rglib_text "-- RGLIB1")
        assert ok (str contains rglib_text "math cube")
        so_bytes = read bytes "target/test_lib_work/geom_lib.so"
        -- ELF64 magic: 0x7F 'E' 'L' 'F' (127, 69, 76, 70)
        assert int equals (byte at so_bytes 0) 127 "ELF64 magic 0"
        assert int equals (byte at so_bytes 1) 69 "ELF64 magic E"
        assert int equals (byte at so_bytes 2) 76 "ELF64 magic L"
        assert int equals (byte at so_bytes 3) 70 "ELF64 magic F"
        -- ELF64 e_type at offset 16..17: ET_DYN = 3 (little-endian: 3, 0)
        assert int equals (byte at so_bytes 16) 3 "ELF64 ET_DYN low byte"
        assert int equals (byte at so_bytes 17) 0 "ELF64 ET_DYN high byte"
        -- Consumer program importing the compiled .rglib bundle
        app_src = "import \"target/test_lib_work/geom_lib.rglib\"\n\nfn :: check eq Int Int => ()\n      check eq a   b\n        | a == b = ()\n        | otherwise = sys exit 1\n\nfn :: main => ()\n      main =\n        check eq (math cube 4) 64\n        check eq (shape area (Rect 5 8)) 40\n        check eq (shape area (Circle 3)) 27\n"
        write file "target/test_lib_work/consumer_app.rg" app_src
        st_app = shell exec ("\"" + ridgunc_bin + "\" run target/test_lib_work/consumer_app.rg")
        assert int equals st_app 0 "ridgunc run consumer_app with .rglib"
        echo "=== FR-TOOL-001 / FR-TOOL-002 / FR-TOOL-003: Comprehensive `stable` Test Suite ==="
        -- 1. `stable version` and `stable help`
        st_ver = shell exec ("\"" + stable_bin + "\" version > target/test_lib_work/stable_ver.txt")
        assert int equals st_ver 0 "stable version exit code"
        ver_out = str trim (read file "target/test_lib_work/stable_ver.txt")
        assert ok (str starts with ver_out "stable 0.9.")
        assert ok (str contains ver_out "100% self-hosted in Ridgun")
        st_help = shell exec ("\"" + stable_bin + "\" help > target/test_lib_work/stable_help.txt")
        assert int equals st_help 0 "stable help exit code"
        help_out = read file "target/test_lib_work/stable_help.txt"
        assert ok (str contains help_out "Available `stable` commands:")
        assert ok (str contains help_out "new [--lib] <name>")
        assert ok (str contains help_out "build lib | built lib")
        -- 2. `stable new <app>`: scaffold, check, test, format, compile, built, run, clean, duplicate guard
        st_new_app = shell exec ("cd target/test_lib_work && \"" + stable_bin + "\" new hello_app > new_app.txt")
        assert int equals st_new_app 0 "stable new hello_app"
        assert ok (str contains (read file "target/test_lib_work/new_app.txt") "[success] Scaffolded Ridgun project 'hello_app'")
        assert ok (is file "target/test_lib_work/hello_app/build.rg")
        assert ok (is file "target/test_lib_work/hello_app/src/main/ridgun/hello_app/main.rg")
        assert ok (is file "target/test_lib_work/hello_app/src/test/ridgun/test.rg")
        assert ok (is file "target/test_lib_work/hello_app/src/test/ridgun/test main.rg")
        -- Duplicate `stable new hello_app` must fail cleanly with [error]
        st_dup_app = shell exec ("cd target/test_lib_work && \"" + stable_bin + "\" new hello_app > dup_app.txt")
        assert int equals st_dup_app 1 "duplicate stable new hello_app returns 1"
        assert ok (str contains (read file "target/test_lib_work/dup_app.txt") "[error] Project 'hello_app' already exists")
        -- `stable check` inside hello_app
        st_chk_app = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" check > chk.txt")
        assert int equals st_chk_app 0 "stable check hello_app"
        chk_out = read file "target/test_lib_work/hello_app/chk.txt"
        assert ok (str contains chk_out "[info] Checking project 'hello_app'")
        assert ok (str contains chk_out "[ok]")
        assert ok (str contains chk_out "[success] Checked 1 module(s) — 0 errors.")
        -- `stable test` inside hello_app
        st_tst_app = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" test > tst.txt")
        assert int equals st_tst_app 0 "stable test hello_app"
        tst_out = read file "target/test_lib_work/hello_app/tst.txt"
        assert ok (str contains tst_out "[PASS]")
        assert ok (str contains tst_out "[success] Passed 1/1 test suite(s) — 0 failures.")
        -- `stable format` on an unaligned file + idempotence check
        unaligned_src = "fn :: add pair Int Int => Int\n      add pair x y = x + y\n      add pair 0 y = y\n"
        write file "target/test_lib_work/hello_app/src/main/ridgun/lib/math_util.rg" unaligned_src
        st_fmt1 = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" format src/main/ridgun/lib/math_util.rg > fmt1.txt")
        assert int equals st_fmt1 0 "stable format first pass"
        assert ok (str contains (read file "target/test_lib_work/hello_app/fmt1.txt") "[fmt]")
        formatted_once = read file "target/test_lib_work/hello_app/src/main/ridgun/lib/math_util.rg"
        st_fmt2 = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" format src/main/ridgun/lib/math_util.rg > fmt2.txt")
        assert int equals st_fmt2 0 "stable format second pass (idempotent)"
        assert ok (str contains (read file "target/test_lib_work/hello_app/fmt2.txt") "(already formatted)")
        assert str eq (read file "target/test_lib_work/hello_app/src/main/ridgun/lib/math_util.rg") formatted_once "format idempotence"
        -- `stable compile` (.rgc bytecode emission) and `stable clean`
        st_comp_app = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" compile > comp.txt")
        assert int equals st_comp_app 0 "stable compile hello_app"
        assert ok (str contains (read file "target/test_lib_work/hello_app/comp.txt") "[rgc]")
        assert ok (is file "target/test_lib_work/hello_app/target/hello_app_main.rgc")
        assert ok (is file "target/test_lib_work/hello_app/target/math_util.rgc")
        st_clean_app = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" clean > clean.txt")
        assert int equals st_clean_app 0 "stable clean hello_app"
        assert not (is file "target/test_lib_work/hello_app/target/hello_app_main.rgc")
        assert not (is file "target/test_lib_work/hello_app/target/math_util.rgc")
        -- `stable built` and `stable run` inside hello_app
        st_built_app = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" built > built.txt")
        assert int equals st_built_app 0 "stable built hello_app"
        assert ok (is file "target/test_lib_work/hello_app/target/hello_app")
        st_run_app = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" run > run.txt")
        assert int equals st_run_app 0 "stable run hello_app"
        assert ok (str contains (read file "target/test_lib_work/hello_app/run.txt") "Hello from hello_app!")
        -- 3. `stable init` in a fresh directory & `stable new -l` (via `cli.rglib` short flag `-l`)
        shell exec "mkdir -p target/test_lib_work/init_proj"
        st_init = shell exec ("cd target/test_lib_work/init_proj && \"" + stable_bin + "\" init > init1.txt")
        assert int equals st_init 0 "stable init in empty dir"
        assert ok (is file "target/test_lib_work/init_proj/build.rg")
        st_init_again = shell exec ("cd target/test_lib_work/init_proj && \"" + stable_bin + "\" init > init2.txt")
        assert int equals st_init_again 0 "stable init when build.rg already exists"
        assert ok (str contains (read file "target/test_lib_work/init_proj/init2.txt") "build.rg already exists")
        st_new_short_lib = shell exec ("cd target/test_lib_work && \"" + stable_bin + "\" new -l shortlib")
        assert int equals st_new_short_lib 0 "stable new -l shortlib"
        assert ok (is file "target/test_lib_work/shortlib/src/main/ridgun/lib/shortlib.rg")
        -- 4. `stable new --lib`, `stable test`, `stable built lib`, `stable add`, and `stable deps`
        st_new_lib = shell exec ("cd target/test_lib_work && \"" + stable_bin + "\" new --lib mathkit")
        assert int equals st_new_lib 0 "stable new --lib mathkit"
        st_test_lib = shell exec ("cd target/test_lib_work/mathkit && \"" + stable_bin + "\" test")
        assert int equals st_test_lib 0 "stable test inside scaffolded mathkit library"
        st_built_lib = shell exec ("cd target/test_lib_work/mathkit && \"" + stable_bin + "\" built lib")
        assert int equals st_built_lib 0 "stable built lib mathkit"
        assert ok (is file "target/test_lib_work/mathkit/target/mathkit.rglib")
        assert ok (is file "target/test_lib_work/mathkit/target/libmathkit.so")
        mathkit_so = read bytes "target/test_lib_work/mathkit/target/libmathkit.so"
        assert int equals (byte at mathkit_so 0) 127 "ELF64 magic byte 0"
        assert int equals (byte at mathkit_so 16) 3 "ELF64 ET_DYN e_type"
        -- Add `mathkit` as a local dependency of `hello_app` via `stable add` & `stable deps`
        st_add_dep = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" add ../mathkit > add_dep.txt")
        assert int equals st_add_dep 0 "stable add ../mathkit"
        assert ok (str contains (read file "target/test_lib_work/hello_app/add_dep.txt") "[dep]")
        assert ok (is file "target/test_lib_work/hello_app/.stable/deps/mathkit.rglib")
        st_deps_sync = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" deps > deps.txt")
        assert int equals st_deps_sync 0 "stable deps sync"
        assert ok (str contains (read file "target/test_lib_work/hello_app/deps.txt") "[success] Dependencies synchronized.")
        -- 5. Custom Tasks, Multi-Word Tasks, Plugins, and Executable Plugins (`FR-TOOL-003`)
        shell exec "rm -rf target/test_lib_work/web_proj && mkdir -p target/test_lib_work/web_proj/plugins"
        web_build = "fn :: project name => String\n      project name =  \"demo_web\"\n\nfn :: project version => String\n      project version =  \"0.1.0\"\n\nfn :: plugins => [String]\n      plugins =  [\"router\"]\n\nfn :: task serve => String\n      task serve =  \"printf SERVE_OK > target_serve.txt\"\n\nfn :: task db migrate => String\n      task db migrate =  \"printf MIGRATE_OK > target_migrate.txt\"\n"
        router_plugin = "fn :: task routes => String\n      task routes =  \"printf ROUTES_OK > target_routes.txt\"\n"
        gen_plugin = "fn :: main => ()\n      main =  write file \"target_exec_plugin.txt\" \"EXEC_PLUGIN_OK\" -> ()\n"
        write file "target/test_lib_work/web_proj/build.rg" web_build
        write file "target/test_lib_work/web_proj/plugins/router.rg" router_plugin
        write file "target/test_lib_work/web_proj/plugins/codegen.rg" gen_plugin
        st_serve = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" serve")
        assert int equals st_serve 0 "stable serve exit status"
        assert str eq (read file "target/test_lib_work/web_proj/target_serve.txt") "SERVE_OK" "stable serve output"
        st_mig = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" db migrate")
        assert int equals st_mig 0 "stable db migrate exit status"
        assert str eq (read file "target/test_lib_work/web_proj/target_migrate.txt") "MIGRATE_OK" "stable db migrate output"
        st_routes = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" routes")
        assert int equals st_routes 0 "stable routes plugin task exit status"
        assert str eq (read file "target/test_lib_work/web_proj/target_routes.txt") "ROUTES_OK" "stable routes plugin output"
        -- Executable plugin (`plugins/codegen.rg` with `fn :: main => ()`)
        st_codegen = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" codegen")
        assert int equals st_codegen 0 "stable executable plugin codegen"
        assert str eq (read file "target/test_lib_work/web_proj/target_exec_plugin.txt") "EXEC_PLUGIN_OK" "executable plugin output"
        -- Verify `stable tasks`, `stable plugins`, `stable info`, and unknown command handling
        st_tasks = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" tasks > target_tasks.txt")
        assert int equals st_tasks 0 "stable tasks exit status"
        tasks_out = read file "target/test_lib_work/web_proj/target_tasks.txt"
        assert ok (str contains tasks_out "=== Built-in `stable` Tasks ===")
        assert ok (str contains tasks_out "db migrate")
        assert ok (str contains tasks_out "routes")
        st_plugins = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" plugins > target_plugins.txt")
        assert int equals st_plugins 0 "stable plugins exit status"
        plugins_out = read file "target/test_lib_work/web_proj/target_plugins.txt"
        assert ok (str contains plugins_out "=== Loaded `stable` Plugins ===")
        assert ok (str contains plugins_out "plugins/router.rg")
        assert ok (str contains plugins_out "plugins/codegen.rg")
        st_info = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" info > target_info.txt")
        assert int equals st_info 0 "stable info exit status"
        info_out = read file "target/test_lib_work/web_proj/target_info.txt"
        assert ok (str contains info_out "=== Project Info (build.rg) ===")
        assert ok (str contains info_out "demo_web")
        st_unknown = shell exec ("cd target/test_lib_work/web_proj && \"" + stable_bin + "\" nonexistent_cmd > target_unknown.txt")
        assert int equals st_unknown 1 "unknown command returns exit code 1"
        assert ok (str contains (read file "target/test_lib_work/web_proj/target_unknown.txt") "[error] Unknown command: 'nonexistent_cmd'")
        -- 6. Creative Multi-Angle Stress & Edge-Case Tests for `stable`
        -- 6a. Longest-prefix task disambiguation (`task db` vs `task db migrate` vs `task db migrate rollback`) + extra arg forwarding
        disambig_build = "fn :: project name => String\n      project name =  \"disambig_proj\"\n\nfn :: task db => String\n      task db =  \"echo DB_ROOT:\"\n\nfn :: task db migrate => String\n      task db migrate =  \"echo DB_MIG:\"\n\nfn :: task db migrate rollback => String\n      task db migrate rollback =  \"echo DB_ROLLBACK:\"\n"
        shell exec "mkdir -p target/test_lib_work/disambig_proj/.stable/plugins"
        write file "target/test_lib_work/disambig_proj/build.rg" disambig_build
        write file "target/test_lib_work/disambig_proj/.stable/plugins/hidden_plug.rg" "fn :: task secret deploy => String\n      task secret deploy =  \"printf SECRET_DEPLOY_OK > secret.txt\"\n"
        st_db1 = shell exec ("cd target/test_lib_work/disambig_proj && \"" + stable_bin + "\" db > db1.txt")
        assert int equals st_db1 0 "task db root"
        assert ok (str contains (read file "target/test_lib_work/disambig_proj/db1.txt") "DB_ROOT:")
        st_db2 = shell exec ("cd target/test_lib_work/disambig_proj && \"" + stable_bin + "\" db migrate > db2.txt")
        assert int equals st_db2 0 "task db migrate"
        assert ok (str contains (read file "target/test_lib_work/disambig_proj/db2.txt") "DB_MIG:")
        st_db3 = shell exec ("cd target/test_lib_work/disambig_proj && \"" + stable_bin + "\" db migrate rollback --step=2 > db3.txt")
        assert int equals st_db3 0 "task db migrate rollback with extra args"
        db3_out = read file "target/test_lib_work/disambig_proj/db3.txt"
        assert ok (str contains db3_out "DB_ROLLBACK: --step=2")
        -- Hidden `.stable/plugins/*.rg` auto-discovery & multi-word task execution
        st_sec = shell exec ("cd target/test_lib_work/disambig_proj && \"" + stable_bin + "\" secret deploy")
        assert int equals st_sec 0 "hidden .stable/plugins task execution"
        assert str eq (read file "target/test_lib_work/disambig_proj/secret.txt") "SECRET_DEPLOY_OK" ".stable/plugins task output"
        -- 6b. Multi-executable project (`alpha` and `beta` in `src/main/ridgun/<target>/main.rg`), selective `built beta`, `run beta`, `run alpha`
        shell exec "mkdir -p target/test_lib_work/multi_app/src/main/ridgun/alpha target/test_lib_work/multi_app/src/main/ridgun/beta target/test_lib_work/multi_app/src/main/ridgun/lib target/test_lib_work/multi_app/src/test/ridgun"
        multi_build = "fn :: project name => String\n      project name =  \"alpha\"\n\nfn :: project version => String\n      project version =  \"0.2.0\"\n\nfn :: main entry => String\n      main entry =  \"src/main/ridgun/alpha/main.rg\"\n"
        write file "target/test_lib_work/multi_app/build.rg" multi_build
        write file "target/test_lib_work/multi_app/src/main/ridgun/lib/shared_tag.rg" "fn :: tag prefix => String\n      tag prefix =  \"MULTI\"\n"
        write file "target/test_lib_work/multi_app/src/main/ridgun/alpha/main.rg" "import shared_tag\n\nfn :: main => ()\n      main =  echo ((tag prefix) + \":ALPHA\")\n"
        write file "target/test_lib_work/multi_app/src/main/ridgun/beta/main.rg" "import shared_tag\n\nfn :: main => ()\n      main =  echo ((tag prefix) + \":BETA\")\n"
        -- Selective build of `beta` only
        st_b_beta = shell exec ("cd target/test_lib_work/multi_app && \"" + stable_bin + "\" built beta")
        assert int equals st_b_beta 0 "selective stable built beta"
        assert ok (is file "target/test_lib_work/multi_app/target/beta")
        assert not (is file "target/test_lib_work/multi_app/target/alpha")
        -- `stable run` (default target `alpha`) must auto-build `alpha` on demand and run it!
        st_r_alpha = shell exec ("cd target/test_lib_work/multi_app && \"" + stable_bin + "\" run > run_alpha.txt")
        assert int equals st_r_alpha 0 "stable run auto-builds default target alpha"
        assert ok (is file "target/test_lib_work/multi_app/target/alpha")
        assert ok (str contains (read file "target/test_lib_work/multi_app/run_alpha.txt") "MULTI:ALPHA")
        -- `stable run beta` runs the specific `beta` target
        st_r_beta = shell exec ("cd target/test_lib_work/multi_app && \"" + stable_bin + "\" run beta > run_beta.txt")
        assert int equals st_r_beta 0 "stable run beta"
        assert ok (str contains (read file "target/test_lib_work/multi_app/run_beta.txt") "MULTI:BETA")
        -- 6c. End-to-end dependency consumption: `hello_app` imports `mathkit` from `.stable/deps/mathkit.rglib` and passes `stable check` & `stable run`
        hello_with_dep = "import mathkit\n\nfn :: main => ()\n      main =  echo (greet \"from_dep\")\n"
        write file "target/test_lib_work/hello_app/src/main/ridgun/hello_app/main.rg" hello_with_dep
        st_chk_dep = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" check")
        assert int equals st_chk_dep 0 "stable check hello_app importing mathkit from .stable/deps"
        st_built_dep = shell exec ("cd target/test_lib_work/hello_app && \"" + stable_bin + "\" built && \"" + stable_bin + "\" run > run_dep.txt")
        assert int equals st_built_dep 0 "stable built & run hello_app with mathkit dependency"
        assert ok (str contains (read file "target/test_lib_work/hello_app/run_dep.txt") "Hello from library from_dep!")
        -- 6c-bis. Regression suite: external project (`ext_solstice`) resolving `.stable/deps/{mod}.rglib`, `.stable/deps/{mod}.rg`, `.stable/deps/ridgun-libs/src/main/ridgun/lib/{mod}.rg`, transitive imports via local `.rg` modules, diamond imports, 0-arg ADTs, record getters & postfix operators
        shell exec "mkdir -p target/test_lib_work/ext_solstice/.stable/deps/ridgun-libs/src/main/ridgun/lib target/test_lib_work/ext_solstice/src/main/ridgun/lib target/test_lib_work/ext_solstice/src/main/ridgun/ext_solstice"
        shell exec "cp -f target/test_lib_work/mathkit/target/mathkit.rglib target/test_lib_work/ext_solstice/.stable/deps/mathkit.rglib"
        ext_base_src = "type ExtMode = ModeFast | ModeSafe\n\ntype ExtCfg = ext_port: Int, ext_tag: String\n\nop :: String trim ext => String\n      s      trim ext =  s + \"_ok\"\n"
        ext_mid_src = "import ext_base\n\nfn :: build ext cfg Int => ExtCfg\n      build ext cfg p   =  ExtCfg p (\"p\" trim ext)\n"
        local_hlp_src = "import ext_mid\nimport mathkit\n\nfn :: check mode ExtMode => Bool\n      check mode ModeFast = True\n      check mode ModeSafe = False\n\nfn :: format helper ExtCfg Bool => String\n      format helper cfg True = (greet (ext_tag cfg)) + \":\" + (int to str (ext_port cfg))\n      format helper _ False = \"bad\"\n\nfn :: run helper Int => String\n      run helper p   =\n        cfg = build ext cfg p\n        ok_m = check mode ModeFast\n        format helper cfg ok_m\n"
        ext_main_src = "import local_helper\nimport ext_base\n\nfn :: main => ()\n      main =  echo (run helper 8080)\n"
        write file "target/test_lib_work/ext_solstice/.stable/deps/ridgun-libs/src/main/ridgun/lib/ext_base.rg" ext_base_src
        write file "target/test_lib_work/ext_solstice/.stable/deps/ext_mid.rg" ext_mid_src
        write file "target/test_lib_work/ext_solstice/src/main/ridgun/lib/local_helper.rg" local_hlp_src
        write file "target/test_lib_work/ext_solstice/src/main/ridgun/ext_solstice/main.rg" ext_main_src
        st_ext_chk = shell exec ("cd target/test_lib_work/ext_solstice && \"" + ridgunc_bin + "\" check src/main/ridgun/ext_solstice/main.rg > ext_chk.txt")
        assert int equals st_ext_chk 0 "ridgunc check in external project with transitive .stable/deps imports"
        assert ok (str contains (read file "target/test_lib_work/ext_solstice/ext_chk.txt") "0 error(s)")
        st_ext_bld = shell exec ("cd target/test_lib_work/ext_solstice && \"" + ridgunc_bin + "\" build src/main/ridgun/ext_solstice/main.rg -o ext_bin && ./ext_bin > ext_out.txt")
        assert int equals st_ext_bld 0 "ridgunc build & run in external project with transitive .stable/deps imports"
        assert ok (str contains (read file "target/test_lib_work/ext_solstice/ext_out.txt") "Hello from library p_ok!:8080")
        -- 6d. Negative tests: `stable check` on a broken type error and `stable test` on a failing assertion must both exit with code 1
        shell exec "mkdir -p target/test_lib_work/broken_proj/src/main/ridgun/broken target/test_lib_work/broken_proj/src/test/ridgun"
        write file "target/test_lib_work/broken_proj/build.rg" "fn :: project name => String\n      project name =  \"broken\"\n"
        write file "target/test_lib_work/broken_proj/src/main/ridgun/broken/main.rg" "fn :: bad fn Int => Int\n      bad fn x   =  \"not_an_int\"\n\nfn :: main => ()\n      main =  ()\n"
        st_bad_chk = shell exec ("cd target/test_lib_work/broken_proj && \"" + stable_bin + "\" check > bad_chk.txt")
        assert int equals st_bad_chk 1 "stable check on broken module returns exit code 1"
        assert ok (str contains (read file "target/test_lib_work/broken_proj/bad_chk.txt") "[err]")
        -- Fix source module, add a failing test suite using `test.rg`, and verify `stable test` returns exit code 1
        write file "target/test_lib_work/broken_proj/src/main/ridgun/broken/main.rg" "fn :: main => ()\n      main =  ()\n"
        shell exec "cp -f src/test/ridgun/test.rg target/test_lib_work/broken_proj/src/test/ridgun/test.rg"
        write file "target/test_lib_work/broken_proj/src/test/ridgun/test_fail.rg" "import test\n\nfn :: main => ()\n      main =  assert int equals 2 3 \"intentional failure\"\n"
        st_bad_tst = shell exec ("cd target/test_lib_work/broken_proj && \"" + stable_bin + "\" test > bad_tst.txt")
        assert int equals st_bad_tst 1 "stable test on failing assertion returns exit code 1"
        bad_tst_out = read file "target/test_lib_work/broken_proj/bad_tst.txt"
        assert ok (str contains bad_tst_out "[FAIL]")
        assert ok (str contains bad_tst_out "[error] Passed 0/1 test suite(s) — 1 failed.")
        -- 6e. `stable install` with isolated HOME into `$HOME/.local/bin/` and `./bin/`
        shell exec "mkdir -p target/test_lib_work/fake_home"
        st_inst = shell exec ("cd target/test_lib_work/multi_app && HOME=\"$PWD/../fake_home\" \"" + stable_bin + "\" install alpha > inst.txt")
        assert int equals st_inst 0 "stable install alpha with isolated HOME"
        assert ok (is file "target/test_lib_work/fake_home/.local/bin/alpha")
        assert ok (is file "target/test_lib_work/multi_app/bin/alpha")
        -- 6f. Interactive REPL piped session (`info`, `reload`, `tasks`, `exit`)
        repl_in = "info\nreload\ntasks\nexit\n"
        write file "target/test_lib_work/multi_app/repl_in.txt" repl_in
        st_repl = shell exec ("cd target/test_lib_work/multi_app && \"" + stable_bin + "\" < repl_in.txt > repl_out.txt")
        assert int equals st_repl 0 "interactive REPL session exits cleanly with 0"
        repl_out = read file "target/test_lib_work/multi_app/repl_out.txt"
        assert ok (str contains repl_out "Welcome to stable 0.9.25")
        assert ok (str contains repl_out "Reloaded build.rg — current project is 'alpha'")
        assert ok (str contains repl_out "Exiting stable.")
        echo "=== FR-COMP-007: Cross-Platform PAL Descriptor/Poll/Process Primitives & with timeout ==="
        -- 0. Target Platform ADTs: `sys os => SysOs` (`Linux | MacOS | Windows`) & `sys arch => SysArch` (`X86_64 | Arm64`)
        assert true ((sys os) == Linux)
        assert true ((sys arch) == X86_64)
        assert equals (os path sep (sys os)) "/"
        assert equals (arch word bits (sys arch)) 64
        -- 1. Duration literals (_ms, _s, _min)
        assert equals 250_ms 250
        assert equals 3_s 3000
        assert equals 2_min 120000
        -- 2. Portable `sys open mode`, `sys write fd`, `sys read fd`, `sys close`
        pal_file = "target/test_lib_work/pal_io_test.txt"
        wfd = sys open mode pal_file "w"
        assert true (wfd >= 0)
        n_written = sys write fd wfd "hello-pal-ridgun"
        assert equals n_written 16
        assert equals (sys close wfd) 0
        rfd = sys open mode pal_file "r"
        assert true (rfd >= 0)
        chunk1 = sys read fd rfd 9
        assert equals chunk1 "hello-pal"
        chunk2 = sys read fd rfd 64
        assert equals chunk2 "-ridgun"
        eof_chunk = sys read fd rfd 16
        assert equals eof_chunk ""
        assert equals (sys close rfd) 0
        -- 3. Normalized PAL flags `sys open` (1 | 64 | 1089 = write+create+append)
        afd = sys open pal_file 1089 420
        assert true (afd >= 0)
        sys write fd afd "!"
        assert equals (sys close afd) 0
        assert equals (read file pal_file) "hello-pal-ridgun!"
        -- 4. `sys getpid`, `sys time ms`, `sys sleep ms`, `sys kill`, `sys terminate`, `sys call`
        my_pid = sys getpid
        assert true (my_pid > 0)
        -- Raw syscall escape hatch: Linux x86_64 SYS_getpid = 39
        raw_pid = sys call 39 0 0 0 0 0 0
        assert equals raw_pid my_pid
        -- Probe process existence with signal 0 (`sys kill pid 0` == 0)
        assert equals (sys kill my_pid 0) 0
        -- Invalid negative pid returns negative errno
        assert true ((sys terminate (0 - 999999) False) < 0)
        -- 4b. `sys pipe` (`=> (Int, Int)`) and `sys waitpid` (`Int Int => (Int, Int)`) with `fork` (`sys call 57 ...`)
        pfds = sys pipe
        pipe_rfd = tuple fst pfds
        pipe_wfd = tuple snd pfds
        assert true (pipe_rfd >= 0)
        assert true (pipe_wfd >= 0)
        sys write fd pipe_wfd "pipe-msg"
        assert equals (sys close pipe_wfd) 0
        pipe_out = sys read fd pipe_rfd 32
        assert equals pipe_out "pipe-msg"
        assert equals (sys close pipe_rfd) 0
        child_pid = sys call 57 0 0 0 0 0 0
        wres = wait child exit child_pid
        assert equals (tuple fst wres) child_pid
        assert equals (tuple snd wres) 42
        -- 5. `with timeout`, `sys deadline ms`, `sys remaining ms`, nested clamping & `sys poll`
        assert equals (sys deadline ms) 0
        assert equals (sys remaining ms) (0 - 1)
        t0 = sys time ms
        sys sleep ms 10_ms
        t1 = sys time ms
        assert true (t1 >= (t0 + 5))
        outer_res = run pal timeout block pal_file
        assert equals outer_res 42
        -- After exiting `with timeout`, deadline is restored to 0 / -1
        assert equals (sys deadline ms) 0
        assert equals (sys remaining ms) (0 - 1)
        -- 6. Verify `--strict` mode rejects `_` in `fn ::` / `op ::` names and `(Int, Int)` outputs, and accepts `fn`/`op`/`where` and `=> Int Int`
        strict_bad = "target/test_lib_work/strict_bad.rg"
        write file strict_bad "fn :: bad_fn_name Int => Int\n      bad_fn_name x = x + 1\n"
        rc_non_strict = shell exec ("\"" + ridgunc_bin + "\" check " + strict_bad + " >/dev/null 2>&1")
        assert equals rc_non_strict 0
        rc_strict_bad = shell exec ("\"" + ridgunc_bin + "\" check --strict " + strict_bad + " >/dev/null 2>&1")
        assert true (rc_strict_bad != 0)
        strict_bad_ret = "target/test_lib_work/strict_bad_ret.rg"
        write file strict_bad_ret "fn :: pair up Int => (Int, Int)\n      pair up x = (x, x + 1)\n"
        rc_strict_bad_ret = shell exec ("\"" + ridgunc_bin + "\" check --strict " + strict_bad_ret + " >/dev/null 2>&1")
        assert true (rc_strict_bad_ret != 0)
        strict_good = "target/test_lib_work/strict_good.rg"
        write file strict_good "fn :: op Int => Int Int\n      op where = (where, where + 1)\nop :: Int fn Int => Int\n      a fn b = a + b\n"
        rc_strict_good = shell exec ("\"" + ridgunc_bin + "\" check --strict " + strict_good + " >/dev/null 2>&1")
        assert equals rc_strict_good 0
        -- 7. Verify the 5 canonical lambda syntax & diagnostic rules (`FR-COMP-013`)
        lam_bad_empty = "target/test_lib_work/lam_bad_empty.rg"
        write file lam_bad_empty "fn :: main => ()\n      main =\n        f = (() => 42)\n        echo (f ())\n"
        rc_lam_empty = shell exec ("\"" + ridgunc_bin + "\" check " + lam_bad_empty + " > target/test_lib_work/lam_empty.txt 2>&1")
        assert true (rc_lam_empty != 0)
        assert ok (str contains (read file "target/test_lib_work/lam_empty.txt") "zero-parameter lambda uses '(=> expr)', not '(() => expr)'")
        lam_bad_sig = "target/test_lib_work/lam_bad_sig.rg"
        write file lam_bad_sig "fn :: run thunk (() => Int) => Int\n      run thunk f = f ()\nfn :: main => ()\n      main = echo 1\n"
        rc_lam_sig = shell exec ("\"" + ridgunc_bin + "\" check " + lam_bad_sig + " > target/test_lib_work/lam_sig.txt 2>&1")
        assert true (rc_lam_sig != 0)
        assert ok (str contains (read file "target/test_lib_work/lam_sig.txt") "zero-parameter function type in signature uses '(=> Type)', not '(() => Type)'")
        lam_bad_unparen = "target/test_lib_work/lam_bad_unparen.rg"
        write file lam_bad_unparen "fn :: main => ()\n      main =\n        f = x => x + 1\n        echo (f 5)\n"
        rc_lam_unparen = shell exec ("\"" + ridgunc_bin + "\" check " + lam_bad_unparen + " > target/test_lib_work/lam_unparen.txt 2>&1")
        assert true (rc_lam_unparen != 0)
        assert ok (str contains (read file "target/test_lib_work/lam_unparen.txt") "lambda expression must be enclosed in parentheses: '(x => expr)'")
        lam_bad_type_expr = "target/test_lib_work/lam_bad_type_expr.rg"
        write file lam_bad_type_expr "fn :: main => ()\n      main =\n        echo (map (Int => Int) [1, 2, 3])\n"
        rc_lam_type_expr = shell exec ("\"" + ridgunc_bin + "\" check " + lam_bad_type_expr + " > target/test_lib_work/lam_type_expr.txt 2>&1")
        assert true (rc_lam_type_expr != 0)
        assert ok (str contains (read file "target/test_lib_work/lam_type_expr.txt") "type signature '(Type => Type)' cannot be used as an expression")
        lam_bad_val_type = "target/test_lib_work/lam_bad_val_type.rg"
        write file lam_bad_val_type "fn :: run handler (conn => conn) Int => Int\n      run handler f x = f x\nfn :: main => ()\n      main = echo 1\n"
        rc_lam_val_type = shell exec ("\"" + ridgunc_bin + "\" check " + lam_bad_val_type + " > target/test_lib_work/lam_val_type.txt 2>&1")
        assert true (rc_lam_val_type != 0)
        assert ok (str contains (read file "target/test_lib_work/lam_val_type.txt") "function type in signature must use uppercase type names")
        lam_bad_tup = "target/test_lib_work/lam_bad_tup.rg"
        write file lam_bad_tup "fn :: main => ()\n      main =\n        echo (map (a b => a + b) [(1, 2), (3, 4)])\n"
        rc_lam_tup = shell exec ("\"" + ridgunc_bin + "\" check " + lam_bad_tup + " > target/test_lib_work/lam_tup.txt 2>&1")
        assert true (rc_lam_tup != 0)
        assert ok (str contains (read file "target/test_lib_work/lam_tup.txt") "use '((a b) => ...)' to destructure a tuple")
        lam_bad_multi = "target/test_lib_work/lam_bad_multi.rg"
        write file lam_bad_multi "fn :: main => ()\n      main =\n        echo (fold ((acc x) => acc + x) 0 [1, 2, 3])\n"
        rc_lam_multi = shell exec ("\"" + ridgunc_bin + "\" check " + lam_bad_multi + " > target/test_lib_work/lam_multi.txt 2>&1")
        assert true (rc_lam_multi != 0)
        assert ok (str contains (read file "target/test_lib_work/lam_multi.txt") "use '(a b => ...)' for multiple parameters")
        -- 8. RG-095 regression test: multi-file module (`module :: modlib` across `modlib.rg` and `modlib_extra.rg`)
        --    imported by an app that defines its own `type Changeset` (both source and `.rglib` bundle)
        write file "target/test_lib_work/modlib_extra.rg" "module :: modlib\n\nfn :: trim field String => String\n      trim field s = s\n"
        write file "target/test_lib_work/modlib.rg" "module :: modlib\nimport modlib_extra\n\ntype Changeset = cs_field: String\n\nfn :: validate required String => Changeset\n      validate required s = Changeset (trim field s)\n"
        write file "target/test_lib_work/modapp.rg" "import modlib\n\ntype Changeset = app_a: String, app_b: String\n\nfn :: app cs val Changeset => String\n      app cs val c = (app_a c) + (app_b c)\n\nfn :: lib cs val modlib.Changeset => String\n      lib cs val c = modlib.cs_field c\n\nfn :: main => ()\n      main =\n        lc = modlib.validate required \"ok\"\n        ac = Changeset \"1\" \"2\"\n        echo ((lib cs val lc) + \":\" + (app cs val ac))\n"
        rc_modapp = shell exec ("\"" + ridgunc_bin + "\" run --strict target/test_lib_work/modapp.rg > target/test_lib_work/modapp_out.txt 2>&1")
        assert int equals rc_modapp 0 "RG-095 multi-file module source run"
        assert str eq (str trim (read file "target/test_lib_work/modapp_out.txt")) "ok:12" "RG-095 multi-file module output"
        rc_modlib_bundle = shell exec ("\"" + ridgunc_bin + "\" build --lib --strict target/test_lib_work/modlib.rg -o target/test_lib_work/modlib.rglib >/dev/null 2>&1")
        assert int equals rc_modlib_bundle 0 "RG-095 multi-file .rglib build"
        shell exec "rm -f target/test_lib_work/modlib.rg target/test_lib_work/modlib_extra.rg"
        rc_modapp_bundle = shell exec ("\"" + ridgunc_bin + "\" run --strict target/test_lib_work/modapp.rg > target/test_lib_work/modapp_bundle_out.txt 2>&1")
        assert int equals rc_modapp_bundle 0 "RG-095 multi-file .rglib bundle run"
        assert str eq (str trim (read file "target/test_lib_work/modapp_bundle_out.txt")) "ok:12" "RG-095 multi-file .rglib bundle output"
        -- 9. RG-094 regression test: Argon2id OWASP (m=19456, t=2, p=1) must execute in < 1,100 ms with LLVM opt -O2
        write file "target/test_lib_work/bench_a2.rg" "import argon2id\n\nfn :: report a2 Int String => String\n      report a2 elapsed h\n        | elapsed < 1100 and (str len h) > 32 = \"argon2id_ok\"\n        | otherwise = \"argon2id_slow\"\n\nfn :: main => ()\n      main =\n        t0 = sys time ms\n        res = argon2id hash \"correct horse battery staple\" \"saltsaltsaltsalt\" 19456 2 1\n        t1 = sys time ms\n        echo (report a2 (t1 - t0) res)\n"
        rc_a2_build = shell exec ("\"" + ridgunc_bin + "\" build target/test_lib_work/bench_a2.rg -o target/test_lib_work/bench_a2 >/dev/null 2>&1")
        assert int equals rc_a2_build 0 "RG-094 Argon2id build"
        rc_a2_run = shell exec "target/test_lib_work/bench_a2 > target/test_lib_work/bench_a2_out.txt 2>&1"
        assert int equals rc_a2_run 0 "RG-094 Argon2id run"
        assert str eq (str trim (read file "target/test_lib_work/bench_a2_out.txt")) "argon2id_ok" "RG-094 Argon2id < 1100 ms"
        -- 10. FR-COMP-012 strict per-module import visibility:
        --     (a) orm imports db_abstract (Conn, Value, query) while solstice and root app also define Conn, Value, Changeset, query
        --     (b) web_sdk imports codec_hlp (json_get_str :: String String => String) while root app imports web_sdk and json_lib (json_get_str :: JsonDoc String => String)
        --     (c) unimported sibling module mod_b is invisible inside mod_a
        write file "target/test_lib_work/db_abstract.rg" "module :: db_abstract\n\ntype Conn = db_fd: Int\ntype Value = VInt Int | VText String\n\nfn :: query Conn String [Value] => String\n      query c sql _ = \"db:\" + (int to str (db_fd c)) + \":\" + sql\n"
        write file "target/test_lib_work/orm.rg" "module :: orm\nimport db_abstract\n\ntype Changeset = orm_valid: Bool\n\nfn :: find by id Conn String Int => String\n      find by id c tbl id = query c tbl [VInt id]\n"
        write file "target/test_lib_work/codec_hlp.rg" "module :: codec_hlp\n\nfn :: json get str String String => String\n      json get str raw key = \"codec:\" + raw + \":\" + key\n"
        write file "target/test_lib_work/solstice.rg" "module :: solstice\nimport codec_hlp\n\ntype Conn = http_status: Int\ntype Value = SVal String\ntype Changeset = sol_ok: Bool\n\nfn :: query Conn => Int\n      query c = http_status c\n\nfn :: extract token String => String\n      extract token body = json get str body \"tok\"\n"
        write file "target/test_lib_work/json_lib.rg" "module :: json_lib\n\ntype JsonDoc = JDoc String\n\nfn :: json get str JsonDoc String => String\n      json get str (JDoc s) k = \"json:\" + s + \":\" + k\n"
        write file "target/test_lib_work/vis_app.rg" "import db_abstract\nimport orm\nimport solstice\nimport json_lib\n\ntype Conn = app_tag: String\n\nfn :: main => ()\n      main =\n        dbc = db_abstract.Conn 7\n        r1 = orm.find by id dbc \"users\" 42\n        sc = solstice.Conn 200\n        r2 = solstice.query sc\n        r3 = solstice.extract token \"payload\"\n        r4 = json get str (JDoc \"doc\") \"id\"\n        ac = Conn \"local\"\n        echo (r1 + \"|\" + (int to str r2) + \"|\" + r3 + \"|\" + r4 + \"|\" + (app_tag ac))\n"
        rc_vis_app = shell exec ("\"" + ridgunc_bin + "\" run --strict target/test_lib_work/vis_app.rg > target/test_lib_work/vis_app_out.txt 2>&1")
        assert int equals rc_vis_app 0 "FR-COMP-012 per-module import visibility run"
        assert str eq (str trim (read file "target/test_lib_work/vis_app_out.txt")) "db:7:users|200|codec:payload:tok|json:doc:id|local" "FR-COMP-012 per-module import visibility output"
        write file "target/test_lib_work/mod_b.rg" "module :: mod_b\n\nfn :: secret b only Int => Int\n      secret b only x = x + 99\n"
        write file "target/test_lib_work/mod_a.rg" "module :: mod_a\n\nfn :: leak attempt Int => Int\n      leak attempt x = secret b only x\n"
        write file "target/test_lib_work/leak_app.rg" "import mod_b\nimport mod_a\n\nfn :: main => ()\n      main =\n        echo (int to str (mod_a.leak attempt 1))\n"
        rc_leak = shell exec ("\"" + ridgunc_bin + "\" check target/test_lib_work/leak_app.rg > target/test_lib_work/leak_out.txt 2>&1")
        assert true (rc_leak != 0)
        shell exec "rm -rf target/test_lib_work"
        echo "=== All library compilation, stable plugin & PAL timeout tests passed ==="
