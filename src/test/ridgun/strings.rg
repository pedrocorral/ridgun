-- ============================================================
-- Ridgun Samples: String Operations
-- ============================================================
-- Demonstrates both string types and string-related features.

-- Interpolated strings (double-quoted) — {expr} is evaluated
name = "Ridgun"
greeting   = "Hello, {name}!"             -- "Hello, Ridgun!"
with_calc  = "Sum is {sum 3 4}"           -- "Sum is 7"
nested     = "Nested: {factorial 5} done" -- "Nested: 120 done"

-- Literal braces — double {{ }} to include { } in the output
literal    = "This is {{not interpolated}}"   -- "This is {not interpolated}"
empty      = "Use {{}} for literal braces"    -- "Use {} for literal braces"

-- Raw strings (single-quoted) — no interpolation, all literal
raw1       = 'Hello, {name}!'             -- "Hello, {name}!" (literal)
raw2       = '{this is just pure chars}'  -- "{this is just pure chars}"
raw3       = 'No {interpolation} here'   -- "No {interpolation} here"

-- Escape sequences (in interpolated strings)
escapes    = "line1\nline2"              -- newline
tabbed     = "col1\tcol2"               -- tab
quoted     = "she said \"hello\""       -- escaped quote

-- String-taking functions
fn :: greet String => ()
      greet name   =  echo "Hello, {name}!"

fn :: show_pair String String => ()
      show_pair a      b      =  echo "{a} and {b}"

fn :: main => ()
      main =
        greet "world"
        show_pair "foo" "bar"
        echo "literal: {{braces}}"
        echo 'raw: {no interpolation}'
