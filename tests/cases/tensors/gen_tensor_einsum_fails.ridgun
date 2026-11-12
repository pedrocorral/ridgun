-- @tests TS-COMP-020
-- case: einsum (@) on a tensor of non-numeric elements is a compile error
-- source: spec.md "Tensors" (element types); FR-COMP-020 §7
-- expect-build-error: einsum (@) needs a tensor of numbers, got a tensor of String

fn :: main => ()
      main =
        a = Tensor[String * 2 * 2]
        b = Tensor[String * 2 * 2]
        c = a_ij @ b_jk
        echo "unreachable"
