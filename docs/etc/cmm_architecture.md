# Ridgun Memory Management (RMM): RMM1 (CMM) & RMM2 Architecture (`FR-COMP-002`)

## 1. Overview & Policy Hierarchy

Ridgun manages memory deterministically without a tracing Garbage Collector (GC) through **RMM (Ridgun Memory Management)**, organized into tiered policies according to static control-flow visibility and data nesting:

| Policy | Name | Scope of Application | Mechanism |
|---|---|---|---|
| **RMM1** | **CMM (Linear + Conditional)** | Statically known control flow over non-nested bindings | **Zero-RC**: Compile-time liveness (`rg_cmm_drop` / `rg_cmm_move`) + 1-cycle conditional pointer-identity guards (`ptr(a) != ptr(c)` via `rg_cmm_drop_unless`). |
| **RMM2** | **Assignment & Cascaded Structure Counting** | Anonymous functions / dynamic higher-order flow, nested containers (`xs = [a..z]`, `xs[3] = a`), and multi-thread sharing | **Assignment-only RC with child cascade**: Scalars uncounted; structures carry `rc` (`+1` on variable/slot assignment, `+0` on read/borrow, move without `-1` on `return`, `-1` on death with cascade `-1` to each child when parent reaches `0`). |
| **RMM3** | **Aggressive RMM** *(Reserved)* | Future aggressive static/region optimization pass | To be specified in a subsequent phase. |

---

## 2. Policy 1: `RMM1` — Compiled Memory Management (Linear + Conditional CMM)

When the execution flow and called functions are statically known at compile time:

1. **Linear CMM (Unconditional Static Lifetime)**:
   For variables whose lifetimes are strictly linear and do not alias other live variables, the compiler determines the exact statement where each variable is used for the last time:
   - Intermediate read-only uses borrow the value (`&RVal`) at **0 cost**.
   - The final use moves ownership (`rg_cmm_move(&mut lv_x)`) or emits an unconditional deallocation (`rg_cmm_drop(&mut lv_x)`) immediately after the statement.
2. **Conditional CMM (Pointer-Identity Guards `ptr(a) != ptr(c)`)**:
   When a known branching call (`c = choose_list cond a b`) returns one of several input candidates and at least one candidate remains live alongside `c`, the compiler tracks the **Ancestor May-Alias Graph (`RCmmAlias`)** at compile time and emits a pointer-identity guard at each variable's static last-use line (`if ptr(x) != ptr(c) { free(x) }`).

### Canonical `choose_list` Trace under `RMM1`

```ridgun
fn :: choose_list Bool [Int] [Int] => [Int]
      choose_list cond a     b     =
        | cond      = a
        | otherwise = b
```

In a caller where `b` is never used after `choose_list`, while `a` **continues to be used** after `choose_list` before `c` is finally consumed:

```ridgun
a = make_a ()               -- Allocates heap block M1
b = make_b ()               -- Allocates heap block M2
c = choose_list cond a b    -- c aliases {a, b}; b reaches its last use here
                            -- [RMM1 for b]: if ptr(b) != ptr(c) { free(b) }
print_list a                -- a is still live here and reaches its last use here
                            -- [RMM1 for a]: if ptr(a) != ptr(c) { free(a) }
consume_list c              -- c reaches its last use here; no aliases remain live
                            -- [RMM1 for c]: free(c) (unconditional)
```

- **Branch `cond == True` (`ptr(c) == ptr(a) == M1`, `ptr(b) == M2`)**:
  - Right after `c = choose_list True a b`: `ptr(b) != ptr(c)` is **True** $\rightarrow$ **`M2` is freed immediately**.
  - Right after `print_list a`: `ptr(a) != ptr(c)` is **False** $\rightarrow$ `M1` is spared.
  - Right after `consume_list c`: no live aliases remain $\rightarrow$ **`M1` is freed unconditionally**.
- **Branch `cond == False` (`ptr(c) == ptr(b) == M2`, `ptr(a) == M1`)**:
  - Right after `c = choose_list False a b`: `ptr(b) != ptr(c)` is **False** $\rightarrow$ `M2` is spared.
  - Right after `print_list a`: `ptr(a) != ptr(c)` is **True** $\rightarrow$ **`M1` is freed immediately**.
  - Right after `consume_list c`: no live aliases remain $\rightarrow$ **`M2` is freed unconditionally**.

---

## 3. Policy 2: `RMM2` — Assignment & Cascaded Structure Counting

When control flow cannot be fully resolved at compile time (**anonymous functions / closures / dynamic higher-order calls**), when values are stored inside **nested data structures** (`xs = [a, b, ..., z]`, `xs[3] = a`, ADTs, tuples), or across **multi-threaded boundaries**, `RMM2` unifies variable lifetime tracking and nested container ownership under a single set of rules:

1. **Primitive Scalars (`Int`, `Real`, `Bool`, `Unit`)**:
   - Never heap-allocated and never reference-counted. Passed and copied by value in CPU registers.
2. **Heap Structures (`List`, `Tuple`, `Adt`, `Tensor`, `Str`)**:
   - Every structure instance has its own counter (`rc`).
   - In a nested structure `xs = [a, b, ..., z]`, the parent container `xs` has its own counter `rc(xs)`, and each child structure `a, b, ..., z` has its own independent counter `rc(a), rc(b), ..., rc(z)`.
3. **Incoming Function Arguments (`pats` / `_arg_i`) Are NEVER Touched (`+0 / -0`)**:
   - A function never increments (`+0`) its incoming arguments on entry and never decrements (`-0`) them on exit. Their ownership belongs to the caller.
4. **Internal Local Variables (`x = ...` / `mut x = ...`) Receive `+1` on Assignment**:
   - Assigning a structure to a new local variable (`a = make_a ()`, `b = a`) or inserting/assigning it into a container slot (`xs = [a, ...]`, `xs[3] = a`) increments that structure's counter by **`+1`**.
   - On mutable variable reassignment (`mut x = a` followed later by `x = b` or `x = choose_list cond x b`), the new value receives **`+1` before** the old value of `x` receives **`-1`** (preventing premature self-destruction on self-referential updates).
5. **End of Function / Scope Exit (`-1` on Local Variables & Transit Survival)**:
   - **Non-returned internal local variables** receive **`-1` first** (in reverse declaration order):
     - If `rc(x) > 0`, the structure survives because another live variable or container still holds it.
     - If `rc(x) == 0`, the parent block `x` is freed and **iterates over its direct children `a, b, ..., z` one by one**, applying `-1` to each child structure and freeing any child whose `rc` reaches `0` (recursively cascading to its own children).
   - **Returned internal local variable (`return a`)**:
     - Receives `-1` at the end of the function (or transfers via `rg_cmm_move`), and **even if its `rc` is `0` in transit, it is NOT destroyed** because the caller's assignment (`c = make_pair ()`) immediately applies `+1` (`0 + 1 = 1`).
   - **Returned incoming argument (`return a` in `choose_list cond a b`)**:
     - Because `a` is an incoming argument, `choose_list` does not touch it (`+0 / -0`, so `rc(a)` remains `1`). When the caller executes `c = choose_list cond a b`, assigning to `c` applies `+1`, leaving `rc(M1) = 1 + 1 = 2` (shared between `a` and `c` in the caller).

### Complete Catalog of the 10 `RMM2` Lifecycle Scenarios

| # | Scenario | Trace & Counter Evolution | Final State |
|---|---|---|---|
| **1** | **Local created and NOT returned** | `a = [1, 2]` (`rc(M1) = 1`) $\rightarrow$ function ends without returning `a`: `a` gets `-1` $\rightarrow$ `rc(M1) = 0` $\rightarrow$ **freed**. | `0` live blocks |
| **2** | **Local created and RETURNED (`c = make_pair ()`)** | Inside `make_pair`: `a = [1, 2]` (`rc(M1) = 1`) $\rightarrow$ returned: `a` gets `-1` (`rc(M1) = 0`, spared in transit) $\rightarrow$ caller `c = make_pair ()` applies `+1` (`rc(M1) = 1`) $\rightarrow$ caller ends: `c` gets `-1` (`rc(M1) = 0`, **freed**). | `0` live blocks |
| **3** | **Local Alias (`b = a`)** | `a = [1, 2]` (`rc(M1) = 1`) $\rightarrow$ `b = a` (`+1` $\rightarrow$ `rc(M1) = 2`) $\rightarrow$ `b` dies (`-1` $\rightarrow$ `rc(M1) = 1`, survives for `a`) $\rightarrow$ `a` dies (`-1` $\rightarrow$ `rc(M1) = 0`, **freed**). | `0` live blocks |
| **4** | **Read-only Borrow (`print_list a`)** | `a = [1, 2]` (`rc(M1) = 1`) $\rightarrow$ `print_list a` (`p` is an incoming argument: `+0 / -0`, `rc(M1)` stays `1`) $\rightarrow$ `a` continues to be used $\rightarrow$ `a` dies (`-1` $\rightarrow$ `rc(M1) = 0`, **freed**). | `0` live blocks |
| **5** | **Branching on Arguments (`c = choose_list cond a b`)** | Caller creates `a` (`M1, rc=1`) and `b` (`M2, rc=1`). Inside `choose_list True a b`: `a` and `b` are incoming arguments (`+0 / -0`). Returns `M1` (`rc=1`). Caller `c = ...` applies `+1` to `M1` (`rc(M1)=2, rc(M2)=1`). `b` dies (`-1` $\rightarrow$ `rc(M2)=0`, **M2 freed**). `a` dies (`-1` $\rightarrow$ `rc(M1)=1`, **M1 survives for `c`**). `c` dies (`-1` $\rightarrow$ `rc(M1)=0`, **M1 freed**). | `0` live blocks |
| **6** | **Nested Container (`xs = [a, b]`)** | `a` (`M1, rc=1`), `b` (`M2, rc=1`). `xs = [a, b]` creates `MX` (`rc=1`) and increments children (`rc(M1)=2, rc(M2)=2`). `a` and `b` die (`-1` $\rightarrow$ `rc(M1)=1, rc(M2)=1`, kept alive by `MX`). `xs` dies (`-1` $\rightarrow$ `rc(MX)=0`, **MX freed**, cascades `-1` to `M1` and `M2` $\rightarrow$ `rc(M1)=0, rc(M2)=0`, **M1 & M2 freed**). | `0` live blocks |
| **7** | **Container Created Inside Function & Returned** | Inside `make_nested_list`: `a` (`M1, rc=1`), `b` (`M2, rc=1`), `xs = [a, b]` (`rc(MX)=1, rc(M1)=2, rc(M2)=2`). At function exit: non-returned locals `a, b` get `-1` (`rc(M1)=1, rc(M2)=1`); returned `xs` gets `-1` (`rc(MX)=0` in transit, spared); caller `c = make_nested_list ()` applies `+1` (`rc(MX)=1`). When `c` dies: `MX` reaches `0` and cascades `-1` to `M1, M2` (**all freed**). | `0` live blocks |
| **8** | **Extracting Child Before Container Dies (`res = xs[0]`)** | `xs` (`MX, rc=1`) holds `M1` (`rc=1`) and `M2` (`rc=1`). `res = xs[0]` applies `+1` to `M1` (`rc(M1)=2`). Non-returned `xs` gets `-1` **before** returned `res`: `MX` reaches `0` and cascades `-1` to `M1` (`2-1=1`, **survives!**) and `M2` (`1-1=0`, **M2 freed**). Returned `res` transfers `M1` to caller (`rc(M1)=1`). | `0` live blocks |
| **9** | **Slot Overwrite (`xs[0] = c`)** | `xs[0]` initially holds `M1` (`rc=1`). Executing `xs[0] = c` (`M3, rc=1`) applies `+1` to `M3` (`rc(M3)=2`) and `-1` to old slot value `M1` (`rc(M1)=0`, **M1 freed immediately**). | `0` live blocks |
| **10** | **Mutable Variable Reassignment (`mut x = a` then `x = b`)** | `mut x = a` (`rc(M1)=1`). Later `x = b` (`M2`): applies `+1` to new value `M2` **before** applying `-1` to old value `M1` (`rc(M1)=0`, **M1 freed immediately**, safe even when `x = x[0]` or `x = choose_list cond x b`). | `0` live blocks |

---

## 4. Compiler & Runtime Implementation (`compiler.rg`)

- **Compile-Time Liveness & Ancestor Alias Pass (`RCmmAlias`)**:
  - `cmm_expr_vars`, `cmm_stmts_vars`, and `cmm_where_vars` compute exact per-statement liveness for every local variable in `EBlock`, `EWhere`, and `FnCase` bodies.
  - `cmm_register_let` and `cmm_find_live_peers` compute the ancestor intersection set $A(x) \cap A(y) \neq \emptyset$ for live variables.
  - `emit_cmm_drops` emits `rg_cmm_drop(&mut lv_x)` when `LivePeers(x) == []` and `rg_cmm_drop_unless(&mut lv_x, &[&lv_c, ...])` when `LivePeers(x)` is non-empty.
- **Runtime Diagnostics & Inspection Built-ins**:
  - `cmm_live_blocks : Int` — current number of live tracked heap structure allocations.
  - `cmm_cond_freed : Int` — cumulative count of conditional guards where `ptr(v) != ptr(keep)` freed the unchosen branch immediately.
  - `cmm_cond_spared : Int` — cumulative count of conditional guards where `ptr(v) == ptr(keep)` spared the aliased block.
  - `cmm_same_ptr : A A => Bool` — returns `True` iff two values point to the exact same heap structure allocation.
