-- case: str_char_at outside the text gives -1 (negative index, at the length, past it)
-- source: book 03:129 and harness skill:214 (str char at returns -1 out of range)
-- expect-output:
--   97
--   -1
--   -1
--   -1

fn :: main => ()
      main =
        echo (int to str (str char at "abc" 0))
        echo (int to str (str char at "abc" (0 - 1)))
        echo (int to str (str char at "abc" 3))
        echo (int to str (str char at "abc" 100))
