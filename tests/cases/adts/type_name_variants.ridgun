-- case: a sum type with bare type-name variants accepts bare values and Type values, and matches literal and typed patterns
-- source: FR-COMP-005 §4 and AC-4 (type Something = String | Int | MyStruct Real Int, expand type Something = Bool)
-- expect-output:
--   admin string
--   string hello
--   zero
--   int 42
--   int 7
--   bool True
--   struct 3

type Something = String | Int | MyStruct Real Int
expand type Something = Bool

fn :: describe Something => String
      describe "admin"      =  "admin string"
      describe 0            =  "zero"
      describe (String s)   =  "string " + s
      describe (Int n)      =  "int " + (int to str n)
      describe (Bool True)  =  "bool True"
      describe (Bool False) =  "bool False"
      describe (MyStruct _ n) =  "struct " + (int to str n)

fn :: main => ()
      main =
        echo (describe "admin")
        echo (describe "hello")
        echo (describe 0)
        echo (describe 42)
        echo (describe (Int 7))
        echo (describe True)
        echo (describe (MyStruct 2.5 3))
