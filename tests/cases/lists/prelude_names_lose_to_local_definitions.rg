-- @tests TS-COMP-024
-- case: a program's own definition of a prelude name wins without an ambiguity error, other prelude helpers stay available, and `import prelude` does nothing
-- source: FR-COMP-024 (requirements 1 and 2); ADR-0004
-- expect-output:
--   mine [b, a]
--   [9] [1]

import prelude

fn :: str join [String] String => String
      str join _ _ =  "mine"

fn :: list take [Int] Int => [Int]
      list take _ _ =  [9]

fn :: main => ()
      main =
        echo (str join ["a"] ",") (list reverse ["a", "b"])
        echo (list take [1, 2] 1) (list drop [0, 1] 1)
