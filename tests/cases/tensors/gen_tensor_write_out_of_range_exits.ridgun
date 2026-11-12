-- @tests TS-COMP-020
-- case: writing a two-dimensional Tensor of String outside its shape stops the program with a runtime error and exit status 1
-- source: spec.md "Tensors" (index out of range); FR-COMP-020 §8
-- expect-output:
--   before
--   runtime error: tensor index out of range
-- expect-exit: 1

fn :: main => ()
      main =
        t = Tensor[String * 2 * 2]
        echo "before"
        t_(1, 2) = "x"
        echo "unreachable"
