-- ============================================================
-- harness/skills/implement-code-ridgun/references/cheatsheet.rg
-- Canonical Ridgun v0.9.3 Reference Cheatsheet for AI Agents
-- ============================================================

-- 1. Sum ADTs, Shared Constructors, Open `expand type` & Product Records (`FR-COMP-005`)
type Shape      = Circle Int | Rect Int Int
type Expr       = Var String | Lit Int
type Pat        = Var String | Lit Int | Wild
type AppErr     = IoError String | Timeout Int
type ServerSpec = host: String, port: Int, tls: Bool

fn :: format_err AppErr        => String
      format_err (IoError msg) =  "IO:{msg}"
      format_err (Timeout ms)  =  "TO:{ms}"
      format_err _             =  "UNKNOWN"

expand type AppErr = AuthError String | DbError Int String

fn :: format_err AppErr           => String
      format_err (AuthError user) =  "AUTH:{user}"
      format_err (DbError   code db) = "DB:{code}:{db}"

-- 2. Tabular Pattern Matching & Polymorphic Generics (A..Z)
fn :: head_or [A]   A => A
      head_or []    d =  d
      head_or (x:_) _ =  x

fn :: list_len [A]    => Int
      list_len []     =  0
      list_len (_:xs) =  1 + (list_len xs)

fn :: fst (A, B) => A
      fst (a, _) =  a

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

fn :: enable_tls ServerSpec => ServerSpec
      enable_tls spec       =  spec with tls: True, port: 443

-- 5. Deeply Nested Decision Trees (`|`) with Compact Inline `|.` Closers
fn :: route_request Int Int Bool Bool Int Int => Int
      route_request method role is_signed is_admin payload_kb rate_limited =
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
fn :: parallel_dag_calc Int  => Int
      parallel_dag_calc base =  net_a + net_b
        || base * 3          -> raw_a
        || base * 5          -> raw_b
        || raw_a - 2         -> net_a
        || raw_b + 1         -> net_b

fn :: parallel_dag_block Int  => Int
      parallel_dag_block base =
        || base + 10          -> left
        || base * 2           -> right ||.
        bonus =
          | left > 15 = 5
          | otherwise = 0 |.
        left + right + bonus

-- 7. Immutable (`x = ...`) vs Explicit Mutable (`mut x = ...`) Bindings
fn :: compute_invoice Bool   Int => Int
      compute_invoice is_vip raw =
        discount =
          | is_vip and raw > 50 = 20
          | otherwise           = 0
        mut total = raw - discount
        total = total + 5
        total

-- 8. First-Class Named Functions & Parallel List Combinators (`||map`, `||filter`)
fn :: double_val Int => Int
      double_val x   =  x * 2

fn :: is_even Int => Bool
      is_even x   =  (x % 2) == 0

fn :: add_pair Int Int => Int
      add_pair a   b   =  a + b

fn :: process_items [Int] => (Int, [Int])
      process_items xs    =
        seq_doubled = map double_val xs
        par_doubled = ||map double_val xs
        par_evens   = ||filter is_even par_doubled
        total       = fold add_pair 0 seq_doubled
        (total, par_evens)

-- 9. Zero-Argument Entrypoint (`fn :: main => ()`)
fn :: main => ()
      main =
        spec  = enable_tls (ServerSpec "localhost" 8080 False)
        code  = route_request 1 2 True True 500 0
        res   = process_items [1, 2, 3, 4, 5]
        total = fst res
        echo "Server {host spec}:{port spec} code={code} total={total}"
