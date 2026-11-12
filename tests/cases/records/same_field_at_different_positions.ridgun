-- case: two records of one module with a field of the same name at different positions: reading it, setting it with `with`, calling it and passing its accessor as a value use the position of the value's own record; a record of an imported module keeps its own position too (libs report campo-compartido, 2026-11-12)
-- source: FR-COMP-001 (records: field accessors and `with`)
-- expect-output:
--   cfg: 5000
--   conn: 5000
--   3 t! 1 s
--   u 2 u
--   7 v
--   [2, 2]
--   mail.x 10.0.0.1 ana
--   mx.y ana

module :: socket

type SockAddr = family: Int, host: String, port: Int

fn :: addr of String Int => SockAddr
      addr of h p =  SockAddr 2 h p

fn :: addr host SockAddr => String
      addr host a =  host a

module :: main

import socket

type Cfg  = name: String, timeout_ms: Int
type Conn = fd: Int, key: String, timeout_ms: Int

type A = x: Int, y: String
type B = y: Int, x: String

type SmtpConfig = host: String, user: String

fn :: mk conn Cfg => Conn
      mk conn cfg =  Conn 3 "secret" (timeout_ms cfg)

fn :: conn timeout Conn => Int
      conn timeout c =  timeout_ms c

fn :: getx B => String
      getx b =  x b

fn :: main => ()
      main =
        cfg = Cfg "x" 5000
        cn = mk conn cfg
        echo "cfg: {timeout_ms cfg}"
        echo "conn: {conn timeout cn}"
        a = A 1 "s"
        b = B 2 "t"
        echo ((y b) + 1) ((x b) + "!") (x a) (y a)
        c = b with x = "u"
        echo (x c) (y c) (getx c)
        d = a with y = "v", x = 7
        echo (x d) (y d)
        echo ([b, c] map y)
        sc = SmtpConfig "mail.x" "ana"
        ad = addr of "10.0.0.1" 25
        echo (host sc) (addr host ad) (user sc)
        e = sc with host = "mx.y"
        echo (host e) (user e)
