-- @tests TS-COMP-024
-- case: the prelude's helpers work without `import`, for any element type: Int, String, tuples and ADTs; take and drop accept n <= 0 and n past the end; nth or and last or return the default when there is no element
-- source: FR-COMP-024; ADR-0004
-- expect-output:
--   [3, 2, 1] [] [c, b, a]
--   [1, 2] [] [] [1, 2, 3]
--   [3] [1, 2, 3] [] []
--   20 -1 -1 z
--   3 0 b 3 0
--   True False True False True
--   a, b, c | x |  | a--b
--   [(2, b), (1, a)] [Blue, Red]

type Colour = Red | Green | Blue

fn :: colour name Colour => String
      colour name Red   =  "Red"
      colour name Green =  "Green"
      colour name Blue  =  "Blue"

fn :: show pair (Int, String) => String
      show pair (n, t) =  "(" + (int to str n) + ", " + t + ")"

fn :: show pairs [(Int, String)] => String
      show pairs ps =  "[" + (str join (map show pair ps) ", ") + "]"

fn :: show colours [Colour] => String
      show colours cs =  "[" + (str join (map colour name cs) ", ") + "]"

fn :: main => ()
      main =
        xs = [1, 2, 3]
        echo (list reverse xs) (list reverse []) (list reverse ["a", "b", "c"])
        echo (list take xs 2) (list take xs 0) (list take xs (0 - 1)) (list take xs 9)
        echo (list drop xs 2) (list drop xs 0) (list drop xs 3) (list drop xs 9)
        echo (list nth or [10, 20, 30] 1 (0 - 1)) (list nth or [10, 20] 5 (0 - 1)) (list nth or [] 0 (0 - 1)) (list nth or ["y", "z"] 1 "")
        echo (list last or xs 0) (list last or [] 0) (list last or ["a", "b"] "") (list len xs) (list len [])
        echo (list contains xs 2) (list contains xs 7) (list contains [(1, "a"), (2, "b")] (2, "b")) (list contains [Red, Green] Blue) (list contains ["p", "q"] "q")
        echo (str join ["a", "b", "c"] ", ") "|" (str join ["x"] "-") "|" (str join [] "-") "|" (str join ["a", "b"] "--")
        echo (show pairs (list reverse [(1, "a"), (2, "b")])) (show colours (list reverse [Red, Blue]))
