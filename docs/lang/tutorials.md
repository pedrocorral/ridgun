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
ridgun run hello.rg main
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
abs n
  | n >= 0 = n
  | otherwise = -n
```

## Advanced Features

### Generics

Type variables (lowercase names) enable generic programming:

```ridgun
-- Type variable 'a can be any type
fn :: identity a => a
identity x = x

-- Generic list operations
fn :: head [a] => a
head (x:_) = x

fn :: null [a] => Bool
null [] = True
null (_:_) = False
```

### Tuple Patterns

Deconstruct tuples with pattern matching:

```ridgun
-- Tuple type: (Type1, Type2, ...)
fn :: swap (Int, String) => (String, Int)
swap (n, s) = (s, n)

fn :: sum_pair (Int, Int) => Int
sum_pair (a, b) = a + b

-- Triple tuples
fn :: triple_add (Int, Int, Int) => Int
triple_add (a, b, c) = a + b + c
```

### Constructor Patterns

Match on algebraic data type constructors:

```ridgun
type Result = Ok Int | Err String

fn :: unwrap_or_default Result => Int
unwrap_or_default (Ok n) = n
unwrap_or_default (Err _) = 0

type Tree = Leaf Int | Node Tree Tree

fn :: tree_sum Tree => Int
tree_sum (Leaf n) = n
tree_sum (Node lhs rhs) = tree_sum lhs + tree_sum rhs
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

### Basic Concurrency

Spawn and synchronize parallel computations:

```ridgun
fn :: worker Int => Int
worker n = n * 2

fn :: main => Int
main =
  let t1 = spawn "worker"
  let t2 = spawn "worker"
  join t1 + join t2
```

### Message Passing

Communicate between threads via mailboxes:

```ridgun
fn :: producer Mailbox => ()
producer mb =
  send 1 mb
  send 2 mb
  send 3 mb

fn :: consumer Mailbox => Int
consumer mb =
  let x = recv mb
  let y = recv mb
  let z = recv mb
  x + y + z

fn :: main => Int
main =
  let mb = new_mailbox
  let _t1 = spawn "producer"
  let _t2 = spawn "consumer"
  join _t2
```

## Type System

### Built-in Types

- `Int` - Arbitrary precision integers
- `String` - UTF-8 text
- `Bool` - True/False values
- `()` - Unit type (no value)
- `[T]` - List of type T
- `(T1, T2, ...)` - Tuple types

### Custom Types

Define algebraic data types:

```ridgun
-- Product type (record)
type Point = x Int, y Int

-- Sum type (variants)
type Shape = Circle Int | Rectangle Int Int

-- Recursive types
type List a = Nil | Cons a (List a)

-- Type parameters
type Optional a = Some a | None
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
fn :: map f [a] => [b]
map f [] = []
map f (x:xs) = f x : map f xs

-- Filter a list
fn :: filter pred [a] => [a]
filter pred [] = []
filter pred (x:xs)
  | pred x = x : filter pred xs
  | otherwise = filter pred xs

-- Fold/reduce
fn :: fold f acc [a] => b
fold f acc [] = acc
fold f acc (x:xs) = fold f (f acc x) xs
```

### Parallel Sum

```ridgun
fn :: sum_list [Int] => Int
sum_list [] = 0
sum_list [x] = x
sum_list lst =
  let mid = length lst / 2
  let left = take mid lst
  let right = drop mid lst
  let t1 = spawn "sum_list"
  let t2 = spawn "sum_list"
  join t1 + join t2
```

## Next Steps

- Read the [Language Specification](spec.md) for complete syntax details
- Explore the [Architecture](../etc/architecture.md) documentation
- Check the [Roadmap](../etc/roadmap.md) for upcoming features
