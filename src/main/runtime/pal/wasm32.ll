; ============================================================
; src/main/runtime/pal/wasm32.ll
; The PAL for wasm32 (ADR-0008, ADR-0013): every system operation the
; runtime needs, as functions of i64 words. System calls are imports of WASI
; (wasi_snapshot_preview1), which every wasm host offers: wasmtime, Node,
; wasm-interp --wasi, and a small shim in the browser (TASK-0089). Memory
; comes from memory.grow.
; ============================================================

declare i32 @llvm.wasm.memory.grow.i32(i32, i32)
declare i32 @llvm.wasm.memory.size.i32(i32)

declare i32 @wasi_fd_write(i32, i32, i32, i32) #0
declare i32 @wasi_fd_read(i32, i32, i32, i32) #1
declare void @wasi_proc_exit(i32) #2

attributes #0 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_write" }
attributes #1 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_read" }
attributes #2 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="proc_exit" noreturn }

declare i32 @wasi_clock_time_get(i32, i64, i32) #3
declare i32 @wasi_poll_oneoff(i32, i32, i32, i32) #4
declare i32 @wasi_args_sizes_get(i32, i32) #5
declare i32 @wasi_args_get(i32, i32) #6
declare i32 @wasi_environ_sizes_get(i32, i32) #7
declare i32 @wasi_environ_get(i32, i32) #8
declare i32 @wasi_fd_prestat_get(i32, i32) #9
declare i32 @wasi_fd_prestat_dir_name(i32, i32, i32) #10
declare i32 @wasi_path_open(i32, i32, i32, i32, i32, i64, i64, i32, i32) #11
declare i32 @wasi_fd_close(i32) #12
declare i32 @wasi_path_filestat_get(i32, i32, i32, i32, i32) #13
declare i32 @wasi_path_readlink(i32, i32, i32, i32, i32, i32) #14
declare i32 @wasi_fd_readdir(i32, i32, i32, i64, i32) #15
declare i32 @wasi_path_create_directory(i32, i32, i32) #16
declare i32 @wasi_path_remove_directory(i32, i32, i32) #17
declare i32 @wasi_path_unlink_file(i32, i32, i32) #18
declare i32 @wasi_path_rename(i32, i32, i32, i32, i32, i32) #19

attributes #3 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="clock_time_get" }
attributes #4 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="poll_oneoff" }
attributes #5 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="args_sizes_get" }
attributes #6 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="args_get" }
attributes #7 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="environ_sizes_get" }
attributes #8 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="environ_get" }
attributes #9 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_prestat_get" }
attributes #10 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_prestat_dir_name" }
attributes #11 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="path_open" }
attributes #12 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_close" }
attributes #13 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="path_filestat_get" }
attributes #14 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="path_readlink" }
attributes #15 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_readdir" }
attributes #16 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="path_create_directory" }
attributes #17 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="path_remove_directory" }
attributes #18 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="path_unlink_file" }
attributes #19 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="path_rename" }

; One iovec and the count WASI writes back (the runtime runs on one thread).
@rg_iov = internal global [2 x i32] zeroinitializer
@rg_iocount = internal global i32 0

define internal i64 @rg_io(i1 %is_write, i64 %fd, i64 %buf, i64 %len) {
entry:
  %b32 = trunc i64 %buf to i32
  %l32 = trunc i64 %len to i32
  store i32 %b32, ptr @rg_iov, align 4
  %lp = getelementptr inbounds [2 x i32], ptr @rg_iov, i32 0, i32 1
  store i32 %l32, ptr %lp, align 4
  %fd32 = trunc i64 %fd to i32
  %iov = ptrtoint ptr @rg_iov to i32
  %cnt = ptrtoint ptr @rg_iocount to i32
  br i1 %is_write, label %w, label %r
w:
  %ew = call i32 @wasi_fd_write(i32 %fd32, i32 %iov, i32 1, i32 %cnt)
  br label %done
r:
  %er = call i32 @wasi_fd_read(i32 %fd32, i32 %iov, i32 1, i32 %cnt)
  br label %done
done:
  %e = phi i32 [ %ew, %w ], [ %er, %r ]
  %bad = icmp ne i32 %e, 0
  %n = load i32, ptr @rg_iocount, align 4
  %n64 = zext i32 %n to i64
  %neg = call i64 @rg_errno(i32 %e)
  %res = select i1 %bad, i64 %neg, i64 %n64
  ret i64 %res
}

; write (fd, address, length): the bytes written, or a negative error.
define i64 @__rg_pal_write(i64 %fd, i64 %buf, i64 %len) {
  %r = call i64 @rg_io(i1 true, i64 %fd, i64 %buf, i64 %len)
  ret i64 %r
}

; read (fd, address, length): the bytes read (0 at the end), or a negative error.
define i64 @__rg_pal_read(i64 %fd, i64 %buf, i64 %len) {
  %r = call i64 @rg_io(i1 false, i64 %fd, i64 %buf, i64 %len)
  ret i64 %r
}

; exit (code): ends the program.
define void @__rg_pal_exit(i64 %code) noreturn {
  %c32 = trunc i64 %code to i32
  call void @wasi_proc_exit(i32 %c32)
  unreachable
}

; memory end: the address just past the memory the program may use now.
define i64 @__rg_pal_memory_end() {
  %pages = call i32 @llvm.wasm.memory.size.i32(i32 0)
  %p64 = zext i32 %pages to i64
  %end = shl i64 %p64, 16
  ret i64 %end
}

; alloc chunk (bytes): a fresh zeroed region of at least `bytes` bytes, or 0
; when there is no memory left. On wasm32 it grows the memory at its end.
define i64 @__rg_pal_alloc_chunk(i64 %bytes) {
entry:
  %b = add i64 %bytes, 65535
  %pages = lshr i64 %b, 16
  %p32 = trunc i64 %pages to i32
  %old = call i32 @llvm.wasm.memory.grow.i32(i32 0, i32 %p32)
  %fail = icmp eq i32 %old, -1
  br i1 %fail, label %none, label %ok
none:
  ret i64 0
ok:
  %o64 = zext i32 %old to i64
  %addr = shl i64 %o64, 16
  ret i64 %addr
}

; LLVM may lower copies to calls of memcpy, memset and memmove (size_t is
; i32 here): give them, on the runtime's own loops.
declare void @rg_copy(i64, i64, i64)
declare void @rg_fill(i64, i8, i64)
declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)

define ptr @memcpy(ptr %d, ptr %s, i32 %n) {
  %di = ptrtoint ptr %d to i64
  %si = ptrtoint ptr %s to i64
  %n64 = zext i32 %n to i64
  call void @rg_copy(i64 %di, i64 %si, i64 %n64)
  ret ptr %d
}

define ptr @memmove(ptr %d, ptr %s, i32 %n) {
  %r = call ptr @memcpy(ptr %d, ptr %s, i32 %n)
  ret ptr %r
}

define ptr @memset(ptr %d, i32 %v, i32 %n) {
  %di = ptrtoint ptr %d to i64
  %b = trunc i32 %v to i8
  %n64 = zext i32 %n to i64
  call void @rg_fill(i64 %di, i8 %b, i64 %n64)
  ret ptr %d
}

; ── Errors ───────────────────────────────────────────────────
; The PAL gives errors as Linux numbers (-errno), on every target. WASI has
; its own numbers: rg_errno turns a WASI error into -errno.
define internal i64 @rg_errno(i32 %e) {
entry:
  switch i32 %e, label %other [ i32 0, label %zero
                                i32 2, label %acces
                                i32 8, label %badf
                                i32 10, label %busy
                                i32 20, label %exist
                                i32 28, label %inval
                                i32 29, label %io
                                i32 31, label %isdir
                                i32 44, label %noent
                                i32 48, label %nomem
                                i32 51, label %nospc
                                i32 52, label %nosys
                                i32 54, label %notdir
                                i32 55, label %notempty
                                i32 58, label %notsup
                                i32 63, label %perm
                                i32 64, label %pipe
                                i32 6, label %again
                                i32 37, label %loop ]
zero:
  ret i64 0
acces:
  ret i64 -13
badf:
  ret i64 -9
busy:
  ret i64 -16
exist:
  ret i64 -17
inval:
  ret i64 -22
io:
  ret i64 -5
isdir:
  ret i64 -21
noent:
  ret i64 -2
nomem:
  ret i64 -12
nospc:
  ret i64 -28
nosys:
  ret i64 -38
notdir:
  ret i64 -20
notempty:
  ret i64 -39
notsup:
  ret i64 -95
perm:
  ret i64 -1
pipe:
  ret i64 -32
again:
  ret i64 -11
loop:
  ret i64 -40
other:
  ret i64 -5
}

; ── Clocks and sleep ─────────────────────────────────────────
@rg_tbuf = internal global i64 0

; clock ns (kind): 0 the monotonic clock, 1 the wall clock, in ns.
define i64 @__rg_pal_clock_ns(i64 %kind) {
  %wall = icmp ne i64 %kind, 0
  %id = select i1 %wall, i32 0, i32 1
  %a = ptrtoint ptr @rg_tbuf to i32
  %e = call i32 @wasi_clock_time_get(i32 %id, i64 1000, i32 %a)
  %t = load i64, ptr @rg_tbuf, align 8
  ret i64 %t
}

; sleep ns (ns): waits on a relative clock subscription.
@rg_sub = internal global [6 x i64] zeroinitializer
@rg_evt = internal global [4 x i64] zeroinitializer
@rg_nevt = internal global i32 0

define void @__rg_pal_sleep_ns(i64 %ns) {
entry:
  %pos = icmp sgt i64 %ns, 0
  br i1 %pos, label %go, label %done
go:
  ; userdata 0, tag 0 (clock), clock id 1 (monotonic), timeout, precision, flags 0
  %p0 = getelementptr inbounds [6 x i64], ptr @rg_sub, i32 0, i32 0
  store i64 0, ptr %p0, align 8
  %p1 = getelementptr inbounds [6 x i64], ptr @rg_sub, i32 0, i32 1
  store i64 0, ptr %p1, align 8
  %p2 = getelementptr inbounds [6 x i64], ptr @rg_sub, i32 0, i32 2
  store i64 1, ptr %p2, align 8
  %p3 = getelementptr inbounds [6 x i64], ptr @rg_sub, i32 0, i32 3
  store i64 %ns, ptr %p3, align 8
  %p4 = getelementptr inbounds [6 x i64], ptr @rg_sub, i32 0, i32 4
  store i64 1000, ptr %p4, align 8
  %p5 = getelementptr inbounds [6 x i64], ptr @rg_sub, i32 0, i32 5
  store i64 0, ptr %p5, align 8
  %si = ptrtoint ptr @rg_sub to i32
  %ei = ptrtoint ptr @rg_evt to i32
  %ni = ptrtoint ptr @rg_nevt to i32
  %e = call i32 @wasi_poll_oneoff(i32 %si, i32 %ei, i32 1, i32 %ni)
  br label %done
done:
  ret void
}

; ── Arguments and environment ────────────────────────────────
; args (buffer, capacity) and env (buffer, capacity): the bytes the
; NUL-terminated strings need; when they fit, they are written one after the
; other at buffer (arguments from argv[0]; environment entries as KEY=VALUE).
@rg_cnt = internal global [2 x i32] zeroinitializer

declare i64 @rg_alloc(i64)
declare void @rg_free(i64)

define internal i64 @rg_strings(i1 %env, i64 %buf, i64 %cap) {
entry:
  %c = ptrtoint ptr @rg_cnt to i32
  %c4 = add i32 %c, 4
  br i1 %env, label %es, label %as
es:
  %e1 = call i32 @wasi_environ_sizes_get(i32 %c, i32 %c4)
  br label %sized
as:
  %e2 = call i32 @wasi_args_sizes_get(i32 %c, i32 %c4)
  br label %sized
sized:
  %e = phi i32 [ %e1, %es ], [ %e2, %as ]
  %bad = icmp ne i32 %e, 0
  br i1 %bad, label %none, label %ok
none:
  ret i64 0
ok:
  %n = load i32, ptr @rg_cnt, align 4
  %szp = getelementptr inbounds [2 x i32], ptr @rg_cnt, i32 0, i32 1
  %sz = load i32, ptr %szp, align 4
  %sz64 = zext i32 %sz to i64
  %fits = icmp sle i64 %sz64, %cap
  br i1 %fits, label %get, label %size
size:
  ret i64 %sz64
get:
  %n64 = zext i32 %n to i64
  %pb = shl i64 %n64, 2
  %pb8 = add i64 %pb, 8
  %ptrs = call i64 @rg_alloc(i64 %pb8)
  %p32 = trunc i64 %ptrs to i32
  %b32 = trunc i64 %buf to i32
  br i1 %env, label %eg, label %ag
eg:
  %g1 = call i32 @wasi_environ_get(i32 %p32, i32 %b32)
  br label %got
ag:
  %g2 = call i32 @wasi_args_get(i32 %p32, i32 %b32)
  br label %got
got:
  call void @rg_free(i64 %ptrs)
  ret i64 %sz64
}

define i64 @__rg_pal_args(i64 %buf, i64 %cap) {
  %r = call i64 @rg_strings(i1 false, i64 %buf, i64 %cap)
  ret i64 %r
}

define i64 @__rg_pal_env(i64 %buf, i64 %cap) {
  %r = call i64 @rg_strings(i1 true, i64 %buf, i64 %cap)
  ret i64 %r
}

; ── Paths ────────────────────────────────────────────────────
; WASI opens files relative to directories the host gives at start
; (preopens). The PAL finds the preopen named "/" and the one named "."
; once. A path is resolved as follows: an absolute path, or any path after a
; chdir, goes to "/" without its leading slashes; a relative path goes to
; "."; with no "." it is made absolute with the working directory.
@rg_pre_root = internal global i32 -2
@rg_pre_dot = internal global i32 -2
@rg_pstat = internal global [2 x i32] zeroinitializer
@rg_pname = internal global [8 x i8] zeroinitializer
; the working directory after a chdir (empty: the host's)
@rg_cwd = internal global [4096 x i8] zeroinitializer
@rg_cwd_len = internal global i64 0
; the resolved path: directory fd, address, length
@rg_rfd = internal global i32 0
@rg_rpath = internal global [4096 x i8] zeroinitializer
@rg_rlen = internal global i32 0

define internal void @rg_find_preopens() {
entry:
  %r0 = load i32, ptr @rg_pre_root, align 4
  %done0 = icmp ne i32 %r0, -2
  br i1 %done0, label %out, label %init
init:
  store i32 -1, ptr @rg_pre_root, align 4
  store i32 -1, ptr @rg_pre_dot, align 4
  br label %loop
loop:
  %fd = phi i32 [ 3, %init ], [ %fd1, %next ]
  %more = icmp slt i32 %fd, 64
  br i1 %more, label %body, label %out
body:
  %ps = ptrtoint ptr @rg_pstat to i32
  %e = call i32 @wasi_fd_prestat_get(i32 %fd, i32 %ps)
  %bad = icmp ne i32 %e, 0
  br i1 %bad, label %out, label %name
name:
  %lp = getelementptr inbounds [2 x i32], ptr @rg_pstat, i32 0, i32 1
  %len = load i32, ptr %lp, align 4
  %small = icmp ule i32 %len, 2
  br i1 %small, label %read, label %next
read:
  store i64 0, ptr @rg_pname, align 8
  %pn = ptrtoint ptr @rg_pname to i32
  %e2 = call i32 @wasi_fd_prestat_dir_name(i32 %fd, i32 %pn, i32 %len)
  %c0 = load i8, ptr @rg_pname, align 1
  %c1p = getelementptr inbounds [8 x i8], ptr @rg_pname, i32 0, i32 1
  %c1 = load i8, ptr %c1p, align 1
  %slash = icmp eq i8 %c0, 47
  %dot = icmp eq i8 %c0, 46
  %one = icmp eq i32 %len, 1
  %c1slash = icmp eq i8 %c1, 47
  %dotslash = and i1 %dot, %c1slash
  %isroot = and i1 %slash, %one
  %isdot1 = and i1 %dot, %one
  %isdot = or i1 %isdot1, %dotslash
  %rprev = load i32, ptr @rg_pre_root, align 4
  %rnone = icmp eq i32 %rprev, -1
  %setr = and i1 %isroot, %rnone
  %rnew = select i1 %setr, i32 %fd, i32 %rprev
  store i32 %rnew, ptr @rg_pre_root, align 4
  %dprev = load i32, ptr @rg_pre_dot, align 4
  %dnone = icmp eq i32 %dprev, -1
  %setd = and i1 %isdot, %dnone
  %dnew = select i1 %setd, i32 %fd, i32 %dprev
  store i32 %dnew, ptr @rg_pre_dot, align 4
  br label %next
next:
  %fd1 = add i32 %fd, 1
  br label %loop
out:
  ret void
}


; Append n bytes at src to the resolved path; false when it does not fit.
define internal i1 @rg_rput(i64 %src, i64 %n) {
entry:
  %l = load i32, ptr @rg_rlen, align 4
  %l64 = zext i32 %l to i64
  %e = add i64 %l64, %n
  %fit = icmp sle i64 %e, 4096
  br i1 %fit, label %put, label %no
put:
  %base = ptrtoint ptr @rg_rpath to i64
  %d = add i64 %base, %l64
  call void @rg_copy(i64 %d, i64 %src, i64 %n)
  %e32 = trunc i64 %e to i32
  store i32 %e32, ptr @rg_rlen, align 4
  ret i1 true
no:
  ret i1 false
}

; The working directory of the host: PWD from the environment, or "/".
@rg_slash = private constant [1 x i8] c"/"
@rg_pwd = private constant [4 x i8] c"PWD="

; Append the host's working directory (no trailing slash) to the resolved path.
define internal void @rg_put_host_cwd() {
entry:
  %need = call i64 @__rg_pal_env(i64 0, i64 0)
  %has = icmp sgt i64 %need, 0
  br i1 %has, label %get, label %root
get:
  %buf = call i64 @rg_alloc(i64 %need)
  %got = call i64 @__rg_pal_env(i64 %buf, i64 %need)
  %end = add i64 %buf, %need
  br label %scan
scan:
  %p = phi i64 [ %buf, %get ], [ %pn, %skip ]
  %more = icmp ult i64 %p, %end
  br i1 %more, label %test, label %freeroot
test:
  %pp = inttoptr i64 %p to ptr
  %m = call i1 @rg_prefix(ptr %pp, ptr @rg_pwd, i64 4)
  br i1 %m, label %found, label %skip
skip:
  %z = call i64 @rg_cstrlen(i64 %p)
  %pn0 = add i64 %p, %z
  %pn = add i64 %pn0, 1
  br label %scan
found:
  %v = add i64 %p, 4
  %vl = call i64 @rg_cstrlen(i64 %v)
  %ok = call i1 @rg_rput(i64 %v, i64 %vl)
  call void @rg_free(i64 %buf)
  ret void
freeroot:
  call void @rg_free(i64 %buf)
  br label %root
root:
  %s = ptrtoint ptr @rg_slash to i64
  %ok2 = call i1 @rg_rput(i64 %s, i64 1)
  ret void
}

define internal i1 @rg_prefix(ptr %a, ptr %b, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %eq ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %yes
body:
  %pa = getelementptr inbounds i8, ptr %a, i64 %i
  %pb = getelementptr inbounds i8, ptr %b, i64 %i
  %ca = load i8, ptr %pa, align 1
  %cb = load i8, ptr %pb, align 1
  %e = icmp eq i8 %ca, %cb
  %i1 = add i64 %i, 1
  br i1 %e, label %eq, label %no
eq:
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

define internal i64 @rg_cstrlen(i64 %p) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %a = add i64 %p, %i
  %ap = inttoptr i64 %a to ptr
  %c = load i8, ptr %ap, align 1
  %i1 = add i64 %i, 1
  %z = icmp eq i8 %c, 0
  br i1 %z, label %done, label %loop
done:
  ret i64 %i
}

; Resolve the path (p, n) into rg_rfd / rg_rpath / rg_rlen; 0 or -errno.
define internal i64 @rg_resolve(i64 %p, i64 %n) {
entry:
  call void @rg_find_preopens()
  store i32 0, ptr @rg_rlen, align 4
  %root = load i32, ptr @rg_pre_root, align 4
  %dotfd = load i32, ptr @rg_pre_dot, align 4
  %pp = inttoptr i64 %p to ptr
  %c0 = load i8, ptr %pp, align 1
  %nz = icmp sgt i64 %n, 0
  %sl = icmp eq i8 %c0, 47
  %abs = and i1 %nz, %sl
  %cwdl = load i64, ptr @rg_cwd_len, align 8
  %moved = icmp sgt i64 %cwdl, 0
  br i1 %abs, label %absolute, label %relative
relative:
  br i1 %moved, label %joincwd, label %rel_host
rel_host:
  %hasdot = icmp sge i32 %dotfd, 0
  br i1 %hasdot, label %todot, label %joinhost
todot:
  store i32 %dotfd, ptr @rg_rfd, align 4
  %okd = call i1 @rg_rput(i64 %p, i64 %n)
  br i1 %okd, label %fixempty, label %toolong
joincwd:
  %cw = ptrtoint ptr @rg_cwd to i64
  %ok1 = call i1 @rg_rput(i64 %cw, i64 %cwdl)
  br label %joinrest
joinhost:
  call void @rg_put_host_cwd()
  br label %joinrest
joinrest:
  %s = ptrtoint ptr @rg_slash to i64
  %ok2 = call i1 @rg_rput(i64 %s, i64 1)
  %ok3 = call i1 @rg_rput(i64 %p, i64 %n)
  br i1 %ok3, label %fromroot, label %toolong
absolute:
  %ok4 = call i1 @rg_rput(i64 %p, i64 %n)
  br i1 %ok4, label %fromroot, label %toolong
fromroot:
  %hasroot = icmp sge i32 %root, 0
  br i1 %hasroot, label %strip, label %noroot
noroot:
  ret i64 -13
strip:
  store i32 %root, ptr @rg_rfd, align 4
  ; drop the leading slashes of rg_rpath
  %len = load i32, ptr @rg_rlen, align 4
  br label %sloop
sloop:
  %k = phi i32 [ 0, %strip ], [ %k1, %sbody ]
  %inr = icmp slt i32 %k, %len
  br i1 %inr, label %stest, label %sdone
stest:
  %kp = getelementptr inbounds [4096 x i8], ptr @rg_rpath, i32 0, i32 %k
  %kc = load i8, ptr %kp, align 1
  %isl = icmp eq i8 %kc, 47
  br i1 %isl, label %sbody, label %sdone
sbody:
  %k1 = add i32 %k, 1
  br label %sloop
sdone:
  %nl = sub i32 %len, %k
  %base = ptrtoint ptr @rg_rpath to i64
  %k64 = zext i32 %k to i64
  %src = add i64 %base, %k64
  %nl64 = zext i32 %nl to i64
  call void @rg_copy(i64 %base, i64 %src, i64 %nl64)
  store i32 %nl, ptr @rg_rlen, align 4
  br label %fixempty
fixempty:
  %fl = load i32, ptr @rg_rlen, align 4
  %empty = icmp eq i32 %fl, 0
  br i1 %empty, label %dot, label %ok
dot:
  store i8 46, ptr @rg_rpath, align 1
  store i32 1, ptr @rg_rlen, align 4
  br label %ok
ok:
  ret i64 0
toolong:
  ret i64 -36
}

; ── Files ────────────────────────────────────────────────────
@rg_fdout = internal global i32 0

; open (path, length, flags, mode): a file descriptor or -errno. Flags as on
; Linux: access 0 read, 1 write, 2 both; 64 create, 128 exclusive, 512
; truncate, 1024 append, 2048 non-blocking, 65536 directory.
define i64 @__rg_pal_open(i64 %p, i64 %n, i64 %flags, i64 %mode) {
entry:
  %r = call i64 @rg_resolve(i64 %p, i64 %n)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %creat = and i64 %flags, 64
  %excl = and i64 %flags, 128
  %trunc = and i64 %flags, 512
  %dir = and i64 %flags, 65536
  %o1 = icmp ne i64 %creat, 0
  %o2 = icmp ne i64 %dir, 0
  %o4 = icmp ne i64 %excl, 0
  %o8 = icmp ne i64 %trunc, 0
  %v1 = select i1 %o1, i32 1, i32 0
  %v2 = select i1 %o2, i32 2, i32 0
  %v4 = select i1 %o4, i32 4, i32 0
  %v8 = select i1 %o8, i32 8, i32 0
  %a = or i32 %v1, %v2
  %b = or i32 %a, %v4
  %oflags = or i32 %b, %v8
  %app = and i64 %flags, 1024
  %nb = and i64 %flags, 2048
  %f1 = icmp ne i64 %app, 0
  %f4 = icmp ne i64 %nb, 0
  %w1 = select i1 %f1, i32 1, i32 0
  %w4 = select i1 %f4, i32 4, i32 0
  %fdflags = or i32 %w1, %w4
  %acc = and i64 %flags, 3
  %rd = icmp ne i64 %acc, 1
  %wr = icmp ne i64 %acc, 0
  ; rights: fd_read (bit 1) and fd_write (bit 6) by the access mode, and
  ; the other rights a file needs (bits 2..28 without bit 6)
  %rr = select i1 %rd, i64 2, i64 0
  %rw = select i1 %wr, i64 64, i64 0
  %rrw = or i64 %rr, %rw
  %rights = or i64 %rrw, 536870844
  %fd = load i32, ptr @rg_rfd, align 4
  %path = ptrtoint ptr @rg_rpath to i32
  %len = load i32, ptr @rg_rlen, align 4
  %out = ptrtoint ptr @rg_fdout to i32
  %e = call i32 @wasi_path_open(i32 %fd, i32 1, i32 %path, i32 %len, i32 %oflags, i64 %rights, i64 %rights, i32 %fdflags, i32 %out)
  %err = icmp ne i32 %e, 0
  br i1 %err, label %werr, label %okfd
werr:
  %x = call i64 @rg_errno(i32 %e)
  ret i64 %x
okfd:
  %nfd = load i32, ptr @rg_fdout, align 4
  %nfd64 = zext i32 %nfd to i64
  ret i64 %nfd64
}

; close (fd): 0 or -errno.
define i64 @__rg_pal_close(i64 %fd) {
  %f = trunc i64 %fd to i32
  %e = call i32 @wasi_fd_close(i32 %f)
  %r = call i64 @rg_errno(i32 %e)
  ret i64 %r
}

; One path operation: 0 make a folder, 1 remove a folder, 2 remove a file.
define internal i64 @rg_path_op(i64 %op, i64 %p, i64 %n) {
entry:
  %r = call i64 @rg_resolve(i64 %p, i64 %n)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %fd = load i32, ptr @rg_rfd, align 4
  %path = ptrtoint ptr @rg_rpath to i32
  %len = load i32, ptr @rg_rlen, align 4
  switch i64 %op, label %unlink [ i64 0, label %mkdir
                                  i64 1, label %rmdir ]
mkdir:
  %e0 = call i32 @wasi_path_create_directory(i32 %fd, i32 %path, i32 %len)
  br label %done
rmdir:
  %e1 = call i32 @wasi_path_remove_directory(i32 %fd, i32 %path, i32 %len)
  br label %done
unlink:
  %e2 = call i32 @wasi_path_unlink_file(i32 %fd, i32 %path, i32 %len)
  br label %done
done:
  %e = phi i32 [ %e0, %mkdir ], [ %e1, %rmdir ], [ %e2, %unlink ]
  %x = call i64 @rg_errno(i32 %e)
  ret i64 %x
}

define i64 @__rg_pal_mkdir(i64 %p, i64 %n, i64 %mode) {
  %r = call i64 @rg_path_op(i64 0, i64 %p, i64 %n)
  ret i64 %r
}

define i64 @__rg_pal_rmdir(i64 %p, i64 %n) {
  %r = call i64 @rg_path_op(i64 1, i64 %p, i64 %n)
  ret i64 %r
}

define i64 @__rg_pal_unlink(i64 %p, i64 %n) {
  %r = call i64 @rg_path_op(i64 2, i64 %p, i64 %n)
  ret i64 %r
}

; rename (from, from length, to, to length): 0 or -errno.
@rg_rpath2 = internal global [4096 x i8] zeroinitializer

define i64 @__rg_pal_rename(i64 %p, i64 %n, i64 %q, i64 %m) {
entry:
  %r = call i64 @rg_resolve(i64 %q, i64 %m)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %second
second:
  %fd2 = load i32, ptr @rg_rfd, align 4
  %len2 = load i32, ptr @rg_rlen, align 4
  %d2 = ptrtoint ptr @rg_rpath2 to i64
  %s1 = ptrtoint ptr @rg_rpath to i64
  %l2 = zext i32 %len2 to i64
  call void @rg_copy(i64 %d2, i64 %s1, i64 %l2)
  %r2 = call i64 @rg_resolve(i64 %p, i64 %n)
  %bad2 = icmp ne i64 %r2, 0
  br i1 %bad2, label %fail2, label %go
fail:
  ret i64 %r
fail2:
  ret i64 %r2
go:
  %fd1 = load i32, ptr @rg_rfd, align 4
  %len1 = load i32, ptr @rg_rlen, align 4
  %p1 = ptrtoint ptr @rg_rpath to i32
  %p2 = ptrtoint ptr @rg_rpath2 to i32
  %e = call i32 @wasi_path_rename(i32 %fd1, i32 %p1, i32 %len1, i32 %fd2, i32 %p2, i32 %len2)
  %x = call i64 @rg_errno(i32 %e)
  ret i64 %x
}

; stat (path, length, out): 0 or -errno. Does not follow a final symlink.
; out[0] kind (1 file, 2 folder, 3 link, 4 fifo, 5 socket, 6 block, 7 char,
; 0 unknown), out[1] links, out[2] size, out[3] mtime (s), out[4] mode bits
; (0: unknown on this system).
@rg_fst = internal global [8 x i64] zeroinitializer

define i64 @__rg_pal_stat(i64 %p, i64 %n, i64 %out) {
entry:
  %r = call i64 @rg_resolve(i64 %p, i64 %n)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %fd = load i32, ptr @rg_rfd, align 4
  %path = ptrtoint ptr @rg_rpath to i32
  %len = load i32, ptr @rg_rlen, align 4
  %buf = ptrtoint ptr @rg_fst to i32
  %e = call i32 @wasi_path_filestat_get(i32 %fd, i32 0, i32 %path, i32 %len, i32 %buf)
  %err = icmp ne i32 %e, 0
  br i1 %err, label %werr, label %fill
werr:
  %x = call i64 @rg_errno(i32 %e)
  ret i64 %x
fill:
  %tp = getelementptr inbounds [8 x i64], ptr @rg_fst, i32 0, i32 2
  %t8 = load i8, ptr %tp, align 8
  %kind = call i64 @rg_kind(i8 %t8)
  %op = inttoptr i64 %out to ptr
  store i64 %kind, ptr %op, align 8
  %nlp = getelementptr inbounds [8 x i64], ptr @rg_fst, i32 0, i32 3
  %nl = load i64, ptr %nlp, align 8
  %o1 = getelementptr inbounds i64, ptr %op, i64 1
  store i64 %nl, ptr %o1, align 8
  %szp = getelementptr inbounds [8 x i64], ptr @rg_fst, i32 0, i32 4
  %sz = load i64, ptr %szp, align 8
  %o2 = getelementptr inbounds i64, ptr %op, i64 2
  store i64 %sz, ptr %o2, align 8
  %mtp = getelementptr inbounds [8 x i64], ptr @rg_fst, i32 0, i32 6
  %mt = load i64, ptr %mtp, align 8
  %mts = udiv i64 %mt, 1000000000
  %o3 = getelementptr inbounds i64, ptr %op, i64 3
  store i64 %mts, ptr %o3, align 8
  %o4 = getelementptr inbounds i64, ptr %op, i64 4
  store i64 0, ptr %o4, align 8
  ret i64 0
}

define internal i64 @rg_kind(i8 %t) {
entry:
  switch i8 %t, label %unknown [ i8 4, label %file
                                 i8 3, label %dir
                                 i8 7, label %link
                                 i8 6, label %sock
                                 i8 5, label %sock
                                 i8 1, label %block
                                 i8 2, label %char ]
file:
  ret i64 1
dir:
  ret i64 2
link:
  ret i64 3
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
@rg_used = internal global i32 0

define i64 @__rg_pal_readlink(i64 %p, i64 %n, i64 %buf, i64 %cap) {
entry:
  %r = call i64 @rg_resolve(i64 %p, i64 %n)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %r
go:
  %fd = load i32, ptr @rg_rfd, align 4
  %path = ptrtoint ptr @rg_rpath to i32
  %len = load i32, ptr @rg_rlen, align 4
  %b = trunc i64 %buf to i32
  %c = trunc i64 %cap to i32
  %u = ptrtoint ptr @rg_used to i32
  %e = call i32 @wasi_path_readlink(i32 %fd, i32 %path, i32 %len, i32 %b, i32 %c, i32 %u)
  %err = icmp ne i32 %e, 0
  br i1 %err, label %werr, label %ok
werr:
  %x = call i64 @rg_errno(i32 %e)
  ret i64 %x
ok:
  %used = load i32, ptr @rg_used, align 4
  %u64 = zext i32 %used to i64
  ret i64 %u64
}

; list dir (path, length, buffer, capacity): the entry names, each followed
; by a NUL byte, in the order the system gives them ("." and ".." left out).
; The result is the bytes they need; they are written only when they fit.
; -errno when the folder cannot be read.
define i64 @__rg_pal_list_dir(i64 %p, i64 %n, i64 %buf, i64 %cap) {
entry:
  %fd = call i64 @__rg_pal_open(i64 %p, i64 %n, i64 65536, i64 0)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %fail, label %go
fail:
  ret i64 %fd
go:
  %fd32 = trunc i64 %fd to i32
  %tmp = call i64 @rg_alloc(i64 4096)
  %t32 = trunc i64 %tmp to i32
  %u = ptrtoint ptr @rg_used to i32
  br label %batch
batch:
  %cookie = phi i64 [ 0, %go ], [ %cookie2, %bdone ]
  %need = phi i64 [ 0, %go ], [ %need2, %bdone ]
  %e = call i32 @wasi_fd_readdir(i32 %fd32, i32 %t32, i32 4096, i64 %cookie, i32 %u)
  %err = icmp ne i32 %e, 0
  br i1 %err, label %finish, label %parse
parse:
  %used = load i32, ptr @rg_used, align 4
  %used64 = zext i32 %used to i64
  %end = add i64 %tmp, %used64
  br label %ent
ent:
  %q = phi i64 [ %tmp, %parse ], [ %qn, %advance ]
  %nd = phi i64 [ %need, %parse ], [ %nd2, %advance ]
  %ck = phi i64 [ %cookie, %parse ], [ %next, %advance ]
  %hdr_end = add i64 %q, 24
  %hfits = icmp ule i64 %hdr_end, %end
  br i1 %hfits, label %rdent, label %bdone_partial
rdent:
  %qp = inttoptr i64 %q to ptr
  %next = load i64, ptr %qp, align 1
  %nlp = getelementptr inbounds i8, ptr %qp, i64 16
  %nl32 = load i32, ptr %nlp, align 1
  %nl = zext i32 %nl32 to i64
  %name = add i64 %q, 24
  %nend = add i64 %name, %nl
  %nfits = icmp ule i64 %nend, %end
  br i1 %nfits, label %useent, label %bdone_partial
useent:
  %skip = call i1 @rg_dots(i64 %name, i64 %nl)
  br i1 %skip, label %advance_skip, label %add
add:
  %nl1 = add i64 %nl, 1
  %after = add i64 %nd, %nl1
  %fit = icmp sle i64 %after, %cap
  br i1 %fit, label %copy, label %advance_add
copy:
  %dst = add i64 %buf, %nd
  call void @rg_copy(i64 %dst, i64 %name, i64 %nl)
  %zp0 = add i64 %dst, %nl
  %zp = inttoptr i64 %zp0 to ptr
  store i8 0, ptr %zp, align 1
  br label %advance_add
advance_add:
  br label %advance
advance_skip:
  br label %advance
advance:
  %nd2 = phi i64 [ %after, %advance_add ], [ %nd, %advance_skip ]
  %qn = add i64 %nend, 0
  br label %ent
bdone_partial:
  ; a full buffer means more entries: read again from the last cookie
  %full = icmp eq i32 %used, 4096
  br i1 %full, label %bdone, label %finish_ok
bdone:
  %cookie2 = phi i64 [ %ck, %bdone_partial ]
  %need2 = phi i64 [ %nd, %bdone_partial ]
  br label %batch
finish_ok:
  call void @rg_free(i64 %tmp)
  %c = call i64 @__rg_pal_close(i64 %fd)
  ret i64 %nd
finish:
  call void @rg_free(i64 %tmp)
  %c2 = call i64 @__rg_pal_close(i64 %fd)
  %x = call i64 @rg_errno(i32 %e)
  ret i64 %x
}

; 1 for the names "." and "..".
define internal i1 @rg_dots(i64 %p, i64 %n) {
entry:
  %pp = inttoptr i64 %p to ptr
  %c0 = load i8, ptr %pp, align 1
  %d0 = icmp eq i8 %c0, 46
  %n1 = icmp eq i64 %n, 1
  %n2 = icmp eq i64 %n, 2
  %p1 = getelementptr inbounds i8, ptr %pp, i64 1
  %c1 = load i8, ptr %p1, align 1
  %d1 = icmp eq i8 %c1, 46
  %one = and i1 %d0, %n1
  %two0 = and i1 %d0, %d1
  %two = and i1 %two0, %n2
  %r = or i1 %one, %two
  ret i1 %r
}

; ── Working directory ────────────────────────────────────────
; getcwd (buffer, capacity): the bytes of the working directory, written
; when they fit.
define i64 @__rg_pal_getcwd(i64 %buf, i64 %cap) {
entry:
  %l = load i64, ptr @rg_cwd_len, align 8
  %moved = icmp sgt i64 %l, 0
  br i1 %moved, label %mine, label %host
mine:
  %fit = icmp sle i64 %l, %cap
  br i1 %fit, label %copy, label %size
copy:
  %c = ptrtoint ptr @rg_cwd to i64
  call void @rg_copy(i64 %buf, i64 %c, i64 %l)
  br label %size
size:
  ret i64 %l
host:
  store i32 0, ptr @rg_rlen, align 4
  call void @rg_put_host_cwd()
  %hl = load i32, ptr @rg_rlen, align 4
  %hl64 = zext i32 %hl to i64
  %hfit = icmp sle i64 %hl64, %cap
  br i1 %hfit, label %hcopy, label %hsize
hcopy:
  %r = ptrtoint ptr @rg_rpath to i64
  call void @rg_copy(i64 %buf, i64 %r, i64 %hl64)
  br label %hsize
hsize:
  ret i64 %hl64
}

; chdir (path, length): 0, or -errno when the path is not a folder.
@rg_cst = internal global [5 x i64] zeroinitializer

define i64 @__rg_pal_chdir(i64 %p, i64 %n) {
entry:
  %out = ptrtoint ptr @rg_cst to i64
  %r = call i64 @__rg_pal_stat(i64 %p, i64 %n, i64 %out)
  %bad = icmp ne i64 %r, 0
  br i1 %bad, label %fail, label %kind
fail:
  ret i64 %r
kind:
  %k = load i64, ptr @rg_cst, align 8
  %isdir = icmp eq i64 %k, 2
  br i1 %isdir, label %set, label %notdir
notdir:
  ret i64 -20
set:
  ; the new directory, as an absolute path: "/" + the resolved path
  %l = load i32, ptr @rg_rlen, align 4
  %l64 = zext i32 %l to i64
  %fd = load i32, ptr @rg_rfd, align 4
  %root = load i32, ptr @rg_pre_root, align 4
  %fromroot = icmp eq i32 %fd, %root
  br i1 %fromroot, label %abs, label %rel
rel:
  ; resolved against ".": prefix the host's directory
  %save = call i64 @rg_alloc(i64 4096)
  %rp = ptrtoint ptr @rg_rpath to i64
  call void @rg_copy(i64 %save, i64 %rp, i64 %l64)
  store i32 0, ptr @rg_rlen, align 4
  call void @rg_put_host_cwd()
  %s = ptrtoint ptr @rg_slash to i64
  %o1 = call i1 @rg_rput(i64 %s, i64 1)
  %o2 = call i1 @rg_rput(i64 %save, i64 %l64)
  call void @rg_free(i64 %save)
  %nl = load i32, ptr @rg_rlen, align 4
  %nl64 = zext i32 %nl to i64
  %c = ptrtoint ptr @rg_cwd to i64
  call void @rg_copy(i64 %c, i64 %rp, i64 %nl64)
  store i64 %nl64, ptr @rg_cwd_len, align 8
  ret i64 0
abs:
  store i8 47, ptr @rg_cwd, align 1
  %c1 = ptrtoint ptr @rg_cwd to i64
  %c1a = add i64 %c1, 1
  %rp2 = ptrtoint ptr @rg_rpath to i64
  %isdot = call i1 @rg_dots(i64 %rp2, i64 %l64)
  %ll = select i1 %isdot, i64 0, i64 %l64
  call void @rg_copy(i64 %c1a, i64 %rp2, i64 %ll)
  %tot = add i64 %ll, 1
  store i64 %tot, ptr @rg_cwd_len, align 8
  ret i64 0
}

; poll (fd, events, ms): waits until fd is ready for reading (events 1) or
; writing (events 4), or ms milliseconds pass (ms < 0: no limit). Gives the
; ready event (1 or 4), 0 when the time passed, or -errno. A negative fd
; only waits.
@rg_psub = internal global [12 x i64] zeroinitializer
@rg_pevt = internal global [8 x i64] zeroinitializer

define i64 @__rg_pal_poll(i64 %fd, i64 %events, i64 %ms) {
entry:
  %base = ptrtoint ptr @rg_psub to i64
  call void @rg_fill(i64 %base, i8 0, i64 96)
  %timed = icmp sge i64 %ms, 0
  br i1 %timed, label %clock, label %fdsub
clock:
  %c1 = add i64 %base, 16
  call void @rg_st(i64 %c1, i64 1)
  %ns = mul i64 %ms, 1000000
  %c3 = add i64 %base, 24
  call void @rg_st(i64 %c3, i64 %ns)
  %c4 = add i64 %base, 32
  call void @rg_st(i64 %c4, i64 1000)
  br label %fdsub
fdsub:
  %n0 = phi i64 [ 0, %entry ], [ 1, %clock ]
  %hasfd = icmp sge i64 %fd, 0
  br i1 %hasfd, label %addfd, label %call
addfd:
  %off = mul i64 %n0, 48
  %s = add i64 %base, %off
  call void @rg_st(i64 %s, i64 1)
  %w = and i64 %events, 4
  %wr = icmp ne i64 %w, 0
  %tag = select i1 %wr, i64 2, i64 1
  %st = add i64 %s, 8
  call void @rg_st(i64 %st, i64 %tag)
  %sf = add i64 %s, 16
  call void @rg_st(i64 %sf, i64 %fd)
  %n1 = add i64 %n0, 1
  br label %call
call:
  %n = phi i64 [ %n0, %fdsub ], [ %n1, %addfd ]
  %none = icmp eq i64 %n, 0
  br i1 %none, label %zero, label %wait
wait:
  %si = ptrtoint ptr @rg_psub to i32
  %ei = ptrtoint ptr @rg_pevt to i32
  %ni = ptrtoint ptr @rg_nevt to i32
  %n32 = trunc i64 %n to i32
  %e = call i32 @wasi_poll_oneoff(i32 %si, i32 %ei, i32 %n32, i32 %ni)
  %bad = icmp ne i32 %e, 0
  br i1 %bad, label %err, label %scan
err:
  %x = call i64 @rg_errno(i32 %e)
  ret i64 %x
scan:
  %got32 = load i32, ptr @rg_nevt, align 4
  %got = zext i32 %got32 to i64
  %eb = ptrtoint ptr @rg_pevt to i64
  br label %loop
loop:
  %k = phi i64 [ 0, %scan ], [ %k1, %next ]
  %more = icmp ult i64 %k, %got
  br i1 %more, label %body, label %zero
body:
  %eo = mul i64 %k, 32
  %ea = add i64 %eb, %eo
  %ud = call i64 @rg_ld(i64 %ea)
  %isfd = icmp eq i64 %ud, 1
  br i1 %isfd, label %ready, label %next
next:
  %k1 = add i64 %k, 1
  br label %loop
ready:
  %erra = add i64 %ea, 8
  %ew = call i64 @rg_ld(i64 %erra)
  %code = and i64 %ew, 65535
  %etype = lshr i64 %ew, 16
  %ty = and i64 %etype, 255
  %failed = icmp ne i64 %code, 0
  br i1 %failed, label %ferr, label %fok
ferr:
  %c32 = trunc i64 %code to i32
  %y = call i64 @rg_errno(i32 %c32)
  ret i64 %y
fok:
  %isw = icmp eq i64 %ty, 2
  %r = select i1 %isw, i64 4, i64 1
  ret i64 %r
zero:
  ret i64 0
}

; ── Threads (ADR-0014) ───────────────────────────────────────
; wasm32 here has no threads: spawn is refused and the runtime runs every job
; on the calling thread.
define i64 @__rg_pal_thread_spawn(i64 %entry, i64 %arg, i64 %stack_top) {
  ret i64 -38
}

define i64 @__rg_pal_thread_id() {
  ret i64 1
}

define void @__rg_pal_yield() {
  ret void
}

define i64 @__rg_pal_futex_wait(i64 %addr, i64 %expected, i64 %timeout_ns) {
  ret i64 -11
}

define i64 @__rg_pal_futex_wake(i64 %addr, i64 %count) {
  ret i64 0
}
