-- @tests TS-VM-003
-- case: a TCP listener, client and accepted connection on 127.0.0.1 in one thread: send both ways, receive into a String and into a Tensor[U8], shut down writing (the peer then reads 0) and close
-- source: FR-VM-003 AC1, ADR-0008
-- expect-output:
--   listen: True port: True connect: True accept: True
--   send: 4 4
--   recv: ping
--   recv into: 4 [0, 112, 111, 110, 103, 0]
--   peer: 127.0.0.1 True
--   after shutdown: 0
--   close: 0 0 0

fn :: main => ()
      main =
        srv = net listen "127.0.0.1" 0 4
        port = net local port srv
        c = net connect "127.0.0.1" port 2000
        a = net accept srv 2000
        echo "listen:" (srv >= 0) "port:" (port > 0) "connect:" (c >= 0) "accept:" (a >= 0)
        echo "send:" (net send c "ping" 2000) (net send a "pong" 2000)
        echo "recv:" (net recv a 64 2000)
        buf = tensor u8 from list [0, 0, 0, 0, 0, 0]
        n = net recv into c buf 1 4 2000
        echo "recv into:" n (tensor to list buf)
        echo "peer:" (net peer ip a) ((net local port c) != port)
        net shutdown c 1
        echo "after shutdown:" (net recv into a buf 0 6 2000)
        echo "close:" (sys close a) (sys close c) (sys close srv)
