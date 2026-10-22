# Chapter 05: Lists, Tuples, and the Ninja Trick of Sequences

A program that only moves one number or one string at a time doesn't get you very far. In the real world you handle lists of files, database rows, network packets, or coordinates.

For that, Ridgun gives you three distinct containers, each designed for a very specific job:
1. **Lists (`[T]`)**: *"I have many elements of the same type (or none at all) and I want to traverse them"*.
2. **Tuples (`(A, B)`)**: *"I want to return a pair or trio of different things together without declaring a new type"*.
3. **Sequences and masks (`s["-+-"]`)**: *"I want to filter or slice arguments on the fly as if I had a mathematical sieve"*.

Let's take them one by one.

---

## 5.1. Lists (`[T]`): Your Daily Bread

In Ridgun, wrapping square brackets around a type gives you a list of that type:
- `[Int]` is a list of integers: `[10, 20, 30]`.
- `[String]` is a list of strings: `["apple", "pear"]`.
- `[]` is the empty list (the wildcard that fits any `[T]`).

> *"Hey, can I put a number and a string together in the same list like `[1, "two"]`?"*
> Raw like that, **no** (and thank the compiler for stopping you, because that guarantees an addition will never blow up in production when it stumbles upon a surprise string). In Chapter 06 we will see how to model `[1, "two"]` with total elegance using an Algebraic Data Type (just like Haskell and Rust do).

### How to Slice Up a List Without `i`, `j`, `k` Indices: `[]` and `(x:xs)`
In imperative languages, walking a list usually means `for (int i = 0; i < list.size(); i++)`, carrying the classic risk of an *off-by-one* error.

In Ridgun you don't count indices; **you take the list apart from the head**:
- `[]`: matches when the list is empty.
- `(x:xs)`: matches when the list has at least one element. It binds the first element to `x` (the **head**) and the rest of the list to `xs` (the **tail**).

Look how satisfying it is to sum a list or count how many elements it has:

```ridgun
sum_list [Int]  => Int
sum_list []     =  0
sum_list (x:xs) =  x + (sum_list xs)

count_elements [A]    => Int
count_elements []     =  0
count_elements (_:xs) =  1 + (count_elements xs)
```

And here is a technical detail that will make your day: in Ridgun, taking the tail `xs` in `(x:xs)` **does not copy the rest of the list in memory**. Internally it is a zero-copy view over the same backing vector that simply advances the start offset by `1` (instantaneous $O(1)$).

### Peeling Off Multiple Elements at Once
The `:` pattern shines when you are parsing commands or network protocols:

```ridgun
parse_command [String]            => String
parse_command []                  =  "You didn't type anything"
parse_command ("help":_)          =  "Showing help..."
parse_command ("copy":src:dst:[]) =  "Copying from {src} to {dst}"
parse_command (cmd:_)             =  "Unknown command: {cmd}"
```

Look at the third row: `("copy":src:dst:[])` verifies in a single stroke that the list has **exactly 3 elements**, that the first one is `"copy"`, and hands you the second and third elements on a silver platter in `src` and `dst`. Try writing that in C or Java and count how many lines of `args.length == 3 && args[0].equals("copy")` you end up with.

### Joining Lists with Double Colon (`::`)
When you are on the right-hand side of `=` (in an expression) and want to concatenate two lists, use **`::`**:

```ridgun
join_lists [Int] [Int] => [Int]
join_lists a     b     =  a :: b

append_item [Int] Int => [Int]
append_item xs    x   =  xs :: [x]
```

*(Quick mnemonic rule: a single `:` in patterns takes a list apart; a double `::` in expressions glues two lists together).*

And what if you genuinely want to grab element number 5 directly without traversing anything? Use square brackets right after the name: `my_list[5]`.

---

## 5.2. Variadic Functions (`T...`): "Pass Me as Many as You Want!"

Sometimes you want callers of your function to write `max_of 4 19 2 88 7` comfortably, without forcing them to wrap the numbers in square brackets `[4, 19, 2, 88, 7]`.

Put three dots **`...`** after the last type in your signature, and inside your function you will automatically receive those arguments packaged as a list:

```ridgun
fn :: sum many Int... => Int
      sum many nums   =  sum list nums

fn :: main => ()
      main =
        echo (sum many 10 20 30)       -- Prints 60
        echo (sum many 1 2 3 4 5 6 7)  -- Prints 28
```

---

## 5.3. Tuples and Unified Space-Separated Type Signatures (`Int Int [String String] String`)

In many languages, returning two or more values from a function is a headache: either you create a throwaway helper class `ResultWithPosition`, or you clutter the signature with redundant commas and parentheses.

In Ridgun, **an argument list `Int String Int` and a tuple `(Int, String, Int)` are conceptually the same thing: a typed sequence (`seq`)**. Because of this, in type signatures you can separate tuple elements simply with **spaces**—after `=>`, inside list brackets `[...]`, and inside parentheses `(...)`:

```ridgun
-- Two return integers separated by a space:
fn :: div rem Int Int => Int Int
      div rem a   b   =  (a / b, a % b)

-- Complex return signature without comma or outer-parenthesis clutter:
fn :: parse header String => Int Int [String String] String
      parse header tag    =  (200, 2, [("Host", "ridgun.org"), ("X-Tag", tag)], "OK")

-- List of tuples [String String] as an input parameter:
fn :: lookup header [String String] String => String
      lookup header []              _      =  "missing"
      lookup header ((k, v):rest)   key
        | k == key  = v
        | otherwise = lookup header rest key
```

Notice how clean `=> Int Int [String String] String` is:
- After `=>`, `Int Int [String String] String` is 100% equivalent to `(Int, Int, [(String, String)], String)`.
- Inside brackets, `[String String]` denotes a list of string pairs `[(String, String)]`.
- Inside parentheses (when passing a tuple as a single grouped parameter), `(Int Int)` is 100% equivalent to `(Int, Int)`:
  ```ridgun
  fn :: explain division (Int Int)             => String
        explain division (quotient, remainder) =  "Fits {quotient} times with {remainder} left over"
  ```
- **Why does this have zero syntactic ambiguity in Ridgun?** Unlike Haskell (where `Maybe Int` applies a type constructor by juxtaposition), parameterized types in Ridgun use explicit parentheses like `Tensor(Float, 3, 3)` and lists use `[T]`. Therefore, two space-separated types (`T1 T2`) always unambiguously denote a tuple/sequence of types while remaining 100% compatible with comma syntax.

### The Star Feature: Automatic Tuple Unpacking Between Functions
Suppose you have `div rem` (which returns `Int Int`) and another function `add pair Int Int => Int` (which expects 2 separate integers). In Ridgun you can plug one function straight into the other:

```ridgun
fn :: add pair Int Int => Int
      add pair x   y   =  x + y

fn :: main => ()
      main =
        -- div rem 17 5 returns (3, 2), and add pair receives 3 and 2 directly:
        echo (add pair (div rem 17 5))  -- Prints 5
```

---

## 5.4. The Ninja Trick: Sequences and Positional Masks (`s["-+-"]`)

Here comes one of Ridgun's most original gems, inherited straight from array languages like J and APL.

Imagine you receive a stream of arguments using the sequence pattern **`(s)`** and want to keep only certain positions while discarding others, without inventing five throwaway variable names (`_a`, `b`, `_c`, `d`...).

You apply a **mask of `+` (keep it) and `-` (drop it) signs** to `s`:

- **`s["-+-"]`**: out of 3 elements, drop the first (`-`), keep the second (`+`), and drop the third (`-`).
- **`s["+-+"]`**: keep the first and the third; returns the sequence containing those two.
- **`s["-- +"]`** (note the space before the last `+`): drop the first two (`--`) and apply `+` **to all remaining elements that follow**, no matter how many there are.

See it in action:

```ridgun
fn :: middle of three Int Int Int => Int
      middle of three (s)         =  s["-+-"]

fn :: drop first two Int... => [Int]
      drop first two (s)    =  s["-- +"]

fn :: main => ()
      main =
        echo (middle of three 100 42 999)     -- Prints 42
        echo (drop first two 1 2 10 20 30)    -- Prints [10, 20, 30]
```

On top of that, if you use the comma operator `,` outside parentheses (`list1 , list2`), Ridgun flattens both collections into a single continuous sequence.

In **Chapter 06** we will take the step that turns a functional programmer into a first-class software architect: **creating your own Algebraic Data Types (ADTs), writing polymorphic functions with `A`..`Z`, and crafting your own custom operators**.
