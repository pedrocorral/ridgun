-- @tests TS-VM-002
-- case: sys execve replaces the process as execve(2): argv is passed whole, argv[0] included, with the given environment; a missing program returns -errno (libs report tensor-u8, 2026-11-09)
-- source: FR-VM-002 (sys_execve)
-- expect-output:
--   before exec
--   -2
--   mysh one ok

fn :: main => ()
      main =
        echo "before exec"
        bad = sys execve "/nonexistent/prog" ["x"] []
        echo bad
        r = sys execve "/bin/sh" ["mysh", "-c", "a0=$(tr '\\000' '\\n' < /proc/$$/cmdline | head -1); echo \"$a0 $1 $RG_V\"", "zero", "one"] ["RG_V=ok", "PATH=/usr/bin:/bin"]
        echo "unreachable" r
