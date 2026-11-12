-- @tests TS-COMP-020
-- case: writing a Real tensor at a negative index stops the program with a runtime error and exit status 1; negative indices do not count from the end
-- source: spec.md "Tensors" (index out of range); FR-COMP-020 §8
-- expect-output:
--   1.5
--   runtime error: tensor index out of range
-- expect-exit: 1

fn :: main => ()
      main =
        t = Tensor[Real * 3]
        t_(2) = 1.5
        echo t_(2)
        t_(0 - 1) = 2.5
        echo "not reached"
