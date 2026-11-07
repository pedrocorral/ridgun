-- @tests TS-COMP-020
-- case: a parallel write (|| expr -> out[i]) into a tensor of non-numeric elements is a compile error
-- source: spec.md "Tensors" (element types); FR-COMP-020 §11
-- expect-build-error: parallel writes into tensor 'out' of String are not supported: its elements are not numbers

fn :: shout String => String
      shout s =  s + "!"

fn :: fill out Tensor[String * 2] => Tensor[String * 2]
      fill out out =  out
        || shout "a" -> out[0]
        || shout "b" -> out[1]

fn :: main => ()
      main =  echo (fill out (Tensor[String * 2]))
