-- case: "{expr}" interpolates any expression; \{ \} and {{ }} give literal braces; '…' strings are raw
-- source: spec.md:28-56 (examples copied with their stated results)
-- expect-output:
--   Hello, Ridgun!
--   Sum is 7
--   Nested: 120 done
--   Shell expansion: ${VAR:-default}
--   This is {not interpolated}
--   Use { } or {} for literal braces
--   Hello, {name}!
--   {this is just pure chars}

fn :: sum Int Int => Int
      sum a b =  a + b

fn :: factorial Int => Int
      factorial n =
        | n <= 1    = 1
        | otherwise = n * (factorial (n - 1))

fn :: main => ()
      main =
        name = "Ridgun"
        _ = echo "Hello, {name}!"
        _ = echo "Sum is {sum 3 4}"
        _ = echo "Nested: {factorial 5} done"
        _ = echo "Shell expansion: \$\{VAR:-default\}"
        _ = echo "This is {{not interpolated}}"
        _ = echo "Use \{ \} or {{}} for literal braces"
        _ = echo 'Hello, {name}!'
        echo '{this is just pure chars}'
