-- @tests TS-COMP-001
-- @tests TS-COMP-002
-- case: Built-in functions passed by name to map and fold execute properly (RG-055)
-- source: FR-COMP-002
-- expect-output:
--   [1, 2, 3]
--   [4, 5]
--   [1, 2, 3]
--   abc

fn :: main => ()
      main =
        [1, 2, 3] map int to str -> echo
        map (int to str) [4, 5] -> echo
        ["a", "bc", "def"] -> map (str len) -> echo
        ["a", "b", "c"] -> fold (str concat) "" -> echo
