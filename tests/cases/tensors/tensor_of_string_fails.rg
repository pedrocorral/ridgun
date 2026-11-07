-- @tests TS-COMP-018
-- case: a tensor of String is a compile error instead of a tensor that silently stores nothing
-- source: spec.md "Tensors" (numeric type); FR-COMP-018 §1
-- expect-build-error: tensor element type 'String' is not supported: a tensor holds numbers only

fn :: main => ()
      main =
        t = Tensor[String * 3]
        t_(1) = "hola"
        echo t_(1)
