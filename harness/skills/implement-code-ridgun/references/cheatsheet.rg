-- ============================================================
-- harness/skills/implement-code-ridgun/references/cheatsheet.rg
-- Canonical Ridgun v0.9.12 Reference Cheatsheet for AI Agents
-- ============================================================

-- 1. Sum ADTs, Shared Constructors, Bare Type Variants, `expand type` & Product Records (`FR-COMP-005`)
type Shape      = Circle Int | Rect Int Int
type Expr       = Var String | Lit Int
type Pat        = Var String | Lit Int | Wild
type AppErr     = IoError String | Timeout Int
type Something  = String | Int | MyStruct Float Int
type ServerSpec = host: String, port: Int, tls: Bool

fn :: format err AppErr        => String
      format err (IoError msg) =  "IO:{msg}"
      format err (Timeout ms)  =  "TO:{ms}"
      format err _             =  "UNKNOWN"

expand type AppErr = AuthError String | DbError Int String

fn :: format err AppErr              => String
      format err (AuthError user)    =  "AUTH:{user}"
      format err (DbError   code db) =  "DB:{code}:{db}"

fn :: describe something Something          => String
      describe something (String   s)       =  "str:{s}"
      describe something (Int      n)       =  "int:{n}"
      describe something (MyStruct f count) =  "struct:{f}:{count}"

-- 2. Tabular Pattern Matching, Natural Spaces in `fn ::`, Unified Tuple/Sequence Types (`FR-COMP-008`) & Generics (A..Z)
fn :: head or [A]   A => A
      head or []    d =  d
      head or (x:_) _ =  x

fn :: list len [A]    => Int
      list len []     =  0
      list len (_:xs) =  1 + (list len xs)

fn :: fst (A B) => A
      fst (a, _) =  a

fn :: parse header packet String => Int Int [String String] String
      parse header packet tag    =  (200, 2, [("Host", "ridgun.org"), ("X-Tag", tag)], "OK")

fn :: lookup header [String String] String => String
      lookup header []              _      =  "missing"
      lookup header ((k, v):rest)   key
        | k == key  = v
        | otherwise = lookup header rest key

fn :: area Shape      => Int
      area (Circle r) =  3 * r * r
      area (Rect w h) =  w * h

-- 3. Natural-Language Mixfix Operator (`op ::`) with `=` + `|` Guards
op :: clamp Int between Int and Int => Int
      clamp x   between lo  and hi  =
        | x < lo    = lo
        | x > hi    = hi
        | otherwise = x

-- 4. Contextual `type` and `with` Inside Mixfix & Record Updates
op :: format String type String with Int  => String
      format label  type kind   with size =  "{label}:{kind}:{size}"

fn :: enable tls ServerSpec => ServerSpec
      enable tls spec       =  spec with tls: True, port: 443

-- 5. Deeply Nested Decision Trees (`|`) with Compact Inline `|.` Closers
fn :: route request Int    Int  Bool      Bool     Int        Int          => Int
      route request method role is_signed is_admin payload_kb rate_limited =
        | method == 0 =
          | payload_kb == 0 = 204
          | otherwise       = 200 |.
        | method == 1 =
          | not is_signed = 401
          | otherwise =
            | rate_limited > 0 =
              | is_admin =
                | payload_kb > 10000 = 413
                | otherwise          = 202 |.
              | otherwise = 429 |.
            | payload_kb > 1000 =
              | role >= 2 and is_admin = 201
              | otherwise              = 413 |.
            | otherwise = 201 |.
        | otherwise = 405

-- 6. Parallel DAG Blocks (`|| expr -> var`, no `where`) & `||.` Closers
fn :: parallel dag calc Int  => Int
      parallel dag calc base =  net_a + net_b
        || base * 3          -> raw_a
        || base * 5          -> raw_b
        || raw_a - 2         -> net_a
        || raw_b + 1         -> net_b

fn :: parallel dag block Int  => Int
      parallel dag block base =
        || base + 10          -> left
        || base * 2           -> right ||.
        bonus =
          | left > 15 = 5
          | otherwise = 0 |.
        left + right + bonus

-- 7. Immutable (`x = ...`) vs Explicit Mutable (`mut x = ...`) Bindings
fn :: compute invoice Bool   Int => Int
      compute invoice is_vip raw =
        discount =
          | is_vip and raw > 50 = 20
          | otherwise           = 0
        mut total = raw - discount
        total = total + 5
        total

-- 8. First-Class Named Functions & Parallel List Combinators (`||map`, `||filter`)
fn :: double val Int => Int
      double val x   =  x * 2

fn :: is even Int => Bool
      is even x   =  (x % 2) == 0

fn :: add pair Int Int => Int
      add pair a   b   =  a + b

fn :: process items [Int] => Int [Int]
      process items xs    =
        seq_doubled = map double val xs
        par_doubled = ||map double val xs
        par_evens   = ||filter is even par_doubled
        total       = fold add pair 0 seq_doubled
        (total, par_evens)

-- 9. Multi-Word Functions Starting With `filter`/`map`/`fold` & Logical `and`/`or` (`FR-COMP-005`)
fn :: filter section loop Int Int => Int
      filter section loop a   b   =  (a * 10) + b

fn :: is comment or flag String => Bool
      is comment or flag line   =
        (str starts with line "--") or (str starts with line "#")

-- 10. Custom `stable` Tasks & Plugins in `build.rg` (`FR-TOOL-003`, `FR-COMP-006`)
fn :: project kind => String
      project kind =  "both"

fn :: plugins => [String]
      plugins =  []

fn :: task check all => String
      task check all =  "./bin/stable check"

-- 11. Declarative Timeouts (`with timeout`) & Cross-Platform PAL Primitives (`FR-COMP-007`)
fn :: check timeout budget => Int
      check timeout budget =
        with timeout 200_ms do
          rem = sys remaining ms
          rem

-- 12. Native Agent Model (`agent`, `send ... to`, `receive from`, `stop`) (`FR-COMP-009`)
fn :: add visits Int    Int   => Int
      add visits visits delta =  visits + delta

fn :: run visit agent => Int
      run visit agent =
        counter = agent (add visits) 10
        send 5 to counter
        res = receive from counter
        stop counter
        res

-- 13. User-Defined Generic ADTs & Records and Lexical Closures (`FR-COMP-013`)
type Result T E = Ok T | Err E
type Page T     = page_items: [T], page_total: Int

fn :: unwrap ok (Result A String) A => A
      unwrap ok (Ok v)            _ =  v
      unwrap ok (Err _)           d =  d

fn :: demo generics and closures Int => Int
      demo generics and closures offset =
        p    = Page [1, 2, 3] 3
        nums = map (x => x + offset) (page_items p)
        fold (acc x => acc + x) (unwrap ok (Ok 10) 0) nums

-- 14. Zero-Argument Entrypoint (`fn :: main => ()`)
fn :: main => ()
      main =
        spec  = enable tls (ServerSpec "localhost" 8080 False)
        code  = route request 1 2 True True 500 0
        res   = process items [1, 2, 3, 4, 5]
        total = (fst res) + (filter section loop 4 2) + (run visit agent)
        rem   = check timeout budget
        echo "Server {host spec}:{port spec} code={code} total={total} rem={rem}"
