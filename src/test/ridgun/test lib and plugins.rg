-- ============================================================
-- src/test/ridgun/test lib and plugins.rg
-- Automated Verification of Library Compilation (.rglib & ELF64 .so)
-- and Extensible `stable` Tasks & Plugins
-- @tests FR-COMP-006
-- @tests FR-TOOL-003
-- ============================================================
import test

fn :: byte at [Int] Int => Int
      byte at []    _   =  -1
      byte at (b:_) 0   =  b
      byte at (_:bs) idx = byte at bs (idx - 1)

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
        _ = shell exec "rm -rf target/test_lib_work"
        echo "=== All library compilation & stable plugin tests passed ==="
