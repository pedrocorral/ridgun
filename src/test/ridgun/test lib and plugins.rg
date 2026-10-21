-- ============================================================
-- src/test/ridgun/test lib and plugins.rg
-- Automated Verification of Library Compilation (.rglib & ELF64 .so)
-- and Extensible `stable` Tasks & Plugins
-- @tests FR-COMP-006
-- @tests FR-COMP-007
-- @tests FR-TOOL-003
-- ============================================================
import test

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
          _ = sys close pfd
          assert true (pr > 0)
          42

fn :: main => ()
      main =
        echo "=== FR-COMP-006: Reusable Library Compilation (.rglib & ELF64 ET_DYN .so) ==="
        _ = shell exec "mkdir -p target/test_lib_work"
        lib_src = "-- Reusable math & shape library (no main function)\ntype Shape = Circle Int | Rect Int Int\n\nfn :: math cube Int => Int\n      math cube x   =  x * x * x\n\nfn :: shape area Shape        => Int\n      shape area (Circle r)   =  3 * r * r\n      shape area (Rect   w h) =  w * h\n"
        _ = write file "target/test_lib_work/geom_lib.rg" lib_src
        st_lib = shell exec "./bin/ridgunc build --lib target/test_lib_work/geom_lib.rg -o target/test_lib_work/geom_lib"
        assert equals st_lib 0
        rglib_text = read file "target/test_lib_work/geom_lib.rglib"
        assert true (str starts with rglib_text "-- RGLIB1")
        assert true (str contains rglib_text "math cube")
        so_bytes = read bytes "target/test_lib_work/geom_lib.so"
        -- ELF64 magic: 0x7F 'E' 'L' 'F' (127, 69, 76, 70)
        assert equals (byte at so_bytes 0) 127
        assert equals (byte at so_bytes 1) 69
        assert equals (byte at so_bytes 2) 76
        assert equals (byte at so_bytes 3) 70
        -- ELF64 e_type at offset 16..17: ET_DYN = 3 (little-endian: 3, 0)
        assert equals (byte at so_bytes 16) 3
        assert equals (byte at so_bytes 17) 0
        -- Consumer program importing the compiled .rglib bundle
        app_src = "import \"target/test_lib_work/geom_lib.rglib\"\n\nfn :: check eq Int Int => ()\n      check eq a   b\n        | a == b = ()\n        | otherwise = sys exit 1\n\nfn :: main => ()\n      main =\n        _ = check eq (math cube 4) 64\n        _ = check eq (shape area (Rect 5 8)) 40\n        check eq (shape area (Circle 3)) 27\n"
        _ = write file "target/test_lib_work/consumer_app.rg" app_src
        st_app = shell exec "./bin/ridgunc run target/test_lib_work/consumer_app.rg"
        assert equals st_app 0
        echo "=== FR-TOOL-003: Extensible stable Custom Tasks & Plugins ==="
        _ = shell exec "rm -rf target/test_lib_work/web_proj && mkdir -p target/test_lib_work/web_proj/plugins"
        web_build = "fn :: project name => String\n      project name =  \"demo_web\"\n\nfn :: project version => String\n      project version =  \"0.1.0\"\n\nfn :: plugins => [String]\n      plugins =  [\"router\"]\n\nfn :: task serve => String\n      task serve =  \"printf SERVE_OK > target_serve.txt\"\n\nfn :: task db migrate => String\n      task db migrate =  \"printf MIGRATE_OK > target_migrate.txt\"\n"
        router_plugin = "fn :: task routes => String\n      task routes =  \"printf ROUTES_OK > target_routes.txt\"\n"
        _ = write file "target/test_lib_work/web_proj/build.rg" web_build
        _ = write file "target/test_lib_work/web_proj/plugins/router.rg" router_plugin
        st_serve = shell exec "cd target/test_lib_work/web_proj && ../../../bin/stable serve"
        assert equals st_serve 0
        assert equals (read file "target/test_lib_work/web_proj/target_serve.txt") "SERVE_OK"
        st_mig = shell exec "cd target/test_lib_work/web_proj && ../../../bin/stable db migrate"
        assert equals st_mig 0
        assert equals (read file "target/test_lib_work/web_proj/target_migrate.txt") "MIGRATE_OK"
        st_routes = shell exec "cd target/test_lib_work/web_proj && ../../../bin/stable routes"
        assert equals st_routes 0
        assert equals (read file "target/test_lib_work/web_proj/target_routes.txt") "ROUTES_OK"
        -- Test `stable built lib` on a library project
        st_new_lib = shell exec "cd target/test_lib_work && ../../bin/stable new --lib mathkit"
        assert equals st_new_lib 0
        st_built_lib = shell exec "cd target/test_lib_work/mathkit && ../../../bin/stable built lib"
        assert equals st_built_lib 0
        mathkit_so = read bytes "target/test_lib_work/mathkit/target/libmathkit.so"
        assert equals (byte at mathkit_so 0) 127
        assert equals (byte at mathkit_so 16) 3
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
        -- 3. Normalized PAL flags `sys open` (1 | 64 | 1024 = 1089 = write+create+append)
        afd = sys open pal_file 1089 420
        assert true (afd >= 0)
        _ = sys write fd afd "!"
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
        -- 5. `with timeout`, `sys deadline ms`, `sys remaining ms`, nested clamping & `sys poll`
        assert equals (sys deadline ms) 0
        assert equals (sys remaining ms) (0 - 1)
        t0 = sys time ms
        _ = sys sleep ms 10_ms
        t1 = sys time ms
        assert true (t1 >= (t0 + 5))
        outer_res = run pal timeout block pal_file
        assert equals outer_res 42
        -- After exiting `with timeout`, deadline is restored to 0 / -1
        assert equals (sys deadline ms) 0
        assert equals (sys remaining ms) (0 - 1)
        _ = shell exec "rm -rf target/test_lib_work"
        echo "=== All library compilation, stable plugin & PAL timeout tests passed ==="
