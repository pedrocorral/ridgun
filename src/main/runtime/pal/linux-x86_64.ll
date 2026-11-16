; ============================================================
; src/main/runtime/pal/linux-x86_64.ll
; The PAL for Linux on x86-64 (ADR-0008, ADR-0013, TASK-0096): the same
; contract as pal/wasm32.ll, on raw system calls. Inline assembly appears
; only here. Errors are -errno, as the contract says; Linux already gives
; them in that form.
;
; The program starts at `_start` (module assembly below): it keeps the
; initial stack pointer (for the arguments and the environment), maps the
; first heap chunk and calls `__rg_rt_start` with the four function addresses
; that page 0 of the image holds at 0x400080 (main, spawn, call2, binop).
; ============================================================

module asm ".globl _start"
module asm "_start:"
module asm "  mov %rsp, %rdi"
module asm "  and $-16, %rsp"
module asm "  call __rg_linux_start"
module asm "  ud2"

declare void @rg_copy(i64, i64, i64)
declare void @rg_fill(i64, i8, i64)
declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i64 @__rg_rt_start(i64, i64, i64, i64, i64)

; ── System calls ─────────────────────────────────────────────
define internal i64 @rg_sys(i64 %nr, i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f) alwaysinline {
  %r = call i64 asm sideeffect "syscall", "={rax},{rax},{rdi},{rsi},{rdx},{r10},{r8},{r9},~{rcx},~{r11},~{memory}"(i64 %nr, i64 %a, i64 %b, i64 %c, i64 %d, i64 %e, i64 %f)
  ret i64 %r
}

; ── Start ────────────────────────────────────────────────────
@rg_sp = internal global i64 0
@rg_heap_end = internal global i64 0

; 64 MiB first chunk (mapped lazily by the system).
define void @__rg_linux_start(i64 %sp) noreturn {
  store i64 %sp, ptr @rg_sp, align 8
  ; mmap(0, 64 MiB, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE)
  %m = call i64 @rg_sys(i64 9, i64 0, i64 67108864, i64 3, i64 16418, i64 -1, i64 0)
  %bad = icmp ult i64 %m, -4095
  br i1 %bad, label %ok, label %fail
fail:
  call void @__rg_pal_exit(i64 1)
  unreachable
ok:
  %end = add i64 %m, 67108864
  store i64 %end, ptr @rg_heap_end, align 8
  %main = call i64 @rg_ld(i64 4194432)
  %spawn = call i64 @rg_ld(i64 4194440)
  %call2 = call i64 @rg_ld(i64 4194448)
  %binop = call i64 @rg_ld(i64 4194456)
  %r = call i64 @__rg_rt_start(i64 %m, i64 %main, i64 %spawn, i64 %call2, i64 %binop)
  call void @__rg_pal_exit(i64 0)
  unreachable
}

; ── Input, output, exit, memory ──────────────────────────────
define i64 @__rg_pal_write(i64 %fd, i64 %buf, i64 %len) {
  %r = call i64 @rg_sys(i64 1, i64 %fd, i64 %buf, i64 %len, i64 0, i64 0, i64 0)
  ret i64 %r
}

define i64 @__rg_pal_read(i64 %fd, i64 %buf, i64 %len) {
  %r = call i64 @rg_sys(i64 0, i64 %fd, i64 %buf, i64 %len, i64 0, i64 0, i64 0)
  ret i64 %r
}

define void @__rg_pal_exit(i64 %code) noreturn {
  %r = call i64 @rg_sys(i64 231, i64 %code, i64 0, i64 0, i64 0, i64 0, i64 0)
  unreachable
}

; The end of the first chunk (the heap is initialised with [chunk, end)).
define i64 @__rg_pal_memory_end() {
  %e = load i64, ptr @rg_heap_end, align 8
  ret i64 %e
}

; alloc chunk (bytes): a fresh zeroed region of at least `bytes` bytes, or 0.
define i64 @__rg_pal_alloc_chunk(i64 %bytes) {
  %b = add i64 %bytes, 4095
  %len = and i64 %b, -4096
  %m = call i64 @rg_sys(i64 9, i64 0, i64 %len, i64 3, i64 16418, i64 -1, i64 0)
  %ok = icmp ult i64 %m, -4095
  %r = select i1 %ok, i64 %m, i64 0
  ret i64 %r
}

; LLVM may lower copies to calls of memcpy, memset and memmove.
define ptr @memcpy(ptr %d, ptr %s, i64 %n) {
  %di = ptrtoint ptr %d to i64
  %si = ptrtoint ptr %s to i64
  call void @rg_copy(i64 %di, i64 %si, i64 %n)
  ret ptr %d
}

define ptr @memmove(ptr %d, ptr %s, i64 %n) {
  %r = call ptr @memcpy(ptr %d, ptr %s, i64 %n)
  ret ptr %r
}

define ptr @memset(ptr %d, i32 %v, i64 %n) {
  %di = ptrtoint ptr %d to i64
  %b = trunc i32 %v to i8
  call void @rg_fill(i64 %di, i8 %b, i64 %n)
  ret ptr %d
}

; ── Clocks and sleep ─────────────────────────────────────────
; clock ns (kind): 0 the monotonic clock, 1 the wall clock, in ns.
define i64 @__rg_pal_clock_ns(i64 %kind) {
  %ts = alloca [2 x i64], align 8
  %wall = icmp ne i64 %kind, 0
  %id = select i1 %wall, i64 0, i64 1
  %a = ptrtoint ptr %ts to i64
  %e = call i64 @rg_sys(i64 228, i64 %id, i64 %a, i64 0, i64 0, i64 0, i64 0)
  %sp = getelementptr inbounds [2 x i64], ptr %ts, i64 0, i64 0
  %ns = getelementptr inbounds [2 x i64], ptr %ts, i64 0, i64 1
  %s = load i64, ptr %sp, align 8
  %n = load i64, ptr %ns, align 8
  %sec = mul i64 %s, 1000000000
  %t = add i64 %sec, %n
  ret i64 %t
}

; sleep ns (ns): waits, and continues after an interruption.
define void @__rg_pal_sleep_ns(i64 %ns) {
entry:
  %req = alloca [2 x i64], align 8
  %rem = alloca [2 x i64], align 8
  %pos = icmp sgt i64 %ns, 0
  br i1 %pos, label %go, label %done
go:
  %s = udiv i64 %ns, 1000000000
  %n = urem i64 %ns, 1000000000
  %r0 = getelementptr inbounds [2 x i64], ptr %req, i64 0, i64 0
  %r1 = getelementptr inbounds [2 x i64], ptr %req, i64 0, i64 1
  store i64 %s, ptr %r0, align 8
  store i64 %n, ptr %r1, align 8
  br label %wait
wait:
  %rq = phi ptr [ %req, %go ], [ %rem, %again ]
  %a = ptrtoint ptr %rq to i64
  %b = ptrtoint ptr %rem to i64
  %e = call i64 @rg_sys(i64 35, i64 %a, i64 %b, i64 0, i64 0, i64 0, i64 0)
  %intr = icmp eq i64 %e, -4
  br i1 %intr, label %again, label %done
again:
  br label %wait
done:
  ret void
}

; ── Arguments and environment ────────────────────────────────
; The strings from the array of pointers at `arr` (ending in 0): the bytes
; they need with their NUL bytes, written one after the other at buf when
; they fit in cap.
define internal i64 @rg_pack(i64 %arr, i64 %buf, i64 %cap) {
entry:
  br label %size
size:
  %i = phi i64 [ 0, %entry ], [ %i2, %size_next ]
  %tot = phi i64 [ 0, %entry ], [ %tot2, %size_next ]
  %slot = add i64 %arr, %i
  %p = call i64 @rg_ld(i64 %slot)
  %end = icmp eq i64 %p, 0
  br i1 %end, label %decide, label %measure
measure:
  %l = call i64 @rg_cstrlen(i64 %p)
  %l1 = add i64 %l, 1
  %tot2 = add i64 %tot, %l1
  br label %size_next
size_next:
  %i2 = add i64 %i, 8
  br label %size
decide:
  %fits = icmp sle i64 %tot, %cap
  br i1 %fits, label %write, label %out
write:
  br label %wloop
wloop:
  %j = phi i64 [ 0, %write ], [ %j2, %wcopy ]
  %off = phi i64 [ 0, %write ], [ %off2, %wcopy ]
  %wslot = add i64 %arr, %j
  %wp = call i64 @rg_ld(i64 %wslot)
  %wend = icmp eq i64 %wp, 0
  br i1 %wend, label %out, label %wcopy
wcopy:
  %wl = call i64 @rg_cstrlen(i64 %wp)
  %wl1 = add i64 %wl, 1
  %dst = add i64 %buf, %off
  call void @rg_copy(i64 %dst, i64 %wp, i64 %wl1)
  %off2 = add i64 %off, %wl1
  %j2 = add i64 %j, 8
  br label %wloop
out:
  ret i64 %tot
}

define internal i64 @rg_cstrlen(i64 %p) {
entry:
  br label %loop
loop:
  %n = phi i64 [ 0, %entry ], [ %n2, %loop ]
  %a = add i64 %p, %n
  %b = call i64 @rg_ldb(i64 %a)
  %n2 = add i64 %n, 1
  %z = icmp eq i64 %b, 0
  br i1 %z, label %done, label %loop
done:
  ret i64 %n
}

declare i64 @rg_ldb(i64)

define i64 @__rg_pal_args(i64 %buf, i64 %cap) {
  %sp = load i64, ptr @rg_sp, align 8
  %argv = add i64 %sp, 8
  %r = call i64 @rg_pack(i64 %argv, i64 %buf, i64 %cap)
  ret i64 %r
}

define i64 @__rg_pal_env(i64 %buf, i64 %cap) {
entry:
  %sp = load i64, ptr @rg_sp, align 8
  %argc = call i64 @rg_ld(i64 %sp)
  %n8 = shl i64 %argc, 3
  %envp0 = add i64 %sp, %n8
  %envp = add i64 %envp0, 16
  %r = call i64 @rg_pack(i64 %envp, i64 %buf, i64 %cap)
  ret i64 %r
}

; ── Files and folders ────────────────────────────────────────
; A NUL-terminated copy of path (p, n) in dst (4096 bytes): 0, or -36.
define internal i64 @rg_cpath(i64 %p, i64 %n, i64 %dst) {
entry:
  %long = icmp sge i64 %n, 4096
  br i1 %long, label %fail, label %ok
fail:
  ret i64 -36
ok:
  call void @rg_copy(i64 %dst, i64 %p, i64 %n)
  %end = add i64 %dst, %n
  call void @rg_fill(i64 %end, i8 0, i64 1)
  ret i64 0
}

; open (path, length, flags, mode): a file descriptor or -errno. Flags as on
; Linux: access 0 read, 1 write, 2 both; 64 create, 128 exclusive, 512
; truncate, 1024 append, 2048 non-blocking, 65536 directory.
define i64 @__rg_pal_open(i64 %p, i64 %n, i64 %flags, i64 %mode) {
entry:
  %buf = alloca [4096 x i8], align 8
  %d = ptrtoint ptr %buf to i64
  %r = call i64 @rg_cpath(i64 %p, i64 %n, i64 %d)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %fl = or i64 %flags, 524288
  %fd = call i64 @rg_sys(i64 2, i64 %d, i64 %fl, i64 %mode, i64 0, i64 0, i64 0)
  ret i64 %fd
}

define i64 @__rg_pal_close(i64 %fd) {
  %r = call i64 @rg_sys(i64 3, i64 %fd, i64 0, i64 0, i64 0, i64 0, i64 0)
  ret i64 %r
}

; One-path system calls: mkdir (83, mode), rmdir (84), unlink (87), chdir (80).
define internal i64 @rg_path1(i64 %nr, i64 %p, i64 %n, i64 %arg) {
entry:
  %buf = alloca [4096 x i8], align 8
  %d = ptrtoint ptr %buf to i64
  %r = call i64 @rg_cpath(i64 %p, i64 %n, i64 %d)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %x = call i64 @rg_sys(i64 %nr, i64 %d, i64 %arg, i64 0, i64 0, i64 0, i64 0)
  ret i64 %x
}

define i64 @__rg_pal_mkdir(i64 %p, i64 %n, i64 %mode) {
  %r = call i64 @rg_path1(i64 83, i64 %p, i64 %n, i64 %mode)
  ret i64 %r
}

define i64 @__rg_pal_rmdir(i64 %p, i64 %n) {
  %r = call i64 @rg_path1(i64 84, i64 %p, i64 %n, i64 0)
  ret i64 %r
}

define i64 @__rg_pal_unlink(i64 %p, i64 %n) {
  %r = call i64 @rg_path1(i64 87, i64 %p, i64 %n, i64 0)
  ret i64 %r
}

define i64 @__rg_pal_chdir(i64 %p, i64 %n) {
  %r = call i64 @rg_path1(i64 80, i64 %p, i64 %n, i64 0)
  ret i64 %r
}

define i64 @__rg_pal_rename(i64 %p, i64 %n, i64 %q, i64 %m) {
entry:
  %b1 = alloca [4096 x i8], align 8
  %b2 = alloca [4096 x i8], align 8
  %d1 = ptrtoint ptr %b1 to i64
  %d2 = ptrtoint ptr %b2 to i64
  %r1 = call i64 @rg_cpath(i64 %p, i64 %n, i64 %d1)
  %bad1 = icmp ne i64 %r1, 0
  br i1 %bad1, label %fail1, label %second
fail1:
  ret i64 %r1
second:
  %r2 = call i64 @rg_cpath(i64 %q, i64 %m, i64 %d2)
  %bad2 = icmp ne i64 %r2, 0
  br i1 %bad2, label %fail2, label %go
fail2:
  ret i64 %r2
go:
  %x = call i64 @rg_sys(i64 82, i64 %d1, i64 %d2, i64 0, i64 0, i64 0, i64 0)
  ret i64 %x
}

; stat (path, length, out): 0 or -errno. Does not follow a final symlink.
; out[0] kind (1 file, 2 folder, 3 link, 4 fifo, 5 socket, 6 block, 7 char,
; 0 unknown), out[1] links, out[2] size, out[3] mtime (s), out[4] mode bits.
define i64 @__rg_pal_stat(i64 %p, i64 %n, i64 %out) {
entry:
  %buf = alloca [4096 x i8], align 8
  %st = alloca [18 x i64], align 8
  %d = ptrtoint ptr %buf to i64
  %s = ptrtoint ptr %st to i64
  %r = call i64 @rg_cpath(i64 %p, i64 %n, i64 %d)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %e = call i64 @rg_sys(i64 6, i64 %d, i64 %s, i64 0, i64 0, i64 0, i64 0)
  %err = icmp ne i64 %e, 0
  br i1 %err, label %werr, label %fill
werr:
  ret i64 %e
fill:
  ; struct stat: st_nlink at 16 (8 bytes), st_mode at 24 (4 bytes),
  ; st_size at 48, st_mtime at 88.
  %a16 = add i64 %s, 16
  %nl = call i64 @rg_ld(i64 %a16)
  %a24 = add i64 %s, 24
  %mw = call i64 @rg_ld(i64 %a24)
  %mode = and i64 %mw, 4294967295
  %a48 = add i64 %s, 48
  %size = call i64 @rg_ld(i64 %a48)
  %a88 = add i64 %s, 88
  %mt = call i64 @rg_ld(i64 %a88)
  %ft = and i64 %mode, 61440
  %kind = call i64 @rg_kind(i64 %ft)
  %bits = and i64 %mode, 4095
  call void @rg_st(i64 %out, i64 %kind)
  %o1 = add i64 %out, 8
  call void @rg_st(i64 %o1, i64 %nl)
  %o2 = add i64 %out, 16
  call void @rg_st(i64 %o2, i64 %size)
  %o3 = add i64 %out, 24
  call void @rg_st(i64 %o3, i64 %mt)
  %o4 = add i64 %out, 32
  call void @rg_st(i64 %o4, i64 %bits)
  ret i64 0
}

; The kind of a file from the type bits of its mode.
define internal i64 @rg_kind(i64 %ft) {
entry:
  switch i64 %ft, label %unknown [ i64 32768, label %file
                                   i64 16384, label %dir
                                   i64 40960, label %link
                                   i64 4096, label %fifo
                                   i64 49152, label %sock
                                   i64 24576, label %block
                                   i64 8192, label %char ]
file:
  ret i64 1
dir:
  ret i64 2
link:
  ret i64 3
fifo:
  ret i64 4
sock:
  ret i64 5
block:
  ret i64 6
char:
  ret i64 7
unknown:
  ret i64 0
}

; readlink (path, length, buffer, capacity): the bytes of the target, or -errno.
define i64 @__rg_pal_readlink(i64 %p, i64 %n, i64 %buf, i64 %cap) {
entry:
  %pb = alloca [4096 x i8], align 8
  %d = ptrtoint ptr %pb to i64
  %r = call i64 @rg_cpath(i64 %p, i64 %n, i64 %d)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %x = call i64 @rg_sys(i64 89, i64 %d, i64 %buf, i64 %cap, i64 0, i64 0, i64 0)
  ret i64 %x
}

; list dir (path, length, buffer, capacity): the entry names, each followed
; by a NUL byte, in the order the system gives them ("." and ".." left out).
; The result is the bytes they need; they are written only when they fit.
; -errno when the folder cannot be read.
define i64 @__rg_pal_list_dir(i64 %p, i64 %n, i64 %buf, i64 %cap) {
entry:
  %tmp = alloca [8192 x i8], align 8
  %t = ptrtoint ptr %tmp to i64
  %fd = call i64 @__rg_pal_open(i64 %p, i64 %n, i64 65536, i64 0)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %fail, label %batch
fail:
  ret i64 %fd
batch:
  %need = phi i64 [ 0, %entry ], [ %need2, %nextbatch ]
  %got = call i64 @rg_sys(i64 217, i64 %fd, i64 %t, i64 8192, i64 0, i64 0, i64 0)
  %more = icmp sgt i64 %got, 0
  br i1 %more, label %ent, label %finish
ent:
  %off = phi i64 [ 0, %batch ], [ %off2, %entnext ]
  %need1 = phi i64 [ %need, %batch ], [ %need3, %entnext ]
  %fin = icmp sge i64 %off, %got
  br i1 %fin, label %nextbatch, label %rec
rec:
  %rp = add i64 %t, %off
  %lw = add i64 %rp, 16
  %hw = call i64 @rg_ld(i64 %lw)
  %reclen = and i64 %hw, 65535
  %name = add i64 %rp, 19
  %len = call i64 @rg_cstrlen(i64 %name)
  %dots = call i1 @rg_dots(i64 %name, i64 %len)
  br i1 %dots, label %skip, label %keep
keep:
  %l1 = add i64 %len, 1
  %end = add i64 %need1, %l1
  %fits = icmp sle i64 %end, %cap
  br i1 %fits, label %put, label %count
put:
  %dst = add i64 %buf, %need1
  call void @rg_copy(i64 %dst, i64 %name, i64 %l1)
  br label %count
count:
  br label %entnext
skip:
  br label %entnext
entnext:
  %need3 = phi i64 [ %end, %count ], [ %need1, %skip ]
  %off2 = add i64 %off, %reclen
  br label %ent
nextbatch:
  %need2 = phi i64 [ %need1, %ent ]
  br label %batch
finish:
  %r = call i64 @__rg_pal_close(i64 %fd)
  ret i64 %need
}

define internal i1 @rg_dots(i64 %p, i64 %n) {
entry:
  %one = icmp eq i64 %n, 1
  %two = icmp eq i64 %n, 2
  %b0 = call i64 @rg_ldb(i64 %p)
  %p1 = add i64 %p, 1
  %b1 = call i64 @rg_ldb(i64 %p1)
  %d0 = icmp eq i64 %b0, 46
  %d1 = icmp eq i64 %b1, 46
  %a = and i1 %one, %d0
  %b0d = and i1 %two, %d0
  %b = and i1 %b0d, %d1
  %r = or i1 %a, %b
  ret i1 %r
}

; ── Working directory ────────────────────────────────────────
; getcwd (buffer, capacity): the bytes of the working directory, written
; when they fit; -errno on error.
define i64 @__rg_pal_getcwd(i64 %buf, i64 %cap) {
entry:
  %tmp = alloca [4096 x i8], align 8
  %t = ptrtoint ptr %tmp to i64
  %n = call i64 @rg_sys(i64 79, i64 %t, i64 4096, i64 0, i64 0, i64 0, i64 0)
  %bad = icmp sle i64 %n, 0
  br i1 %bad, label %fail, label %ok
fail:
  ret i64 %n
ok:
  %l = sub i64 %n, 1
  %fits = icmp sle i64 %l, %cap
  br i1 %fits, label %copy, label %done
copy:
  call void @rg_copy(i64 %buf, i64 %t, i64 %l)
  br label %done
done:
  ret i64 %l
}

; poll (fd, events, ms): waits until fd is ready for reading (events 1) or
; writing (events 4), or ms milliseconds pass (ms < 0: no limit). Gives the
; ready event (1 or 4), 0 when the time passed, or -errno. A negative fd
; only waits.
define i64 @__rg_pal_poll(i64 %fd, i64 %events, i64 %ms) {
entry:
  %pfd = alloca [2 x i32], align 4
  %fd32 = trunc i64 %fd to i32
  %w = and i64 %events, 4
  %wr = icmp ne i64 %w, 0
  %ev = select i1 %wr, i16 4, i16 1
  %f0 = getelementptr inbounds [2 x i32], ptr %pfd, i64 0, i64 0
  store i32 %fd32, ptr %f0, align 4
  %f1 = getelementptr inbounds [2 x i32], ptr %pfd, i64 0, i64 1
  %ev32 = zext i16 %ev to i32
  store i32 %ev32, ptr %f1, align 4
  %a = ptrtoint ptr %pfd to i64
  %hasfd = icmp sge i64 %fd, 0
  %n = select i1 %hasfd, i64 1, i64 0
  br label %wait
wait:
  %r = call i64 @rg_sys(i64 7, i64 %a, i64 %n, i64 %ms, i64 0, i64 0, i64 0)
  %intr = icmp eq i64 %r, -4
  br i1 %intr, label %wait, label %done
done:
  %neg = icmp slt i64 %r, 0
  br i1 %neg, label %out, label %ready
ready:
  %any = icmp sgt i64 %r, 0
  %res = select i1 %any, i64 %w, i64 0
  %rd = icmp eq i64 %w, 0
  %fixed = select i1 %any, i64 1, i64 0
  %final = select i1 %wr, i64 %res, i64 %fixed
  ret i64 %final
out:
  ret i64 %r
}

; ── trunc ────────────────────────────────────────────────────
; llc lowers @llvm.trunc.f64 to a call of `trunc` on x86-64 without SSE4.1.
; The runtime has no C library: truncation on the bits of the double
; (exponent e: the low 52 - e bits of the fraction are cleared).
define double @trunc(double %x) {
entry:
  %b = bitcast double %x to i64
  %ex = lshr i64 %b, 52
  %e11 = and i64 %ex, 2047
  %e = sub i64 %e11, 1023
  %small = icmp slt i64 %e, 0
  br i1 %small, label %tozero, label %check
tozero:
  %sign = and i64 %b, -9223372036854775808
  %z = bitcast i64 %sign to double
  ret double %z
check:
  %big = icmp sge i64 %e, 52
  br i1 %big, label %same, label %cut
same:
  ret double %x
cut:
  %sh = sub i64 52, %e
  %one = shl i64 1, %sh
  %low = sub i64 %one, 1
  %mask = xor i64 %low, -1
  %r = and i64 %b, %mask
  %d = bitcast i64 %r to double
  ret double %d
}
