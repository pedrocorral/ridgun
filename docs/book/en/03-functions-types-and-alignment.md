# Chapter 03: Functions, Type Signatures, and the Art of Writing Code as a Table

There is a question every programmer asks the first time they see functional code:

> *"If there are no classes, no objects, and no variables that mutate all over the place... where do I put my logic?"*

In **functions**. Not those 200-line monster functions tangled with boolean flags that we have all suffered through at some point, but small, direct functions so easy to read they look like a table drawn on a whiteboard.

Let's see how they are built.

---

## 3.1. Two Ways to Present a Function (Pick Your Suit)

In Ridgun every function begins with its **type signature** (what goes in and what comes out after `=>`), followed below by its **implementation clauses** (with `=`).

You can write the header in two ways:

### Option A: Straight to the point (no prefix)
```ridgun
apply_discount Int   Int     => Int
apply_discount price percent =  price - (price * percent / 100)
```

### Option B: With an explicit label (`fn ::`)
```ridgun
fn :: apply_discount Int   Int     => Int
      apply_discount price percent =  price - (price * percent / 100)
```

*"Hey, why do both exist?"*
Because different people like different styles:
- Some prefer functions to start flush against the left margin without typing `fn ::` every time (after all, the `=>` arrow already shouts loud and clear that the line is a type signature).
- Others prefer having a dedicated left-hand column for declaration labels (`fn ::`, `op ::`, `type`, `import`) so they can scan the file visually.

Both the compiler and `stable format` understand both styles effortlessly.

---

## 3.2. The Magic of Columns: Why Your Eyes Can Relax

Look at this function that calculates shipping costs based on destination country and whether delivery is express:

```ridgun
shipping_cost String Bool  Int    => Int
shipping_cost "ES"   False _      =  5
shipping_cost "ES"   True  _      =  12
shipping_cost _      False weight =  10 + (weight * 2)
shipping_cost _      True  weight =  25 + (weight * 4)
```

Try this test: cover the right half of the screen and look only at the three input columns:
- First column (`String`): `"ES"`, `"ES"`, `_`, `_`.
- Second column (`Bool`): `False`, `True`, `False`, `True`.
- Third column (`Int`): `_`, `_`, `weight`, `weight`.

Do you spot any logical gaps? None: all 4 possible combinations are right in front of your eyes, aligned vertically underneath `String`, `Bool`, and `Int`. In a traditional `if / else` block you would have to read 18 lines just to be sure you didn't miss an edge case.

---

## 3.3. Basic Types and a Gift so You Never Count Zeros Again (`_KB`, `_MB`, `_GB`)

Ridgun's scalar types are direct and surprise-free:

| Type | What It Actually Is | Examples |
|---|---|---|
| `Int` | Signed 64-bit integer (`i64`) | `0`, `42`, `-100`, `0xFF00`, `1_000_000` |
| `U64` | Unsigned 64-bit integer (`u64`) for cryptography and systems | `0xdeadbeefcafe0001`, `a xor b`, `x rotr 24` |
| `Byte` | Unsigned octet (`0..255`) in tensors and binary buffers | `Tensor[Byte * 64]` |
| `Real` / `Float` | Double-precision float (`f64`) | `3.14159`, `0.001`, `-2.5` |
| `String` | Immutable text or length-delimited binary buffer | `"Hello"`, `'raw\path'`, `sha256 raw "abc"` |
| `Char` | Character code point | Returned by `str char at` |
| `Bool` | Classic boolean | `True`, `False` |
| `()` | Empty (*Unit*, when you only print or perform I/O) | `()` |

### 1-Cycle Bitwise Operators and Lexical Flexibility (`fn`, `op`, `where`)
For cryptography, binary protocols, and high-performance systems code, `Int` and `U64` provide native 1-cycle bitwise, shift, and rotation operators:
- **Logical & bitwise**: `and`, `or`, `xor`, `not`
- **64-bit shifts & rotations**: `shl` (shift left), `shr` (unsigned logical shift right), `rotl` (rotate left), `rotr` (rotate right)

Ridgun's vocabulary is also deliberately minimal and orthogonal:
- **`where` is not a reserved keyword**: parallel DAG bindings are written exclusively with `||`, so `where` has no special meaning and can be used as a normal identifier.
- **`fn` and `op` can be part of function and operator names**: after `fn ::` or `op ::`, the words `fn` and `op` can appear freely inside the name (`fn :: op Int => Int`, `op :: Int fn Int => Int`, `op :: A op B => A`).
- **Space-separated multi-value outputs (`=> Int Int`)**: functions returning multiple values write their output types separated by spaces (`fn :: divmod Int Int => Int Int`), and callers can destructure them without heap-allocating intermediate tuples (`q, r = divmod 17 5`).

### Tired of writing `65536` or `1048576` and praying you didn't drop a digit?
In Ridgun, numeric literals directly accept the **`_KB`**, **`_MB`**, and **`_GB`** suffixes, as well as underscores `_` to separate digit groups:

```ridgun
buffer_size => Int
buffer_size =  64_KB      -- The compiler translates this to 65536

file_limit => Int
file_limit =  16_MB       -- The compiler translates this to 16777216

octet_mask => Int
octet_mask =  0xFF_00     -- Clean, readable hexadecimal
```

---

## 3.4. Double Quotes (`"..."`) vs. Single Quotes (`'...'`)

In many languages, single quotes and double quotes do the exact same thing (a total waste). In Ridgun, each has a crystal-clear mission:

### 1. Double Quotes (`"..."`): Smart and Interpolated
They interpret escape sequences (`\n`, `\t`, `\"`, `\\`) and **evaluate any variable or expression you place inside curly braces `{...}`**:

```ridgun
order_summary String Int Int   => String
order_summary item   qty price =
  "You ordered {qty}x {item}. Total due: {qty * price} euros."
```

*(Pro tip: if you need a literal curly brace inside double quotes—for instance when generating a shell script `"$\{VAR:-default\}"` or JSON—you can escape it with a backslash `\{` and `\}` or double it as `{{` and `}}`).*

### 2. Single Quotes (`'...'`): Raw and Literal (*Raw Strings*)
Whatever you write inside single quotes comes out **verbatim**, without touching a single backslash `\` or curly brace `{}`. Perfect when generating code in another language, writing shell commands, or working with backslash-heavy paths:

```ridgun
sed_command => String
sed_command =  's/\([0-9]+\)/[\1]/g'
```

### Your String Toolbox (`String`)
Joining strings is as simple as adding them with `+`: `"Hello, " + name`. And when you need fine-grained surgery on text, these native functions are ready to go without importing a thing:

- `str_len s` $\rightarrow$ length of `s`.
- `str_char_at s i` $\rightarrow$ numeric code (`Int`) of the character at index `i` (`-1` if out of bounds).
- `str_slice s start end` $\rightarrow$ slices from `start` up to `end` (excluding `end`).
- `char_from_code c` $\rightarrow$ converts a numeric code (`Int`, e.g. `10` for `\n` or `34` for `"`) into a 1-character `String`.
- `str_contains s needle` and `str_starts_with s prefix` $\rightarrow$ return `True` or `False`.
- `int_to_str n` and `str_to_int s` $\rightarrow$ convert numbers to strings and vice versa (`str_to_int` even understands `"0xFF"`!).

---

## 3.5. Multi-Line Blocks, the Universal `=` Rule, and `mut` Variables

When a function doesn't fit on a single line, add a newline after `=` and indent the block.

Look at how a block reads step by step:

```ridgun
compute_invoice Int  Int     => Int
compute_invoice base tax_pct =
  taxes = base * tax_pct / 100
  handling_fee = 5
  echo "Breakdown -> Base:" base "Taxes:" taxes
  base + taxes + handling_fee
```

Four golden rules make blocks in Ridgun clean and uniform:
1. **Immutable by default without `let` or `const`**: write `taxes = ...` and you have an immutable local constant. If you accidentally try to overwrite `taxes = 99` further down in the same block, the compiler stops you cold.
2. **Explicit mutable variables with `mut`**: when you genuinely want to update a local accumulator step by step inside a function, declare it with **`mut`** and then reassign it freely with `=`:
   ```ridgun
   apply_surcharges Int   => Int
   apply_surcharges price =
     mut total = price
     total = total + 10
     total = total * 2
     total
   ```
   *(And if `total` holds a heap-allocated list or structure, Ridgun's **`RMM2`** policy adds `+1` to the new value before subtracting `-1` from the old one, freeing it immediately if nothing else references it).*
3. **The universal `=` rule**: after **any `=`** (in a function, an operator, a local variable `x =`, or a conditional branch) you can always place any of Ridgun's three block forms:
   - **`(nothing)`**: indented sequential lines (like above).
   - **`|`**: a tree of conditional guards.
   - **`||`**: a parallel computation graph with `->`.
4. **The last expression is always the return value**: `base + taxes + handling_fee` is what `compute_invoice` returns. No `return` keyword needed.

In **Chapter 04** we will see how to make complex decisions—including multi-level decision trees with `|.`—without ever writing an `if/else` or a `while` loop: welcome to the world of **boolean guards** and **zero-cost tail recursion**.
