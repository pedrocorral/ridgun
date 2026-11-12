-- case: read_file gives back exactly the bytes write_file wrote, for every byte value 0..255
-- source: consistency: write_file writes the bytes it is given (checked on disk) and read_file returns a file's
--   contents; Solstice register RG-089 (read_file changes bytes that aren't valid UTF-8: 1 024 bytes come back as 1 536)
-- expect-output:
--   256 bytes back
--   same bytes: True
--   text: aé€
-- uses-libs

import crypto

fn :: upto Int Int [Int] => [Int]
      upto i n acc =
        | i >= n    = acc
        | otherwise = upto (i + 1) n (acc :: [i])

fn :: bool text Bool => String
      bool text True  =  "True"
      bool text False =  "False"

fn :: main => ()
      main =
        data = bytes from list (upto 0 256 [])
        write file "bytes.bin" data
        back = read file "bytes.bin"
        echo ((int to str (str len back)) + " bytes back")
        echo ("same bytes: " + (bool text (back == data)))
        write file "text.txt" "aé€"
        echo ("text: " + (read file "text.txt"))
