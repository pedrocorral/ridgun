-- ============================================================
-- src/test/ridgun/test core language.rg
-- Ridgun Test Suite: ADTs, Custom Operators & Variadics
-- @tests FR-COMP-001
-- @tests FR-COMP-002
-- @tests FR-COMP-003
-- @tests FR-COMP-005
-- @tests FR-COMP-012
-- @tests FR-COMP-013
-- ============================================================

import test

type Shape = Circle Int | Rect Int Int

fn :: area Shape      => Int
      area (Circle r) =  3 * r * r
      area (Rect w h) =  w * h

op :: clamp Int between Int and Int => Int
      clamp x   between lo  and hi
        | x < lo = lo
        | x > hi = hi
        | otherwise = x

fn :: sum int list [Int]  => Int
      sum int list []     =  0
      sum int list (x:xs) =  x + (sum int list xs)

fn :: sum variadic Int... => Int
      sum variadic items  =  sum int list items

fn :: double val Int => Int
      double val n   =  n * 2

fn :: is even Int => Bool
      is even n   =  (n % 2) == 0

fn :: add pair Int Int => Int
      add pair acc x   =  acc + x

fn :: apply twice (Int => Int) Int => Int
      apply twice f            x   =  f (f x)

list len [A]    => Int
list len []     =  0
list len (_:xs) =  1 + (list len xs)

swap A with B => (B, A)
swap x with y =  (y, x)

fst (A, B) => A
fst (a, _) =  a

head or [A]   A => A
head or []    d =  d
head or (x:_) _ =  x

type LsSpec = one_per_line: Bool, color: Bool, width: Int

op :: format String type String with Int  => String
      format label  type type   with with =  "{label}:{type}:{with}"

fn :: guard block calc Int Int   => Int
      guard block calc idx limit
        | idx >= limit =
          capped = limit - 1
          scaled = capped * 2
          scaled + 10
        | otherwise =
          next_i = idx + 1
          next_i * 3

fn :: elegir Bool [Int] [Int] => [Int]
      elegir cond a     b
        | cond = a
        | otherwise = b

-- @tests FR-COMP-002
fn :: cmm trace elegir Bool => Int Int Int Int Int Int
      cmm trace elegir cond =
        base_live = cmm_live_blocks
        base_freed = cmm_cond_freed
        base_spared = cmm_cond_spared
        a = [10, 20, 30]
        b = [40, 50, 60]
        vivos_ab = cmm_live_blocks - base_live
        c = elegir cond a b
        vivos_tras_elegir = cmm_live_blocks - base_live
        _ = list len a
        vivos_tras_usar_a = cmm_live_blocks - base_live
        _ = list len c
        vivos_tras_usar_c = cmm_live_blocks - base_live
        delta_freed = cmm_cond_freed - base_freed
        delta_spared = cmm_cond_spared - base_spared
        (vivos_ab, vivos_tras_elegir, vivos_tras_usar_a, vivos_tras_usar_c, delta_freed, delta_spared)

fn :: cmm check ptr identity Bool => Bool Bool
      cmm check ptr identity cond =
        a = [1, 2, 3]
        b = [4, 5, 6]
        c = elegir cond a b
        same_a = cmm same ptr a c
        same_b = cmm same ptr b c
        (same_a, same_b)

fn :: cmm trace cascada Bool Bool => Int Int Int
      cmm trace cascada c1   c2   =
        base = cmm_live_blocks
        a = [1, 2]
        b = [3, 4]
        d = [5, 6]
        c = elegir c1 a b
        e = elegir c2 c d
        vivos_tras_cascada = cmm_live_blocks - base
        _ = list len a
        vivos_tras_a = cmm_live_blocks - base
        _ = list len e
        vivos_tras_e = cmm_live_blocks - base
        (vivos_tras_cascada, vivos_tras_a, vivos_tras_e)

fn :: rmm2 trace nested => Int Int Int
      rmm2 trace nested =
        base = cmm_live_blocks
        a = [10, 20]
        b = [30, 40]
        xs = [a, b]
        vivos_inicial = cmm_live_blocks - base
        _ = list len xs
        vivos_tras_xs = cmm_live_blocks - base
        _ = list len a
        vivos_final = cmm_live_blocks - base
        (vivos_inicial, vivos_tras_xs, vivos_final)

-- @tests FR-COMP-003
-- 1. Unified `=` before `|` and 4-level nested decision tree with inline `|.` closers
fn :: route request Int Int Bool Bool Int Int => Int
      route request method role is_signed is_admin payload_kb rate_limited =
        | method == 0 =
          | payload_kb == 0 = 204
          | otherwise = 200 |.
        | method == 1 =
          | not is_signed = 401
          | otherwise =
            -- Level 2: signed POST request
            | rate_limited > 0 =
              -- Level 3: rate-limited check
              | is_admin =
                -- Level 4: admin override under rate limit
                | payload_kb > 10000 = 413
                | otherwise = 202 |.
              | otherwise = 429 |.
            | payload_kb > 1000 =
              -- Level 3: back from Level 4 via `|.`!
              | role >= 2 and is_admin = 201
              | otherwise = 413 |.
            | otherwise = 201 |.
        | method == 2 and (is_admin or role >= 3) = 200
        | otherwise = 405

-- 2. Local variable assigned via guard block (`x =\n  | ...`) and inline `|.`
fn :: compute shipping Bool   Int    Bool       => Int
      compute shipping is_vip weight is_express =
        base_fee =
          | is_vip =
            | weight > 50 = 10
            | otherwise = 0 |.
          | weight > 50 = 35
          | otherwise = 15
        surcharge =
          | is_express and not is_vip = 12
          | otherwise = 0
        base_fee + surcharge

-- 3. Parallel DAG bindings (`|| expr -> var`) without `where` + inline `||.`
fn :: parallel dag calc Int Int => Int
      parallel dag calc x   y   =
        || x * x       -> x2
        || y * y       -> y2
        || x2 + y2     -> sum_sq ||.
        offset = 10
        sum_sq + offset

fn :: parallel dag bottom Int Int => Int
      parallel dag bottom a   b   =  prod + diff
        || a * b -> prod
        || a - b -> diff

-- 4. Mutable local variables (`mut x = ...`) with `RMM2` heap rebinding
fn :: accum and rebind Int => Int Int Int
      accum and rebind n   =
        base = cmm_live_blocks
        mut acc = n
        acc = acc + 10
        acc = acc * 2
        mut items = [1, 2, 3]
        live_before_rebind = cmm_live_blocks - base
        items = [10, 20, 30, 40]
        live_after_rebind = cmm_live_blocks - base
        total = acc + (list len items)
        (total, live_before_rebind, live_after_rebind)

-- 5. Lowercase logical operators (`and`, `or`, `xor`, `not`)
fn :: eval logic ops Bool Bool => Bool Bool Bool Bool
      eval logic ops a    b    =
        (a and b, a or b, a xor b, not a)

-- ============================================================
-- FR-COMP-005: Shared ADT Constructors, Bare Type Variants, `expand type`,
-- Automatic `fn ::` Merging, and Natural Spaces in `fn ::`
-- ============================================================

type ParseOut = Parsed Int | Error String
type DbOut    = Rows Int   | Error Int String
type MiniExpr = Var String | Lit Int
type MiniPat  = Var String | Lit Int | Wild

fn :: describe parse ParseOut    => String
      describe parse (Parsed n)  =  "parsed:{n}"
      describe parse (Error msg) =  "parse_err:{msg}"

fn :: describe db DbOut             => String
      describe db (Rows count)      =  "rows:{count}"
      describe db (Error code text) =  "db_err:{code}:{text}"

fn :: expr name MiniExpr   => String
      expr name (Var name) =  "expr_var:{name}"
      expr name (Lit n)    =  "expr_lit:{n}"

fn :: pat name MiniPat    => String
      pat name (Var name) =  "pat_var:{name}"
      pat name (Lit n)    =  "pat_lit:{n}"
      pat name Wild       =  "pat_wild"

type AppErr = IoError String | Timeout Int

fn :: format app err AppErr        => String
      format app err (IoError msg) =  "IO:{msg}"
      format app err (Timeout ms)  =  "TO:{ms}"
      format app err _             =  "UNKNOWN"

expand type AppErr = AuthError String | DbError Int String

fn :: format app err AppErr           => String
      format app err (AuthError user) =  "AUTH:{user}"
      format app err (DbError   code db) = "DB:{code}:{db}"

type AppConfig        = host: String, port: Int
expand type AppConfig = tls: Bool

type Something = String | Int | MyStruct Float Int

fn :: describe something Something    => String
      describe something "admin"      =  "special_admin"
      describe something 0            =  "zero_int"
      describe something (String   s) =  "str:{s}"
      describe something (Int      n) =  "int:{n}"
      describe something (MyStruct ratio cnt) = "struct:{ratio}:{cnt}"
      describe something _            =  "other"

expand type Something = Bool

fn :: describe something Something => String
      describe something (Bool b)  =  "bool:{b}"

-- Parser edge cases from unix-tools:
-- 1) Multi-word calls on the left of logical `and` / `or`
fn :: is comment or flag String => Bool
      is comment or flag t      =
        (str starts with t "--") or (str starts with t "#")

fn :: is scoped flag String => Bool
      is scoped flag t      =
        (str starts with t "--") and (str contains t "=")

-- 2) Multi-word functions starting with `filter`, `map`, or `fold`
fn :: filter section loop Int Int => Int
      filter section loop a   b   =  (a * 10) + b

fn :: map item value Int => Int
      map item value x   =  x + 100

fn :: fold pair sum Int Int => Int
      fold pair sum x   y   =  x + y + 1

-- 3) Symbolic Runtime Slots 1..16 (Tail-call frame slide & RMM2 rebind/cascade):
fn :: tco list accum Int [Int] => [Int]
      tco list accum 0   acc   =  acc
      tco list accum n   acc   =  tco list accum (n - 1) ([n] :: acc)

fn :: rmm2 rebind self trace => Int Int
      rmm2 rebind self trace =
        base = cmm_live_blocks
        mut xs = [100, 200, 300]
        xs = elegir True xs [400, 500]
        live_mid = cmm_live_blocks - base
        len_xs = list len xs
        (len_xs, live_mid)

-- 4) FR-COMP-008: Unified Space-Separated Tuple & Sequence Type Signatures:
fn :: parse header packet String => Int Int [String String] String
      parse header packet tag    =  (200, 2, [("Host", "ridgun.org"), ("X-Tag", tag)], "OK")

fn :: lookup header [String String] String => String
      lookup header []              _      =  "missing"
      lookup header ((k, v):rest)   key
        | k == key = v
        | otherwise = lookup header rest key

fn :: unpack nested tuple (Int [String String] String) => String
      unpack nested tuple (code, hdrs, msg)            =
        host_val = lookup header hdrs "Host"
        "{code}:{host_val}:{msg}"

-- 5) FR-COMP-012: Module Namespaces & Qualified Types:
module :: http

type Config =
  host: String
  port: Int

type Status = Ok Int | Failed String

fn :: default config => Config
      default config = Config "localhost" 8080

fn :: check status Config => Status
      check status cfg
        | (port cfg) == 8080 = Ok 200
        | otherwise = Failed "custom-port"

fn :: bump port Config Int => Config
      bump port cfg delta =
        cfg with port = (port cfg) + delta

module :: db

type Config =
  port: Int
  pool_size: Int

type Status = Ok String | Failed Int

fn :: default config => Config
      default config = Config 5432 16

fn :: check status Config => Status
      check status cfg
        | (port cfg) == 5432 = Ok "connected"
        | otherwise = Failed (port cfg)

fn :: bump port Config Int => Config
      bump port cfg delta =
        cfg with port = (port cfg) + delta

module :: main

import db as d

type HttpConfig = http.Config

fn :: describe http status http.Status => String
      describe http status (http.Ok code) = "http-ok:{code}"
      describe http status (http.Failed msg) = "http-err:{msg}"

fn :: describe db status d.Status => String
      describe db status (d.Status.Ok tag) = "db-ok:{tag}"
      describe db status (d.Status.Failed code) = "db-err:{code}"

fn :: total port pair http.Config d.Config => Int
      total port pair hcfg dcfg =
        (http.port hcfg) + (d.port dcfg)

type GenericResult T E = GenOk T | GenErr E

type GenericBox A = GenBox A

type GenericPage T = page_items: [T], page_total: Int

fn :: safe gen div Int Int => GenericResult Int String
      safe gen div _ 0 = GenErr "div-zero"
      safe gen div a b = GenOk (a / b)

fn :: unwrap gen int (GenericResult Int String) Int => Int
      unwrap gen int (GenOk v) _ = v
      unwrap gen int (GenErr _) d = d

fn :: unwrap gen str GenericResult String Int => String
      unwrap gen str (GenOk s) = "ok:" + s
      unwrap gen str (GenErr _) = "err"

fn :: unbox gen GenericBox A => A
      unbox gen (GenBox x) = x

fn :: page first str (GenericPage String) => String
      page first str p =
        xs = page_items p
        (int_to_str (page_total p)) + ":" + (head or xs "")

fn :: page sum two GenericPage Int => Int
      page sum two p =
        xs = page_items p
        (page_total p) + (sum int list xs)

fn :: with session check String (String => String) => String
      with session check tok handler = handler tok

fn :: run lazy thunk (=> Int) => Int
      run lazy thunk thunk = thunk ()

fn :: main => ()
      main =
        echo "=== Core Language, ADTs, Mixfix, Variadics & Higher-Order Ops ==="
        assert equals (area (Rect 6 7)) 42
        assert equals (clamp 150 between 0 and 100) 100
        assert equals (sum variadic 10 20 30 40) 100
        assert equals (apply twice double val 5) 20
        assert equals (list len [10, 20, 30, 40]) 4
        assert equals (list len ["a", "b", "c"]) 3
        assert equals (swap 7 with "ok") ("ok", 7)
        assert equals (fst (42, "hello")) 42
        assert equals (fst ("hello", 42)) "hello"
        assert equals (head or [10, 20] 99) 10
        assert equals (head or ["x", "y"] "z") "x"
        base_spec = LsSpec False False 80
        spec1 = base_spec with color = True
        spec2 = spec1 with one_per_line = True, width = 120
        assert equals (color spec1) True
        assert equals (width spec1) 80
        assert equals (one_per_line spec2) True
        assert equals (color spec2) True
        assert equals (width spec2) 120
        assert equals (format "box" type "solid" with 64) "box:solid:64"
        assert equals (guard block calc 10 10) 28
        assert equals (guard block calc 4 10) 15
        assert equals "$\{VAR:-default\}" '${VAR:-default}'
        assert equals "setenv \{ ok \}" 'setenv { ok }'
        assert equals "{{double}}" '{double}'
        assert equals (map double val [1, 2, 3, 4, 5]) [2, 4, 6, 8, 10]
        assert equals (||map double val [1, 2, 3, 4, 5]) [2, 4, 6, 8, 10]
        assert equals (filter is even [1, 2, 3, 4, 5, 6]) [2, 4, 6]
        assert equals (||filter is even [1, 2, 3, 4, 5, 6]) [2, 4, 6]
        assert equals (fold add pair 0 [1, 2, 3, 4, 5]) 15
        echo "=== RMM2 Assignment & Cascaded Structure Counting ==="
        assert equals (cmm check ptr identity True) (True, False)
        assert equals (cmm check ptr identity False) (False, True)
        assert equals (cmm trace elegir True) (2, 1, 1, 0, 2, 1)
        assert equals (cmm trace elegir False) (2, 2, 1, 0, 2, 1)
        assert equals (cmm trace cascada True True) (1, 1, 0)
        assert equals (cmm trace cascada False False) (2, 1, 0)
        assert equals (rmm2 trace nested) (3, 1, 0)
        echo "=== FR-COMP-003: Unified `=`, 4-Level Guards (`|.`), `||`, `mut`, and Lowercase Logic ==="
        assert equals (route request 0 1 False False 0 0) 204
        assert equals (route request 0 1 False False 50 0) 200
        assert equals (route request 1 1 False False 50 0) 401
        assert equals (route request 1 1 True True 20000 1) 413
        assert equals (route request 1 1 True True 500 1) 202
        assert equals (route request 1 1 True False 500 1) 429
        assert equals (route request 1 2 True True 2500 0) 201
        assert equals (route request 1 1 True False 2500 0) 413
        assert equals (route request 1 1 True False 100 0) 201
        assert equals (route request 2 3 True False 0 0) 200
        assert equals (route request 9 0 False False 0 0) 405
        assert equals (compute shipping True 60 True) 10
        assert equals (compute shipping True 20 True) 0
        assert equals (compute shipping False 60 True) 47
        assert equals (compute shipping False 20 False) 15
        assert equals (parallel dag calc 3 4) 35
        assert equals (parallel dag bottom 6 4) 26
        assert equals (accum and rebind 5) (34, 1, 1)
        assert equals (eval logic ops True False) (False, True, True, False)
        echo "=== FR-COMP-005: Shared ADT Constructors, expand type, and Clause Merging ==="
        assert equals (describe parse (Error "unexpected token")) "parse_err:unexpected token"
        assert equals (describe db (Error 500 "deadlock")) "db_err:500:deadlock"
        assert equals (expr name (Var "x")) "expr_var:x"
        assert equals (pat name (Var "x")) "pat_var:x"
        assert equals (expr name (Lit 42)) "expr_lit:42"
        assert equals (pat name (Lit 42)) "pat_lit:42"
        assert equals (format app err (IoError "disk full")) "IO:disk full"
        assert equals (format app err (Timeout 3000)) "TO:3000"
        assert equals (format app err (AuthError "alice")) "AUTH:alice"
        assert equals (format app err (DbError 504 "primary")) "DB:504:primary"
        cfg0 = AppConfig "localhost" 8080 False
        cfg1 = cfg0 with tls = True, port = 8443
        assert equals (host cfg1) "localhost"
        assert equals (port cfg1) 8443
        assert equals (tls cfg1) True
        assert equals (describe something "admin") "special_admin"
        assert equals (describe something "hej") "str:hej"
        assert equals (describe something (String "explicit")) "str:explicit"
        assert equals (describe something 0) "zero_int"
        assert equals (describe something 42) "int:42"
        assert equals (describe something (Int 99)) "int:99"
        assert equals (describe something (MyStruct 3.5 7)) "struct:3.5:7"
        assert equals (describe something True) "bool:True"
        assert equals (describe something (Bool False)) "bool:False"
        assert equals (is comment or flag "--help") True
        assert equals (is comment or flag "#comment") True
        assert equals (is comment or flag "plain") False
        assert equals (is scoped flag "--mode=fast") True
        assert equals (is scoped flag "--mode") False
        assert equals (filter section loop 4 2) 42
        assert equals (map item value 23) 123
        assert equals (fold pair sum 10 20) 31
        assert equals (tco list accum 5 []) [1, 2, 3, 4, 5]
        assert equals (rmm2 rebind self trace) (3, 1)
        echo "=== FR-COMP-008: Unified Space-Separated Tuple & Sequence Type Signatures ==="
        pkt = parse header packet "v0.9.9"
        assert equals pkt (200, 2, [("Host", "ridgun.org"), ("X-Tag", "v0.9.9")], "OK")
        assert equals (lookup header [("Host", "ridgun.org"), ("Mode", "native")] "Mode") "native"
        assert equals (unpack nested tuple (201, [("Host", "ridgun.org")], "CREATED")) "201:ridgun.org:CREATED"
        echo "=== FR-COMP-012: Module Namespaces & Qualified Types ==="
        h0 = http.default config
        d0 = d.default config
        assert equals (http.port h0) 8080
        assert equals (d.port d0) 5432
        assert equals (total port pair h0 d0) 13512
        h1 = http.bump port h0 100
        d1 = d.bump port d0 1
        assert equals (http.port h1) 8180
        assert equals (d.port d1) 5433
        h2 = h1 with http.port = 9090
        d2 = d1 with d.port = 6432
        assert equals (http.port h2) 9090
        assert equals (d.port d2) 6432
        h_alias = HttpConfig "0.0.0.0" 8080
        assert equals (describe http status (http.check status h_alias)) "http-ok:200"
        assert equals (describe http status (http.check status h2)) "http-err:custom-port"
        assert equals (describe db status (d.check status d0)) "db-ok:connected"
        assert equals (describe db status (d.check status d2)) "db-err:6432"
        assert equals (describe parse (ParseOut.Error "bad syntax")) "parse_err:bad syntax"
        assert equals (describe db (DbOut.Error 503 "unavailable")) "db_err:503:unavailable"
        echo "=== FR-COMP-013: User-Defined Generics & Lexical Closures ==="
        assert equals (unwrap gen int (safe gen div 84 2) 0) 42
        assert equals (unwrap gen int (safe gen div 84 0) 99) 99
        assert equals (unwrap gen str (GenOk (unbox gen (GenBox "ridgun")))) "ok:ridgun"
        p_str = GenericPage ["alpha", "beta"] 2
        p_int = GenericPage [10, 20, 30] 3
        assert equals (page first str p_str) "2:alpha"
        assert equals (page sum two p_int) 63
        offset = 10
        bonus = 3
        prefix = "sess:"
        assert equals (apply twice (x => x + offset) 5) 25
        assert equals (with session check "alice" (u => prefix + u)) "sess:alice"
        assert equals (map (x => x + offset) [1, 2, 3]) [11, 12, 13]
        assert equals (filter (x => x >= bonus) [1, 2, 3, 4]) [3, 4]
        assert equals (fold (acc x => acc + x + bonus) 0 [1, 2, 3]) 15
        assert equals (run lazy thunk (=> offset + bonus)) 13
        assert equals (map ((a b) => a + b + offset) [(1, 2), (3, 4)]) [13, 17]
        multi_res = map (x =>
          doubled = x * 2
          doubled + offset
        ) [1, 2, 3]
        assert equals multi_res [12, 14, 16]
        echo "=== All core language tests passed ==="
