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
      show ints (x:xs) =  "[" + (int to str x) + (show rest xs) + "]"

fn :: show rest [Int] => String
      show rest []     =  ""
      show rest (x:xs) =  ", " + (int to str x) + (show rest xs)

fn :: describe [Int] => String
      describe []         =  "empty"
      describe (x:[])     =  "one " + (int to str x)
      describe (a:b:rest) =  "two or more " + (int to str a) + " " + (int to str b) + " rest " + (show ints rest)

fn :: command [String] => String
      command ("copy":src:dst:[]) =  "copy " + src + " " + dst
      command _                   =  "unknown command"

fn :: main => ()
      main =
        echo (show ints ([1, 2] :: [3, 4]))
        echo (show ints ([1, 2] :: []))
        echo (show ints ([] :: [3, 4]))
        echo (show ints ([] :: []))
        echo (describe [])
        echo (describe [7])
        echo (describe [1, 2, 3])
        echo (command ["copy", "a.txt", "b.txt"])
        echo (command ["copy", "a.txt"])
