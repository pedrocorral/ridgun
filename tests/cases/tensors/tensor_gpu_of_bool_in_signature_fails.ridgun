-- @tests TS-COMP-018
-- case: a non-numeric element type in a Tensor_GPU parameter type is a compile error that names the function
-- source: spec.md "Tensors" (element types); FR-COMP-018 §1-§2; FR-COMP-020 §7
-- expect-build-error: Tensor_GPU element type 'Bool' is not supported: a Tensor_GPU holds numbers only (Int, Byte, U8, U16, U32, U64, I8, I16, I32, I64, Usize, Real, Float) in function 'count set'

fn :: count set Tensor_GPU[Bool * n] Int => Int
      count set t i = i

fn :: main => ()
      main =  echo (int to str (count set (Tensor [1, 0, 1]) 0))
