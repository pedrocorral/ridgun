-- case: a parameter or local binding named like a top-level 0-argument function refers to the parameter or binding
-- source: lexical scoping of parameters and bindings (spec.md:105-123, 674-695); the compiler team's TASK-0024
--   ("allow local parameters/bindings to shadow 0-arg top-level functions"), fixing Solstice register RG-073/RG-035
-- expect-output:
--   51
--   7
--   100

fn :: store => Int
      store =  1

fn :: total => Int
      total =  100

fn :: bump Int => Int
      bump store =  store + 41

fn :: local sum => Int
      local sum =
        total = 3 + 4
        total

fn :: main => ()
      main =
        echo (int to str (bump 10))
        echo (int to str (local sum))
        echo (int to str total)
