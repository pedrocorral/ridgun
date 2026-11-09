-- @tests TS-COMP-005
-- case: and, or, xor, not, shl, shr, rotl and rotr can be words of a function name in any position, and calls to such functions work; the same words still act as operators elsewhere (libs report tensor-u8, 2026-11-09)
-- source: spec.md "Every lowercase token in a top-level signature is part of the function name"; FR-COMP-005
-- expect-output:
--   5
--   3
--   5
--   ab
--   8
--   5
--   True
--   False
--   16
--   2
--   7
--   1 False 8 4 True

fn :: mask xor Int Int => Int
      mask xor a b = a xor b

fn :: pred and Int Int => Int
      pred and a b = a + b

fn :: first str or String String => String
      first str or a b = a + b

fn :: xor first Int => Int
      xor first a = a * 2

fn :: and then Int => Int
      and then a = a + 1

fn :: not empty [Int] => Bool
      not empty [] = False
      not empty _ = True

fn :: rot shl Int Int => Int
      rot shl a b = a shl b

fn :: rot shr Int Int => Int
      rot shr a b = a shr b

fn :: spin rotl twice Int => Int
      spin rotl twice a = a + 2

fn :: main => ()
      main =
        echo (mask xor 6 3)
        x = mask xor 1 2
        echo x
        echo (pred and 2 3)
        echo (first str or "a" "b")
        echo (xor first 4)
        echo (and then 4)
        echo (not empty [1])
        echo (not empty [])
        echo (rot shl 1 4)
        echo (rot shr 8 2)
        echo (spin rotl twice 5)
        echo ((6 xor 3) and 1) (True and False) (1 shl 3) (16 shr 2) (not (1 == 2))
