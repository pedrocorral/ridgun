-- @tests TS-COMP-005
-- case: `not` and `with` can be words of a function name in any position, and calls to such functions work; elsewhere `not` still negates and `with` still updates a record (compiler defect report 2026-11-11, item 2)
-- source: spec.md "Every lowercase token in a top-level signature is part of the function name"; FR-COMP-005
-- expect-output:
--   loaded 1
--   not loaded 2
--   5 8 9
--   False 7

type Res = Loaded Int | NotLoaded [String]
type Rec = rv: Int

fn :: loaded or not Int [String] => Res
      loaded or not n   []       =  Loaded n
      loaded or not _   faults   =  NotLoaded faults

fn :: with record Int Int => Int
      with record a b =  a + b

fn :: is it not here Int => Int
      is it not here n =  n * 2

fn :: merge with Int => Int
      merge with n =  n + 1

fn :: show Res => String
      show (Loaded n)     =  "loaded {n}"
      show (NotLoaded fs) =  "not loaded {list len fs}"

fn :: main => ()
      main =
        echo (show (loaded or not 1 []))
        echo (show (loaded or not 1 ["a", "b"]))
        echo (with record 2 3) (is it not here 4) (merge with 8)
        r = Rec 3
        r2 = r with rv = 7
        echo (not True) (rv r2)
