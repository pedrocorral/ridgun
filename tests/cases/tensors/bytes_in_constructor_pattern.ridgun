-- @tests TS-COMP-022
-- case: a Tensor[U8] bound inside a constructor, a list cons or Some in a parameter pattern is read by bytes (libs report tensor-u8, 2026-11-09)
-- source: FR-COMP-022 §2
-- expect-output:
--   [97, 98, 99, 100]
--   98
--   abcd
--   120
--   122
--   0

type R = ROk Int Tensor[U8] | RErr String

fn :: as list R => [Int]
      as list (ROk _ p) = tensor to list p
      as list (RErr _)  = []

fn :: second R => Int
      second (ROk _ p) = p_(1)
      second (RErr _)  = 0

fn :: as str R => String
      as str (ROk _ p) = tensor to str p
      as str (RErr _)  = ""

fn :: head first [Tensor[U8]] => Int
      head first (t:_) = t_(0)
      head first [] = 0 - 1

fn :: some last (Option Tensor[U8]) => Int
      some last (Some t) = t_(2)
      some last None = 0

fn :: main => ()
      main =
        r = ROk 1 (tensor from str "abcd")
        echo (as list r)
        echo (second r)
        echo (as str r)
        echo (head first [tensor from str "xyz"])
        echo (some last (Some (tensor from str "xyz")))
        echo (second (RErr "no"))
