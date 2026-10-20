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
   When a known branching call (`c = elegir cond a b`) returns one of several input candidates and at least one candidate remains live alongside `c`, the compiler tracks the **Ancestor May-Alias Graph (`RCmmAlias`)** at compile time and emits a pointer-identity guard at each variable's static last-use line (`if ptr(x) != ptr(c) { free(x) }`).

### Canonical `elegir` Trace under `RMM1`

```ridgun
fn :: elegir Bool [Int] [Int] => [Int]
      elegir cond a     b
        | cond = a
        | otherwise = b
```

In a caller where `b` is never used after `elegir`, while `a` **continues to be used** after `elegir` before `c` is finally consumed:

```ridgun
a = crear_a ()          -- Allocates heap block M1
b = crear_b ()          -- Allocates heap block M2
c = elegir cond a b     -- c aliases {a, b}; b reaches its last use here
                        -- [RMM1 for b]: if ptr(b) != ptr(c) { free(b) }
imprimir a              -- a is still live here and reaches its last use here
                        -- [RMM1 for a]: if ptr(a) != ptr(c) { free(a) }
usar c                  -- c reaches its last use here; no aliases remain live
                        -- [RMM1 for c]: free(c) (unconditional)
```

- **Branch `cond == True` (`ptr(c) == ptr(a) == M1`, `ptr(b) == M2`)**:
  - Right after `c = elegir True a b`: `ptr(b) != ptr(c)` is **True** $\rightarrow$ **`M2` is freed immediately**.
  - Right after `imprimir a`: `ptr(a) != ptr(c)` is **False** $\rightarrow$ `M1` is spared.
  - Right after `usar c`: no live aliases remain $\rightarrow$ **`M1` is freed unconditionally**.
- **Branch `cond == False` (`ptr(c) == ptr(b) == M2`, `ptr(a) == M1`)**:
  - Right after `c = elegir False a b`: `ptr(b) != ptr(c)` is **False** $\rightarrow$ `M2` is spared.
  - Right after `imprimir a`: `ptr(a) != ptr(c)` is **True** $\rightarrow$ **`M1` is freed immediately**.
  - Right after `usar c`: no live aliases remain $\rightarrow$ **`M2` is freed unconditionally**.

---

## 3. Policy 2: `RMM2` — Assignment & Cascaded Structure Counting

When control flow cannot be fully resolved at compile time (**anonymous functions / closures / dynamic higher-order calls**), when values are stored inside **nested data structures** (`xs = [a, b, ..., z]`, `xs[3] = a`, ADTs, tuples), or across **multi-threaded boundaries**, `RMM2` unifies variable lifetime tracking and nested container ownership under one rule:

1. **Primitive Scalars (`Int`, `Real`, `Bool`, `Unit`)**:
   - Never heap-allocated and never reference-counted. Passed and copied by value in CPU registers.
2. **Heap Structures (`List`, `Tuple`, `Adt`, `Tensor`, `Str`)**:
   - Every structure instance has its own counter (`rc`), initialized to `1` upon creation.
   - In a nested structure `xs = [a, b, ..., z]`, the parent container `xs` has its own counter `rc(xs)`, and each child structure `a, b, ..., z` has its own independent counter `rc(a), rc(b), ..., rc(z)`.
3. **`+1` Only on Assignment (`b = a` or `xs[3] = a`)**:
   - Assigning a structure to a new variable (`b = a`) or inserting/assigning it into a container slot (`xs = [a, ...]`, `xs[3] = a`) increments `a`'s counter by `+1` (and if `xs[3]` previously held a structure `old`, `old` is decremented by `-1`).
   - Read-only uses and borrowed function arguments (`imprimir a`, `list_len a`, `a + 1`) perform **`+0 / -0`** counter operations.
4. **Move-on-Return (`return`)**:
   - When a function returns a variable (`return x`), ownership is transferred directly to the caller (`rg_cmm_move`): `x` is **not** decremented on exit.
5. **`-1` on Death & Parent-to-Child Cascade**:
   - When a local variable `x` is **not** returned and reaches its static CMM last-use point (or scope exit), it performs `-1` on `rc(x)`.
   - If `rc(x) > 0`, the structure survives (it remains referenced by another live variable or container).
   - If `rc(x) == 0`, the parent block `x` is deallocated and **iterates over its direct children `a, b, ..., z` one by one**:
     - Basic scalar children are ignored.
     - Each child structure has its counter decremented by `-1`; any child whose counter reaches `0` is immediately freed (recursively cascading to its own children), while any child with `rc > 0` (e.g., extracted into an outer variable) survives intact.
   - This exact cascade invariant holds identically for both single-threaded and multi-threaded execution.

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
