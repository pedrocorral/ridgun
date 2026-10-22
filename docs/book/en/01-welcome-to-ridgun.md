# Chapter 01: Your First Contact with Ridgun (No Boilerplate, No Braces, No Semicolons)

Alright, Chapter 00 convinced you that we weren't crazy for creating Ridgun. Right now you're probably thinking:

> *"Nice speech about tables and 16 cores, but show me real code. How long does it take to write something that actually works without fighting the compiler?"*

Let's get right to it!

---

## 1.1. "Hello, World!", But with Teeth

Most programming books show you a bland `print("Hello world")` and turn the page. We are going to jump straight into a function with real logic so you can see how Ridgun breathes from minute one.

Create a file named `hello.rg` and write this:

```ridgun
greet String => String
greet ""     =  "Hello, mysterious traveler! (You didn't tell me your name)"
greet "Root" =  "Hey there, Root! Careful what you delete today."
greet name   =  "Hello, {name}! Welcome to Ridgun."

main => ()
main =
  echo (greet "Ada")
  echo (greet "Root")
  echo (greet "")
```

To run it right now:

```bash
ridgunc run hello.rg
```

And you will see in your terminal:

```text
Hello, Ada! Welcome to Ridgun.
Hey there, Root! Careful what you delete today.
Hello, mysterious traveler! (You didn't tell me your name)
```

Pause for a moment and look at the `greet` block above. Notice what is **NOT** there?
- **No `function`, `def`, or `pub fn`** (you can put `fn ::` before the signature if you like, but it's optional).
- **No parentheses `(String name)` or curly braces `{ ... }`** cluttering the screen.
- **No `if (name == "") ... else if (name == "Root") ... else ...`**.
- **No `return`**.

---

## 1.2. How Your Brain Reads an `.rg` File

Let's dissect those four lines of `greet`, because 50% of Ridgun's philosophy is already right here:

```ridgun
greet String => String
greet ""     =  "Hello, mysterious traveler! (You didn't tell me your name)"
greet "Root" =  "Hey there, Root! Careful what you delete today."
greet name   =  "Hello, {name}! Welcome to Ridgun."
```

1. **The first line is the contract (`greet String => String`)**:
   It says: *"My name is `greet`, I take a `String`, and I give you back (`=>`) another `String`"*. Period. If someone tries to call me with the number `42`, the compiler will tap them on the shoulder before the program even runs.
2. **The lines below are the cases (top to bottom)**:
   - Did you pass me the empty string `""`? I return the first sentence.
   - Did you pass me the exact string `"Root"`? I return the second sentence.
   - Did you pass me anything else? I bind it to the variable `name` and interpolate it directly into the string using `{name}`.
3. **And what is `main => ()`?**:
   Since `main` takes no arguments, we place `=>` right after its name. And it returns `()` (the empty or *Unit* type), because its only job is to print things to the screen with `echo`.

---

## 1.3. "Wait... do I have to align those spaces by hand like a medieval scribe?"

Not a chance! If you had to hit the spacebar counting columns by eye, you would quit Ridgun in ten minutes (and rightfully so).

You type your code quickly, with just a single space between words:

```ridgun
greet String => String
greet "" = "Hello, mysterious traveler!"
greet name = "Hello, {name}!"
```

And when you run **`stable format`** (or press `TAB` / save the file in Emacs with `ridgun-mode`), the canonical formatter places every parameter directly beneath its type and aligns every `=` with pinpoint precision. You write fast; the machine typesets the table.

---

## 1.4. From Quick Script to Battle-Ready Binary in One Command

When you run `ridgunc run hello.rg`, you are compiling and launching the program on the fly. But imagine you've finished your tool and want to deploy it to a production server or share it with a teammate who doesn't have Ridgun installed.

You run:

```bash
ridgunc build hello.rg -o hello
```

And now you have `./hello`: a **native Linux x86_64 ELF executable**, lean, stripped of dead code (*Tree-Shaking*), built with full link-time optimization (*LTO*), and completely independent of any external interpreter.

---

## 1.5. The Honest Cheat Sheet: Where Does Every Idea in Ridgun Come From?

Ridgun doesn't try to reinvent the flat tire; it unapologetically borrows the best ideas from four traditions:

| From Whom | What Ridgun Borrows | What It Leaves Behind (For Your Sanity) |
|---|---|---|
| **Haskell / ML** | Pure functions, case-by-case *pattern matching*, algebraic data types (`Option`, `Result`), and polymorphism (`A`..`Z`). | Abstract monad transformers, 40 `LANGUAGE` pragmas, and the garbage collector. |
| **J / APL** | Obsession with tabular code layout, native tensors, and sequence masks (`s["-+-"]`). | Hieroglyphic symbols that are impossible to type on a normal keyboard. |
| **Rust / C** | Tiny native ELF binaries, zero GC, deterministic memory control (`with region`), and POSIX system calls. | Constant battles with the *borrow checker*, `'a` *lifetimes*, and syntactic verbosity. |
| **Erlang / Go** | Isolated agents (`agent`, `send ... to`, `receive from`) and channel-based concurrency (`new bounded channel`). | `nil` pointers and accidental shared mutable state. |

---

## 1.6. Most Importantly: What Does Ridgun Do That Nobody Else Has?

Giving credit to the classics is good manners, but if Ridgun were just a "greatest hits album" of other languages, you wouldn't be reading this book.

There are **seven things** we designed and integrated into Ridgun that you won't find together—and many of them not even separately—in any other language today:

### 1. Parallel `||` blocks with `->` that are true parallel graphs, not mere syntactic sugar
In other functional languages, a local binding block merely orders expressions that are then evaluated on a single thread.
In Ridgun, **a `||` block with `->` arrows is a parallel-execution Directed Acyclic Graph (DAG)** without even needing extra keywords like `where`:
```ridgun
annual_report Int => Int
annual_report id  =  revenue - expenses
  || compute_sales id -> revenue
  || compute_costs id -> expenses
```
You draw the dataflow arrows (`->`). The compiler analyzes what depends on what, **statically verifies that you haven't created any infinite dependency cycles**, and launches independent branches in parallel without you writing a single `async`, `await`, `Future`, or `Mutex`.

### 2. Code as a two-dimensional table where the signature is the column header
In every other language, the type signature lives on its own line and the function body sits below it like an ordinary paragraph of text.
In Ridgun, **the type signature is literally the header of a table**, and every clause below aligns each pattern vertically under its type and each `=` under the `=>`:
```ridgun
divide Int Int => Option
divide _   0   =  None
divide a   b   =  Some (a / b)
```
No other language treats the signature and its equations as a single visual matrix verified by the compiler and automatically typeset by `stable format`.

### 3. Typed and aligned N-ary phrase operators (*Mixfix* `op ::`)
In most languages, you either settle for `+`, `-`, `*` or at best define a cryptic binary operator like `<|>` that nobody can read.
In Ridgun you can create **operators that read like natural phrases with as many typed slots as you want** (even using contextual words like `type` or `with`):
```ridgun
op :: Int clamped_between Int and_max Int => Int
      x   clamped_between min and_max max =
        | x < min   = min
        | x > max   = max
        | otherwise = x
```
And then in your code you write `speed clamped_between 0 and_max 120`. It reads like plain English, yet it is 100% statically typed and compiled to native machine code.

### 4. Visual sequence masks (`s(+ _)` and `s["-+-"]`)
Have you ever had to write an index salad like `filter(\(i, x) -> i % 2 == 0)` just to keep even elements or extract a rhythmic pattern from a list?
In Ridgun you pass a **visual mask** directly:
- `data["-+-"]`: drops the first (`-`), keeps the second (`+`), drops the third (`-`).
- `data["+-~"]`: the `~` symbol repeats the `+-` pattern in a loop until the end of the list (all even indices in one stroke).
Zero index arithmetic, zero *off-by-one* bugs.

### 5. "Zero-noise" polymorphism (`A`..`Z`) governed by your domain
In Rust, TypeScript, or Java, making a function generic means littering the line with angle brackets: `fn swap<A, B>(pair: (A, B)) -> (B, A)`.
In Ridgun you simply use a standalone uppercase letter:
```ridgun
swap (A, B) => (B, A)
swap (x, y) =  (y, x)
```
*"What if I want a real type in my program called `type A`?"* — No problem: in Ridgun **your `type` declarations win**. If `type A` does not exist, `A` is a generic type variable; the instant you define `type A = ...`, it becomes your concrete type across the module.

### 6. Zero foreign configuration files: `build.rg` is pure Ridgun
Forget learning TOML for Cargo, JSON for npm, XML for Maven, or the arcane tab-sensitive syntax of a `Makefile`. In Ridgun, the recipe that builds your project (`build.rg`) **is just another `.rg` file**, using the exact same pure functions and *pattern matching* as the rest of your code.

### 7. The "Holy Trinity" that seemed impossible: Haskell-level expressiveness + RMM memory without GC or Lifetimes + ~350 KB binaries
Until today you had to choose:
- If you wanted pure functional expressiveness (Haskell, OCaml, Elixir), you paid for it with a garbage collector and a heavy runtime.
- If you wanted tiny GC-free systems binaries (C, Rust, Zig), you paid for it by juggling raw pointers or wrestling with the *borrow checker* while writing imperative code full of `let mut`.

Ridgun breaks that dilemma by combining **Ridgun Memory Management (`RMM`: static `RMM1` and cascading assignment-counted `RMM2`)**, **lexical regions (`with region`)** that free entire arenas in $O(1)$, **tail recursion compiled into native `loop`s**, and **call-graph dead-code elimination (*Tree-Shaking*)** starting from `main`. The result: you write high-level declarative code and get a self-contained **~350 KB** ELF executable ready to go toe-to-toe with tools written in C.

Now that all cards are on the table, let's head to **Chapter 02** and put **`ridgunc`** and **`stable`** to work.
