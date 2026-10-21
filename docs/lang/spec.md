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

To include a literal brace inside `"..."`, either escape it with a backslash (`\{` and `\}`) or double it (`{{` and `}}`):

```ridgun
"Shell expansion: \$\{VAR:-default\}"    -- "Shell expansion: ${VAR:-default}"
"This is {{not interpolated}}"           -- "This is {not interpolated}"
"Use \{ \} or {{}} for literal braces"   -- "Use { } or {} for literal braces"
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
| `"..."` | Yes — `{expr}` (escape braces with `\{`/`\}` or `{{`/`}}`) | Dynamic strings with embedded expressions |
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

## Functions & Operators

Functions and natural-language/infix operators are declared by a type signature ending in `=> <return_type>`, followed by one or more equations (`cases`). The leading `fn ::` and `op ::` prefixes are **optional**:

- **Canonical prefixless form** (starts at column 0):
  ```ridgun
  list len [A]    => Int
  list len []     =  0
  list len (_:xs) =  1 + (list len xs)

  swap A with B => (B, A)
  swap x with y =  (y, x)
  ```
- **Explicit prefixed form** (`fn ::` / `op ::`, starts at column 0 with clauses aligned at column 6):
  ```ridgun
  fn :: sum Int Int => Int
        sum a   b   =  a + b

  fn :: format app err AppErr        => String
        format app err (IoError msg) =  "IO:{msg}"
  ```
- **Natural-language spaces in `fn ::`, built-ins, and filenames (`FR-COMP-005`)**:
  - `fn ::` declarations and calls support multi-word names separated by spaces (`fn :: format app err AppErr => String`, `fn :: project name => String`), just like `op ::` and prefixless declarations.
  - Built-in runtime and test functions can be called with spaces (`assert equals a b`, `str len s`, `read file p`, `cmm live blocks`) while keeping `_` forms backward-compatible.
  - First-class multi-word function references (`map double val xs`, `||map double val xs`, `filter is even xs`, `fold add pair 0 xs`) and `.rg` filenames with spaces (`src/test/ridgun/test core language.rg`) are supported natively by `ridgunc` and `stable`.

### Polymorphic Type Variables (`A`..`Z`) & Contextual Keywords (`type`, `with`)

To guarantee zero lexical ambiguity between operator words and type parameters in both prefixed (`op ::`) and prefixless signatures:
- **Every type token in a signature starts with an uppercase letter** (or `[...]` / `(...)`):
  - **Single uppercase letters (`A`..`Z`)** denote **polymorphic type variables** (e.g., `[A]`, `(A, B)`, `(A => B)`, `swap A with B => (B, A)`). Repeated occurrences of a type variable across parameters are unified at each call site and substituted into the return type.
  - **Multi-character capitalized identifiers** (`Int`, `String`, `Bool`, `RExpr`, `Tensor`) denote concrete or user-defined types.
- **Every lowercase token** (or operator symbol `+`, `-`, `*`, `/`, `%`) in a top-level signature is part of the function or mixfix operator name.
- **Contextual keywords `type` and `with`**: `type` only introduces a type declaration at the top level when followed by `UpperName =`. Everywhere else (`fn ::` and `op ::` signatures, operator words, parameter patterns, local variables, and record field names), `type` and `with` are valid identifiers/words without ambiguity.
- A top-level signature with **one leading lowercase identifier** followed only by types before `=>` is a prefix function (`fn`); any signature with **two or more lowercase words** or operator symbols interleaved with types before `=>` is a mixfix/infix/postfix operator (`op`).

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

### Parallel Operators (`||`)

Operators can express **parallel execution** as a first-class concept using `||`:

```ridgun
-- Run two configs in parallel with named DAG bindings (|| expr -> var)
op :: run Conf and Conf in parallel => Res, Res
      run a and b in parallel       =  res_a, res_b
        || run my own process a     -> res_a
        || run my own process b     -> res_b
```

Key elements:
- **Multiple return values** — `=> Res, Res` declares two return values
- **`|| expr -> var` block** — Binds sub-computations to result names (`where` is eliminated; `||` unifies all parallel branches)
- **`->`** — Assigns the result of a parallel sub-computation to a variable (or tensor slice `-> out[i, j]`)
- Independent `||` branches execute concurrently as a parallel DAG based on data dependencies

### Direct Parallel Pipe Block (`|| expr`)

When an expression or function directly returns a tuple of parallel computations without intermediate variable names, `||` lines appear directly after `=`:

```ridgun
-- Run two processes in parallel and return their results as a tuple
op :: another way to run two processes Conf Conf in parallel => Res, Res
      another way to run two processes a b in parallel =
        || run my own process a
        || run my own process b
```

Each `||` line runs as an independent parallel task. Results are collected in declaration order.

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
| | Logical | `and`, `or`, `xor`, `not` |
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
      is_valid n =
        | n > 0     = True
        | otherwise = False
```

### Logical Operators

Ridgun uses **word-based lowercase** logical operators instead of symbolic ones:

| Operator | Meaning | Example |
|---|---|---|
| `and` | Logical conjunction | `a and b` |
| `or` | Logical disjunction | `a or b` |
| `xor` | Exclusive or | `a xor b` |
| `not` | Logical negation | `not a` |

```ridgun
result = True and False                  -- False
result = True or False                   -- True
result = True xor True                   -- False
result = not False                       -- True
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

#### Product Types (records) & Record Update Syntax (`with`)

A type with named fields:

```ridgun
type Conf  = host: String, port: Int, tls: Bool
type Point = x: Real, y: Real
```

Fields are accessed by name as functions (`host c`, `port c`), and updated functionally using `with` and colons `:`:

```ridgun
fn :: get_host Conf => String
      get_host c    =  host c

-- Functional record update (creates a new Conf with updated fields;
-- mutates in place via Arc::try_unwrap when the record is uniquely owned):
fn :: enable_tls Conf => Conf
      enable_tls c    =  c with tls: True, port: 443
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

#### Shared Constructor Names Across Types (`FR-COMP-005`)

Multiple `type` declarations can reuse the same variant constructor names (such as `Error`, `Var`, `Lit`, `None`) with the same or different arities. The typechecker disambiguates constructor patterns via the expected parameter type of the column, and resolves constructor calls by argument arity/types and union ADT return types:

```ridgun
type ParseOut = Parsed Int | Error String
type DbOut    = Rows Int   | Error Int String
type MiniExpr = Var String | Lit Int
type MiniPat  = Var String | Lit Int | Wild
```

#### Open Type Extensions (`expand type`) & Automatic `fn ::` Clause Merging (`FR-COMP-005`)

Existing Sum ADTs and Product Records can be extended with `expand type UpperName = ...`:

- **Extending a Sum ADT**: appends new variant constructors to the existing type.
- **Extending a Product Record**: appends new named fields (`field: Type`) and auto-generates their field accessor functions.
- **Type-Name Variants Without Redundant Constructor Names**: in `type` and `expand type` sum declarations, a variant whose name is a bare built-in type (`String`, `Int`, `Real`/`Float`, `Bool`, `Char`) with no extra type arguments after it represents values of that type directly (without writing `Int Int` or `String String`). Callers can pass bare values (`describe "hej"`, `describe 42`) or explicit constructor calls (`describe (String "hej")`, `describe (Int 42)`), and equations can match both literals (`"admin"`, `0`) and typed patterns (`(String s)`, `(Int n)`).
- **Automatic `fn ::` / `op ::` Clause Merging (without `expand fn`)**: re-declaring an existing `fn ::` or `op ::` with new pattern clauses automatically merges those clauses into the existing function definition, placing specific constructor/literal pattern clauses **before** any catch-all (`_` / variable) fallback clause:

```ridgun
type Something = String | Int | MyStruct Float Int
expand type Something = Bool

fn :: describe something Something            => String
      describe something "admin"              =  "special_admin"
      describe something 0                    =  "zero_int"
      describe something (String   s)         =  "str:{s}"
      describe something (Int      n)         =  "int:{n}"
      describe something (Bool     b)         =  "bool:{b}"
      describe something (MyStruct ratio cnt) =  "struct:{ratio}:{cnt}"
```

```ridgun
type AppErr = IoError String | Timeout Int

fn :: format app err AppErr        => String
      format app err (IoError msg) =  "IO:{msg}"
      format app err (Timeout ms)  =  "TO:{ms}"
      format app err _             =  "UNKNOWN"

expand type AppErr = AuthError String | DbError Int String

fn :: format app err AppErr              => String
      format app err (AuthError user)    =  "AUTH:{user}"
      format app err (DbError   code db) =  "DB:{code}:{db}"

type AppConfig        = host: String, port: Int
expand type AppConfig = tls: Bool
```

---

## Unified `=` Grammar (`(none)`, `|`, `||`) & Local Variables (`FR-COMP-003`)

Every definition or binding in Ridgun — whether a function clause (`fn ::`), an operator clause (`op ::`), an immutable local variable (`x =`), a mutable local variable (`mut x =`), or a guard branch (`| cond =` / `| otherwise =`) — ends with `=` and accepts the **exact same four block/expression forms** on the right-hand side:

| Prefix after `=` | Execution Semantics | Meaning |
|---|---|---|
| **Inline `<expr>`** | Single expression (with optional `\|\| expr -> var` lines below) | Evaluates `<expr>` directly (resolving any parallel `\|\|` DAG bindings beneath it). |
| **`(none)`** *(indented lines)* | **Sequential** (top-to-bottom) | Evaluates statements in order (`mut`, assignments, side effects); the last expression is the result. |
| **`\| <cond> = ...`** | **Conditional** (guards & nested decision trees) | Evaluates boolean conditions top-to-bottom until the first `True` branch (or `\| otherwise =`). |
| **`\|\| <expr>`** | **Parallel** (green-thread DAG / tuple) | Evaluates `\|\|` branches concurrently (`\|\| expr -> var` for named DAG nodes, `\|\| expr` for parallel tuple results). |

### 1. Guards (`|`) Always Follow `=` (Functions, Operators, Local Variables, and Nested Decision Trees)

Guard blocks (`| cond = ...` and `| otherwise = ...`) **always appear behind an `=`**, unifying function clauses, operator clauses, local variable definitions, and nested conditional trees:

#### Function & Operator Clauses with Guards
```ridgun
fn :: abs Int => Int
      abs n =
        | n < 0     = 0 - n
        | otherwise = n

op :: clamp Int between Int and Int => Int
      clamp x   between lo  and hi  =
        | x < lo    = lo
        | x > hi    = hi
        | otherwise = x
```

#### Local Variable Assignment with Guards
Because `|` is valid after any `=`, local variables can be bound conditionally without needing an `if/else` keyword or a helper function:
```ridgun
discount =
  | is_vip      = 20
  | total > 100 = 10
  | otherwise   = 0
```

#### Multi-Line Sequential Blocks, Deep Decision Trees, and Nested Closers (`|.` / `||.`)
Each guard branch ends with `=`, so its body can itself be a sequential block (`(none)`), a parallel block (`||`), or **another nested `|` guard block** — enabling arbitrary decision trees (3–4+ levels deep) inside `| cond =` and `| otherwise =`.

- **Closing nested levels (`|.` and `||.`)**:
  - In simple 1-level blocks or at the end of a function/tree, **no closing token is needed**.
  - When a nested `|` (or `||`) sub-block finishes and execution **returns to an outer level** where more branches or statements follow below it, **`|.`** (for `|`) or **`||.`** (for `||`) explicitly closes that nested level.
  - Both **inline placement at the end of the last line** (`| otherwise = val |.`, the canonical compact style) and placement on the next line (`|.`) are valid:

```ridgun
fn :: evaluate_payment Account Customer Payment => String
      evaluate_payment account customer payment =
        | is_locked account   = "REJECTED_ACCOUNT_LOCKED"
        | amount payment <= 0 = "ERROR_INVALID_AMOUNT"
        | otherwise =
            | tier customer == "ENTERPRISE" =
                | amount payment > 50000 =
                    | has_dual_signature payment = "APPROVED_ENTERPRISE_DUAL_SIG"
                    | tenure customer > 10       = "RISK_COMMITTEE_REVIEW"
                    | otherwise                  = "REJECTED_ENTERPRISE_LIMIT" |.
                | country payment != "US" =
                    | is_whitelisted (country payment) = "APPROVED_ENTERPRISE_INTL"
                    | otherwise                        = "HELD_COMPLIANCE_INTL" |.
                | otherwise = "APPROVED_ENTERPRISE_STANDARD" |.
            | tier customer == "VIP" =
                | amount payment > 10000 =
                    | has_2fa payment = "APPROVED_VIP_2FA"
                    | otherwise       = "REQUEST_VIP_SMS" |.
                | otherwise = "APPROVED_VIP_DIRECT" |.
            | otherwise =
                | amount payment > 1000 =
                    | has_2fa payment and risk payment < 30 = "APPROVED_RETAIL_2FA"
                    | otherwise                             = "REJECTED_RETAIL_RISK" |.
                | otherwise = "APPROVED_RETAIL_LOW_AMOUNT"

fn :: charge_order Payment => Int
      charge_order payment =
        || fetch_base_fee payment     -> base_fee
        || compute_risk_score payment -> risk_score ||.
        surcharge =
          | risk_score > 80 = 50
          | otherwise       = 0 |.
        base_fee + surcharge
```

### 2. Immutable by Default (`x = ...`) vs Explicit Mutable Variables (`mut x = ...`)

Inside sequential blocks, local variables follow **Option 1**:
- **Immutable binding (`x = <rhs>`)**:
  - Declares a new immutable local variable `x`.
  - Attempting to reassign `x = ...` later in the same scope without a prior `mut x = ...` declaration is a **compile-time error**.
- **Mutable declaration (`mut x = <rhs>`) & Reassignment (`x = <new_rhs>`)**:
  - `mut x = <rhs>` declares `x` as mutable in the current scope and initializes it.
  - Subsequent reassignments to `x` in the same scope are written simply as `x = <new_rhs>` (without repeating `mut`).
  - Under `RMM2`, reassigning `x = <new_rhs>` increments the new structure (`+1`) **before** decrementing the old structure (`-1`, cascading to its children if its counter reaches `0`).

```ridgun
fn :: accumulate Int => Int
      accumulate n =
        factor = 2
        mut acc = n * factor
        acc = acc + 10
        acc =
          | acc > 100 = 100
          | otherwise = acc
        acc
```

### 3. Pattern Matching on Literals & ADT Constructors

```ridgun
fn :: factorial Int => Int
      factorial 0   =  1
      factorial n   =  n * factorial (n - 1)

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

## Parallelism Primitives (`||`)

Ridgun unifies all parallel execution under `||` (`where` is removed):

### Named Parallel DAG Bindings (`|| expr -> var`)

```ridgun
fn :: compute_total Int Int => Int
      compute_total a   b   =  x + y + z
        || heavy_calc a     -> x
        || heavy_calc b     -> y
        || combine x y      -> z
```

- All `|| expr -> var` lines beneath an expression form a **parallel Directed Acyclic Graph (DAG)**.
- The compiler analyzes variable dependencies across `||` lines (`x` and `y` have no dependencies and run in parallel in Wave 1; `z` depends on `x` and `y` and runs in Wave 2 before `x + y + z` is evaluated).
- Parallel tensor slice writes (`|| expr -> out[i, j]`) are also supported.

### Direct Parallel Pipe Blocks (`|| expr`)

```ridgun
op :: run Conf and Conf in parallel => Res, Res
      run a    and b    in parallel =
        || run_process a
        || run_process b
```

Each `||` line runs as a separate parallel green thread, and results are returned as a tuple in declaration order (or joined when placed inside a sequential block).

### Typed Channels

For streaming data and producer-consumer topologies across green threads, Ridgun provides typed MPMC channels (`Channel`):

| Built-in Function / Operator | Signature | Purpose |
|---|---|---|
| `new_channel` | `() => Channel` | Create an unbounded typed channel |
| `new_bounded_channel` | `Int => Channel` | Create a bounded channel with backpressure capacity |
| `send_through` | `T Channel => ()` | Send a value into a channel (blocks if bounded and full) |
| `receive_from` | `Channel => T` | Receive the next value from a channel |
| `try_receive_from` | `Channel => Option` | Non-blocking poll returning `Some v` or `None` |

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
| Immutable local binding | `x = expr` | Bind an immutable local variable (`=` supports `(none)`, `\|`, `\|\|`) |
| Mutable local binding | `mut x = expr` | Declare a mutable local variable (reassigned via `x = new_expr`) |
| Guard block | `\| cond = expr` | Conditional guard branch after `=` (supports nested `\|`) |
| Parallel DAG block | `\|\| expr -> var` | Parallel sub-computations with named DAG results |
| Parallel pipe block | `\|\| expr` | Parallel execution returning a tuple |
| Operator overloading | `op :: type + type => type` | Overload existing operators for new types |
| Bool literals | `True`, `False` | Boolean primitive values |
| Logical operators | `and`, `or`, `xor`, `not` | Word-based lowercase logical operators |
| Entry point | `fn :: main => ()` | Required program entry point |

---

## Canonical Source Code Formatting (`stable format` & Editor Tooling)

> **Aesthetic Only — Not a Compiler Requirement (`FR-TOOL-001`)**: Ridgun's lexer and parser are insensitive to horizontal column alignment. Unaligned and column-aligned `.rg` source files are 100% equivalent to `ridgunc`. The rules below define the **canonical aesthetic layout** applied by `stable format` and GNU Emacs `ridgun-mode` (`C-c C-f`).

1. **Alignment Group per Signature (`fn ::` / `op ::`)**:
   - Each `fn ::` or `op ::` declaration starts an alignment group spanning its signature, its pattern-matching clauses, and its `|| expr -> var` bindings, ending at the next top-level declaration (`fn`, `op`, `type`, `import`, `global`, `context`, `shared`, `hardware`, `@`).
2. **Column Alignment of LHS Tokens ($C_0 = 6$)**:
   - `fn :: ` and `op :: ` are 6 characters wide, so token $0$ of the signature LHS starts at column $C_0 = 6$.
   - Each token slot $i \in [0, N-1]$ before `=>`/`->` (treating `"..."`, `'...'`, `[...]`, and `(...)` as single tokens) has width $W_i = \max(\text{len}(\text{sig\_tok}_i), \max_{\text{clause} : \text{len}(\text{clause\_tok}_i) \le 18} \text{len}(\text{clause\_tok}_i))$ and starts at column $C_i = C_{i-1} + W_{i-1} + 1$. Clause patterns wider than `18` characters are treated as outliers: they do not stretch $W_i$ for the rest of the group and simply overflow on their own line with 1 space.
   - Matching definition clauses are indented to column $6$ ($C_0$) so the function name or operator words and every argument pattern align vertically beneath their corresponding signature slots.
3. **Vertical Alignment of `=>`, `=`, and `->` ($C_{\text{arrow}}$)**:
   - Let $C_{\text{arrow}} = \max\big(C_{N-1} + W_{N-1} + 1,\; \max_{\text{pipe\_bind}}(8 + 3 + \text{len}(\text{pipe\_lhs}) + 1)\big)$ and $C_{\text{ret}} = C_{\text{arrow}} + \text{len}(\text{arrow}) + 1$.
   - In the signature, `=>` is placed at $C_{\text{arrow}}$ and the return type at $C_{\text{ret}}$.
   - In single-line clauses (`<lhs> = <rhs>`), multi-line block clauses (`<lhs> =`), and guard-headed clauses (`<lhs> =` followed by `| cond = ...`), `=` is placed at $C_{\text{arrow}}$ (aligned directly beneath `=>`); in single-line clauses, `<rhs>` starts at $C_{\text{ret}}$.
   - In parallel DAG bindings (`|| <lhs> -> <rhs>`), `||` starts at column $8$ (`6 + 2`), `->` is placed at $C_{\text{arrow}}$, and `<rhs>` starts at $C_{\text{ret}}$.
   - **Compact Fallback (`> 4` Parameters or `> 80` Columns)**: If a declaration has more than `4` parameter slots or its aligned signature line would exceed `80` characters, horizontal column padding is disabled for that group and tokens are separated by a single space (`" "`) while preserving column-6 clause indentation.
4. **Structural Indentation (2-Space Offset)**:
   - Top-level declarations (`fn`, `op`, `type`, `import`, `global`, `context`, `shared`, `hardware`, `@`): column `0`.
   - Function/operator clauses under a signature: column `6`.
   - Guards (`| cond = expr`) and parallel pipes (`|| expr` / `|| expr -> var`): `prev_indent + 2` (column `8` inside a clause, or `indent + 2` inside a local binding or nested guard).
   - Sequential block body lines following a line ending in `=`: `prev_indent + 2`.

---

## Sequential & Parallel Higher-Order Collection Operations (`FR-COMP-001`)

Ridgun provides standard sequential collection combinators (`map`, `filter`, `fold`) alongside explicit multicore parallel combinators prefixed with `||` (`||map`, `||filter`):

| Built-in | Signature | Execution Model |
|---|---|---|
| `map` | `(A => B) [A] => [B]` | **Sequential**: evaluates `f x` strictly left-to-right on the calling thread. |
| `||map` | `(A => B) [A] => [B]` | **Parallel (`||`)**: evaluates `f x` across list elements concurrently on worker threads, preserving output order. |
| `filter` | `(A => Bool) [A] => [A]` | **Sequential**: evaluates predicate `p x` strictly left-to-right on the calling thread. |
| `||filter` | `(A => Bool) [A] => [A]` | **Parallel (`||`)**: evaluates predicate `p x` concurrently on worker threads and retains matching elements in order. |
| `fold` | `(B A => B) B [A] => B` | **Sequential left fold**: accumulates `acc = f acc x` from left to right starting from `init`. |

---

## Verbatim File I/O, Byte Streams & POSIX Built-ins (`FR-VM-001`, `FR-VM-002`)

1. **Verbatim File & Byte Stream I/O (`FR-VM-001`)**:
   - `read_file : String => String` reads file contents verbatim (preserving `\r\n` and exact EOF newline presence/absence, and never running the compiler's `.rg` `import` preprocessor on data files).
   - `load_rg_source : String => String` is used exclusively by the compiler toolchain when loading `.rg` source files with `import` splicing.
   - `read_bytes : String => [Int]` and `write_bytes : String [Int] => ()` read and write raw binary byte streams (`0..255`, including `0x00` NUL and `0x80..0xFF`).
2. **POSIX Filesystem, Process & Security Built-ins (`FR-VM-002`)**:
   - **Filesystem**: `list_dir`, `file_lstat`, `sha256_file`, `sys_mkdir`, `sys_chmod`.
   - **Process & Environment**: `sys_exec`, `sys_chdir`, `sys_getcwd`, `sys_getenv`, `sys_setenv`, `sys_exit`.
   - **Security & Privilege Separation**: `sys_getuid`, `sys_getgid`, `sys_username`, `sys_user_groups`, `sys_lookup_uid_gid`, `sys_setresgid`, `sys_setgroups`, `sys_setresuid`, `sys_execve`, `sys_read_pass`.

---

## Ridgun Memory Management (RMM): `RMM1` (CMM) & `RMM2` (`FR-COMP-002`)

Ridgun manages heap memory (`String`, `[a]`, `(a, b)`, ADTs, `Tensor`) deterministically without a tracing Garbage Collector (GC) through **Ridgun Memory Management (RMM)**:

1. **Policy `RMM1` — Compiled Memory Management (CMM Linear + Conditional)**:
   - Applied when control flow and called functions are statically known at compile time over non-nested bindings:
     - **Linear CMM (`rg_cmm_move` / `rg_cmm_drop`)**: The compiler determines the exact last-use statement of every local variable at compile time, moving returned variables (`rg_cmm_move(&mut lv_x)`) and emitting unconditional deallocation (`rg_cmm_drop(&mut lv_x)`) immediately after a variable's last use when no may-aliases remain live.
     - **Conditional CMM (`rg_cmm_drop_unless` / `ptr(a) != ptr(c)`)**: When a static branching call (`c = choose_list cond a b`) returns one of several candidate inputs and one or more candidates remain live alongside `c`, the compiler builds the **Ancestor May-Alias Table (`RCmmAlias`)** and emits a 1-cycle pointer-identity guard at each variable's static last-use statement:
       ```ridgun
       a = make_a ()               -- Allocates M1
       b = make_b ()               -- Allocates M2
       c = choose_list cond a b    -- b dies here while c is live -> if ptr(b) != ptr(c) { free(b) }
       print_list a                -- a dies here while c is live -> if ptr(a) != ptr(c) { free(a) }
       consume_list c              -- c dies here (no live peers) -> free(c) (unconditional)
       ```
2. **Policy `RMM2` — Assignment & Cascaded Structure Counting (Active Policy)**:
   - Unifies memory management across functions, branching returns (`choose_list`), nested containers (`xs = [a, b, ..., z]`, `xs[3] = a`), mutable local variables (`mut x = ...`), and multi-thread execution:
     - **Primitive Scalars (`Int`, `Real`, `Bool`, `()`)**: Never counted; copied by value on the stack/registers.
     - **Incoming Function Arguments (`pats`)**: **Never touched** (`+0` on entry, `-0` on exit).
     - **Internal Local Variables (`x = ...` / `mut x = ...`)**: Receive **`+1` on assignment** (`x = expr`, `xs[3] = a`). On mutable reassignment (`x = new_expr`), `new_expr` receives `+1` before old `x` receives `-1`.
     - **End of Function / Scope Exit**:
       - Non-returned internal local variables receive `-1` first: if `rc == 0`, the parent block is freed and **cascades `-1` one by one to each direct child structure** (recursively freeing any child whose `rc` reaches `0`).
       - A returned internal local variable (`return a`) receives `-1` (or is moved via `rg_cmm_move`), and even if its `rc` is `0` in transit, it is **spared** so the caller's assignment (`c = make_pair ()`) adds `+1` (`0 + 1 = 1`). When an incoming argument is returned (`choose_list cond a b`), it was untouched inside the function (`rc = 1`), so the caller's `c = choose_list cond a b` adds `+1` (`1 + 1 = 2`, shared between `a` and `c`).
3. **Policy `RMM3`** *(Reserved)*:
   - Reserved for a subsequent aggressive static optimization policy.
   - See [`docs/etc/cmm_architecture.md`](../etc/cmm_architecture.md) for the complete `RMM1` and `RMM2` specification.


