# Chapter 04: Goodbye `if/else`, Goodbye `while` (Pattern Matching, Guards, and TCO)

When you tell someone that Ridgun **has no `if`, no `else`, no `switch`, no `for`, and no `while` keyword**, they usually look at you as if you just said you're going to build a house without a hammer or nails:

> *"No `if` and no `while`? Then how on earth do I make a decision or loop over a million items?"*

It turns out that `if/else` and `while` are fairly blunt tools inherited from how hardware jumps (`GOTO`) worked in the 1950s. In Ridgun we replace them with three pieces that fit together like a glove:
1. ***Pattern Matching*** (when deciding based on the **shape or exact value** of data).
2. **Boolean guards `|`** (when deciding based on a **condition or range**).
3. **Tail recursion with TCO** (which the compiler turns into a blazing-fast native `loop` under the hood).

Let's see them in action.

---

## 4.1. *Pattern Matching*: When the Argument Already Gives You the Answer

We saw a preview of this in the previous chapter. Instead of taking a generic variable `x` and opening five `if (x == ...)` branches inside the function body, in Ridgun you put the cases right at the front door of the function:

```ridgun
http_status Int => String
http_status 200 =  "OK: Everything went smoothly"
http_status 301 =  "Moved permanently"
http_status 404 =  "Not found (did you check under the couch?)"
http_status 500 =  "Server is on fire"
http_status n   =  "Unknown status code: {n}"
```

Ridgun tests the rows **from top to bottom**:
- If `404` comes in, it jumps straight to the third row.
- If `418` comes in, none of the first four rows match, so it falls through to the last row (`n`), which catches any integer and names it `n` so you can format it.
- And what if in the last case you don't even care what number it was? Put an underscore `_` (*wildcard*) and forget about it: `http_status _ = "Other status code"`.

---

## 4.2. Boolean Guards (`|`): Your Scalpel for Ranges, Conditional Bindings, and Decision Trees

*"Okay, pattern matching is great when I'm looking for `200` or `404`. But what if I want to check whether `score >= 5` or `age > 18 and age < 65`? I'm not going to write 47 rows for every number between 18 and 65!"*

Of course not! That is what **guards (`|`)** are for.

When the result depends on an inequality or a logical combination, right after the `=` of the function (or of any local variable) you open a ladder of vertical bars `|`:

```ridgun
grade Int   => String
grade score =
  | score < 0   = "Impossible score (negative points?)"
  | score < 5   = "Fail"
  | score < 7   = "Pass"
  | score < 9   = "Merit"
  | score <= 10 = "Distinction"
  | otherwise   = "Off the scale"
```

Look closely at how it works:
- The `=` sign on the header line (`grade score =`) aligns underneath `=>` just like in any other function.
- Below it, you read top to bottom just like a rate card: each `| condition = result` line is checked in order. The moment one evaluates to `True`, it returns that result and we're done.
- At the end you place **`| otherwise = ...`**, which means *"in any other case"* (your safety net so no path ever falls through without a return value).

### Clear Lowercase Boolean Logic (`and`, `or`, `xor`, `not`)
Have you ever noticed how many languages use `|` for bits, `||` for booleans, `!` for negation... so when you read a complex condition it looks like a cat walked across your keyboard (`if (!a && (b || c))`)?

In Ridgun, since `|` is already the sacred symbol for guards and algebraic data types, and `||` is the parallelism operator, **boolean operators are written as clear lowercase words**:

- **`and`**: both sides must hold (`age >= 18 and has_license`).
- **`or`**: at least one side holds (`day == "saturday" or day == "sunday"`).
- **`xor`**: one or the other holds, but not both at once.
- **`not`**: flips the boolean (`not (is_empty text)`).

Look how clean the classic leap-year check becomes:

```ridgun
is_leap_year Int => Bool
is_leap_year y   =
  | (y % 400) == 0                  = True
  | (y % 4) == 0 and (y % 100) != 0 = True
  | otherwise                       = False
```

Zero cryptic symbols. Someone who has never seen Ridgun can read it and understand it on the first try.

### Conditional Local Variables (`x =` + `|`)
Because every `=` in Ridgun follows the same universal rule, **you can also use `|` to assign a local variable** without having to extract a separate helper function:

```ridgun
ticket_price Int  Bool            => Int
ticket_price base is_large_family =
  discount =
    | is_large_family = 20
    | base > 100      = 10
    | otherwise       = 0
  base - (base * discount / 100)
```

### Nested Decision Trees and the Compact Terminator `|.`
*"What if inside a `| cond =` or `| otherwise =` branch I want to open another sub-tree of `|` guards 3 or 4 levels deep, and then return to an outer level?"*

You can nest `|` inside `|` as many levels deep as you want. And when a nested `|` block finishes while more branches of a parent level (or more sequential statements in the block) continue below it, you place **`|.`** at the end of its last line (`| otherwise = value |.`) to indicate with zero ambiguity that the sub-tree is closed and you are stepping back to the parent level:

```ridgun
route_request Int    Int  Bool   Bool     Int     Int     => Int
route_request method role signed is_admin size_kb limited =
  | method == 0 =
    | size_kb == 0 = 204
    | otherwise    = 200 |.
  | method == 1 =
    | not signed = 401
    | otherwise =
      -- Level 2: signed POST request
      | limited > 0 =
        -- Level 3: rate-limit check
        | is_admin =
          -- Level 4: administrator override
          | size_kb > 10000 = 413
          | otherwise       = 202 |.
        | otherwise = 429 |.
      | size_kb > 1000 =
        -- Level 3: back from Level 4 thanks to `|.`
        | role >= 2 and is_admin = 201
        | otherwise              = 413 |.
      | otherwise = 201 |.
  | otherwise = 405
```

Notice how clean that is:
- In a flat 1-level guard tree (or at the very end of the entire function) **you never need to write `|.`** (that would be unnecessary noise).
- You only write `|.` when closing a nested branch that is followed below by a branch at an outer level.

### Multi-Line Blocks Inside a Guard (`| cond =` + indented block)
Just as you can open a multi-line indented block after the `=` of a normal function, **after the `=` of any `| cond =` or `| otherwise =` guard you can also add a newline and open a sequential block**:

```ridgun
adjust_window Int Int   => Int
adjust_window idx limit =
  | idx >= limit =
      cap = limit - 1
      scaled = cap * 2
      scaled + 10
  | otherwise =
      next = idx + 1
      next * 2
```

Each guard branch gets its own clean local scope, and its last line is the value returned by that branch.

---

## 4.3. "No `while`? Won't the Stack Blow Up If I Scan a Large File?"

Let's address the elephant in the room.

If you come from Python, Java, or JavaScript, you were taught from day one that *"recursion looks pretty on a university whiteboard, but in the real world it blows the call stack (`StackOverflowError`) after 1,000 iterations; use a `while` loop"*.

That is true in languages that do **not** optimize tail calls. But in a systems functional language like Ridgun, **tail recursion IS a `while` loop dressed up as a pure function**.

### What Is the Difference Between Normal Recursion and Tail Recursion?
Look at these two functions that count down from `n` to `0` while summing the numbers:

```ridgun
-- Version A: NORMAL recursion (leaves pending work for the return trip)
sum_slow Int => Int
sum_slow 0   =  0
sum_slow n   =  n + (sum_slow (n - 1))

-- Version B: TAIL recursion (keeps a running total in `acc`)
sum_fast_loop Int Int => Int
sum_fast_loop 0   acc =  acc
sum_fast_loop n   acc =  sum_fast_loop (n - 1) (acc + n)
```

- In **Version A**, before it can compute `n + ...`, the function has to wait for `sum_slow (n - 1)` to finish. That forces the CPU to push `n` onto the call stack at every step.
- In **Version B**, the call to `sum_fast_loop` **is the very last thing that happens on the line**. Nothing is left waiting after it. You pass the updated running total right into `acc + n`.

### `ridgunc`'s Magic Trick (TCO: *Tail-Call Optimization*)
When `ridgunc` compiles `sum_fast_loop`, it sees that the function calls itself in tail position and says:

> *"Why would I allocate a new stack frame when the current one is finished? I'll just overwrite `n` with `n - 1`, overwrite `acc` with `acc + n`, and jump back to the top with a native `loop { ... continue; }`."*

The result:
1. You can call `sum_fast_loop 100_000_000 0` (one hundred million iterations) and it will consume **exactly 0 extra bytes of stack**.
2. It runs at the exact same speed as a hand-written `while` loop in Rust or C, without you having to declare a single mutable variable in your Ridgun code.

---

## 4.4. The Master Pattern You Will Use in Every Ridgun Program

Whenever you would think in another language *"I'll write a `while` loop with an index `i` and an accumulator"*, in Ridgun you write a pair of functions like this (the clean public function and its tail-recursive `_loop` helper):

```ridgun
find_char_loop String Int Int Int    => Int
find_char_loop text   pos end target =
  | pos >= end                       = -1
  | (str_char_at text pos) == target = pos
  | otherwise                        = find_char_loop text (pos + 1) end target

find_char String Int    => Int
find_char text   target =  find_char_loop text 0 (str_len text) target
```

Look at the three guards in `find_char_loop`:
1. Did I reach the end (`pos >= end`)? Return `-1` (end of loop).
2. Did I find the character at `pos`? Return `pos` (end of loop).
3. Not this one? Advance to the next index (`pos + 1`) with a tail call (which the compiler turns into `continue;`).

Clean, immune to clobbered-state bugs, and fast as lightning.

In **Chapter 05** we will get our hands on data collections: **lists, tuples, functions that accept an arbitrary number of arguments (`...`), and J/APL-style sequence masks**.
