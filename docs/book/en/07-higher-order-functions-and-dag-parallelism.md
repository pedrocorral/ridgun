# Chapter 07: Higher-Order Functions and Sweat-Free Parallelism (No `Mutex`, No `Deadlocks`)

In almost every programming language there is a dramatic moment in the life of a project—the day someone says in a meeting:

> *"This is running slow. We need to parallelize it with threads."*

Silence falls over the room. Everyone knows what comes next: weeks chasing phantom *race conditions* that only happen on Tuesdays during a full moon, *deadlocks*, and irreproducible bugs.

In Ridgun, when someone says *"we need to parallelize this"*, you simply prefix your list operations with `||` (**`||map`** and **`||filter`**) or drop your calculations into a parallel `||` block with `->` arrows and go grab a coffee.

Why? Because **when your functions are pure and your data is immutable by default, two CPU cores working side by side can never step on each other's toes**.

Let's walk through it step by step.

---

## 7.1. Functions That Take Functions: `map`, `||map`, `filter`, `||filter`, and `fold`

In Ridgun a function is just another value. You can pass it as an argument the exact same way you pass the number `7`.

The language comes out of the box with collection combinators so you can transform lists without writing a single manual recursion, both in sequential mode (`map`, `filter`, `fold`) and in multicore parallel mode using the `||` prefix (**`||map`**, **`||filter`**):

### 1. `map` (sequential) and `||map` (multicore parallel)
Suppose you have a function `expensive Int => Int` and a list of numbers:

```ridgun
expensive Int => Int
expensive x   =  (x * x) + (x * 3)

main => ()
main =
  data = [1, 2, 3, 4, 5, 6, 7, 8]
  -- Strict left-to-right sequential:
  r1 = map expensive data
  -- Multicore parallel with the `||` prefix:
  r2 = ||map expensive data
  echo r1
  echo r2
```

- With **`map`**, Ridgun applies the function element by element from left to right on the current thread (ideal for small lists or functions with ordered I/O side effects).
- With **`||map`**, the Ridgun runtime distributes the elements of `data` across your processor's worker threads and reassembles the final list **in the exact same order**, guaranteeing that `||map f xs == map f xs`.

### 2. `filter` (sequential) and `||filter` (parallel): Keeping only elements that match a condition
You pass a function that returns `Bool` (a *predicate*) and a list:

```ridgun
is_positive Int => Bool
is_positive n   =  n > 0

main => ()
main =
  clean = filter is_positive [-5, 10, 0, -2, 42]
  clean_par = ||filter is_positive [-5, 10, 0, -2, 42]
  echo clean      -- Prints [10, 42]
  echo clean_par  -- Prints [10, 42]
```

### 3. `fold`: Reducing an entire list down to a single result
You pass a two-argument combining function `(Accumulator Element => Accumulator)`, the initial value, and the list:

```ridgun
multiply_acc Int Int => Int
multiply_acc acc x   =  acc * x

main => ()
main =
  echo (fold multiply_acc 1 [2, 3, 4, 5])  -- 1 * 2 * 3 * 4 * 5 = 120
```

### How Do I Write My Own Function That Accepts Another Function?
Very easily: in the type signature, wrap the guest function's signature in parentheses `(Input => Output)`:

```ridgun
run_twice (A => A) A => A
run_twice f        x =  f (f x)
```

---

## 7.2. The Crown Jewel: `||` Blocks with `->` as Parallel Graphs (DAGs)

This is where Ridgun changes how you think.

In an ordinary imperative language, when you write three lines in a row:
1. First line 1 runs.
2. Then line 2 runs (even if it has nothing to do with line 1).
3. Then line 3 runs.

That forces your computer to work wearing blinders. In Ridgun, when you use parallel bars **`||`** with arrows **`->`** (without needing any extra keyword like `where`), you are not issuing sequential commands: you are drawing a **Directed Acyclic Graph (DAG)** that declares which computation feeds which variable:

```ridgun
fib Int => Int
fib 0   =  0
fib 1   =  1
fib n   =  (fib (n - 1)) + (fib (n - 2))

fact Int => Int
fact 0   =  1
fact n   =  n * (fact (n - 1))

super_calc => Int
super_calc =  left_branch + right_branch
  || fib 10 -> left_branch
  || fact 6 -> right_branch
```

Read it out loud:
- *"I want to compute `left_branch + right_branch`, while in parallel (`||`) `fib 10` flows into `left_branch` (`->`) and `fact 6` flows into `right_branch` (`->`)."*

### What `ridgunc` Does Behind the Scenes with Your `||` Lines:
1. It inspects the `->` arrows and builds the dependency graph (DAG).
2. **It catches cycles statically**: if by mistake you write `|| a + 1 -> b` and `|| b + 1 -> a`, the compiler stops you on the spot with *"Hold on! There is a circular dependency"* and refuses to compile an infinite hang.
3. It sees that `fib 10` and `fact 6` do not depend on each other, so they get the green light to run in parallel before being added in `left_branch + right_branch`.

You can even build a multi-stage pipeline inside the same `||` block—either attached to the bottom of an expression or right after `=`—and the compiler will figure out all by itself which stages can run simultaneously and which ones must wait:

```ridgun
quarterly_balance Int  => Int
quarterly_balance base =
  || base * 100                -> gross_sales
  || base * 40                 -> fixed_costs
  || gross_sales - fixed_costs -> gross_profit ||.
  gross_profit * 80 / 100
```

Notice the **`||.`** terminator at the end of the last `||` line: just as `|.` closes a nested guard tree, **`||.`** closes the parallel `||` block when normal sequential statements continue below it. Here `gross_sales` and `fixed_costs` start in parallel; once both finish, `gross_profit` is computed, and finally `gross_profit * 80 / 100` is returned. All without a single `async`, `Future`, `Promise`, or `Mutex`.

---

## 7.3. The Nameless `||` Shortcut: Parallel Pipelines That Return a Tuple

What if you just want to launch two or three calculations in parallel and collect them together into a tuple without even inventing variable names with `->`?

Use `||` directly:

```ridgun
parallel_pair Int => (Int, Int)
parallel_pair n   =
  || fib n
  || fact n
```

Direct, visual, and it returns the tuple `(fib n, fact n)`.

---

## 7.4. When You Want Manual Steering: `spawn`, `join`, and CSP Channels

Automatic parallelism via `||` blocks and `map` covers 90% of real-world cases. But sometimes you are building an actor system, a job queue, or a producer-consumer pipeline and want to control tasks and messages yourself.

For that, you have two clean tools:

### 1. Launching tasks with `spawn` and collecting the result with `join`
```ridgun
process_batch Int => Int
process_batch id  =  id * 100

main => ()
main =
  task1 = spawn process_batch 1
  task2 = spawn process_batch 2
  -- Meanwhile you could do other work right here...
  res1 = join task1
  res2 = join task2
  echo "Finished with:" res1 "and" res2
```

### 2. Passing messages through bounded channels (`new_bounded_channel`)
Just like in Go or Erlang, instead of sharing mutable memory across threads, you send immutable values through a thread-safe pipe:

- `new_bounded_channel capacity`: creates a channel with room for `capacity` messages.
- `chan_send value channel` (or `send_through value channel`): puts a message into the pipe.
- `chan_recv channel` (or `receive_from channel`): pulls the next message from the pipe.
- `chan_try_recv channel`: checks whether a message is waiting without blocking; returns `Some value` or `None`.
- `receive_from_timeout channel ticks`: waits up to a time limit and returns `Ok value` or `Err Timeout`.

```ridgun
main => ()
main =
  pipe = new_bounded_channel 4
  _ = chan_send "Task A completed" pipe
  _ = chan_send "Task B completed" pipe
  first = chan_recv pipe
  second = chan_recv pipe
  echo first "|" second
```

And now, fasten your seatbelt for **Chapter 08**, the grand finale: **tensors with compile-time verified dimensions, scoped variables (`context`/`shared`), deterministic memory regions, direct MMIO hardware access, and UNIX/POSIX systems programming**.
