# Shared runtime extension (`FR-COMP-022`, `FR-COMP-023`)

The shared runtime is machine code at fixed addresses (`x86_64.ridgun`). Both backends use it: the pure x86-64 encoder places it at `0x401000`, and the LLVM backend links the same bytes with a linker script. The extension adds byte tensors, CRC-32, the clocks, byte I/O and `sys call` with buffers **once**, for both backends.

## Where it lives

- `x86 rt ext` in `x86_64.ridgun`: the machine code, appended after the runtime at `x86 rt ext addr` = `0x417290` (4289168). `build x8664 rt kernel` pads the runtime up to that address.
- `win rt ext` in `pe64.ridgun`: the Windows build of the same source (`-DRG_WIN`), at the same address in Windows images. See *Windows build* below.
- Entry point: `rg_rtx(id, slots, count)`, the first byte of the extension.
- Callers: `NCallBuiltin id` with `id >= 100`. The x86-64 encoder emits `mov rdi, id; lea rsi, [slots]; mov rdx, count; call 0x417290`. The LLVM backend calls `@__rg_rt_ext(i64 id, ptr slots, i64 count)`; the linker script defines `__rg_rt_ext = 4289168`.
- The LLVM backend also has two inline fast paths, `@__rg_u8_get1` and `@__rg_u8_set1` (`llvm u8 helpers`): a one-dimensional read or write with an Int index in range (and a value in 0..255) touches the byte directly. Every other case calls the extension, which reports the error.

## Calling convention

The arguments are the values in `slots[0 .. count-1]`. The routine consumes them: it drops each owned value and sets every slot to 0. A *borrowed* slot (filled with `NPeekSlot` from a variable that keeps ownership) is set to 0 and not dropped. The result is returned in `rax` (the accumulator).

| id | Ridgun | Slots | Result |
|---|---|---|---|
| 100 | `sys time ns` | none | `CLOCK_MONOTONIC` in ns |
| 101 | `sys wall time ms` | none | `CLOCK_REALTIME` in ms |
| 102 | `sys time ms` | none | `CLOCK_MONOTONIC` in ms |
| 103 | `crc32 range` | data, from, to, crc | CRC-32 |
| 104 | `Tensor[U8 * d1 ...]`, `... with v` | fill, d1 ... dk | new `Tensor[U8]` |
| 105 | `t_(i ...)` | i1 ... ik, t (borrowed) | Int 0..255 |
| 106 | `t_(i ...) = v` | i1 ... ik, v, t (borrowed) | unit |
| 107 | shape patterns | k, t (borrowed) | rank (k = 0) or dimension k |
| 108 | `tensor from str` | s | `Tensor[U8]` |
| 109 | `tensor to str` | t | String |
| 110 | `tensor to list` on `Tensor[U8]` | t | `[Int]` |
| 111 | `echo` of a `Tensor[U8]` | t | numeric tensor, one word per element |
| 112 | `read bytes` | path | `Tensor[U8]` |
| 113 | `write bytes` | path, `Tensor[U8]` or `[Int]` | unit |
| 114 | `sys read into` | fd, t, from, count | bytes read or `-errno` |
| 115 | `sys write from` | fd, t, from, count | bytes written or `-errno` |
| 116 | `sys call` | nr, a1 ... a6 | the system call result |
| 117 | `sha256 raw` on `Tensor[U8]` | t | 32-byte String |
| 118 | `sha256 digest` | String or `Tensor[U8]` | `Tensor[U8 * 32]` |
| 119 | `tensor u8 from list` | list of Int 0..255 | `Tensor[U8]` |
| 120 | `sys execve` | path, argv (argv[0] included), envp | `-errno` (returns only on failure) |
| 121 | `+` on Strings in a tail position (OPT-020) | left String (owned), right String | the left String with the right one appended in place when its header has rc 1; else `0`, and both slots are left as they are (the caller then does the usual `+`) |
| 122 | `remove file` | path | `0` or `-errno` (`unlinkat`) |
| 123 | `remove dir` | path | `0` or `-errno` (`unlinkat`, `AT_REMOVEDIR`) |
| 124 | `rename path` | from, to | `0` or `-errno` (`renameat`, replaces `to`) |
| 125 | `net connect` | host, port, timeout ms | handle or `-errno` (FR-VM-003) |
| 126 | `net listen` | host, port, backlog | handle or `-errno`; port `0` takes a free port |
| 127 | `net accept` | handle, timeout ms | handle or `-errno` |
| 128 | `net send` | handle, String or `Tensor[U8]`, timeout ms | bytes sent or `-errno` |
| 129 | `net recv into` | handle, t, from, count, timeout ms | bytes received (`0` at the end) or `-errno` |
| 130 | `net recv` | handle, max, timeout ms | String (`""` at the end or on error) |
| 131 | `net shutdown` | handle, how | `0` or `-errno` |
| 132 | `net option` | handle, name, value | `0` or `-errno` (`-92` for an unknown name) |
| 133 | `net local port` | handle | port or `-errno` |
| 134 | `net peer ip` | handle | IPv4 text or `""` |
| 135 | `net resolve` | host name | IPv4 text or `""` (`/etc/hosts`, then DNS) |

## `Tensor[U8]` layout

A `Tensor[U8]` is a numeric tensor (heap tag 5) whose shape vector is `[W]` and whose data vector holds `W` 64-bit words:

- word 0: the rank `k`;
- words 1 .. k: the dimensions;
- then the `N` bytes (the product of the dimensions), packed and zero padded to a whole word.

Every runtime routine sees a valid one-dimensional numeric tensor of `W` words. None of them can read outside the buffer, and the runtime's equality (`==`) and copy (the `t_` copy, copies on send) are exact, because they compare or copy every word, the dimensions included. Drop and clone do not depend on the element type.

The type checker gives `U8` and `Byte` in element position their own type (kind `B`). A `Tensor[U8]` is compatible only with another `Tensor[U8]`, so lowering always knows which tensors are packed. Operations without a byte version (`@`, element-wise and bitwise operators, row and column slices and maps) are compile errors.

Known limit: `echo` of a list, tuple or record that holds a `Tensor[U8]` shows its storage words, because the runtime prints the nested value. `echo t` on the tensor itself shows its elements.

## Clocks

The first clock read looks up `__vdso_clock_gettime`: the address of the vDSO comes from the auxiliary vector (`AT_SYSINFO_EHDR`), read with `prctl(PR_GET_AUXV)` (Linux 6.4 and later) or, on older kernels, from `/proc/self/auxv`. The result is cached in the extension (the image is one writable segment). Without a vDSO the clocks use the `clock_gettime` system call.

## System parts (ADR-0008)

The source has one common part and one part per system, chosen at build time:

- **Linux** (default): `syscall` instructions, the vDSO for clocks, and the TCP sockets of FR-VM-003 with Linux system calls (`os_*` functions): `poll` waits, `MSG_DONTWAIT`, `/etc/hosts` and a UDP query to the first `nameserver` of `/etc/resolv.conf` for host names.
- **Windows** (`-DRG_WIN`): `sc6` calls the Windows layer's `rg_pal` (its address is at `0x4000A0`) instead of trapping, except `clone`, `fork`, `vfork`, `execve`, `exit` and `exit_group`, which need the thread context and keep one `syscall` site (`sc_trap`). The `os_*` socket functions are the layer's operations 1000..1009 (docs/etc/runtime_windows.md).

The common part decodes the arguments, resolves an IPv4 address written as text, turns a timeout of `-1` into the time left in a `with timeout` block (id 73 of the PAL entry `0x416680`, the entry of builtin ids 70..99), and builds the results.

## Building the bytes

The source is `rtx.c` and the linker script `rtx.ld` below. The code is freestanding (no libc) and position independent: calls into the runtime go to its fixed addresses, everything else is relative. Static data (the CRC table, the vDSO cache) lives in the same output section.

```bash
CF="-Os -ffreestanding -fno-builtin -fPIE -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -mgeneral-regs-only -fno-zero-initialized-in-bss -ffunction-sections -fdata-sections -fcf-protection=none"
clang $CF -c rtx.c -o rtx.o
ld.lld -T rtx.ld -o rtx.elf rtx.o
llvm-objcopy -O binary --only-section=.rtx rtx.elf rtx.bin
```

Then check that the object has only PC-relative relocations (`llvm-readobj -r rtx.o`: `R_X86_64_PC32` and `R_X86_64_PLT32`), and that `llvm-nm rtx.elf` lists no undefined symbol. Replace the list in `x86 rt ext` with the bytes of `rtx.bin` (`od -An -tu1 -v rtx.bin`), writing the trailing zero bytes as `zero bytes n`. Built with clang 19.1.7: 17 952 bytes, of which the last 4 096 are zero.

**Windows build.** The same commands with `-DRG_WIN` give the bytes of `win rt ext` in `pe64.ridgun` (15 456 bytes, of which the last 4 096 are zero). Its one `syscall` (in `sc_trap`) is listed in `win rt sites` after the sites of the base runtime.

**LLVM runtime cache.** The LLVM backend keeps the assembled runtime and its linker script in `/tmp/__rg_llvm_cache_<runtime fingerprint>_<script fingerprint>.rt` / `.lds` (`llvm rt cache base` in `llvm.ridgun`). Any change to the runtime gives a new name, so no build links a stale copy. Until 0.9.49 the name held only the version: a runtime changed without a version bump was linked stale, and a builtin missing from it crashed or did nothing in LLVM builds while x86-64 builds worked.

To test the logic natively, compile `rtx.c` with `-DHARNESS` and link it with a C file that defines the `rt_*` functions.

### `rtx.ld`

```
SECTIONS {
  . = 0;
  .rtx : { *(.text.rg_rtx) *(.text .text.*) *(.rodata .rodata.*) *(.data .data.*) *(.bss .bss.*) *(COMMON) }
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.llvm_addrsig) }
}
```

### `rtx.c`

```c
/* Ridgun shared runtime extension (FR-COMP-022, FR-COMP-023).
 *
 * One entry point, rg_rtx(id, slots, count), called by NCallBuiltin with
 * id >= 100 from both backends. The arguments are the values in
 * slots[0 .. count-1]. The routine consumes them: it drops each owned
 * value and sets every slot to 0. A "borrowed" slot holds a value that a
 * variable still owns (NPeekSlot): it is set to 0 and not dropped.
 *
 * Values: an Int is (n << 1) | 1. A heap value is a pointer with the low
 * 3 bits 0; the i32 at +0 is its tag: 1 String, 2 List, 5 numeric tensor.
 *   String: +8 header; header +8 data, +16 length.
 *   List:   +8 header; header +8 data (64-bit values), +16 length; +16 start.
 *   Tensor: +8 shape header, +16 data header (64-bit words).
 *
 * A Tensor[U8] is a numeric tensor (tag 5) with shape [W] and W data
 * words: word 0 = rank k, words 1..k = the dimensions, then the N bytes
 * packed and zero padded. Every runtime routine sees a valid tensor of W
 * words, so none of them reads outside the buffer, and the runtime's
 * equality and copy are exact.
 *
 * Freestanding: no libc, no globals except the vDSO cache, position
 * independent. Calls into the runtime go to fixed addresses.
 */
typedef unsigned long u64;
typedef long i64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;

#ifndef HARNESS
#define RT_ALLOC_BUF  4205566L
#define RT_BOX_RC_VEC 4208821L
#define RT_BOX_RVAL   4209847L
#define RT_ALLOC_STR  4212489L
#define RT_DROP_VAL   4214519L
#define RT_BUILTIN    4241227L
#define RT_PAL        4286080L
static inline void *rt_alloc_buf(i64 n) { return ((void *(*)(i64))RT_ALLOC_BUF)(n); }
static inline i64 rt_box_rc_vec(i64 *t) { return ((i64 (*)(i64 *))RT_BOX_RC_VEC)(t); }
static inline i64 rt_box_rval(i64 *t) { return ((i64 (*)(i64 *))RT_BOX_RVAL)(t); }
static inline i64 rt_alloc_str(const void *src, i64 n) { return ((i64 (*)(const void *, i64))RT_ALLOC_STR)(src, n); }
static inline void rt_drop_val(i64 v) { ((i64 (*)(i64))RT_DROP_VAL)(v); }
static inline i64 rt_builtin(i64 id, i64 *slots, i64 count) { return ((i64 (*)(i64, i64 *, i64))RT_BUILTIN)(id, slots, count); }
/* Builtin ids 70..99 (PAL: deadlines, poll...) have their own entry. */
static inline i64 rt_pal(i64 id, i64 *slots, i64 count) { return ((i64 (*)(i64, i64 *, i64))RT_PAL)(id, slots, count); }
#else
void *rt_alloc_buf(i64 n);
i64 rt_box_rc_vec(i64 *t);
i64 rt_box_rval(i64 *t);
i64 rt_alloc_str(const void *src, i64 n);
void rt_drop_val(i64 v);
i64 rt_builtin(i64 id, i64 *slots, i64 count);
i64 rt_pal(i64 id, i64 *slots, i64 count);
#endif

/* ── System calls ─────────────────────────────────────────────── */
#ifdef RG_WIN
/* Windows build (ADR-0008): a call goes straight to the Windows layer's
 * rg_pal, whose address the layer stores at 0x4000A0. Linux numbers below
 * 1000 are its system-call emulation, PAL operations start at 1000. The
 * calls that need the thread context (clone, fork, vfork, execve, exit)
 * still trap: their `syscall` becomes `ud2` in the image. */
__attribute__((noinline)) static i64 sc_trap(i64 n, i64 a, i64 b, i64 c, i64 d, i64 e, i64 f) {
  register i64 r10 __asm__("r10") = d;
  register i64 r8 __asm__("r8") = e;
  register i64 r9 __asm__("r9") = f;
  i64 r;
  __asm__ volatile("syscall"
                   : "=a"(r)
                   : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9)
                   : "rcx", "r11", "memory");
  return r;
}
typedef i64 (*pal_fn)(i64, i64, i64, i64, i64, i64, i64);
static inline i64 sc6(i64 n, i64 a, i64 b, i64 c, i64 d, i64 e, i64 f) {
  if ((n >= 56 && n <= 60) || n == 231) return sc_trap(n, a, b, c, d, e, f);
  return (*(pal_fn volatile *)0x4000A0)(n, a, b, c, d, e, f);
}
#else
static inline i64 sc6(i64 n, i64 a, i64 b, i64 c, i64 d, i64 e, i64 f) {
  register i64 r10 __asm__("r10") = d;
  register i64 r8 __asm__("r8") = e;
  register i64 r9 __asm__("r9") = f;
  i64 r;
  __asm__ volatile("syscall"
                   : "=a"(r)
                   : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10), "r"(r8), "r"(r9)
                   : "rcx", "r11", "memory");
  return r;
}
#endif
#define sc3(n, a, b, c) sc6(n, a, b, c, 0, 0, 0)

static void mem_copy(u8 *d, const u8 *s, i64 n) {
  for (i64 i = 0; i < n; i++) d[i] = s[i];
}
static void mem_zero(u8 *d, i64 n) {
  for (i64 i = 0; i < n; i++) d[i] = 0;
}

/* ── Values ───────────────────────────────────────────────────── */
static inline int is_int(i64 v) { return (v & 1) != 0; }
static inline i64 untag(i64 v) { return v >> 1; }
static inline i64 tag_int(i64 n) { return (n << 1) | 1; }
static inline int is_ptr(i64 v) { return v != 0 && (v & 7) == 0; }
static inline u32 heap_tag(i64 v) { return *(const u32 *)v; }
static inline i64 *field(i64 v, int k) { return (i64 *)(v + 8 * k); }

/* An Int argument: a tagged Int, or a boxed 64-bit payload (header 0). */
static i64 int_arg(i64 v) {
  if (is_int(v)) return untag(v);
  if (is_ptr(v) && heap_tag(v) == 0) return *field(v, 1);
  return 0;
}

static void drop_slot(i64 *s) {
  i64 v = *s;
  *s = 0;
  if (is_ptr(v)) rt_drop_val(v);
}
static void drop_slots(i64 *s, i64 n) {
  for (i64 i = 0; i < n; i++) drop_slot(&s[i]);
}

static const char MSG_U8[] = "runtime error: U8 element out of 0..255\n";
static const char MSG_OOB[] = "runtime error: tensor index out of range\n";
static const char MSG_CRC[] = "runtime error: crc32 range: range out of bounds\n";
static const char MSG_BYTES[] = "runtime error: write bytes: element out of 0..255\n";
static const char MSG_IO[] = "runtime error: byte range out of bounds\n";

static __attribute__((noreturn)) void fail(const char *msg, i64 len) {
  sc3(1, 2, (i64)msg, len);
  i64 slot = tag_int(1);
  rt_builtin(24, &slot, 1);
  for (;;) sc3(60, 1, 0, 0);
}
#define FAIL(m) fail(m, sizeof(m) - 1)

static i64 vec_new(i64 *buf, i64 len) {
  i64 t[3] = {len, (i64)buf, len};
  return rt_box_rc_vec(t);
}
static i64 rval_new(i64 tag, i64 a, i64 b) {
  i64 t[3] = {tag, a, b};
  return rt_box_rval(t);
}

/* ── Byte data of a String or a Tensor[U8] ────────────────────── */
static i64 *u8_words(i64 t) { return *(i64 **)(*field(t, 2) + 8); }
static i64 u8_rank(i64 t) { return u8_words(t)[0]; }
static i64 u8_count(i64 t) {
  i64 *w = u8_words(t);
  i64 n = 1;
  for (i64 k = 0; k < w[0]; k++) n *= w[1 + k];
  return n;
}
static u8 *u8_data(i64 t) {
  i64 *w = u8_words(t);
  return (u8 *)(w + 1 + w[0]);
}

/* The bytes of a String or a Tensor[U8]; 0 otherwise. */
static int bytes_of(i64 v, u8 **data, i64 *len) {
  if (!is_ptr(v)) return 0;
  u32 tg = heap_tag(v);
  if (tg == 1) {
    i64 h = *field(v, 1);
    *data = *(u8 **)(h + 8);
    *len = *(i64 *)(h + 16);
    return 1;
  }
  if (tg == 5) {
    *data = u8_data(v);
    *len = u8_count(v);
    return 1;
  }
  return 0;
}

/* A new Tensor[U8] of rank k with dims d, every byte equal to fill. */
static i64 u8_new(i64 k, const i64 *d, int fill) {
  i64 n = 1;
  for (i64 j = 0; j < k; j++) n *= (d[j] > 0 ? d[j] : 0);
  i64 w = 1 + k + (n + 7) / 8;
  i64 *data = (i64 *)rt_alloc_buf(w * 8);
  data[0] = k;
  for (i64 j = 0; j < k; j++) data[1 + j] = d[j] > 0 ? d[j] : 0;
  u8 *b = (u8 *)(data + 1 + k);
  mem_zero(b, (w - 1 - k) * 8);
  if (fill) for (i64 i = 0; i < n; i++) b[i] = (u8)fill;
  i64 *shape = (i64 *)rt_alloc_buf(8);
  shape[0] = w;
  return rval_new(5, vec_new(shape, 1), vec_new(data, w));
}

static i64 u8_from_bytes(const u8 *src, i64 n) {
  i64 d = n;
  i64 t = u8_new(1, &d, 0);
  mem_copy(u8_data(t), src, n);
  return t;
}

/* Linear offset of the indices in slots[0 .. k-1]; stops on a bad index. */
static i64 u8_offset(i64 t, i64 *idx, i64 k) {
  i64 *w = u8_words(t);
  if (w[0] != k) FAIL(MSG_OOB);
  i64 off = 0;
  for (i64 j = 0; j < k; j++) {
    i64 i = is_int(idx[j]) ? untag(idx[j]) : -1;
    if (i < 0 || i >= w[1 + j]) FAIL(MSG_OOB);
    off = off * w[1 + j] + i;
    idx[j] = 0;
  }
  return off;
}

/* ── CRC-32 (IEEE 802.3, reflected 0xEDB88320), slicing by 4 ──── */
static u32 crc_tab[4][256];
static int crc_ready;

static void crc_init(void) {
  for (u32 i = 0; i < 256; i++) {
    u32 c = i;
    for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
    crc_tab[0][i] = c;
  }
  for (u32 i = 0; i < 256; i++) {
    u32 c = crc_tab[0][i];
    for (int t = 1; t < 4; t++) {
      c = crc_tab[0][c & 255] ^ (c >> 8);
      crc_tab[t][i] = c;
    }
  }
  __atomic_store_n(&crc_ready, 1, __ATOMIC_RELEASE);
}

static u32 crc32(u32 crc, const u8 *p, i64 n) {
  if (!__atomic_load_n(&crc_ready, __ATOMIC_ACQUIRE)) crc_init();
  u32 c = ~crc;
  while (n > 0 && ((u64)p & 3)) { c = crc_tab[0][(c ^ *p++) & 255] ^ (c >> 8); n--; }
  while (n >= 4) {
    c ^= *(const u32 *)p;
    c = crc_tab[3][c & 255] ^ crc_tab[2][(c >> 8) & 255] ^ crc_tab[1][(c >> 16) & 255] ^ crc_tab[0][c >> 24];
    p += 4;
    n -= 4;
  }
  while (n-- > 0) c = crc_tab[0][(c ^ *p++) & 255] ^ (c >> 8);
  return ~c;
}

/* ── Clocks through the vDSO ──────────────────────────────────── */
typedef i64 (*cgt_fn)(i64, i64 *);
static u64 vdso_cgt; /* 0 not looked up, 1 none, else __vdso_clock_gettime */

static u64 vdso_base(void) {
  u64 aux[64];
  /* prctl(PR_GET_AUXV), Linux 6.4 and later. */
  i64 n = sc6(157, 0x41555856, (i64)aux, sizeof aux, 0, 0, 0);
  if (n <= 0) {
    u64 path[2] = {0x65732f636f72702fUL, 0x00767875612f666cUL}; /* /proc/self/auxv */
    i64 fd = sc3(2, (i64)path, 0, 0);
    if (fd < 0) return 0;
    n = sc3(0, fd, (i64)aux, sizeof aux);
    sc3(3, fd, 0, 0);
  }
  if (n > (i64)sizeof aux) n = sizeof aux;
  for (i64 i = 0; i + 1 < n / 8; i += 2) {
    if (aux[i] == 0) break;
    if (aux[i] == 33) return aux[i + 1]; /* AT_SYSINFO_EHDR */
  }
  return 0;
}

static int name_is(const u8 *s, const char *want) {
  for (int i = 0;; i++) {
    if (s[i] != (u8)want[i]) return 0;
    if (want[i] == 0) return 1;
  }
}

static u64 vdso_lookup(u64 base) {
  if (base == 0) return 0;
  const u8 *eh = (const u8 *)base;
  u64 phoff = *(const u64 *)(eh + 32);
  u16 phentsize = *(const u16 *)(eh + 54);
  u16 phnum = *(const u16 *)(eh + 56);
  u64 bias = 0, dyn = 0;
  int have_load = 0;
  for (u16 i = 0; i < phnum; i++) {
    const u8 *ph = eh + phoff + (u64)i * phentsize;
    u32 type = *(const u32 *)ph;
    u64 off = *(const u64 *)(ph + 8), vaddr = *(const u64 *)(ph + 16);
    if (type == 1 && !have_load) { bias = base + off - vaddr; have_load = 1; }
    if (type == 2) dyn = vaddr;
  }
  if (!have_load || dyn == 0) return 0;
  u64 symtab = 0, strtab = 0, hash = 0;
  for (const i64 *d = (const i64 *)(bias + dyn); d[0] != 0; d += 2) {
    if (d[0] == 4) hash = bias + (u64)d[1];
    else if (d[0] == 5) strtab = bias + (u64)d[1];
    else if (d[0] == 6) symtab = bias + (u64)d[1];
  }
  if (symtab == 0 || strtab == 0) return 0;
  u64 count = hash ? *(const u32 *)(hash + 4) : (strtab > symtab ? (strtab - symtab) / 24 : 0);
  if (count > 4096) count = 4096;
  for (u64 i = 0; i < count; i++) {
    const u8 *sym = (const u8 *)(symtab + i * 24);
    u32 name = *(const u32 *)sym;
    u16 shndx = *(const u16 *)(sym + 6);
    u64 value = *(const u64 *)(sym + 8);
    if (shndx != 0 && value != 0 &&
        (name_is((const u8 *)(strtab + name), "__vdso_clock_gettime") ||
         name_is((const u8 *)(strtab + name), "clock_gettime")))
      return bias + value;
  }
  return 0;
}

/* mode 0: CLOCK_MONOTONIC ns; 1: CLOCK_REALTIME ms; 2: CLOCK_MONOTONIC ms. */
static i64 clock_read(i64 mode) {
  if (vdso_cgt == 0) {
    u64 f = vdso_lookup(vdso_base());
    vdso_cgt = f ? f : 1;
  }
  i64 clk = mode == 1 ? 0 : 1;
  i64 ts[2] = {0, 0};
  if (vdso_cgt != 1) ((cgt_fn)vdso_cgt)(clk, ts);
  else sc3(228, clk, (i64)ts, 0);
  if (mode == 0) return ts[0] * 1000000000L + ts[1];
  return ts[0] * 1000L + ts[1] / 1000000L;
}

/* ── Files ────────────────────────────────────────────────────── */
/* A NUL-terminated copy of a String path on the stack buffer p. */
static int path_of(i64 s, char *p, i64 cap) {
  u8 *d;
  i64 n;
  if (!bytes_of(s, &d, &n) || n >= cap) return 0;
  mem_copy((u8 *)p, d, n);
  p[n] = 0;
  return 1;
}

/* remove file, remove dir (unlinkat, AT_REMOVEDIR) and rename path
 * (renameat, which replaces the target): 0 or -errno. */
static i64 path_call(i64 id, i64 a, i64 b) {
  char p[4096], q[4096];
  if (!path_of(a, p, sizeof p)) return -2; /* ENOENT */
  if (id == 124) {
    if (!path_of(b, q, sizeof q)) return -2;
    return sc6(264, -100, (i64)p, -100, (i64)q, 0, 0);
  }
  return sc3(263, -100, (i64)p, id == 123 ? 0x200 : 0);
}

static i64 read_all(i64 fd, u8 *dst, i64 cap) {
  i64 got = 0;
  while (got < cap) {
    i64 r = sc3(0, fd, (i64)(dst + got), cap - got);
    if (r <= 0) break;
    got += r;
  }
  return got;
}

/* Files without a size (pipes, procfs, terminals): one pass into an
 * anonymous mapping that doubles with mremap. A pipe cannot be read
 * twice, so the bytes are never counted first and read again. */
static i64 read_unsized(i64 fd) {
  i64 cap = 65536, got = 0, empty = 0;
  i64 m = sc6(9, 0, cap, 3, 0x22, -1, 0); /* mmap RW, MAP_PRIVATE|MAP_ANONYMOUS */
  if (m < 0 && m > -4096) return u8_new(1, &empty, 0);
  for (;;) {
    if (got == cap) {
      i64 nm = sc6(25, m, cap, cap * 2, 1, 0, 0); /* mremap MREMAP_MAYMOVE */
      if (nm < 0 && nm > -4096) break;
      m = nm;
      cap *= 2;
    }
    i64 r = sc3(0, fd, m + got, cap - got);
    if (r == -4) continue; /* EINTR */
    if (r <= 0) break;
    got += r;
  }
  i64 t = u8_from_bytes((const u8 *)m, got);
  sc3(11, m, cap, 0); /* munmap */
  return t;
}

static i64 read_bytes(i64 path) {
  char p[4096];
  i64 empty = 0;
  if (!path_of(path, p, sizeof p)) return u8_new(1, &empty, 0);
  i64 fd = sc3(2, (i64)p, 0, 0);
  if (fd < 0) return u8_new(1, &empty, 0);
  i64 st[18];
  i64 size = sc3(5, fd, (i64)st, 0) == 0 ? st[6] : 0; /* fstat: st_size */
  if (size <= 0) {
    i64 u = read_unsized(fd);
    sc3(3, fd, 0, 0);
    return u;
  }
  i64 t = u8_new(1, &size, 0);
  i64 got = read_all(fd, u8_data(t), size);
  sc3(3, fd, 0, 0);
  u8_words(t)[1] = got; /* a shorter read keeps the bytes it got */
  return t;
}

static i64 write_bytes(i64 path, i64 data) {
  char p[4096];
  if (!path_of(path, p, sizeof p)) return 0;
  i64 fd = sc6(2, (i64)p, 01 | 0100 | 01000, 0644, 0, 0, 0); /* O_WRONLY|O_CREAT|O_TRUNC */
  if (fd < 0) return 0;
  if (is_ptr(data) && heap_tag(data) == 2) {
    /* A list of Ints 0..255, written through a stack buffer. */
    i64 h = *field(data, 1);
    i64 *xs = *(i64 **)(h + 8);
    i64 n = *(i64 *)(h + 16), st = *field(data, 2);
    u8 buf[4096];
    i64 m = 0;
    for (i64 i = st; i < n; i++) {
      i64 b = int_arg(xs[i]);
      if (b < 0 || b > 255) FAIL(MSG_BYTES);
      buf[m++] = (u8)b;
      if (m == sizeof buf) { sc3(1, fd, (i64)buf, m); m = 0; }
    }
    if (m > 0) sc3(1, fd, (i64)buf, m);
  } else {
    u8 *d;
    i64 n;
    if (bytes_of(data, &d, &n)) {
      i64 done = 0;
      while (done < n) {
        i64 r = sc3(1, fd, (i64)(d + done), n - done);
        if (r <= 0) break;
        done += r;
      }
    }
  }
  sc3(3, fd, 0, 0);
  return 0;
}

/* sys read into fd t from count / sys write from fd t from count */
static i64 fd_io(i64 nr, i64 *s) {
  i64 fd = int_arg(s[0]), t = s[1], from = int_arg(s[2]), count = int_arg(s[3]);
  u8 *d;
  i64 n;
  if (!bytes_of(t, &d, &n) || from < 0 || count < 0 || from > n || count > n - from) FAIL(MSG_IO);
  return sc3(nr, fd, (i64)(d + from), count);
}

/* sys call nr a1..a6: a Tensor[U8] or String argument passes the address
   of its first byte; the arguments stay alive until the call returns. */
static i64 sys_call(i64 *s, i64 count) {
  i64 a[7] = {0, 0, 0, 0, 0, 0, 0};
  for (i64 i = 0; i < count && i < 7; i++) {
    u8 *d;
    i64 n;
    if (is_ptr(s[i]) && heap_tag(s[i]) != 0 && bytes_of(s[i], &d, &n)) a[i] = (i64)d;
    else a[i] = int_arg(s[i]);
  }
  return sc6(a[0], a[1], a[2], a[3], a[4], a[5], a[6]);
}

/* ── Conversions ──────────────────────────────────────────────── */
static i64 u8_to_list(i64 t) {
  i64 n = u8_count(t);
  u8 *b = u8_data(t);
  i64 *xs = (i64 *)rt_alloc_buf((n > 0 ? n : 1) * 8);
  for (i64 i = 0; i < n; i++) xs[i] = tag_int(b[i]);
  return rval_new(2, vec_new(xs, n), 0);
}

/* A numeric tensor of the same shape with one word per element (show). */
static i64 u8_to_words(i64 t) {
  i64 k = u8_rank(t), n = u8_count(t);
  i64 *w = u8_words(t);
  u8 *b = u8_data(t);
  i64 *shape = (i64 *)rt_alloc_buf((k > 0 ? k : 1) * 8);
  for (i64 j = 0; j < k; j++) shape[j] = w[1 + j];
  i64 *data = (i64 *)rt_alloc_buf((n > 0 ? n : 1) * 8);
  for (i64 i = 0; i < n; i++) data[i] = b[i];
  return rval_new(5, vec_new(shape, k), vec_new(data, n));
}

/* sys execve path argv envp, as execve(2): argv is passed whole (argv[0]
   included). The strings are copied NUL-terminated into one block with the
   two pointer tables. Returns only on failure, with -errno. */
static i64 str_list(i64 v, i64 **xs, i64 *st) {
  if (!is_ptr(v) || heap_tag(v) != 2) return 0;
  i64 h = *field(v, 1);
  *xs = *(i64 **)(h + 8);
  *st = *field(v, 2);
  i64 n = *(i64 *)(h + 16) - *st;
  return n > 0 ? n : 0;
}
static i64 list_bytes(i64 *xs, i64 st, i64 n) {
  i64 total = 0;
  for (i64 i = 0; i < n; i++) {
    u8 *d;
    i64 len;
    if (bytes_of(xs[st + i], &d, &len)) total += len;
    total += 1;
  }
  return total;
}
static char **fill_table(char **tab, char *buf, i64 *xs, i64 st, i64 n, char **next) {
  for (i64 i = 0; i < n; i++) {
    u8 *d;
    i64 len = 0;
    if (!bytes_of(xs[st + i], &d, &len)) len = 0;
    mem_copy((u8 *)buf, d, len);
    buf[len] = 0;
    tab[i] = buf;
    buf += len + 1;
  }
  tab[n] = 0;
  *next = buf;
  return tab;
}
static i64 exec_full(i64 path, i64 argv, i64 envp) {
  char p[4096];
  if (!path_of(path, p, sizeof p)) return -2; /* ENOENT */
  i64 *av = 0, *ev = 0, ast = 0, est = 0;
  i64 an = str_list(argv, &av, &ast), en = str_list(envp, &ev, &est);
  i64 size = (an + 1 + en + 1) * 8 + list_bytes(av, ast, an) + list_bytes(ev, est, en);
  char **block = (char **)rt_alloc_buf(size > 8 ? size : 8);
  char *strs = (char *)(block + an + 1 + en + 1);
  char *next;
  char **a = fill_table(block, strs, av, ast, an, &next);
  char **e = fill_table(block + an + 1, next, ev, est, en, &next);
  return sc3(59, (i64)p, (i64)a, (i64)e);
}

/* tensor u8 from list: a list of Ints 0..255 => Tensor[U8 * n] */
static i64 list_to_u8(i64 v) {
  i64 *xs = 0, n = 0, st = 0;
  if (is_ptr(v) && heap_tag(v) == 2) {
    i64 h = *field(v, 1);
    xs = *(i64 **)(h + 8);
    n = *(i64 *)(h + 16);
    st = *field(v, 2);
  }
  i64 d = n > st ? n - st : 0;
  for (i64 i = 0; i < d; i++) {
    i64 b = int_arg(xs[st + i]);
    if (b < 0 || b > 255) FAIL(MSG_U8);
  }
  i64 t = u8_new(1, &d, 0);
  u8 *out = u8_data(t);
  for (i64 i = 0; i < d; i++) out[i] = (u8)int_arg(xs[st + i]);
  return t;
}

static i64 str_to_u8(i64 s) {
  u8 *d;
  i64 n;
  if (!bytes_of(s, &d, &n)) n = 0;
  return u8_from_bytes(d, n);
}

static int hex_val(u8 c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return 0;
}

/* The 32-byte SHA-256 digest of a String or a Tensor[U8] (consumed), in
   out. The runtime builtin 21 gives the digest as 64 hex digits. */
static void sha256_of(i64 v, u8 *out) {
  u8 *d;
  i64 n;
  i64 slot;
  if (is_ptr(v) && heap_tag(v) == 5 && bytes_of(v, &d, &n)) {
    slot = rt_alloc_str(d, n);
    rt_drop_val(v);
  } else {
    slot = v;
  }
  i64 h = rt_builtin(21, &slot, 1);
  mem_zero(out, 32);
  if (bytes_of(h, &d, &n) && n >= 64)
    for (int i = 0; i < 32; i++) out[i] = (u8)(hex_val(d[2 * i]) * 16 + hex_val(d[2 * i + 1]));
  if (is_ptr(h)) rt_drop_val(h);
}

/* ── Entry ────────────────────────────────────────────────────── */
/* ── In-place String append (a + b in a tail position) ─────────
 * A String's header is {capacity, data, length, rc}. When the left
 * String's header has rc 1 (one owner), b's bytes are appended to its
 * buffer, which grows by doubling, so building a String in a loop is
 * linear. The old buffer is freed by dropping a String made around it.
 * Returns 0 and leaves both slots as they are when the operands are not
 * two Strings or the left one is shared: the caller then does the usual
 * `+` (a new String). */
static i64 str_append(i64 *s) {
  i64 a = s[0], b = s[1];
  if (!is_ptr(a) || heap_tag(a) != 1 || !is_ptr(b) || heap_tag(b) != 1) return 0;
  i64 *h = (i64 *)*field(a, 1);
  if (h[3] != 1) return 0;
  u8 *bd;
  i64 bn;
  bytes_of(b, &bd, &bn);
  i64 cap = h[0], len = h[2];
  if (cap - len < bn) {
    i64 nc = cap * 2;
    if (nc < len + bn) nc = len + bn;
    if (nc < 32) nc = 32;
    u8 *nb = (u8 *)rt_alloc_buf(nc);
    mem_copy(nb, (const u8 *)h[1], len);
    if (cap > 0) {
      i64 t[3] = {cap, h[1], 0};
      rt_drop_val(rval_new(1, rt_box_rc_vec(t), 0));
    }
    h[0] = nc;
    h[1] = (i64)nb;
  }
  mem_copy((u8 *)h[1] + len, bd, bn);
  h[2] = len + bn;
  s[0] = 0;
  s[1] = 0;
  rt_drop_val(b);
  return a;
}

/* ── PAL TCP sockets (FR-VM-003, ADR-0008) ────────────────────── */
/* A common part (arguments, host names, limits) and one system part per
 * target: Linux system calls, or the Windows layer. Results are a value
 * >= 0 or a negative Linux errno. Option index: 0 nodelay, 1 keepalive,
 * 2 reuseport, 3 broadcast, 4 rcvbuf, 5 sndbuf. */

/* A wait limit in ms: t >= 0 as given; -1 is the time left in a `with timeout`
 * block (sys remaining ms, id 73 of the PAL entry), or no limit outside one. */
static i64 wait_limit(i64 t) {
  if (t >= 0) return t;
  i64 slot = 0;
  i64 rem = int_arg(rt_pal(73, &slot, 0));
  return rem >= 0 ? rem : -1;
}

static int ip4_parse(const char *s, u32 *out) {
  u32 v = 0;
  int parts = 0;
  for (;;) {
    i64 n = 0;
    int digits = 0;
    while (*s >= '0' && *s <= '9') {
      n = n * 10 + (*s++ - '0');
      if (++digits > 3 || n > 255) return 0;
    }
    if (!digits) return 0;
    v = (v << 8) | (u32)n;
    if (++parts == 4) break;
    if (*s++ != '.') return 0;
  }
  if (*s) return 0;
  *out = v;
  return 1;
}

static i64 ip4_text(u32 v, char *d) {
  i64 k = 0;
  for (int i = 3; i >= 0; i--) {
    u32 b = (v >> (8 * i)) & 255;
    if (b >= 100) d[k++] = (char)('0' + b / 100);
    if (b >= 10) d[k++] = (char)('0' + (b / 10) % 10);
    d[k++] = (char)('0' + b % 10);
    if (i) d[k++] = '.';
  }
  return k;
}

static int name_eq(const char *a, const char *b) {
  while (*a && *a == *b) { a++; b++; }
  return *a == *b;
}

#ifndef RG_WIN
/* Linux: sockets stay blocking for sys read fd / sys write fd; these
 * routines wait with poll and use MSG_DONTWAIT. */
enum { NR_POLL = 7, NR_SOCKET = 41, NR_CONNECT = 42, NR_SENDTO = 44, NR_RECVFROM = 45,
       NR_SHUTDOWN = 48, NR_BIND = 49, NR_LISTEN = 50, NR_GETSOCKNAME = 51,
       NR_GETPEERNAME = 52, NR_SETSOCKOPT = 54, NR_GETSOCKOPT = 55, NR_FCNTL = 72,
       NR_ACCEPT4 = 288 };

static u8 lower_c(u8 c) { return (c >= 'A' && c <= 'Z') ? (u8)(c + 32) : c; }

/* The revents of one descriptor, or -110 when the time ends. */
static i64 poll1(i64 fd, i64 ev, i64 ms) {
  struct { int fd; short ev, rev; } p;
  if (fd < 0 || fd > 0x7FFFFFFF) return -9;
  for (;;) {
    p.fd = (int)fd;
    p.ev = (short)ev;
    p.rev = 0;
    i64 r = sc3(NR_POLL, (i64)&p, 1, ms);
    if (r == -4) continue;
    if (r < 0) return r;
    if (r == 0) return -110;
    return p.rev;
  }
}

/* What is left of a limit of lim ms started at start; -1 without limit. */
static i64 left_ms(i64 lim, i64 start) {
  if (lim < 0) return -1;
  i64 left = lim - (clock_read(2) - start);
  return left < 0 ? 0 : left;
}

static void sa_fill(u8 *sa, u32 ip, i64 port) {
  mem_zero(sa, 16);
  sa[0] = 2;
  sa[2] = (u8)(port >> 8);
  sa[3] = (u8)port;
  sa[4] = (u8)(ip >> 24);
  sa[5] = (u8)(ip >> 16);
  sa[6] = (u8)(ip >> 8);
  sa[7] = (u8)ip;
}

static u32 sa_ip(const u8 *sa) { return ((u32)sa[4] << 24) | ((u32)sa[5] << 16) | ((u32)sa[6] << 8) | sa[7]; }

/* Reads a small text file into buf (NUL-terminated); 0 when it is missing. */
static i64 read_small(const char *path, char *buf, i64 cap) {
  i64 fd = sc6(257, -100, (i64)path, 0x80000, 0, 0, 0);
  if (fd < 0) return 0;
  i64 n = read_all(fd, (u8 *)buf, cap - 1);
  sc3(3, fd, 0, 0);
  buf[n] = 0;
  return n;
}

/* The IPv4 address of `name` in the hosts table text, line by line. */
static int hosts_lookup(const char *t, const char *name, u32 *ip) {
  while (*t) {
    const char *e = t;
    while (*e && *e != '\n') e++;
    char tok[256];
    const char *q = t;
    int first = 1;
    u32 addr = 0;
    while (q < e && *q != '#') {
      while (q < e && (*q == ' ' || *q == '\t' || *q == '\r')) q++;
      if (q >= e || *q == '#') break;
      i64 k = 0;
      while (q < e && *q != ' ' && *q != '\t' && *q != '\r' && *q != '#') {
        if (k < 255) tok[k++] = *q;
        q++;
      }
      tok[k] = 0;
      if (first) {
        if (!ip4_parse(tok, &addr)) break;
        first = 0;
      } else {
        const char *x = tok, *y = name;
        while (*x && lower_c((u8)*x) == lower_c((u8)*y)) { x++; y++; }
        if (!*x && !*y) { *ip = addr; return 1; }
      }
    }
    t = *e ? e + 1 : e;
  }
  return 0;
}

/* The first `nameserver` IPv4 address of resolv.conf text. */
static int resolv_server(const char *t, u32 *ip) {
  while (*t) {
    const char *e = t;
    while (*e && *e != '\n') e++;
    const char *k = "nameserver";
    const char *q = t;
    while (*k && q < e && *q == *k) { q++; k++; }
    if (!*k && q < e && (*q == ' ' || *q == '\t')) {
      while (q < e && (*q == ' ' || *q == '\t')) q++;
      char tok[64];
      i64 n = 0;
      while (q < e && n < 63 && *q != ' ' && *q != '\t' && *q != '\r') tok[n++] = *q++;
      tok[n] = 0;
      if (ip4_parse(tok, ip)) return 1;
    }
    t = *e ? e + 1 : e;
  }
  return 0;
}

/* Skips a DNS name at off; -1 when it runs out of the message. */
static i64 dns_skip(const u8 *m, i64 n, i64 off) {
  while (off < n) {
    u8 c = m[off];
    if (c == 0) return off + 1;
    if ((c & 0xC0) == 0xC0) return off + 2 <= n ? off + 2 : -1;
    off += 1 + c;
  }
  return -1;
}

/* One A query over UDP to the server; the first A answer. */
static int dns_query(u32 server, const char *name, u32 *ip, i64 ms) {
  u8 q[300], r[512], sa[16];
  i64 n = 12;
  u16 id = (u16)clock_read(0);
  mem_zero(q, 12);
  q[0] = (u8)(id >> 8); q[1] = (u8)id; q[2] = 1; q[5] = 1;
  const char *s = name;
  while (*s) {
    const char *e = s;
    while (*e && *e != '.') e++;
    i64 len = e - s;
    if (len < 1 || len > 63 || n + len + 6 > (i64)sizeof q) return 0;
    q[n++] = (u8)len;
    mem_copy(q + n, (const u8 *)s, len);
    n += len;
    s = *e ? e + 1 : e;
  }
  q[n++] = 0; q[n++] = 0; q[n++] = 1; q[n++] = 0; q[n++] = 1;
  i64 fd = sc3(NR_SOCKET, 2, 2 | 0x80000, 0);
  if (fd < 0) return 0;
  sa_fill(sa, server, 53);
  int ok = 0;
  if (sc3(NR_CONNECT, fd, (i64)sa, 16) == 0 && sc6(NR_SENDTO, fd, (i64)q, n, 0x4000, 0, 0) == n &&
      poll1(fd, 1, ms) > 0) {
    i64 got = sc6(NR_RECVFROM, fd, (i64)r, sizeof r, 0x40, 0, 0);
    if (got >= 12 && r[0] == q[0] && r[1] == q[1] && (r[3] & 15) == 0) {
      i64 an = ((i64)r[6] << 8) | r[7];
      i64 off = dns_skip(r, got, 12);
      if (off >= 0) off += 4;
      for (i64 i = 0; i < an && off >= 0 && off < got; i++) {
        off = dns_skip(r, got, off);
        if (off < 0 || off + 10 > got) break;
        i64 type = ((i64)r[off] << 8) | r[off + 1];
        i64 rdlen = ((i64)r[off + 8] << 8) | r[off + 9];
        off += 10;
        if (off + rdlen > got) break;
        if (type == 1 && rdlen == 4) {
          *ip = sa_ip(r + off - 4);
          ok = 1;
          break;
        }
        off += rdlen;
      }
    }
  }
  sc3(3, fd, 0, 0);
  return ok;
}

/* A host name: /etc/hosts, then `localhost`, then the DNS server. */
static int os_resolve(const char *name, u32 *ip) {
  i64 m = sc6(9, 0, 65536, 3, 0x22, -1, 0);
  if (m < 0 && m > -4096) return 0;
  char *buf = (char *)m;
  int ok = read_small("/etc/hosts", buf, 65536) && hosts_lookup(buf, name, ip);
  if (!ok) {
    const char *x = name, *y = "localhost";
    while (*x && lower_c((u8)*x) == *y) { x++; y++; }
    if (!*x && !*y) { *ip = 0x7F000001; ok = 1; }
  }
  u32 server;
  if (!ok && read_small("/etc/resolv.conf", buf, 65536) && resolv_server(buf, &server)) {
    i64 lim = wait_limit(-1);
    ok = dns_query(server, name, ip, lim < 0 || lim > 5000 ? 5000 : lim);
  }
  sc3(11, m, 65536, 0);
  return ok;
}

static i64 os_connect(u32 ip, i64 port, i64 lim) {
  u8 sa[16];
  sa_fill(sa, ip, port);
  i64 fd = sc3(NR_SOCKET, 2, 1 | 0x800 | 0x80000, 0);
  if (fd < 0) return fd;
  i64 r = sc3(NR_CONNECT, fd, (i64)sa, 16);
  if (r == -115) {
    i64 ev = poll1(fd, 4, lim);
    if (ev < 0) r = ev;
    else {
      int e = 0;
      u32 len = 4;
      i64 g = sc6(NR_GETSOCKOPT, fd, 1, 4, (i64)&e, (i64)&len, 0);
      r = g < 0 ? g : -(i64)e;
    }
  }
  if (r < 0) {
    sc3(3, fd, 0, 0);
    return r;
  }
  sc3(NR_FCNTL, fd, 4, 2);
  return fd;
}

static i64 os_listen(u32 ip, i64 port, i64 backlog) {
  u8 sa[16];
  int one = 1;
  i64 fd = sc3(NR_SOCKET, 2, 1 | 0x80000, 0);
  if (fd < 0) return fd;
  sc6(NR_SETSOCKOPT, fd, 1, 2, (i64)&one, 4, 0);
  sa_fill(sa, ip, port);
  i64 r = sc3(NR_BIND, fd, (i64)sa, 16);
  if (r >= 0) r = sc3(NR_LISTEN, fd, backlog, 0);
  if (r < 0) {
    sc3(3, fd, 0, 0);
    return r;
  }
  return fd;
}

static i64 os_accept(i64 fd, i64 lim) {
  i64 ev = poll1(fd, 1, lim);
  if (ev < 0) return ev;
  return sc6(NR_ACCEPT4, fd, 0, 0, 0x80000, 0, 0);
}

static i64 os_send(i64 fd, const u8 *d, i64 n, i64 lim) {
  i64 start = clock_read(2), sent = 0;
  while (sent < n) {
    i64 ev = poll1(fd, 4, left_ms(lim, start));
    if (ev < 0) return sent ? sent : ev;
    i64 r = sc6(NR_SENDTO, fd, (i64)(d + sent), n - sent, 0x40 | 0x4000, 0, 0);
    if (r == -11 || r == -4) continue;
    if (r < 0) return sent ? sent : r;
    sent += r;
  }
  return sent;
}

static i64 os_recv(i64 fd, u8 *d, i64 n, i64 lim) {
  i64 start = clock_read(2);
  for (;;) {
    i64 ev = poll1(fd, 1, left_ms(lim, start));
    if (ev < 0) return ev;
    i64 r = sc6(NR_RECVFROM, fd, (i64)d, n, 0x40, 0, 0);
    if (r == -11 || r == -4) continue;
    return r;
  }
}

static i64 os_shutdown(i64 fd, i64 how) { return sc3(NR_SHUTDOWN, fd, how, 0); }

static i64 os_option(i64 fd, i64 idx, i64 value) {
  i64 level = 1, opt;
  switch (idx) {
  case 0: level = 6; opt = 1; break;
  case 1: opt = 9; break;
  case 2: opt = 15; break;
  case 3: opt = 6; break;
  case 4: opt = 8; break;
  case 5: opt = 7; break;
  default: return -92;
  }
  int v = (int)value;
  return sc6(NR_SETSOCKOPT, fd, level, opt, (i64)&v, 4, 0);
}

/* The local port (peer = 0) or the peer's IPv4 address (peer = 1). */
static i64 os_name(i64 fd, int peer) {
  u8 sa[16];
  u32 len = 16;
  mem_zero(sa, 16);
  i64 r = sc3(peer ? NR_GETPEERNAME : NR_GETSOCKNAME, fd, (i64)sa, (i64)&len);
  if (r < 0) return r;
  if (sa[0] != 2) return -22;
  return peer ? (i64)sa_ip(sa) : (((i64)sa[2] << 8) | sa[3]);
}

#else
/* Windows: the operations of the Windows layer (rtw.c, rg_pal 1000..1009). */
static inline i64 pal5(i64 op, i64 a, i64 b, i64 c, i64 d) { return sc6(op, a, b, c, d, 0, 0); }
static int os_resolve(const char *name, u32 *ip) {
  i64 r = pal5(1009, (i64)name, 0, 0, 0);
  if (r < 0) return 0;
  *ip = (u32)r;
  return 1;
}
static i64 os_connect(u32 ip, i64 port, i64 lim) { return pal5(1000, ip, port, lim, 0); }
static i64 os_listen(u32 ip, i64 port, i64 backlog) { return pal5(1001, ip, port, backlog, 0); }
static i64 os_accept(i64 fd, i64 lim) { return pal5(1002, fd, lim, 0, 0); }
static i64 os_send(i64 fd, const u8 *d, i64 n, i64 lim) { return pal5(1003, fd, (i64)d, n, lim); }
static i64 os_recv(i64 fd, u8 *d, i64 n, i64 lim) { return pal5(1004, fd, (i64)d, n, lim); }
static i64 os_shutdown(i64 fd, i64 how) { return pal5(1005, fd, how, 0, 0); }
static i64 os_option(i64 fd, i64 idx, i64 value) { return pal5(1006, fd, idx, value, 0); }
static i64 os_name(i64 fd, int peer) { return pal5(peer ? 1008 : 1007, fd, 0, 0, 0); }
#endif

/* An IPv4 address in text, or a host name the system resolves. */
static int resolve4(const char *name, u32 *ip) {
  if (!name[0]) return 0;
  if (ip4_parse(name, ip)) return 1;
  return os_resolve(name, ip);
}

static i64 net_connect(i64 hostv, i64 port, i64 tmo) {
  char h[256];
  u32 ip;
  if (!path_of(hostv, h, sizeof h) || port < 0 || port > 65535) return -22;
  if (!resolve4(h, &ip)) return -2;
  return os_connect(ip, port, wait_limit(tmo));
}

static i64 net_listen(i64 hostv, i64 port, i64 backlog) {
  char h[256];
  u32 ip = 0;
  if (!path_of(hostv, h, sizeof h) || port < 0 || port > 65535 || backlog < 1) return -22;
  if (h[0] && !resolve4(h, &ip)) return -2;
  return os_listen(ip, port, backlog);
}

static i64 net_send(i64 fd, i64 data, i64 tmo) {
  u8 *d;
  i64 n;
  if (!bytes_of(data, &d, &n)) return -22;
  if (n == 0) return 0;
  return os_send(fd, d, n, wait_limit(tmo));
}

static i64 net_recv_into(i64 *s) {
  i64 fd = int_arg(s[0]), t = s[1], from = int_arg(s[2]), count = int_arg(s[3]), tmo = int_arg(s[4]);
  u8 *d;
  i64 n;
  if (!bytes_of(t, &d, &n) || from < 0 || count < 0 || from > n || count > n - from) return -22;
  if (count == 0) return 0;
  return os_recv(fd, d + from, count, wait_limit(tmo));
}

static i64 net_recv(i64 fd, i64 max, i64 tmo) {
  if (max < 1) return rt_alloc_str("", 0);
  i64 m = sc6(9, 0, max, 3, 0x22, -1, 0);
  if (m < 0 && m > -4096) return rt_alloc_str("", 0);
  i64 r = os_recv(fd, (u8 *)m, max, wait_limit(tmo));
  i64 str = rt_alloc_str((const void *)m, r > 0 ? r : 0);
  sc3(11, m, max, 0);
  return str;
}

static i64 net_option(i64 fd, i64 namev, i64 value) {
  char nm[32];
  if (!path_of(namev, nm, sizeof nm)) return -22;
  i64 i = name_eq(nm, "nodelay") ? 0 : name_eq(nm, "keepalive") ? 1 : name_eq(nm, "reuseport") ? 2
        : name_eq(nm, "broadcast") ? 3 : name_eq(nm, "rcvbuf") ? 4 : name_eq(nm, "sndbuf") ? 5 : -1;
  return i < 0 ? -92 : os_option(fd, i, value);
}

static i64 net_peer_ip(i64 fd) {
  char t[16];
  i64 ip = os_name(fd, 1);
  if (ip < 0) return rt_alloc_str("", 0);
  return rt_alloc_str(t, ip4_text((u32)ip, t));
}

static i64 net_resolve(i64 namev) {
  char h[256], t[16];
  u32 ip;
  if (!path_of(namev, h, sizeof h) || !resolve4(h, &ip)) return rt_alloc_str("", 0);
  return rt_alloc_str(t, ip4_text(ip, t));
}

enum {
  ID_TIME_NS = 100, ID_WALL_MS = 101, ID_TIME_MS = 102, ID_CRC = 103,
  ID_U8_NEW = 104, ID_U8_GET = 105, ID_U8_SET = 106, ID_U8_DIM = 107,
  ID_FROM_STR = 108, ID_TO_STR = 109, ID_TO_LIST = 110, ID_TO_WORDS = 111,
  ID_READ_BYTES = 112, ID_WRITE_BYTES = 113, ID_READ_INTO = 114, ID_WRITE_FROM = 115,
  ID_SYS_CALL = 116, ID_SHA_RAW = 117, ID_SHA_DIGEST = 118, ID_FROM_LIST = 119, ID_EXECVE = 120,
  ID_STR_APPEND = 121, ID_UNLINK = 122, ID_RMDIR = 123, ID_RENAME = 124,
  ID_NET_CONNECT = 125, ID_NET_LISTEN = 126, ID_NET_ACCEPT = 127, ID_NET_SEND = 128,
  ID_NET_RECV_INTO = 129, ID_NET_RECV = 130, ID_NET_SHUTDOWN = 131, ID_NET_OPTION = 132,
  ID_NET_LOCAL_PORT = 133, ID_NET_PEER_IP = 134, ID_NET_RESOLVE = 135
};

__attribute__((used)) i64 rg_rtx(i64 id, i64 *s, i64 count) {
  i64 r = 0;
  switch (id) {
  case ID_TIME_NS: return tag_int(clock_read(0));
  case ID_WALL_MS: return tag_int(clock_read(1));
  case ID_TIME_MS: return tag_int(clock_read(2));
  case ID_CRC: { /* data from to crc */
    u8 *d;
    i64 n;
    i64 from = int_arg(s[1]), to = int_arg(s[2]), crc = int_arg(s[3]);
    if (!bytes_of(s[0], &d, &n) || from < 0 || from > to || to > n) FAIL(MSG_CRC);
    r = tag_int((i64)crc32((u32)crc, d + from, to - from));
    drop_slots(s, count);
    return r;
  }
  case ID_U8_NEW: { /* fill d1 .. dk */
    i64 fill = int_arg(s[0]);
    if (fill < 0 || fill > 255) FAIL(MSG_U8);
    i64 d[16];
    i64 k = count - 1;
    if (k > 16) k = 16;
    for (i64 j = 0; j < k; j++) d[j] = int_arg(s[1 + j]);
    drop_slots(s, count);
    return u8_new(k, d, (int)fill);
  }
  case ID_U8_GET: { /* i1 .. ik t(borrowed) */
    i64 t = s[count - 1];
    s[count - 1] = 0;
    return tag_int(u8_data(t)[u8_offset(t, s, count - 1)]);
  }
  case ID_U8_SET: { /* i1 .. ik v t(borrowed) */
    i64 t = s[count - 1], v = int_arg(s[count - 2]);
    s[count - 1] = 0;
    if (v < 0 || v > 255) FAIL(MSG_U8);
    drop_slot(&s[count - 2]);
    u8_data(t)[u8_offset(t, s, count - 2)] = (u8)v;
    return 0;
  }
  case ID_U8_DIM: { /* k t(borrowed): k 0 rank, k >= 1 dimension k-1 */
    i64 k = int_arg(s[0]), t = s[1];
    s[0] = 0;
    s[1] = 0;
    i64 *w = u8_words(t);
    if (k == 0) return tag_int(w[0]);
    return tag_int(k <= w[0] ? w[k] : 0);
  }
  case ID_FROM_STR: r = str_to_u8(s[0]); break;
  case ID_TO_STR: r = rt_alloc_str(u8_data(s[0]), u8_count(s[0])); break;
  case ID_TO_LIST: r = u8_to_list(s[0]); break;
  case ID_FROM_LIST: r = list_to_u8(s[0]); break;
  case ID_EXECVE: r = tag_int(exec_full(s[0], s[1], s[2])); break;
  case ID_STR_APPEND: return str_append(s);
  case ID_NET_CONNECT: r = tag_int(net_connect(s[0], int_arg(s[1]), int_arg(s[2]))); break;
  case ID_NET_LISTEN: r = tag_int(net_listen(s[0], int_arg(s[1]), int_arg(s[2]))); break;
  case ID_NET_ACCEPT: r = tag_int(os_accept(int_arg(s[0]), wait_limit(int_arg(s[1])))); break;
  case ID_NET_SEND: r = tag_int(net_send(int_arg(s[0]), s[1], int_arg(s[2]))); break;
  case ID_NET_RECV_INTO: r = tag_int(net_recv_into(s)); break;
  case ID_NET_RECV: r = net_recv(int_arg(s[0]), int_arg(s[1]), int_arg(s[2])); break;
  case ID_NET_SHUTDOWN: r = tag_int(os_shutdown(int_arg(s[0]), int_arg(s[1]))); break;
  case ID_NET_OPTION: r = tag_int(net_option(int_arg(s[0]), s[1], int_arg(s[2]))); break;
  case ID_NET_LOCAL_PORT: r = tag_int(os_name(int_arg(s[0]), 0)); break;
  case ID_NET_PEER_IP: r = net_peer_ip(int_arg(s[0])); break;
  case ID_NET_RESOLVE: r = net_resolve(s[0]); break;
  case ID_UNLINK: case ID_RMDIR: case ID_RENAME: r = tag_int(path_call(id, s[0], count > 1 ? s[1] : 0)); break;
  case ID_TO_WORDS: r = u8_to_words(s[0]); break;
  case ID_READ_BYTES: r = read_bytes(s[0]); break;
  case ID_WRITE_BYTES: r = write_bytes(s[0], s[1]); break;
  case ID_READ_INTO: r = tag_int(fd_io(0, s)); break;
  case ID_WRITE_FROM: r = tag_int(fd_io(1, s)); break;
  case ID_SYS_CALL: r = tag_int(sys_call(s, count)); break;
  case ID_SHA_RAW: { /* String or Tensor[U8] => the 32 raw bytes as a String */
    u8 dg[32];
    i64 v = s[0];
    s[0] = 0;
    sha256_of(v, dg);
    return rt_alloc_str(dg, 32);
  }
  case ID_SHA_DIGEST: { /* String or Tensor[U8] => Tensor[U8 * 32] */
    u8 dg[32];
    i64 v = s[0];
    s[0] = 0;
    sha256_of(v, dg);
    return u8_from_bytes(dg, 32);
  }
  default: break;
  }
  drop_slots(s, count);
  return r;
}
```
