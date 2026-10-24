-- case: sys_exit n ends the program with exit status n, without running what follows
-- source: FR-VM-002:32,45 (sys_exit n exits with code n)
-- expect-output:
--   before
-- expect-exit: 3

fn :: main => ()
      main =
        _ = echo "before"
        _ = sys_exit 3
        echo "after"
