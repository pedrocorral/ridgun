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
sum_many Int... => Int
sum_many nums   =  sum_list nums

main => ()
main =
  echo (sum_many 10 20 30)       -- Prints 60
  echo (sum_many 1 2 3 4 5 6 7)  -- Prints 28
```

---

## 5.3. Tuples: When a Function Wants to Return More Than One Thing

In many languages, returning two values from a function is a headache: either you create a throwaway helper class `ResultWithPosition`, or you pass out-pointers by reference.

In Ridgun you return a **tuple** `(A, B)`:

```ridgun
div_rem Int Int => (Int, Int)
div_rem a   b   =  (a / b, a % b)
```

You can even omit the parentheses on the signature line if you find it cleaner:
`div_rem Int Int => Int Int`.

### How to Unpack a Tuple
Just as you build it with `(a, b)`, you unpack it in the parameters of any function with `(quotient, remainder)`:

```ridgun
explain_division (Int, Int)            => String
explain_division (quotient, remainder) =  "Fits {quotient} times with {remainder} left over"
```

### The Star Feature: Automatic Tuple Unpacking Between Functions
Suppose you have `div_rem` (which returns a tuple of 2 integers) and another function `add_pair Int Int => Int` (which expects 2 separate integers). In Ridgun you don't have to unpack the tuple by hand into an intermediate variable; you can plug one function straight into the other:

```ridgun
add_pair Int Int => Int
add_pair x   y   =  x + y

main => ()
main =
  -- div_rem 17 5 returns (3, 2), and add_pair receives 3 and 2 directly:
  echo (add_pair (div_rem 17 5))  -- Prints 5
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
middle_of_three Int Int Int => Int
middle_of_three (s)         =  s["-+-"]

drop_first_two Int... => [Int]
drop_first_two (s)    =  s["-- +"]

main => ()
main =
  echo (middle_of_three 100 42 999)     -- Prints 42
  echo (drop_first_two 1 2 10 20 30)    -- Prints [10, 20, 30]
```

On top of that, if you use the comma operator `,` outside parentheses (`list1 , list2`), Ridgun flattens both collections into a single continuous sequence.

In **Chapter 06** we will take the step that turns a functional programmer into a first-class software architect: **creating your own Algebraic Data Types (ADTs), writing polymorphic functions with `A`..`Z`, and crafting your own custom operators**.
