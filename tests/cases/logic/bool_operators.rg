-- case: and, or, xor, not on Bool give the classic truth tables
-- source: spec.md:313-329; FR-COMP-003 §4 (lowercase word operators)
-- expect-output:
--   and: False False False True
--   or: False True True True
--   xor: False True True False
--   not: True False

fn :: b Bool => String
      b True  =  "True"
      b False =  "False"

fn :: main => ()
      main =
        _ = echo ("and: " + (b (False and False)) + " " + (b (False and True)) + " " + (b (True and False)) + " " + (b (True and True)))
        _ = echo ("or: " + (b (False or False)) + " " + (b (False or True)) + " " + (b (True or False)) + " " + (b (True or True)))
        _ = echo ("xor: " + (b (False xor False)) + " " + (b (False xor True)) + " " + (b (True xor False)) + " " + (b (True xor True)))
        echo ("not: " + (b (not False)) + " " + (b (not True)))
