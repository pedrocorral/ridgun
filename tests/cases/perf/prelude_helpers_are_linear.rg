-- @tests TS-COMP-024
-- case: the prelude's `list reverse` and `str join` run in linear time and constant stack: 1 000 000 elements reversed, 200 000 strings joined
-- source: FR-COMP-024 (requirement 4)
-- expect-output:
--   1000000 999999 0
--   399999 x,x,x
-- max-ms: 3000
-- max-rss-mb: 256

fn :: count up Int Int [Int] => [Int]
      count up i n acc
        | i >= n = acc
        | otherwise = count up (i + 1) n (acc :: [i])

fn :: copies Int [String] => [String]
      copies 0 acc =  acc
      copies n acc =  copies (n - 1) (acc :: ["x"])

fn :: main => ()
      main =
        r = list reverse (count up 0 1000000 [])
        echo (list len r) (list nth or r 0 (0 - 1)) (list last or r (0 - 1))
        j = str join (copies 200000 []) ","
        echo (str len j) (str slice j 0 5)
