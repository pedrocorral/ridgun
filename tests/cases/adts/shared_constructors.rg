-- case: two types share constructor names (Error); calls and patterns resolve by the expected type
-- source: FR-COMP-005 §1 and AC-1
-- expect-output:
--   ok 42
--   parse error: bad digit
--   3 rows
--   db error 7: locked

type ParseResult = Ok Int | Error String
type DbResult    = Rows Int | Error Int String

fn :: show parse ParseResult => String
      show parse (Ok n)    =  "ok " + (int_to_str n)
      show parse (Error m) =  "parse error: " + m

fn :: show db DbResult => String
      show db (Rows n)      =  (int_to_str n) + " rows"
      show db (Error c m)   =  "db error " + (int_to_str c) + ": " + m

fn :: main => ()
      main =
        _ = echo (show_parse (Ok 42))
        _ = echo (show_parse (Error "bad digit"))
        _ = echo (show_db (Rows 3))
        echo (show_db (Error 7 "locked"))
