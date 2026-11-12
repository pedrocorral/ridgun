-- @tests TS-COMP-018
-- case: a Tensor_GPU of String is a compile error; only Tensor accepts non-numeric elements
-- source: spec.md "Tensors" (element types); FR-COMP-018 §1; FR-COMP-020 §7
-- expect-build-error: Tensor_GPU element type 'String' is not supported: a Tensor_GPU holds numbers only

fn :: main => ()
      main =
        t = Tensor_GPU[String * 3]
        echo "unreachable"
