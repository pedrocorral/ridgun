-- @tests TS-COMP-020
-- case: reading a two-dimensional tensor of Strings with a column outside its shape stops the program with a runtime error and exit status 1, after valid reads of the first and last element
-- source: spec.md "Tensors" (index out of range); FR-COMP-020 §8
-- expect-output:
--   a
--   z
--   runtime error: tensor index out of range
-- expect-exit: 1

fn :: main => ()
      main =
        g = Tensor[String * 2 * 3] with "a"
        g_(1, 2) = "z"
        echo g_(0, 0)
        echo g_(1, 2)
        echo g_(0, 3)
        echo "not reached"
