-- @tests TS-COMP-018
-- case: tensors with numeric element types (Int, U64, Byte, Real) still build, and integer tensors keep the values written to them
-- source: spec.md "Tensors"; FR-COMP-018 §1
-- expect-output:
--   7
--   42
--   255
--   real tensor built

fn :: main => ()
      main =
        a = Tensor[Int * 3]
        a_(1) = 7
        b = Tensor[U64 * 2]
        b_(0) = 42
        c = Tensor[Byte * 2]
        c_(1) = 255
        r = Tensor[Real * 2 * 2]
        echo (int to str a_(1))
        echo (int to str b_(0))
        echo (int to str c_(1))
        echo "real tensor built"
