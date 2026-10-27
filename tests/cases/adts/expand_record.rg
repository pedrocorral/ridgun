-- case: expand type adds fields to a record, with accessors and with updates
-- source: FR-COMP-005 §2 and AC-2 (ServerConfig example); record update form `r with f = v` (current syntax)
-- expect-output:
--   example.org:443 tls=True conns=100
--   example.org:8443 tls=True conns=200

type ServerConfig = host: String, port: Int
expand type ServerConfig = tls: Bool, max_conns: Int

fn :: describe ServerConfig => String
      describe c =  (host c) + ":" + (int to str (port c)) + " tls=" + (bool text (tls c)) + " conns=" + (int to str (max_conns c))

fn :: bool text Bool => String
      bool text True  =  "True"
      bool text False =  "False"

fn :: main => ()
      main =
        c = ServerConfig "example.org" 443 True 100
        echo (describe c)
        c2 = c with port = 8443, max_conns = 200
        echo (describe c2)
