-- case: `sys call` accepts 1..7 arguments by zero-padding omitted syscall registers and never emits undefined `@__rg_fn_0` in live or DCE-eliminated agent workers (TASK-0045)
-- source: FR-COMP-007 (system call lowering) and FR-COMP-009 (agents)
-- expect-output:
--   True
--   pg:live

fn :: dce syscall6 worker String => String
      dce syscall6 worker s =
        pid = sys call 39 0 0 0 0 0
        (pid > 0) -> ok
        "dce:" + s

fn :: live syscall6 worker String => String
      live syscall6 worker s =
        pid = sys call 39 0 0 0 0 0
        (pid > 0) -> ok
        "pg:" + s

fn :: run live session String => String
      run live session dsn =
        ag = agent (live syscall6 worker)
        res = ask ag dsn
        stop ag
        res

fn :: main => ()
      main =
        p1 = sys call 39
        p3 = sys call 39 0 0
        p6 = sys call 39 0 0 0 0 0
        p7 = sys call 39 0 0 0 0 0 0
        echo (p1 > 0 and p1 == p3 and p3 == p6 and p6 == p7)
        echo (run live session "live")
