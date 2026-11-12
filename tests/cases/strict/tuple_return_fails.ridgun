-- case: --strict refuses a parenthesised, comma-separated tuple as a return type
-- source: book 02:193-197; FR-COMP-008 (space-separated tuple types)
-- expect-build-error: strict mode

fn :: pair => (Int, Int)
      pair =  (1, 2)

fn :: main => ()
      main =  echo "built"
