-- case: cutting a text at any index k and joining the halves gives the text back (ASCII and UTF-8 text)
-- source: consistency: str_slice s a b takes [a, b) (book 03:130, harness skill:215), so for every k in 0..len,
--   str_slice s 0 k + str_slice s k len == s whatever the index unit; Solstice register RG-087 (slice snaps to UTF-8)
-- expect-output:
--   ascii ok
--   utf8 ok
--   whole ok

fn :: halves ok String Int => Bool
      halves ok s k =
        | k > (str_len s)                                                          = True
        | ((str_slice s 0 k) + (str_slice s k (str_len s))) != s                   = False
        | otherwise                                                                = halves_ok s (k + 1)

fn :: report String Bool => String
      report label True  =  label + " ok"
      report label False =  label + " FAILED"

fn :: main => ()
      main =
        _ = echo (report "ascii" (halves_ok "hello, world" 0))
        _ = echo (report "utf8" (halves_ok "aéb€c😀d" 0))
        echo (report "whole" ((str_slice "aéb" 0 (str_len "aéb")) == "aéb"))
