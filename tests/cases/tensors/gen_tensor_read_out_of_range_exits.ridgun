-- @tests TS-COMP-020
-- case: reading a Tensor of String outside its shape stops the program with a runtime error and exit status 1 instead of returning a zero value
-- source: spec.md "Tensors" (index out of range); FR-COMP-020 §8
-- expect-output:
--   before
--   runtime error: tensor index out of range
-- expect-exit: 1

fn :: main => ()
      main =
        t = Tensor[String * 2]
        echo "before"
        echo t_(2)
        echo "unreachable"
