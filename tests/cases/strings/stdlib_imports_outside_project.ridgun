-- case: standard library modules (str, io, posix, crypto) resolve outside project directories
-- source: FR-COMP-006; implement-code-ridgun §6
-- expect-output:
--   trimmed: hello
--   replaced: a-b-c
--   upper: RIDGUN
--   lower: ridgun
--   idx: 3
--   exists: True
--   sha256_len: 64

import str
import io
import posix
import crypto

fn :: b Bool => String
      b True  =  "True"
      b False =  "False"

fn :: main => ()
      main =
        echo ("trimmed: " + (str trim "  hello  "))
        echo ("replaced: " + (str replace "a_b_c" "_" "-"))
        echo ("upper: " + (str to upper "ridgun"))
        echo ("lower: " + (str to lower "RIDGUN"))
        echo ("idx: " + (int to str (str index of "abcdef" "def")))
        echo ("exists: " + (b (file exists ".")))
        echo ("sha256_len: " + (int to str (str len (sha256 hex "abc"))))
