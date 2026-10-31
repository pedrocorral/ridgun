# Ridgun Tutorials

## Getting Started

### Your First Ridgun Program

Create a file `hello.rg`:

```ridgun
fn :: main => ()
main = echo "Hello, World!"
```

Run it:
```bash
ridgunc run hello.rg
```

Output:
```
Hello, World!
```

### Basic Functions

Functions are defined with type signatures:

```ridgun
-- Function signature: fn :: <name> <param_types...> => <return_type>
fn :: sum Int Int => Int
sum a b = a + b

fn :: factorial Int => Int
factorial 0 = 1
factorial n = n * factorial (n - 1)
```

### Pattern Matching

Ridgun supports Haskell-style pattern matching:

```ridgun
-- Multiple patterns for different cases
fn :: describe Int => String
describe 0 = "zero"
describe 1 = "one"
describe n = "other number"

-- List patterns with cons (:)
fn :: length [Int] => Int
length [] = 0
length (_:xs) = 1 + length xs

-- Guard clauses
fn :: abs Int => Int
      abs n =
        | n >= 0    = n
        | otherwise = 0 - n
```

## Advanced Features

### Generics

Type variables (single uppercase letters `A`..`Z`) enable generic programming:

```ridgun
-- Type variable A can be any type
fn :: identity A => A
      identity x =  x

-- Generic list operations
fn :: head [A]    => A
      head (x:_)  =  x

fn :: null [A]    => Bool
      null []     =  True
      null (_:_)  =  False
```

### Tuple Patterns

Deconstruct tuples with pattern matching:

```ridgun
-- Tuple type: (Type1, Type2, ...)
fn :: swap (Int, String) => (String, Int)
swap (n, s) = (s, n)

fn :: sum pair (Int, Int) => Int
sum pair (a, b) = a + b

-- Triple tuples
fn :: triple add (Int, Int, Int) => Int
triple add (a, b, c) = a + b + c
```

### Constructor Patterns

Match on algebraic data type constructors:

```ridgun
type Result = Ok Int | Err String

fn :: unwrap or default Result => Int
unwrap or default (Ok n) = n
unwrap or default (Err _) = 0

type Tree = Leaf Int | Node Tree Tree

fn :: tree sum Tree => Int
tree sum (Leaf n) = n
tree sum (Node lhs rhs) = tree sum lhs + tree sum rhs
```

### Negative Literals

Use negative numbers directly in patterns:

```ridgun
fn :: classify Int => String
classify 0 = "zero"
classify -1 = "minus one"
classify n
  | n < 0 = "negative"
  | otherwise = "positive"
```

## Concurrency

### Parallel DAG Blocks (`||`)

Evaluate independent branches concurrently and combine their results:

```ridgun
fn :: worker Int => Int
      worker n   =  n * 2

fn :: compute both Int Int => Int
      compute both a   b   =  r1 + r2
        || worker a        -> r1
        || worker b        -> r2
```

### Native Agents (`agent`, `send ... to`, `receive from`, `ask ... to`)

Communicate with concurrent stateful or stateless agents:

```ridgun
fn :: counter step Int Int => Int Int
      counter step st  inc =  (st + inc, st + inc)

fn :: main => ()
      main =
        ag = agent counter step 0
        send 10 to ag
        send 20 to ag
        r1 = receive from ag
        r2 = receive from ag
        r3 = ask 5 to ag
        echo (int to str (r1 + r2 + r3))
```

## Type System

### Built-in Types

- `Int` - 64-bit integers
- `Real` / `Float` - Floating-point numbers
- `String` - UTF-8 text
- `Bool` - `True` / `False` values
- `()` - Unit type (no value)
- `[T]` - List of type `T`
- `(T1, T2, ...)` - Tuple types

### Custom Types

Define algebraic data types:

```ridgun
-- Product type (record)
type Point = x: Int, y: Int

-- Sum type (variants)
type Shape = Circle Int | Rectangle Int Int

-- Recursive types
type List A = Nil | Cons A (List A)

-- Type parameters
type Optional A = Some A | None
```

### Type Inference

Ridgun can infer types in many cases:

```ridgun
-- Compiler infers: add :: Int -> Int -> Int
fn :: add a b = a + b

-- With explicit signature (recommended)
fn :: add Int Int => Int
add a b = a + b
```

## Best Practices

1. **Always specify type signatures** - Improves readability and catches errors early
2. **Use pattern matching** - More idiomatic than conditionals
3. **Favor immutability** - All values are immutable by default
4. **Use guards for complex conditions** - More readable than nested if-else
5. **Document complex logic** - Use comments to explain non-obvious code

## Examples

### Fibonacci Numbers

```ridgun
fn :: fib Int => Int
fib 0 = 0
fib 1 = 1
fib n = fib (n - 1) + fib (n - 2)
```

### List Operations

```ridgun
-- Map over a list
fn :: map (A => B) [A]    => [B]
      map _        []     =  []
      map f        (x:xs) =  [f x] :: (map f xs)

-- Filter a list
fn :: filter (A => Bool) [A]    => [A]
      filter _           []     =  []
      filter pred        (x:xs) =
        | pred x    = [x] :: (filter pred xs)
        | otherwise = filter pred xs

-- Fold/reduce
fn :: fold (B A => B) B   [A]    => B
      fold _          acc []     =  acc
      fold f          acc (x:xs) =  fold f (f acc x) xs
```

### Parallel Sum

```ridgun
fn :: sum list [Int]  => Int
      sum list []     =  0
      sum list (x:[]) =  x
      sum list (x:xs) =  x + (sum list xs)

fn :: parallel sum pairs [Int] [Int] => Int
      parallel sum pairs a     b     =  sa + sb
        || sum list a                -> sa
        || sum list b                -> sb
```

## Next Steps

- Read the [Language Specification](spec.md) for complete syntax details
- Explore the [Architecture](../etc/architecture.md) documentation
- Check the [Roadmap](../etc/roadmap.md) for upcoming features
