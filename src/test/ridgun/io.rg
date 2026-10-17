-- ============================================================
-- Ridgun Samples: I/O Operations
-- ============================================================
-- Demonstrates echo and out primitives.

-- echo — prints strings separated by spaces, followed by newline
-- fn :: echo String... => ()

-- out — writes a string, returns it (allows chaining)
-- op :: String out => String

-- Basic echo
fn :: hello => ()
      hello =  echo "Hello, Ridgun!"

-- Multiple arguments to echo
fn :: multi => ()
      multi =  echo "hello" "world" "!"

-- String interpolation in echo
fn :: show_sum Int Int => ()
      show_sum a   b   =  echo "sum: {a + b}"

-- Chaining with out
fn :: log_and_process String => String
      log_and_process s      =  process (s out) and report

-- Echo with escape sequences
fn :: formatted => ()
      formatted =  echo "line1\nline2\tcol"

fn :: main => ()
      main =
        hello
        multi
        show_sum 3 4
        formatted
