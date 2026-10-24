-- case: :: joins two lists (no cons in expressions); [], (x:xs), (a:b:rest) and literal multi-cons patterns match
-- source: spec.md:351 (patterns), spec.md:363-368 and book 05:59-69 (:: concatenates), book 05:51-56 (multi-cons with literals)
-- expect-output:
--   [1, 2, 3, 4]
--   [1, 2]
--   [3, 4]
--   []
--   empty
--   one 7
--   two or more 1 2 rest [3]
--   copy a.txt b.txt
--   unknown command

fn :: show ints [Int] => String
      show ints []     =  "[]"
      show ints (x:xs) =  "[" + (int_to_str x) + (show rest xs) + "]"

fn :: show rest [Int] => String
      show rest []     =  ""
      show rest (x:xs) =  ", " + (int_to_str x) + (show rest xs)

fn :: describe [Int] => String
      describe []         =  "empty"
      describe (x:[])     =  "one " + (int_to_str x)
      describe (a:b:rest) =  "two or more " + (int_to_str a) + " " + (int_to_str b) + " rest " + (show_ints rest)

fn :: command [String] => String
      command ("copy":src:dst:[]) =  "copy " + src + " " + dst
      command _                   =  "unknown command"

fn :: main => ()
      main =
        _ = echo (show_ints ([1, 2] :: [3, 4]))
        _ = echo (show_ints ([1, 2] :: []))
        _ = echo (show_ints ([] :: [3, 4]))
        _ = echo (show_ints ([] :: []))
        _ = echo (describe [])
        _ = echo (describe [7])
        _ = echo (describe [1, 2, 3])
        _ = echo (command ["copy", "a.txt", "b.txt"])
        echo (command ["copy", "a.txt"])
