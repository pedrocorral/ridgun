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

### 4. Idiomatic Left-to-Right Pipelines (`->`) — The 100% Ridgun Way!
When you chain several transformations (`map`, `filter`, `fold`, or your own functions and `op ::` operators), nesting parentheses from right to left (`compact l (filter g (map f xs))`) forces you to read inside-out.

In Ridgun, the **recommended idiomatic style (`2b`)** reads from left to right using the pipeline operator **`->`**, where **whatever comes from the left always enters as the first argument** of the next function or `op ::`:

```ridgun
-- Recommended idiomatic Ridgun style (2b):
xs map (x => x * 2) -> filter (x => x > 10) -> fold (acc x => acc + x) 0 -> total

-- And if a function returns a tuple, filter it with a mask and unpack it into the next stage:
parse packet "v0.9.9" -> (+ _ _ +) -> combine code -> summary
```

Plus, any expression with side effects (writing a file, invoking a system call) can stand on its own line without `echo` or dummy `_ =` variables—or end with `-> ()` when you want to discard its return value explicitly.

### 5. Lexical Closures and Anonymous Functions (`(x => expr)`, `(acc x => expr)`)
When you want to pass a short function on the fly or capture local variables from the enclosing scope (such as an offset, a prefix, or an active session) without declaring a separate top-level helper, use a parenthesized **lexical closure** with **`=>`**:

```ridgun
fn :: process with session => [Int]
      process with session =
        offset   = 10
        bonus    = 3
        added    = map (x => x + offset) [1, 2, 3]
        filtered = filter (x => x >= bonus) [1, 2, 3, 4]
        total    = fold (acc x => acc + x + bonus) 0 [1, 2, 3]
        pairs    = map ((a b) => a + b + offset) [(1, 2), (3, 4)]
        added :: filtered :: [total] :: pairs
```

Five rules keep lambdas clean and unambiguous:
- **Mandatory parentheses**: every lambda is enclosed in parentheses `(... => ...)`.
- **Zero-parameter lambdas (`(=> expr)`)**: just as `fn :: main => ()` forbids `()` before `=>`, a zero-parameter lambda is written `(=> expr)` (and its type is `(=> Type)`), never `(() => expr)`.
- **Multiple parameters vs. tuple (`(a b => ...)` vs. `((a b) => ...)`)**: `(acc x => ...)` takes two separate parameters, whereas `((a b) => ...)` takes a single tuple and destructures it.
- **Multi-line bodies**: placing a newline after `=>` lets you write an indented multi-step block before the closing `)`:
  ```ridgun
  doubled = map (x =>
    step = x * 2
    step + offset
  ) [1, 2, 3]
  ```
- **Uppercase vs. lowercase**: `(Conn => Conn)` is a function type (uppercase initial) and `(conn => conn)` is a lambda value (lowercase initial).

Captured bindings (`offset`, `bonus`) are automatically lifted with deterministic `RMM1`/`RMM2` reference management—zero memory leaks and zero garbage-collector pauses.

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

## 7.4. When You Want Manual Steering: the Native Agent Model (`agent`, `send ... to`, `receive from`) and CSP Channels

Automatic parallelism via `||` blocks and `||map` covers 90% of real-world cases. But when you are building a persistent server, isolated user sessions, a job queue, or a producer-consumer pipeline, you want **concurrent agents with isolated memory and statically typed message passing**.

In Ridgun there is no need for a special `actor ::` declaration keyword: **any normal function (`fn ::` or `op ::`) becomes a concurrent agent in a single line with `agent`**:

### 1. Stateless and stateful agents (`agent`, `send ... to`, `receive from`, `stop`)
- `ag = agent (my function)`: wraps a function `M => R` into a stateless agent of type `Agent M R`.
- `ag = agent (stateful function) initial_state`: wraps a function `S M => S` (or `S M => S R`) into an agent with isolated state that remembers its state across messages without a single `Mutex`.
- `send msg to ag` (or with multiple arguments: `send a b to ag`): sends a typed message to the agent's inbox.
- `res = receive from ag` (or non-blocking `try receive from ag`): pulls the next reply from the agent's outbox.
- `stop ag`: terminates the agent and deterministically frees its state via `RMM1`/`RMM2`.

```ridgun
fn :: add visit Int Int => Int
      add visit acc n   =  acc + n

fn :: process batch Int Int => Int
      process batch id  t   =  (id * 100) + t

fn :: main => ()
      main =
        counter = agent (add visit) 10
        send 5 to counter
        send 7 to counter
        v1 = receive from counter
        v2 = receive from counter
        stop counter

        worker = agent (process batch)
        send 3 25 to worker
        batch = receive from worker
        stop worker
        echo "Visits:" v1 "->" v2 "| Batch:" batch
```

### 2. Smart compile-time strategy selection (*Green Threads* vs. Real OS Kernel Threads)
A common question is: *"Do `||`, `||map`, and `agent` always spawn OS threads, or do they run as lightweight green tasks?"*

In Ridgun, **the compiler makes that decision for you by statically analyzing each function**:
- **Lightweight functions (`TierTrivial` / `StratInlineSequential`)**: If the function passed to `||`, `||map`, `||filter`, or `agent` has shallow depth (arithmetic, string formatting, fast HTTP session state transitions), warming up OS threads would cost more than the computation itself. The compiler executes it as an ultra-lightweight *green-thread* step with zero `SYS_clone` overhead.
- **Heavy or deeply recursive computations (`TierDynamicRecursive` / `TierHeavyCPU`)**: If the function has deep recursion (like `fib` or `fact`) or tensor algebra (`einsum`, `hadamard`, `@`), the compiler automatically emits multicore dispatch across **real OS kernel threads (`SYS_clone`)**, processing `||` branches or queued `agent` messages in true hardware parallelism across your CPU cores.

### 3. Passing messages through bounded channels (`new bounded channel`)
Just like in Go or Erlang, in addition to agents you can also create explicit thread-safe pipes to connect pipeline stages:

- `new bounded channel capacity`: creates a channel with room for `capacity` messages.
- `send through value channel` (or `chan send value channel`): puts a message into the pipe.
- `receive from channel` (or `chan recv channel`): pulls the next message from the pipe.
- `try receive from channel`: checks whether a message is waiting without blocking; returns `Some value` or `None`.
- `receive from timeout channel ticks`: waits up to a time limit and returns `Ok value` or `Err Timeout`.

```ridgun
fn :: main => ()
      main =
        pipe = new bounded channel 4
        _ = send through "Task A completed" pipe
        _ = send through "Task B completed" pipe
        first = receive from pipe
        second = receive from pipe
        echo first "|" second
```

And now, fasten your seatbelt for **Chapter 08**, the grand finale: **tensors with compile-time verified dimensions, scoped variables (`context`/`shared`), deterministic memory regions, direct MMIO hardware access, and UNIX/POSIX systems programming**.
