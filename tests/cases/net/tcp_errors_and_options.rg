-- @tests TS-VM-003
-- case: TCP errors are negative errno numbers (refused, timeout, address in use), `localhost` resolves to 127.0.0.1, a `with timeout` block bounds a wait of -1, and `net option` sets nodelay and rejects an unknown name
-- source: FR-VM-003 AC2, AC4
-- expect-output:
--   refused: -111
--   accept timeout: -110
--   in a with timeout block: -110
--   resolve: 127.0.0.1 10.1.2.3
--   in use: -98
--   nodelay: 0 unknown: -92
--   connect to localhost: True

fn :: main => ()
      main =
        free = net listen "" 0 1
        free_port = net local port free
        sys close free
        echo "refused:" (net connect "127.0.0.1" free_port 1000)
        l = net listen "127.0.0.1" 0 1
        port = net local port l
        echo "accept timeout:" (net accept l 100)
        with timeout 100 do
          echo "in a with timeout block:" (net accept l (-1))
        echo "resolve:" (net resolve "localhost") (net resolve "10.1.2.3")
        echo "in use:" (net listen "127.0.0.1" port 1)
        c = net connect "localhost" port 1000
        echo "nodelay:" (net option c "nodelay" 1) "unknown:" (net option c "cork" 1)
        echo "connect to localhost:" (c >= 0)
        sys close c
        sys close l
