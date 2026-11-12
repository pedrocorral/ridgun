-- case: Non-terminal `expr -> name` binds a local variable when `name` is referenced later in the block, even if a record field or unary function shares `name`; terminal `expr -> name` invokes the getter/function (TASK-0045)
-- source: FR-COMP-014 §1 (pipeline local binding vs unary function/getter call)
-- expect-output:
--   4
--   99
--   21
--   107
--   20

type Plan =
  target: Int

fn :: bump Int => Int
      bump x =  x + 1

fn :: run local target Int => Int
      run local target n =
        bump n -> target
        target

fn :: run terminal getter Plan => Int
      run terminal getter p =
        p -> target

fn :: tagval Int => Int
      tagval n =  n + 100

fn :: run local unary Int => Int
      run local unary x =
        x + 2 -> tagval
        tagval * 3

fn :: run terminal unary Int => Int
      run terminal unary x =
        x + 2 -> tagval

fn :: run rebind chain Int => Int
      run rebind chain x =
        mut target = 0
        x + 1 -> target
        target * 2 -> target
        target + 10

fn :: main => ()
      main =
        echo (run local target 3)
        echo (run terminal getter (Plan 99))
        echo (run local unary 5)
        echo (run terminal unary 5)
        echo (run rebind chain 4)
