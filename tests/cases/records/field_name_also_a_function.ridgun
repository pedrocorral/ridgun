-- @tests TS-COMP-011
-- case: a user function with the same name as a record field wins over the generated accessor, also when the call is lowered as a direct field read (OPT-016); the other field still reads through its accessor
-- source: TASK-0059; docs/etc/compiler_optimizations.md OPT-016 (getter marks `"#g " + name`)
-- expect-output:
--   30
--   40
--   x

type P = size: Int, name: String

fn :: size P => Int
      size (P n _) = n * 10

fn :: main => ()
      main =
        p = P 3 "x"
        echo (size p)
        echo (size (P 4 "y"))
        echo (name p)
