-- @tests TS-COMP-022
-- case: a shape pattern on a Tensor[U8] binds the real dimensions also when the tensor itself is `_` or has no name (libs report tensor-u8, 2026-11-09)
-- source: FR-COMP-022 §1, FR-COMP-020 (shape patterns)
-- expect-output:
--   300 300 300
--   5 5 5
--   203 203

fn :: len unnamed Tensor[U8] => Int
      len unnamed (Tensor[U8 * n] _) = n

fn :: len named Tensor[U8] => Int
      len named (Tensor[U8 * n] t) = n

fn :: len bare Tensor[Byte] => Int
      len bare (Tensor[Byte * n]) = n

fn :: grid unnamed Tensor[U8] => Int
      grid unnamed (Tensor[U8 * r * c] _) = r * 100 + c
      grid unnamed _ = 0 - 1

fn :: grid named Tensor[U8] => Int
      grid named (Tensor[U8 * r * c] g) = r * 100 + c
      grid named _ = 0 - 1

fn :: main => ()
      main =
        a = Tensor[U8 * 300]
        b = tensor from str "hello"
        g = Tensor[U8 * 2 * 3]
        echo (len unnamed a) (len named a) (len bare a)
        echo (len unnamed b) (len named b) (len bare b)
        echo (grid unnamed g) (grid named g)
