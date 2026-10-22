# Chapter 00: Why Do I Need Ridgun? Oh Really? I Had No Idea... Tell Me More!

Let's be honest: when someone tells you *"we've created a new programming language"*, your first natural—and very healthy—reaction is to raise an eyebrow and think:

> *"Another one? Look, I already have Python for moving fast, Rust or C when I need raw speed, and Bash for gluing things together in the terminal. Why on earth would I need to learn Ridgun?"*

That is an excellent question. And the short answer is: **because you've gotten used to suffering three daily pains while assuming they were inevitable**.

Let's put a name to them.

---

## Pain #1: "The Two-World Syndrome" (Prototype in one, rewrite in another)

You have almost certainly lived through this movie:

1. You start building a tool or a calculation engine in **Python**, **JavaScript**, or **Ruby** because you want to think about the problem, not about pointers or the compiler.
2. The code comes out short and clean... until you feed it a 500 MB file or try to use all 16 cores on your machine, and it crawls. And if you want to deploy your program to a clean server, you have to ship half a gigabyte of virtual environments, an interpreter, and dynamic libraries.
3. Resigned, you decide to rewrite it in **C**, **C++**, or **Rust**. Now it flies and takes up just a few hundred kilobytes, but your 40-line script has ballooned into 300 lines packed with `unwrap()`, `&mut`, `'a`, `Arc<Mutex<...>>`, curly braces `{}`, and semicolons `;`.

**What changes with Ridgun?**
In Ridgun you write code that is **shorter and cleaner than Python**, yet when you run `ridgunc build`, you get **a single ~350 KB native ELF binary** with no interpreter, no external virtual machine, and no garbage collector. There is no *"we'll rewrite it in the fast language later"* phase: the clean code where you think through the problem **is already** the native production binary.

---

## Pain #2: "Reading someone else's code (or your own from 6 months ago) feels like playing detective"

Look at how we write conditional logic in almost every mainstream language:

```text
if (status == ACTIVE && (role == ADMIN || (role == EDITOR && hasPermission))) {
    if (quota > 0) {
        return process(user);
    } else {
        return deny("Out of quota");
    }
} else {
    return deny("Unauthorized");
}
```

Our eyes did not evolve to match nested curly braces or untangle deeply indented `if / else` trees. When engineers, mathematicians, or physicists want to understand complex rules without making mistakes, they don't write paragraphs of `if / else`: **they draw a table**.

In Ridgun, **the code is that table**:

```ridgun
authorize String   String   Bool  Int   => String
authorize "active" "admin"  _     quota =
  | quota > 0 = "Processing request"
  | otherwise = "Denied: out of quota"
authorize "active" "editor" True  quota =
  | quota > 0 = "Processing request"
  | otherwise = "Denied: out of quota"
authorize _        _        _     _     =  "Denied: unauthorized"
```

Look at the columns:
- Column 1: the status (`"active"` or `_`).
- Column 2: the role (`"admin"`, `"editor"`, or `_`).
- Column 3: whether permission is granted (`True` or `_`).
- Column 4: the `quota`.

You don't have to mentally execute the program line by line to figure out what happens when an `"editor"` comes in with permission `False`: your eyes scan straight down the table and spot the answer in half a second.

---

## Pain #3: "My computer has 16 cores, but my program only uses 1 (because touching threads terrifies me)"

Today even a modest phone has 8 cores, and any server or developer laptop has between 12 and 32. Yet 95% of everyday programs still run on a single sequential thread.

Why? Because in imperative languages, parallelizing means opening Pandora's box:
- What if two threads mutate the same dictionary at the same time? (*Data race*).
- What if I lock `Mutex` A and then B in one thread, and B and then A in another? (*Deadlock*).
- What if I infect my entire codebase with `async` and `await` from top to bottom?

In Ridgun, **every function is pure and all data is immutable by default**. That has a magical consequence: **two expressions that do not depend on each other can never interfere with each other**.

Because of that, you don't have to manage threads to use your CPU in Ridgun. You simply declare **what depends on what** using parallel bars `||` and arrows `->`:

```ridgun
monthly_report Data => Report
monthly_report d    =  combine net_metrics disk_metrics cpu_metrics
  || analyze_net d  -> net_metrics
  || analyze_disk d -> disk_metrics
  || analyze_cpu d  -> cpu_metrics
```

You only wrote three clean lines stating where each piece of data comes from. The compiler sees that the three branches are independent and knows it can launch them in parallel without even the slightest possibility of a *data race* or a *deadlock*.

And what if you need persistent concurrent agents with an isolated mailbox and state (for example, to maintain thousands of client sessions, background workers, or network connections)? In Ridgun you don't need `Actor` classes or `Mutex` locks: **any ordinary function becomes an autonomous agent in a single line with `agent`**:

```ridgun
counter = agent (add visit) 0
send 1 to counter
send 5 to counter
total = receive from counter
stop counter
```

Even better, the compiler performs **smart compile-time strategy selection**: it statically analyzes the depth and computational weight of each function in `||`, `||map`, `||filter`, and `agent`, executing lightweight functions as zero-overhead *green-thread* steps (without paying OS thread warmup costs) and automatically dispatching heavy or deeply recursive computations across real OS kernel threads (`SYS_clone`) on multiple CPU cores.

---

## Pain #4: "The garbage collector decides to stop the world at the worst possible moment"

Classic functional languages (Haskell, OCaml, Erlang, Clojure) are wonderful for reasoning about code, but almost all of them rely on a runtime **Garbage Collector**. That rules them out when you need:
- Microsecond-predictable latency.
- Exact control over how much RAM an operation is allowed to consume before cleanly aborting it.
- To write operating system utilities (`ls`, `find`, `sh`, `doas`, `make`) or touch hardware registers (`MMIO`).

Ridgun gives you **all the elegance of pure functional programming, backed by Ridgun Memory Management (`RMM`: static `RMM1` and cascading assignment-counted `RMM2`) plus lexical quota-bounded regions (`with region`)**:

```ridgun
parse_packet String => Result
parse_packet raw    =
  with region 16_KB do
    decode_frame raw
```

Every temporary structure is freed deterministically by the compiler (`RMM1` / `RMM2`) the instant it is no longer used. And if an attacker sends you a malicious packet designed to blow up your memory, the moment it crosses byte 16,384 the region halts immediately, frees its entire arena in $O(1)$ time, and returns `Err OutOfMemory`. No process crashes, no GC pauses, and no memory leaks.

---

## In Summary: When Does Ridgun Shine?

Ridgun is built for you if you have ever wanted to:

1. **Write systems tools, compilers, parsers, or CLI utilities** that start up in microseconds, weigh a few hundred KB, and cannot crash from null pointers or hidden side effects.
2. **Build concurrent systems and servers using the Native Agent Model (`agent`, `send ... to`, `receive from`, `stop`)**, where any pure function becomes a stateless or stateful isolated agent and the compiler smartly selects between ultra-lightweight *green-thread* steps and multicore native kernel threads.
3. **Program algorithms, data pipelines, or tensor algebra** where the compiler verifies even your matrix dimensions (`Tensor[M, K] * Tensor[K, N] => Tensor[M, N]`) before running a single instruction.
4. **Enjoy reading your own code**: where every `.rg` file looks like a page from a well-typeset book thanks to the automatic tabular formatter (`stable format`).

Curious? Turn to **Chapter 01** and let's write our first program in under two minutes.
