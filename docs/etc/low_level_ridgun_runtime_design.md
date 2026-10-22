# Low-Level Ridgun Runtime Architecture: Portable Runtime Kernel vs Symbolic Assembly (`TASK-0013` Study)

## 1. Executive Summary & Motivation

With the completion of `TASK-0013` (`v0.9.11`), the self-hosted Ridgun compiler (`ridgunc`) emits 100% of its native ELF64 runtime kernel (`x86_64` and `arm64`) through symbolic Ridgun functions (`src/main/ridgun/lib/x86_64.rg` and `src/main/ridgun/lib/arm64.rg`), eliminating all legacy pre-assembled hex strings.

However, maintaining two architecture-specific runtime emitters (~3,000 lines of `x86_64` and ~1,800 lines of `arm64` symbolic instruction builders) still requires implementing every runtime routine twice:
1. Once in `x86_64` (`push rbp`, `mov rdi, ...`, `syscall`), and
2. Once in `arm64` (`stp x29, x30, [sp, #-16]!`, `ldr x0, ...`, `svc #0`).

This architectural study evaluates the next evolutionary step: **writing 95%+ of the Ridgun runtime kernel directly in low-level, freestanding Ridgun**, leaving only a minimal (~50-line) architecture-specific bootstrap and syscall/atomics intrinsic lowering per CPU target.

---

## 2. Why Ordinary Ridgun Cannot Directly Implement the Runtime Kernel

If a runtime helper such as `rt clone slot` or `rt drop val` were compiled as a normal Ridgun function today, three circularity hazards (`infinite recursion`) would occur:

1. **Frame Prologue / Epilogue Circularity**:
   Normal Ridgun functions allocate a 16-byte `(tag, payload)` slot frame on the heap/arena via **Slot 0 (`rt init frame`)** and release it via **Slot 1 (`rt epilogue`)**. If `rt init frame` itself were compiled as a normal function, its prologue would call `rt init frame` infinitely.
2. **RMM1 / RMM2 Recursive Drop Circularity**:
   In normal Ridgun, variable reassignments and scope exits automatically emit calls to **Slot 33 (`rt drop val`)** or **Slot 34 (`rt drop unless`)**. If `rt drop val` triggered automatic RMM drops on its own local pointer variables, it would recurse infinitely.
3. **Boxed Value Representation vs Raw 64-Bit Pointers**:
   Normal Ridgun variables hold boxed 16-byte `(tag: i64, payload: i64)` slots. Inside the runtime kernel, routines manipulate raw 64-bit memory addresses, arena bump pointers, Linux `futex` words, and raw `i64` / `u8` memory offsets directly in CPU registers.

---

## 3. Minimal Low-Level Primitives Required (`@freestanding` / Unboxed Mode)

To write the runtime kernel in Ridgun without breaking language purity or introducing C-like syntax, only **two compiler mechanisms** and **six intrinsic operations** are required:

### 3.1 Unboxed Stack-Only Functions (`hardware` or Freestanding Mode)
Functions inside the runtime kernel module execute in **unboxed register/stack mode**:
- Local `Int` bindings map directly to 64-bit stack/register slots (`[rbp - 8*k]` on `x86_64`, `[x29 - 8*k]` on `arm64`) with **no** call to `rt init frame` or `rt epilogue`.
- Automatic RMM1/RMM2 drops are **disabled** inside freestanding runtime functions (since all values are raw 64-bit words/addresses).

### 3.2 Six Intrinsic Low-Level Operations (Lowered Directly to 1–3 Instructions by `x86_64` / `arm64`)

Using Ridgun's natural space-separated syntax and space-separated tuple signatures (`FR-COMP-005`, `FR-COMP-008`), the entire low-level memory and OS interface fits in six intrinsics:

| Intrinsic Signature | Semantics | `x86_64` Lowering (1–2 insts) | `arm64` Lowering (1–2 insts) |
|---|---|---|---|
| `fn :: ptr load i64 (addr) :: Int -> Int` | Read 64-bit word at `addr` | `mov rax, [rdi]` | `ldr x0, [x0]` |
| `fn :: ptr store i64 (addr) (val) :: Int Int -> Int` | Write 64-bit word `val` at `addr` | `mov [rdi], rsi` | `str x1, [x0]` |
| `fn :: ptr load u8 (addr) :: Int -> Int` | Read zero-extended byte at `addr` | `movzx eax, byte [rdi]` | `ldrb w0, [x0]` |
| `fn :: ptr store u8 (addr) (val) :: Int Int -> Int` | Write low byte of `val` at `addr` | `mov [rdi], sil` | `strb w1, [x0]` |
| `fn :: atomic add i64 (addr) (delta) :: Int Int -> Int` | Atomic fetch-and-add (`LOCK XADD` / `LDADDAL`) | `lock xadd [rdi], rsi` | `ldaddal x1, x0, [x0]` |
| `fn :: sys call (nr) (a0) (a1) (a2) (a3) (a4) (a5) :: Int Int Int Int Int Int Int -> Int` | Raw Linux kernel syscall | `mov rax, ...; syscall` | `mov x8, ...; svc #0` |

---

## 4. Side-by-Side Comparison: Symbolic Assembly vs Low-Level Ridgun

### 4.1 Example 1: Arena Bump Allocator & Frame Initialization (`Slot 0: rt init frame`)

#### Current Symbolic `x86_64` (`src/main/ridgun/lib/x86_64.rg`)
```ridgun
fn :: x86 rt slot00 init frame (p) :: Bytes -> Bytes
x86 rt slot00 init frame (p) = do
  c = x86 push rbp (p)
  c = x86 mov rbp rsp (c)
  c = x86 push rbx (c)
  c = x86 push r12 (c)
  c = x86 mov r12 rdi (c)
  c = x86 lea rbx rip (c) 0
  ...
  c
```

#### Proposed Portable Low-Level Ridgun (`src/main/ridgun/lib/runtime kernel.rg`)
```ridgun
-- Arena state layout at global base:
--   offset 0: current bump pointer (Int)
--   offset 8: arena limit pointer (Int)

fn :: rt alloc bytes (arena base) (nbytes) :: Int Int -> Int
rt alloc bytes (arena base) (nbytes) = do
  aligned = ((nbytes + 15) / 16) * 16
  cur = ptr load i64 (arena base)
  lim = ptr load i64 (arena base + 8)
  next = cur + aligned
  ptr = allocate or grow (arena base) (cur) (next) (lim) (aligned)
  ptr

fn :: allocate or grow (arena base) (cur) (next) (lim) (aligned) :: Int Int Int Int Int -> Int
allocate or grow (arena base) (cur) (next) (lim) (aligned)
  | cur != 0 and next <= lim = do
    _ = ptr store i64 (arena base) (next)
    cur
  | otherwise = do
    -- Linux mmap(NULL, 256 MiB, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    chunk size = 268435456
    base = sys call (sys mmap nr) 0 (chunk size) 3 34 (0 - 1) 0
    _ = ptr store i64 (arena base) (base + aligned)
    _ = ptr store i64 (arena base + 8) (base + chunk size)
    base

fn :: rt init frame (arena base) (num slots) :: Int Int -> Int
rt init frame (arena base) (num slots) = do
  nbytes = num slots * 16
  base = rt alloc bytes (arena base) (nbytes)
  _ = zero frame slots (base) 0 (num slots)
  base

fn :: zero frame slots (base) (idx) (total) :: Int Int Int -> Int
zero frame slots (base) (idx) (total)
  | idx >= total = 0
  | otherwise = do
    slot addr = base + (idx * 16)
    _ = ptr store i64 (slot addr) 0
    _ = ptr store i64 (slot addr + 8) 0
    zero frame slots (base) (idx + 1) (total)
```

---

### 4.2 Example 2: RMM2 Reference Counting & Cascaded Drop (`Slots 32..34`)

In RMM2 (`FR-COMP-002`), heap structures (Lists, Maps, Tensors, ADTs) carry an 8-byte atomic reference count (`rc`) at offset `0` of their header, followed by `len` at offset `8` and elements starting at offset `16`.
- Assigning a structure increments `rc` (`+1`).
- Dropping a structure decrements `rc` (`-1`), and when `rc` reaches `0`, cascades `rt drop val` to every child element before returning the block to the free-list.

#### Proposed Portable Low-Level Ridgun (`Slots 32..34`)
```ridgun
-- Value tags:
--   0 = Nil, 1 = Int, 2 = Float, 3 = Bool, 4 = Char
--   5 = String, 6 = List/Seq, 7 = Map, 8 = ADT, 9 = Tensor

fn :: is heap counted tag (tag) :: Int -> Bool
is heap counted tag (tag) = tag >= 6 and tag <= 9

-- Slot 32: rt clone slot (RMM2 +1 reference count on assignment)
fn :: rt clone slot (dst slot) (src slot) :: Int Int -> Int
rt clone slot (dst slot) (src slot) = do
  tag = ptr load i64 (src slot)
  payload = ptr load i64 (src slot + 8)
  _ = bump rc if heap (tag) (payload)
  _ = ptr store i64 (dst slot) (tag)
  _ = ptr store i64 (dst slot + 8) (payload)
  0

fn :: bump rc if heap (tag) (payload) :: Int Int -> Int
bump rc if heap (tag) (payload)
  | is heap counted tag (tag) and payload != 0 = atomic add i64 (payload) 1
  | otherwise = 0

-- Slot 33: rt drop val (RMM1/RMM2 deterministic deallocation with child cascade)
fn :: rt drop val (slot addr) :: Int -> Int
rt drop val (slot addr) = do
  tag = ptr load i64 (slot addr)
  payload = ptr load i64 (slot addr + 8)
  _ = ptr store i64 (slot addr) 0
  _ = ptr store i64 (slot addr + 8) 0
  release payload if needed (tag) (payload)

fn :: release payload if needed (tag) (payload) :: Int Int -> Int
release payload if needed (tag) (payload)
  | not (is heap counted tag (tag)) or payload == 0 = 0
  | otherwise = do
    prev rc = atomic add i64 (payload) (0 - 1)
    cascade if last ref (tag) (payload) (prev rc)

fn :: cascade if last ref (tag) (payload) (prev rc) :: Int Int Int -> Int
cascade if last ref (tag) (payload) (prev rc)
  | prev rc > 1 = 0
  | tag == 6 or tag == 8 = do
    -- List/Seq (tag 6) or ADT (tag 8): [rc: i64, len: i64, elem_0 (16B), elem_1 (16B), ...]
    count = ptr load i64 (payload + 8)
    _ = drop child slots (payload + 16) 0 (count)
    free heap block (payload)
  | otherwise = free heap block (payload)

fn :: drop child slots (items base) (idx) (count) :: Int Int Int -> Int
drop child slots (items base) (idx) (count)
  | idx >= count = 0
  | otherwise = do
    _ = rt drop val (items base + (idx * 16))
    drop child slots (items base) (idx + 1) (count)

-- Slot 34: rt drop unless (Conditional RMM1 pointer-identity guard: ptr(a) != ptr(c))
fn :: rt drop unless (slot a) (slot c) :: Int Int -> Int
rt drop unless (slot a) (slot c) = do
  ptr a = ptr load i64 (slot a + 8)
  ptr c = ptr load i64 (slot c + 8)
  drop when distinct (slot a) (ptr a) (ptr c)

fn :: drop when distinct (slot a) (ptr a) (ptr c) :: Int Int Int -> Int
drop when distinct (slot a) (ptr a) (ptr c)
  | ptr a == ptr c = 0
  | otherwise = rt drop val (slot a)
```

---

### 4.3 Example 3: String Comparison & UTF-8 String Concatenation (`Slots 14 & 29`)

```ridgun
-- String layout in Ridgun native ABI:
--   offset 0: byte length (i64)
--   offset 8..8+len-1: UTF-8 bytes

-- Slot 14: rt str eq
fn :: rt str eq (s1) (s2) :: Int Int -> Int
rt str eq (s1) (s2)
  | s1 == s2 = 1
  | s1 == 0 or s2 == 0 = 0
  | otherwise = do
    len1 = ptr load i64 (s1)
    len2 = ptr load i64 (s2)
    compare string bytes (s1 + 8) (s2 + 8) (len1) (len2) 0

fn :: compare string bytes (p1) (p2) (len1) (len2) (idx) :: Int Int Int Int Int -> Int
compare string bytes (p1) (p2) (len1) (len2) (idx)
  | len1 != len2 = 0
  | idx >= len1 = 1
  | ptr load u8 (p1 + idx) != ptr load u8 (p2 + idx) = 0
  | otherwise = compare string bytes (p1) (p2) (len1) (len2) (idx + 1)

-- Slot 29: rt str concat
fn :: rt str concat (arena base) (s1) (s2) :: Int Int Int -> Int
rt str concat (arena base) (s1) (s2) = do
  len1 = ptr load i64 (s1)
  len2 = ptr load i64 (s2)
  total = len1 + len2
  dst = rt alloc bytes (arena base) (total + 9)
  _ = ptr store i64 (dst) (total)
  _ = copy bytes (dst + 8) (s1 + 8) 0 (len1)
  _ = copy bytes (dst + 8 + len1) (s2 + 8) 0 (len2)
  _ = ptr store u8 (dst + 8 + total) 0
  dst

fn :: copy bytes (dst) (src) (idx) (count) :: Int Int Int Int -> Int
copy bytes (dst) (src) (idx) (count)
  | idx >= count = 0
  | otherwise = do
    b = ptr load u8 (src + idx)
    _ = ptr store u8 (dst + idx) (b)
    copy bytes (dst) (src) (idx + 1) (count)
```

---

## 5. Architectural Trade-Off Analysis

| Dimension | Current Symbolic Assembly (`x86_64.rg` + `arm64.rg`, `v0.9.11`) | Portable Low-Level Ridgun Runtime (`runtime kernel.rg`) |
|---|---|---|
| **Zero Hex / 100% Auditable** | Yes (`0` hex blobs; every instruction is a named Ridgun function call) | Yes (`0` hex blobs; runtime logic is high-level guarded Ridgun functions) |
| **Lines of Target-Specific Code** | ~3,000 lines (`x86_64.rg`) + ~1,800 lines (`arm64.rg`) | ~150 lines per target (only `_start`, slot jump table, and the 6 intrinsics) |
| **Adding a 3rd Target (e.g., `riscv64`)** | Requires writing ~2,000 lines of `riscv64` runtime slot assembly | Requires only ~150 lines of `riscv64` codegen for the 6 intrinsics + `_start` |
| **Execution Overhead** | Hand-tuned register usage per slot (0 spill overhead) | Requires a simple register-allocation or stack-slot pass for freestanding `Int` locals |
| **Compiler Complexity** | Zero new compiler passes; uses existing `Bytes` buffers | Requires adding a `@freestanding` / unboxed compilation mode in `compiler.rg` |

## 6. Recommendation & Staged Roadmap

1. **Short-Term (`v0.9.11` — Completed)**:
   `src/main/ridgun/lib/x86_64.rg` and `src/main/ridgun/lib/arm64.rg` are now 100% symbolic, free of hex blobs, formatted with natural spaces, and verified at the 2-stage self-hosting fixed point (`cmp -s target/ridgunc_stage1 target/ridgunc_candidate`).
2. **Medium-Term (`v0.10.x` Candidate)**:
   Introduce an internal unboxed/freestanding compilation mode for `src/main/ridgun/lib/runtime.rg` with the 6 low-level intrinsics (`ptr load i64`, `ptr store i64`, `ptr load u8`, `ptr store u8`, `atomic add i64`, `sys call`), migrating complex data-structure runtime routines (`Slot 37` JSON/TOML/YAML parser, `Slot 40` Einsum, `Slot 55` built-in string/collection helpers, and `PAL` services) into a single architecture-independent Ridgun module shared by `x86_64`, `arm64`, and future targets.
