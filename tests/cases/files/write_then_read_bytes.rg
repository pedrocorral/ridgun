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
        data = bytes_from_list (upto 0 256 [])
        _ = write_file "bytes.bin" data
        back = read_file "bytes.bin"
        _ = echo ((int_to_str (str_len back)) + " bytes back")
        _ = echo ("same bytes: " + (bool_text (back == data)))
        _ = write_file "text.txt" "aé€"
        echo ("text: " + (read_file "text.txt"))
