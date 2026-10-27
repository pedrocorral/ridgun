-- ============================================================
-- src/test/ridgun/test parallel and tensors.rg
-- Ridgun Test Suite: Parallel where-DAG, Tensors & Regions
-- @implements FR-COMP-010
-- @implements FR-COMP-011
-- ============================================================

import test

fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  (fib (n - 1)) + (fib (n - 2))

fn :: fact Int => Int
      fact 0   =  1
      fact n   =  n * (fact (n - 1))

fn :: parallel dag calc => Int
      parallel dag calc =  a + b
        || fib 10       -> a
        || fact 6       -> b

fn :: parallel pipe heavy => Int Int
      parallel pipe heavy =
        || fib 10
        || fact 6

fn :: parallel pipe light => Int Int
      parallel pipe light =
        || triple val 4
        || triple val 5

fn :: tensor slice calc => Int
      tensor slice calc =
        m = Tensor [[1, 2], [3, 4]]
        m[0, 1] = 50
        m[0][1] + m[1][0]

fn :: tensor einsum hadamard Tensor Tensor => Int Int
      tensor einsum hadamard A      B      =
        c = A_ik @ B_kj
        h = A_ij + B_ij
        (c[0, 0] + c[1, 1], h[0, 0] + h[1, 1])

fn :: middle seq mask Int Int Int => Int
      middle seq mask (s)         =  s(_ + _)

type Result = Ok Int | QuotaExceeded

fn :: unwrap arena Result        => Int
      unwrap arena (Ok n)        =  n
      unwrap arena QuotaExceeded =  0 - 1

fn :: compute in arena => Result
      compute in arena =
        with region 64_KB do
          xs = [10, 20, 30]
          xs[1] + xs[2]

fn :: sumfreed keywords Int    Int     Int    Int    => Int
      sumfreed keywords global context shared atomic =  global + context + shared + atomic

fn :: scoped arena calc => Int String
      scoped arena calc =
        reg_val = unwrap arena (compute in arena)
        kw_sum = sumfreed keywords 3 4 5 3
        (reg_val + kw_sum, "phase3-region")

fn :: triple val Int => Int
      triple val x   =  x * 3

fn :: gt ten Int => Bool
      gt ten x   =  x > 10

fn :: sum pair Int Int => Int
      sum pair acc x   =  acc + x

fn :: apply hof (Int => Int) (Int Int => Int) [Int] => [Int] Int
      apply hof f            g                xs    =
        mapped = ||map f xs
        filtered = ||filter gt ten mapped
        total = fold g 0 filtered
        (filtered, total)

fn :: channel roundtrip String => String
      channel roundtrip msg    =
        ch = new channel
        send through msg ch
        receive from ch

type OptionStr = Some String | None

fn :: unwrap opt str OptionStr => String
      unwrap opt str (Some s)  =  s
      unwrap opt str None      =  "empty"

op :: procesar mensaje String con tiempo Int => String
      procesar mensaje msg    con tiempo t   =  "{msg}:{t}ms"

fn :: dormir agente Int => String
      dormir agente ms  =
        sys sleep ms ms
        "despierto-{ms}"

fn :: fst pipe fd (Int Int) => Int
      fst pipe fd (a, _)    =  a

fn :: snd pipe fd (Int Int) => Int
      snd pipe fd (_, b)    =  b

fn :: esperar pipe bloqueante Int => Int
      esperar pipe bloqueante ms =
        fds = sys pipe
        rfd = fst pipe fd fds
        wfd = snd pipe fd fds
        rc = sys poll rfd 1 ms
        sys close rfd
        sys close wfd
        rc

fn :: delegar espera pipe Int => Int
      delegar espera pipe ms  =  esperar pipe bloqueante ms

fn :: eco ligero Int => Int
      eco ligero x   =  x + 1

fn :: bombear agente (Agent Int Int) Int Int => Int
      bombear agente ag i n
        | i >= n = 0
        | otherwise =
          send i to ag
          r = receive from ag
          bombear agente ag r n

type OptionInt = Some Int | None

fn :: unwrap opt int OptionInt => Int
      unwrap opt int (Some n)  =  n
      unwrap opt int None      =  0 - 1

fn :: dormir con estado Int Int => Int
      dormir con estado acc ms  =
        sys sleep ms ms
        acc + ms

fn :: sumar visita Int     Int   => Int
      sumar visita visitas delta =  visitas + delta

type SesionHttp = usuario: String, peticiones: Int

op :: atender http SesionHttp String => SesionHttp String
      atender http ses        req
        | str starts with req "LOGIN:" =
          nombre = str slice req 6 (str len req)
          nueva = ses with usuario = nombre, peticiones = (peticiones ses) + 1
          (nueva, "200-LOGIN-{nombre}")
        | otherwise =
          n = (peticiones ses) + 1
          nueva = ses with peticiones = n
          quien = usuario ses
          (nueva, "200-{quien}-req-{n}")

fn :: consultar contador (Agent Int Int) Int => Int
      consultar contador ag              n   =
        send n to ag
        receive from ag

fn :: tensor shape sum Tensor[Byte] => Int
      tensor shape sum (Tensor[Byte * f * c] m) = f * 100 + c + m_(0, 0)
      tensor shape sum (Tensor[Byte * n] v) = n * 10 + v_(0)
      tensor shape sum _            =  0 - 1

fn :: inc vec elem Tensor[U64 * _] => Tensor[U64 * _]
      inc vec elem v               =
        v_(0) = v_(0) + 10
        v

fn :: double scalar U64 => U64
      double scalar x   =  x * 2

fn :: f blamka U64 U64 => U64
      f blamka x   y   =  x + y + 2 * ((x and 0xFFFFFFFF) * (y and 0xFFFFFFFF))

fn :: blamka g U64 U64 U64 U64 => U64 U64 U64 U64
      blamka g a b c d =
        mut a = f blamka a b
        mut d = (d xor a) rotr 32
        mut c = f blamka c d
        mut b = (b xor c) rotr 24
        a = f blamka a b
        d = (d xor a) rotr 16
        c = f blamka c d
        b = (b xor c) rotr 63
        (a, b, c, d)

fn :: blamka p16 Tensor[U64 * 16] => ()
      blamka p16 v                =
        v_(0), v_(4), v_(8),  v_(12) = blamka g v_(0) v_(4) v_(8)  v_(12)
        v_(1), v_(5), v_(9),  v_(13) = blamka g v_(1) v_(5) v_(9)  v_(13)
        v_(2), v_(6), v_(10), v_(14) = blamka g v_(2) v_(6) v_(10) v_(14)
        v_(3), v_(7), v_(11), v_(15) = blamka g v_(3) v_(7) v_(11) v_(15)
        v_(0), v_(5), v_(10), v_(15) = blamka g v_(0) v_(5) v_(10) v_(15)
        v_(1), v_(6), v_(11), v_(12) = blamka g v_(1) v_(6) v_(11) v_(12)
        v_(2), v_(7), v_(8),  v_(13) = blamka g v_(2) v_(7) v_(8)  v_(13)
        v_(3), v_(4), v_(9),  v_(14) = blamka g v_(3) v_(4) v_(9)  v_(14)

fn :: compress block Tensor[U64 * 8 * 16] Tensor[U64 * 8 * 16] => Tensor[U64 * 8 * 16]
      compress block x y =
        r_ij = x_ij xor y_ij
        z_ij = r_ij
        ||map blamka p16 in z_(i,)
        ||map blamka p16 in z_(,j)
        z_ij xor r_ij

type FnBox3 = cb3: (String String String => String)

fn :: join3 String String String => String
      join3 a0     a1     a2     =  a0 + a1 + a2

fn :: join4 String String String String => String
      join4 a0     a1     a2     a3     =  a0 + a1 + a2 + a3

fn :: join6 String String String String String String => String
      join6 a0 a1 a2 a3 a4 a5 = a0 + a1 + a2 + a3 + a4 + a5

fn :: call3 (String String String => String) String String String => String
      call3 g                                a0     a1     a2     =  g a0 a1 a2

fn :: call4 (String String String String => String) String String String String => String
      call4 g a0 a1 a2 a3 = g a0 a1 a2 a3

fn :: call6 (String String String String String String => String) String String String String String String => String
      call6 g a0 a1 a2 a3 a4 a5 = g a0 a1 a2 a3 a4 a5

fn :: call box3 FnBox3 String String String => String
      call box3 b a0 a1 a2 =
        f = cb3 b
        f a0 a1 a2

fn :: scale add Int  Int    Int => Int
      scale add base factor x   =  base + (factor * x)

fn :: make scaler Int Int => (Int => Int)
      make scaler b   f   =  scale add b f

fn :: run closure mem scope String => ()
      run closure mem scope tag    =
        pref = "pre-" + tag
        g = join4 pref ":"
        s1 = g "uno" "!"
        s2 = g "dos" "?"
        esc = make scaler 100 10
        nums = map esc [1, 2, 3]
        assert equals (s1 + "|" + s2) "pre-ok:uno!|pre-ok:dos?"
        assert equals nums [110, 120, 130]

fn :: bench blamka loop Tensor[U64 * 1 * 16] Int => Tensor[U64 * 1 * 16]
      bench blamka loop v                    rem
        | rem <= 0  = v
        | otherwise =
          map blamka p16 in v_(i,)
          bench blamka loop v (rem - 1)

fn :: bench sha256 raw loop String Int => String
      bench sha256 raw loop cur rem
        | rem <= 0  = cur
        | otherwise = bench sha256 raw loop (sha256 raw cur) (rem - 1)

fn :: mutate tensor ret int Tensor[U64 * 8 * 16] => Int
      mutate tensor ret int z                    =
        z_(3, 7) = 123456
        0

fn :: mutate row ret int Tensor[U64 * 16] => Int
      mutate row ret int r                =
        r_(5) = r_(5) + 77
        0

fn :: bench hmac sha256 fused String String String Int => String
      bench hmac sha256 fused ipad   opad   u      rem
        | rem <= 0  = u
        | otherwise =
          u_next = sha256 raw (opad + (sha256 raw (ipad + u)))
          bench hmac sha256 fused ipad opad u_next (rem - 1)

fn :: main => ()
      main =
        echo "=== Parallel || DAG, Tensors, Einsum, Masks & Region ==="
        assert equals (parallel dag calc) 775
        assert equals (tensor slice calc) 53
        ta = Tensor [[1, 2], [3, 4]]
        tb = Tensor [[2, 0], [1, 2]]
        assert equals (tensor einsum hadamard ta tb) (12, 9)
        assert equals (middle seq mask 10 42 99) 42
        assert equals (scoped arena calc) (65, "phase3-region")
        assert equals (apply hof triple val sum pair [2, 4, 6, 8]) ([12, 18, 24], 54)
        assert equals (channel roundtrip "phase4-channel-ok") "phase4-channel-ok"
        echo "=== FR-COMP-009: Native Agent Model (agent, send to, receive from, try receive from, stop) ==="
        ag_msg = agent (procesar mensaje con tiempo)
        assert equals (unwrap opt str (try receive from ag_msg)) "empty"
        send "pedido-1" 15 to ag_msg
        send "pedido-2" 30 to ag_msg
        sys sleep ms 10
        assert equals (unwrap opt str (try receive from ag_msg)) "pedido-1:15ms"
        assert equals (receive from ag_msg) "pedido-2:30ms"
        assert equals (unwrap opt str (try receive from ag_msg)) "empty"
        ag_cnt = agent (sumar visita) 10
        assert equals (agent alive ag_cnt) True
        assert equals (consultar contador ag_cnt 5) 15
        assert equals (consultar contador ag_cnt 7) 22
        assert equals (ask ag_cnt 8) 30
        assert equals (ask 12 to ag_cnt) 42
        stop ag_cnt
        assert equals (agent alive ag_cnt) False
        ag_http = agent (atender http) (SesionHttp "anon" 0)
        send "LOGIN:ana" to ag_http
        send "GET /carrito" to ag_http
        send "POST /comprar" to ag_http
        assert equals (receive from ag_http) "200-LOGIN-ana"
        assert equals (receive from ag_http) "200-ana-req-2"
        assert equals (receive from ag_http) "200-ana-req-3"
        assert equals (ask ag_http "GET /perfil") "200-ana-req-4"
        stop ag_http
        assert equals (agent alive ag_http) False
        ag_sleep = agent (dormir agente)
        t0 = sys time ms
        send 120 to ag_sleep
        t1 = sys time ms
        assert true ((t1 - t0) < 50)
        assert equals (unwrap opt str (try receive from ag_sleep)) "empty"
        sys sleep ms 170
        assert equals (unwrap opt str (try receive from ag_sleep)) "despierto-120"
        stop ag_sleep
        ag_sleep_st = agent (dormir con estado) 100
        ts0 = sys time ms
        send 120 to ag_sleep_st
        ts1 = sys time ms
        assert true ((ts1 - ts0) < 50)
        assert equals (unwrap opt int (try receive from ag_sleep_st)) (0 - 1)
        sys sleep ms 170
        ts2 = sys time ms
        assert equals (receive from ag_sleep_st) 220
        ts3 = sys time ms
        assert true ((ts3 - ts2) < 20)
        assert equals (ask ag_sleep_st 30) 250
        stop ag_sleep_st
        assert equals (parallel pipe heavy) (55, 720)
        assert equals (parallel pipe light) (12, 15)
        assert equals (||map fib [8, 9, 10]) [21, 34, 55]
        assert equals (||map fib [6, 7, 8, 9, 10, 11]) [8, 13, 21, 34, 55, 89]
        ag_fib = agent fib
        send 10 to ag_fib
        send 11 to ag_fib
        send 12 to ag_fib
        assert equals (receive from ag_fib) 55
        assert equals (receive from ag_fib) 89
        assert equals (receive from ag_fib) 144
        send 9 to ag_fib
        send 10 to ag_fib
        assert equals (receive from ag_fib) 34
        assert equals (receive from ag_fib) 55
        assert equals (ask ag_fib 11) 89
        assert equals (ask 12 to ag_fib) 144
        send 28 to ag_fib
        sys sleep ms 150
        t_fib0 = sys time ms
        assert equals (receive from ag_fib) 317811
        t_fib1 = sys time ms
        assert true ((t_fib1 - t_fib0) < 20)
        stop ag_fib
        assert equals (agent alive ag_fib) False
        -- RG-093 regression test: two agents blocking on empty pipes via poll_fd_ms must overlap in ~300 ms (< 480 ms), not 600 ms
        ag_poll1 = agent (delegar espera pipe)
        ag_poll2 = agent (delegar espera pipe)
        tp0 = sys time ms
        send 300 to ag_poll1
        send 300 to ag_poll2
        rp1 = receive from ag_poll1
        rp2 = receive from ag_poll2
        tp1 = sys time ms
        poll_overlap_ms = tp1 - tp0
        echo "  [bench] 2 x 300 ms blocking poll_fd_ms agents elapsed:" poll_overlap_ms "ms"
        assert equals rp1 0
        assert equals rp2 0
        assert true (poll_overlap_ms >= 280 and poll_overlap_ms < 480)
        stop ag_poll1
        stop ag_poll2
        -- RG-069 regression test: 5,000 round-trip messages on a stateless agent must leak 0 CMM blocks
        ag_noleak = agent (eco ligero)
        bombear agente ag_noleak 0 10
        live_ag0 = cmm live blocks
        bombear agente ag_noleak 0 5000
        live_ag1 = cmm live blocks
        assert equals live_ag1 live_ag0
        stop ag_noleak
        echo "=== FR-COMP-010: Typed Tensors, Subscript Views, Axis Map & Bitwise Ops ==="
        assert equals (1 shl 8) 256
        assert equals (256 shr 4) 16
        assert equals ((1 shl 4) rotl 4) 256
        assert equals ((256 rotr 4) xor 3) 19
        assert equals (0xFF and 0x0F) 15
        assert equals (0xF0 or 0x0F) 255
        assert equals (not (not 42)) 42
        m23 = Tensor [[7, 8, 9], [10, 11, 12]]
        v4 = Tensor [5, 6, 7, 8]
        assert equals (tensor shape sum m23) 210
        assert equals (tensor shape sum v4) 45
        z23 = Tensor[Byte * 2 * 3]
        assert equals (tensor shape sum z23) 203
        z23_(1, 2) = 99
        assert equals z23_(1, 2) 99
        col1 = m23_(,1)
        assert equals col1_(0) 8
        assert equals col1_(1) 11
        z23_(0,) = Tensor [1, 2, 3]
        z23_(,2) = Tensor [30, 40]
        assert equals z23_(0, 1) 2
        assert equals z23_(0, 2) 30
        assert equals z23_(1, 2) 40
        m23Copy = map inc vec elem m23_(i,)
        assert equals m23_(0, 0) 7
        assert equals m23Copy_(0, 0) 17
        assert equals m23Copy_(1, 0) 20
        map double scalar in m23Copy_ij
        assert equals m23Copy_(0, 0) 34
        assert equals m23Copy_(1, 0) 40
        bx = Tensor[U64 * 8 * 16]
        by = Tensor[U64 * 8 * 16]
        bx_(0, 0) = 1
        by_(0, 0) = 2
        bz = compress block bx by
        assert equals (tensor shape sum bz) ((800 + 16) + bz_(0, 0))
        assert true (bz_(0, 0) != 0)
        assert equals (call3 join3 "a" "b" "c") "abc"
        assert equals (call4 join4 "a" "b" "c" "d") "abcd"
        assert equals (call6 join6 "a" "b" "c" "d" "e" "f") "abcdef"
        box3 = FnBox3 join3
        assert equals (call box3 box3 "x" "y" "z") "xyz"
        assert equals ((cb3 box3) "1" "2" "3") "123"
        assert equals (cb3 box3 "p" "q" "r") "pqr"
        live0 = cmm live blocks
        run closure mem scope "ok"
        assert equals (cmm live blocks) live0
        echo "=== Speed & Zero-Leak Benchmarks: sha256 raw & BlaMka Tensor Permutations ==="
        raw_empty = sha256 raw ""
        bytes_empty = sha256 bytes ""
        assert equals (str len raw_empty) 32
        assert equals raw_empty bytes_empty
        assert equals (str char at raw_empty 0) 227
        assert equals (str char at raw_empty 1) 176
        assert equals (str char at raw_empty 31) 85
        tb0 = sys time ms
        live_sha0 = cmm live blocks
        final_digest = bench sha256 raw loop "ridgun-bench-seed" 10000
        assert equals (str len final_digest) 32
        tb1 = sys time ms
        sha_ms = tb1 - tb0
        echo "  [bench] 10,000 x sha256 raw iterations:" sha_ms "ms"
        assert true (sha_ms < 500)
        mut bv = Tensor[U64 * 1 * 16]
        bv_(0, 0) = 1
        bv_(0, 1) = 2
        live_bl0 = cmm live blocks
        tb2 = sys time ms
        bv = bench blamka loop bv 2000
        tb3 = sys time ms
        bl_ms = tb3 - tb2
        assert equals (cmm live blocks) live_bl0
        assert true (bv_(0, 0) != 1)
        echo "  [bench] 2,000 x blamka p16 (16,000 x blamka g 4-tuple unpacks):" bl_ms "ms (0 heap leaks)"
        assert true (bl_ms < 500)
        echo "=== FR-COMP-011: O(N) Large 2D Tensor Allocation, In-Place Argument Mutation & Fused SHA-256 ==="
        xs_tail = [40, 50]
        assert equals (10:20:30:xs_tail) [10, 20, 30, 40, 50]
        assert equals (1:2:3:[]) [1, 2, 3]
        assert equals ("a":"b":["c", "d"]) ["a", "b", "c", "d"]
        t_alloc0 = sys time ms
        big_mem = Tensor[U64 * 160000 * 16]
        t_alloc1 = sys time ms
        alloc_ms = t_alloc1 - t_alloc0
        echo "  [bench] Tensor[U64 * 160000 * 16] (20 MiB) allocation:" alloc_ms "ms"
        assert true (alloc_ms < 200)
        big_mem_(0, 0) = 42
        big_mem_(159999, 15) = 999999
        assert equals big_mem_(0, 0) 42
        assert equals big_mem_(159999, 15) 999999
        mut z_mut = Tensor[U64 * 8 * 16]
        mutate tensor ret int z_mut
        assert equals z_mut_(3, 7) 123456
        map mutate row ret int in z_mut_(i,)
        assert equals z_mut_(0, 5) 77
        assert equals z_mut_(7, 5) 77
        s_a = "hello-"
        s_b = "world"
        s_ab = "hello-world"
        assert equals (sha256 raw (s_a + s_b)) (sha256 raw s_ab)
        live_hm0 = cmm live blocks
        ipad64 = "6666666666666666666666666666666666666666666666666666666666666666"
        opad64 = "\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\"
        seed32 = sha256 raw "pbkdf2-seed"
        pre_in = ipad64 + seed32
        fused_in = sha256 raw (ipad64 + seed32)
        assert equals fused_in (sha256 raw pre_in)
        th0 = sys time ms
        hm_out = bench hmac sha256 fused ipad64 opad64 seed32 10000
        th1 = sys time ms
        hm_ms = th1 - th0
        assert equals (str len hm_out) 32
        assert equals (cmm live blocks) live_hm0
        echo "  [bench] 10,000 x HMAC-SHA256 (20,000 x fused sha256 raw (pad64 + u)):" hm_ms "ms (0 heap leaks)"
        assert true (hm_ms < 200)
        echo "=== All parallel & tensor tests passed ==="
