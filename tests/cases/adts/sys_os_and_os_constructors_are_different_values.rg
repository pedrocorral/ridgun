-- @tests TS-COMP-015
-- case: the constructors `Linux`, `MacOS` and `Windows` written as values keep their own value; only `sys os` reads the system (`sys os` has its own marker that Windows and macOS images rewrite)
-- source: FR-COMP-015; Solstice report sysos-literal-rewritten (2026-11-12)
-- expect-output:
--   Linux -> linux
--   MacOS -> macos
--   Windows -> windows
--   sys os -> linux
--   all: [linux, macos, windows]
--   Linux == sys os: True

fn :: name of SysOs => String
      name of Linux   =  "linux"
      name of MacOS   =  "macos"
      name of Windows =  "windows"

fn :: main => ()
      main =
        a = name of Linux
        b = name of MacOS
        c = name of Windows
        d = name of (sys os)
        echo "Linux -> {a}"
        echo "MacOS -> {b}"
        echo "Windows -> {c}"
        echo "sys os -> {d}"
        echo "all:" ([Linux, MacOS, Windows] -> map name of)
        echo "Linux == sys os:" ((name of Linux) == (name of (sys os)))
