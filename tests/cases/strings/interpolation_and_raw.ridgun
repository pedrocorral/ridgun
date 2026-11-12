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
        echo "Hello, {name}!"
        echo "Sum is {sum 3 4}"
        echo "Nested: {factorial 5} done"
        echo "Shell expansion: \$\{VAR:-default\}"
        echo "This is {{not interpolated}}"
        echo "Use \{ \} or {{}} for literal braces"
        echo 'Hello, {name}!'
        echo '{this is just pure chars}'
