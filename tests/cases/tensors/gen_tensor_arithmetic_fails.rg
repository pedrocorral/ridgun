-- @tests TS-COMP-020
-- case: arithmetic between tensors of non-numeric elements is a compile error
-- source: spec.md "Tensors" (element types); FR-COMP-020 §7
-- expect-build-error: arithmetic operator + needs tensors of numbers, got a tensor of String

fn :: main => ()
      main =
        a = Tensor[String * 2]
        b = Tensor[String * 2]
        c = a + b
        echo "unreachable"
