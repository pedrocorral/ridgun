-- @tests TS-COMP-020
-- case: a Tensor of String is written and read in place in one and two dimensions, is passed by reference to functions, shows its elements with echo and compares with ==
-- source: spec.md "Tensors" (element types); FR-COMP-020 §1, §3, §4, §10
-- expect-output:
--   [ana, , luis]
--   ana
--   [ana, eva, luis]
--   [[, , ], [, , x]]
--   x
--   True
--   False

fn :: first name Tensor[String * n] => String
      first name t =  t_(0)

fn :: set name Tensor[String * n] Int String => ()
      set name t i s =
        t_(i) = s
        ()

fn :: main => ()
      main =
        names = Tensor[String * 3]
        names_(0) = "ana"
        names_(2) = "luis"
        echo names
        echo (first name names)
        set name names 1 "eva"
        echo names
        grid = Tensor[String * 2 * 3]
        grid_(1, 2) = "x"
        echo grid
        echo grid_(1, 2)
        a = Tensor[String * 2]
        b = Tensor[String * 2]
        echo (a == b)
        b_(0) = "x"
        echo (a == b)
