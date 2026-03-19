# Ridgun Language Specification

## Overview

Ridgun is a functional, parallel-first language with natural language operators and strong static typing. Its syntax draws inspiration from Haskell and ML family languages while introducing novel constructs for parallelism and human-readable operator definitions.

Key characteristics:
- **Natural language operators** — Operators read like English sentences
- **Implicit parallelism** — Parallel execution is a syntactic primitive, not a library call
- **Strong static typing** — All types are declared in signatures
- **Pattern-style definitions** — Functions and operators are defined by equations

---

## Comments

Single-line comments use `--`:

```ridgun
-- This is a comment
```

---

## Strings

Ridgun has two string literal types with different interpolation behavior.

### Interpolated Strings (double quotes)

Double-quoted strings support **inline code interpolation** using `{expr}`. The expression inside braces is evaluated and its result is inserted into the string.

```ridgun
name = "Ridgun"
"Hello, {name}!"                         -- "Hello, Ridgun!"
"Sum is {sum 3 4}"                       -- "Sum is 7"
"Nested: {factorial 5} done"             -- "Nested: 120 done"
```

To include a literal brace, double it:

```ridgun
"This is {{not interpolated}}"           -- "This is {not interpolated}"
"Use {{}} for literal braces"            -- "Use {} for literal braces"
```

### Raw Strings (single quotes)

Single-quoted strings are **raw** — no interpolation is performed. All characters are treated as literal text, including braces.

```ridgun
'Hello, {name}!'                         -- "Hello, {name}!"
'{this is just pure chars}'              -- "{this is just pure chars}"
'No {interpolation} here'               -- "No {interpolation} here"
```

### Summary

| Syntax | Interpolation | Use case |
|---|---|---|
| `"..."` | Yes — `{expr}` | Dynamic strings with embedded expressions |
| `'...'` | No — all literal | Static text, templates, regex patterns |

---

## Program Structure

All executable code in Ridgun must live inside a function or operator. The `main` function is the **required entry point** for program execution.

```ridgun
fn :: main => ()
      main = echo "Hello, Ridgun!"
```

A Ridgun source file may contain only:
- `import` statements
- `type` definitions
- `fn` and `op` declarations and definitions
- A `main` function as the entry point

No loose top-level expressions are allowed. Everything that runs must be called from `main`.

### CLI Usage

```
ridgun [subcommand] <file.rg>
```

If no subcommand is given, `run` is assumed.

| Subcommand | Status | Purpose |
|---|---|---|
| `run` | ✅ Active | Execute the program (default) |
| `check` | 🔜 Planned | Type-check without running |
| `compile` | 🔜 Planned | Emit bytecode `.rgc` file |
| `fmt` | 🔜 Planned | Format source code |
| `repl` | 🔜 Planned | Interactive REPL |
| `test` | 🔜 Planned | Run tests with formatted output |

---

## Functions

Functions are declared with `fn ::` followed by a type signature, then defined by equation.

### Syntax

```
fn :: <name> <param_types...> => <return_type>
      <name> <params...> = <body>
```

### Example

```ridgun
-- Declaration: sum takes two Ints, returns an Int
fn :: sum Int Int => Int
      sum a b = a + b
```

The declaration and definition are separate:
- **Declaration** (`fn ::`) — specifies the name, parameter types, and return type
- **Definition** — binds parameter names and provides the implementation

---

## Operators

Operators are Ridgun's distinctive feature. They are **named with natural language** and defined with `op ::`. Unlike traditional operators (`+`, `-`), Ridgun operators are multi-word expressions that read like sentences.

### Syntax

```
op :: <natural language signature with types> -> <return_type>
      <natural language pattern with params> = <body>
```

### Basic Example

```ridgun
-- Declaration: "add [Int] to [Int]" returns an Int
op :: add Int to Int => Int
      add a to b = a + b
```

Usage would read as: `add 3 to 5` → `8`

The words between typed parameters (`to`, `and`, `in`, etc.) are **keywords of the operator** — they are part of the operator's identity and must appear at call sites.

### Parallel Operators

Operators can express **parallel execution** as a first-class concept:

```ridgun
-- Run two configs in parallel, return two results
op :: run Conf and Conf in parallel => Res, Res
      run a and b in parallel       =  res_a, res_b
        where
          run my own process a      -> res_a
          run my own process b      -> res_b
```

Key elements:
- **Multiple return values** — `=> res, res` declares two return values
- **`where` block** — Binds sub-computations to result names
- **`->`** — Assigns the result of a sub-computation to a variable
- The `where` block implies parallel execution of its bindings

### Pipe Syntax for Parallelism

An alternative syntax for expressing parallel execution uses `||` (double pipe):

```ridgun
-- Another way to run two processes in parallel
op :: another way to run two processes Conf Conf in parallel => Res, Res
      another way to run two processes a b in parallel =
        || run my own process a
        || run my own process b
```

Each `||` line runs as an independent parallel task. Results are collected in order.

### Operator Overloading

Existing operators (including built-in ones like `+`) can be overloaded for new types:

```ridgun
-- Overload + for Complex numbers
op :: Complex + Complex => Complex
      a + b = (real a) + (real b) + complex_i * ((imaginary a) + (imaginary b))
```

### Precedence

**Symbolic operators have the highest precedence** — math first.

When symbolic operators (like `+`, `*`) appear inside natural language operator bodies, they bind tighter than the surrounding operator keywords. This ensures arithmetic expressions evaluate as expected without extra parentheses.

| Precedence | Category | Examples |
|---|---|---|
| **Highest** | Symbolic operators | `*`, `/`, `+`, `-`, `%` |
| | Function application | `f x` |
| | Comparison | `==`, `!=`, `<`, `>` |
| | Logical | `AND`, `OR`, `XOR`, `NOT` |
| **Lowest** | Natural language operators | `add a to b`, `run a and b in parallel` |

### Operator Chaining

Operators that return sequences can be **chained** — the output of one operator flows directly as the input to the next:

```ridgun
op :: Int Int switch -> Int Int
      a   b   switch =  b   a

-- Output of one operator feeds into the next:
op :: Int Int invariant -> Int Int
      a   b   invariant =  a b switch switch
```

`a b switch` produces `b, a`. That output sequence feeds directly into the second `switch`, producing `a, b` — back to the original. This gives point-free composition without special syntax.

> **Note:** `->` and `=>` are both accepted as return type separators. Use `->` for operators that *transform* sequences, `=>` for functions that *produce* a result.

---

## Type System

### Type Signatures

Type signatures appear in declarations after `fn ::` or `op ::`:

```
fn :: <name> <type1> <type2> ... => <return_type>
op :: <words and types mixed> => <return_type>
```

- Parameters are positional; types appear where parameters are expected
- Multiple return values are comma-separated: `=> res, res`
- The `=>` arrow separates input types from the return type

### Built-in Types

| Type | Description |
|---|---|
| `Int` | Integer |
| `Real` | Real number |
| `Bool` | Boolean |
| `Char` | Single Unicode character (UTF-8) |
| `String` | Text string (UTF-8) |
| `Complex` | Complex number |
| `Tensor` | Mutable N-dimensional tensor (`Real` elements, CPU) |
| `Tensor_GPU` | Mutable N-dimensional tensor (`Real` elements, GPU) |

> [!NOTE]
> All text in Ridgun is UTF-8 encoded by default. `Char` represents a single Unicode codepoint, `String` is a sequence of `Char`.

### Bool Literals

`Bool` has two primitive values:

```ridgun
True                                     -- boolean true
False                                    -- boolean false
```

`True` and `False` are constructors — they can be used in expressions, passed as arguments, and pattern-matched:

```ridgun
fn :: is_valid Int => Bool
      is_valid n
        | n > 0     = True
        | otherwise = False
```

### Logical Operators

Ridgun uses **word-based** logical operators instead of symbolic ones:

| Operator | Meaning | Example |
|---|---|---|
| `AND` | Logical conjunction | `a AND b` |
| `OR` | Logical disjunction | `a OR b` |
| `XOR` | Exclusive or | `a XOR b` |
| `NOT` | Logical negation | `NOT a` |

```ridgun
result = True AND False                  -- False
result = True OR False                   -- True
result = True XOR True                   -- False
result = NOT False                       -- True
```

These are infix keyword operators with standard boolean semantics.

### Native Collection Types

#### Lists

Lists are a built-in **immutable** recursive type with dedicated syntax. No manual ADT definition is needed. Lists are suited for functional data processing, symbolic computation, and recursive algorithms. For mutable numeric computation, see **Tensors** below.

**Type syntax:** `[type]` — a list of elements of the given type.

```ridgun
fn :: sum_list [Int] => Int
fn :: reverse [Int] => [Int]
```

**Literal syntax:** `[elem1, elem2, ...]` — a list literal. `[]` is the empty list.

```ridgun
fn :: my_list => [Int]
my_list = [1, 2, 3, 4, 5]
```

**Cons-pattern matching:** `(x:xs)` — destructures a list into its head `x` and tail `xs`. `[]` matches the empty list. Use `_` as a wildcard that matches but does not bind.

```ridgun
fn :: sum_list [Int] => Int
      sum_list []     = 0
      sum_list (x:xs) = x + sum_list xs

fn :: list_length [Int] => Int
      list_length []     = 0
      list_length (_:xs) = 1 + list_length xs
```

**Concatenation:** `::` joins two lists (or sequences).

```ridgun
fn :: append [Int] [Int] => [Int]
      append a b = a :: b
```

#### Tensors

Tensors are Ridgun's native **mutable** N-dimensional numeric type. They generalize vectors, matrices, and higher-dimensional arrays into a single type. Elements are `Real` by default.

**Literal syntax:** `Tensor` followed by nested brackets. The nesting depth determines the dimensionality.

```ridgun
v = Tensor [1, 2, 3]                    -- 1D (vector), shape: (3)
m = Tensor [[1, 2], [5, 3]]              -- 2D (matrix), shape: (2, 2)
t = Tensor [[[1, 2], [3, 4]],            -- 3D tensor, shape: (2, 2, 2)
            [[5, 6], [7, 8]]]
```

**Indexing:** Both chained and comma-separated indexing are supported.

```ridgun
val = m[0][1]        -- chained indexing: row 0, col 1
val = m[0, 1]        -- comma indexing: equivalent
row = m[0]           -- slice: entire first row
```

**Mutation (in-place):** Tensors are mutable — elements and slices can be modified in place (PyTorch/NumPy style).

```ridgun
m[0, 1] = 5.0                            -- set element
m[0] = Tensor [10, 20]                   -- set entire row
```

**Tensor contraction (`@`):** The `@` operator performs Einstein summation. Subscript indices on each operand define the contraction: indices shared across **all** operands are summed; unique indices survive in the result.

```ridgun
-- A has shape (s, d, f), B has shape (n, d, f)
-- Shared indices: d, f → contracted (summed)
-- Result T has shape (s, n)
T = A_sdf @ B_ndf

-- Equivalent to: np.einsum('sdf,ndf->sn', A, B)
```

Contraction works across **multiple tensors** in a single expression:

```ridgun
-- A(a,b,c), B(a,b,c), C(a,b,c,d)
-- Shared: a, b, c → contracted. Result R has shape (d)
R = A_abc @ B_abc @ C_abcd

-- Equivalent to: np.einsum('abc,abc,abcd->d', A, B, C)
```

**Hadamard operations (`+`, `-`, `*`, `/`):** Arithmetic operators with subscript indices perform **element-wise** operations. Matching indices align dimensions; unmatched indices are broadcast.

```ridgun
-- Element-wise multiply: same shape, same indices
H = A_ij * B_ij                          -- shape (i, j)

-- Broadcasting: B has fewer dimensions
S = A_ij * B_j                           -- B broadcasts along i

-- Element-wise add
C = A_ij + B_ij

-- Element-wise divide
D = A_ij / B_j                           -- B broadcasts along i
```

This eliminates the need for `unsqueeze`, `expand_dims`, or manual reshaping — the indices **are** the broadcasting rules.

**GPU variant:** `Tensor_GPU` places the tensor on GPU memory for accelerated computation.

```ridgun
g = Tensor_GPU [[1, 2], [3, 4]]
result = g_ij @ g_jk                     -- GPU-accelerated matrix multiply
```

#### Sequences (`seq`)

Sequences are Ridgun's core compound type. A `seq` is an ordered, fixed-size collection of values — essentially a typed tuple. Function and operator parameter lists are implicitly sequences.

```ridgun
-- These parameter types form implicit sequences:
fn :: sum Int Int => Int          -- params: seq(Int, Int)
fn :: process Int Real => Bool   -- params: seq(Int, Real)
```

**Seq binding (`(name)`)** — wrapping a parameter name in parentheses binds all parameters as a single seq variable:

```ridgun
fn :: first_of_seq Int Int => Int
      first_of_seq (s)     =  s(+ _)

-- Equivalent without seq binding:
fn :: first_of Int Int => Int
      first_of s   _   => s
```

**Mask selector (`s(+ _)`)** — extracts elements by mask, where `+` selects a position and `_` skips it:

```ridgun
s(+ _)                -- select 1st, skip 2nd
s(_ +)                -- skip 1st, select 2nd
s(+ _ _ _)            -- select 1st, skip 2nd-4th
s(_ _ _ +)            -- skip 1st-3rd, select 4th
```

**Index selector (`s(0 3)`)** — extracts elements by their zero-based positions:

```ridgun
fn :: extreme_points Int Int Int Int => Int Int
      extreme_points (s)             =  s(0 3)
```

**Flat join (`:`)** — concatenates two sequences into a single flat sequence:

```ridgun
seq1 = a, b         -- seq(a, b)
seq2 = c, d         -- seq(c, d)
seq1:seq2            -- seq(a, b, c, d)
```

**Nesting (`,`)** — composes sequences as distinct elements (seq of seqs):

```ridgun
seq1, seq2           -- seq(seq(a, b), seq(c, d))
```

### Algebraic Data Types (ADTs)

Ridgun uses **algebraic data types** for user-defined types. There are no classes, methods, or `impl` blocks — functions and operators take types as parameters.

#### Product Types (records)

A type with named fields:

```ridgun
type Conf = host String, port Int
type Point = x Real, y Real
```

Fields are accessed by name as functions:

```ridgun
fn :: get_host Conf => String
get_host c = host c

-- or directly in expressions
fn :: connect Conf => Result
connect c = open_connection (host c) (port c)
```

#### Sum Types (variants)

A type with multiple constructors, separated by `|`:

```ridgun
type Result = Ok Int | Err String
type Option = Some Int | None
type Color = Red | Green | Blue
```

#### Recursive Types

Types can reference themselves:

```ridgun
type List = Empty | Cons Int List
type Tree = Leaf Int | Node Tree Tree
```

---

## Pattern Matching

Ridgun supports **Haskell-style pattern matching** — functions and operators can be defined by multiple equations that match on the shape of their arguments.

### Literal Patterns

```ridgun
fn :: factorial Int => Int
      factorial 0   =  1
      factorial n   =  n * factorial (n - 1)

fn :: fib Int => Int
      fib 0   =  0
      fib 1   =  1
      fib n   =  fib (n - 1) + fib (n - 2)
```

### Constructor Patterns

Pattern matching on ADT constructors:

```ridgun
fn :: unwrap Result    => Int
      unwrap (Ok n)    =  n
      unwrap (Err msg) =  0

fn :: length List => Int
      length Empty         =  0
      length (Cons _ rest) =  1 + length rest

fn :: sum_tree Tree              => Int
      sum_tree (Leaf n)          =  n
      sum_tree (Node left right) =  sum_tree left + sum_tree right
```

---

## Parallelism Primitives

Ridgun provides two syntactic forms for parallel execution:

### `where` Blocks

```ridgun
<operator> = <result_bindings>
  where
    <computation_1> -> <result_var_1>
    <computation_2> -> <result_var_2>
```

All computations in a `where` block execute in parallel. Results are bound to variables using `->`.

### Pipe `||` Blocks

```ridgun
<operator> =
  || <computation_1>
  || <computation_2>
```

Each `||` line runs as a separate parallel green thread. Results are returned as a tuple in declaration order.

---

## I/O Primitives

Ridgun provides built-in functions for terminal output.

### `echo`

Prints an arbitrary number of strings to the terminal, separated by spaces, followed by a newline.

```
fn :: echo String... => ()
```

The `...` suffix on the last parameter type marks it as **variadic** — accepting one or more arguments of that type.

```ridgun
echo "hello"                            -- prints: hello
echo "hello" "world" "!"               -- prints: hello world !
echo "result: {result}"                 -- prints: result: 42
```

### `out`

An operator that writes a string directly to the terminal and returns it (allowing chaining).

```
op :: String out => String
```

```ridgun
"hello" out                              -- prints: hello
"step 1 done" out                        -- prints: step 1 done

-- Chaining: out returns the string, so it can be passed onward
fn :: log_and_process String => String
      log_and_process s = process (s out) and report
```

### Summary

| Function | Type | Purpose |
|---|---|---|
| `echo` | `String... => ()` | Print strings with spaces and newline |
| `out` | `String => String` | Print string, return it for chaining |

---

## Standard Library

Libraries are imported with `import`:

```ridgun
import test
```

### Unit Testing (`lib/test.rg`)

A simple test library using `echo` for terminal output.

**Assertions:**

| Operator | Purpose |
|---|---|
| `assert Int equals Int` | Integer equality |
| `assert Real equals Real` | Real equality |
| `assert String equals String` | String equality |
| `assert Bool is true` | Boolean is true |
| `assert Bool is false` | Boolean is false |

**Test structure:**

```ridgun
import test

fn :: main => ()
      main =
        describe "Arithmetic" does

          test "sum adds correctly" does
            assert (sum 3 4) equals 7

          test "factorial base case" does
            assert (factorial 0) equals 1
```

**Terminal output:**

```
═══ Arithmetic ═══
● sum adds correctly
  ✓ PASS
● factorial base case
  ✓ PASS
```

---

## Summary of Syntactic Elements

| Element | Syntax | Purpose |
|---|---|---|
| Comment | `-- text` | Single-line comment |
| Function declaration | `fn :: name types => return` | Declare a function's type signature |
| Function definition | `name params = body` | Define a function's implementation |
| Operator declaration | `op :: words types words => return` | Declare a natural language operator |
| Operator definition | `words params words = body` | Define an operator's implementation |
| Multiple returns | `=> type, type` | Declare multiple return values |
| Variadic parameters | `Type...` | Accept one or more arguments of a type |
| Tensor literal | `Tensor [[1, 2], [3, 4]]` | Create an N-dimensional tensor |
| Tensor indexing | `t[0, 1]` or `t[0][1]` | Access tensor elements |
| Tensor mutation | `t[0, 1] = 5.0` | Mutate tensor elements in place |
| Einstein contraction | `A_ij @ B_jk` | Tensor contraction over shared indices |
| Hadamard operation | `A_ij * B_ij` | Element-wise arithmetic with index alignment |
| `echo` | `echo "a" "b" "c"` | Print strings to terminal |
| `out` | `"text" out` | Output string to terminal |
| Where block | `where expr -> var` | Parallel sub-computations with named results |
| Pipe block | `\|\| expr` | Parallel execution (alternative syntax) |
| Operator overloading | `op :: type + type => type` | Overload existing operators for new types |
| Bool literals | `True`, `False` | Boolean primitive values |
| Logical operators | `AND`, `OR`, `XOR`, `NOT` | Word-based logical operators |
| Entry point | `fn :: main => ()` | Required program entry point |
