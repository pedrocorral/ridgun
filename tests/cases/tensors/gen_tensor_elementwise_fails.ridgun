-- @tests TS-COMP-020
-- case: an element-wise operator on a tensor of non-numeric elements is a compile error
-- source: spec.md "Tensors" (element types); FR-COMP-020 §7
-- expect-build-error: element-wise operator needs tensors of numbers, got a tensor of Bool

fn :: main => ()
      main =
        a = Tensor[Bool * 2 * 2]
        b = Tensor[Bool * 2 * 2]
        c = a_ij * b_ij
        echo "unreachable"
