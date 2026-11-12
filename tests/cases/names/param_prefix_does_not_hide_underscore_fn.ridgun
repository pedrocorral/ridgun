-- @tests TS-COMP-007
-- case: Parameter or local variable x does not hide functions starting with x_ (RG-102)
-- source: FR-COMP-005
-- no-strict
-- expect-output:
--   25
--   True
--   False
--   a-b-c
--   ok:pipe

fn :: page_default_size => Int
      page_default_size =  25

fn :: ip_is_local String => Bool
      ip_is_local a =  a == "127.0.0.1"

fn :: text_join_all [String] => String
      text_join_all [] = ""
      text_join_all (x:[]) = x
      text_join_all (x:xs) = x + "-" + (text_join_all xs)

fn :: pipe_read String => String
      pipe_read p = "ok:" + p

fn :: with_default String => Int
      with_default page =  page_default_size

fn :: check String => Bool
      check ip =  ip_is_local ip

fn :: check_locals => ()
      check_locals =
        text = "a"
        echo (text_join_all [text, "b", "c"])
        pipe = "pipe"
        echo (pipe_read pipe)

fn :: main => ()
      main =
        echo (with_default "custom")
        echo (check "127.0.0.1")
        echo (check "10.0.0.1")
        check_locals
