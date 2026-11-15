; ============================================================
; src/main/runtime/core/system.ll
; System builtins (FR-VM-001, FR-VM-002, FR-COMP-007, FR-COMP-022): program
; arguments, environment, files, folders, clocks, sleep and `with timeout`
; deadlines. Every system operation goes through the PAL (ADR-0008), whose
; errors are -errno with Linux numbers on every target. A builtin takes its
; argument slots. Results observed on the Linux build where no document
; states them: a missing file reads as "", `write file` gives (), a folder
; that cannot be listed gives [], `sys mkdir` gives 0 when the folder is
; already there, `sys deadline ms` gives 0 outside `with timeout`.
; ============================================================

declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i64 @rg_ldb(i64)
declare i1 @rg_has_tag(i64, i64)
declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare void @rg_copy(i64, i64, i64)
declare i64 @rg_str_from(i64, i64)
declare i64 @rg_str_data(i64)
declare i64 @rg_str_len(i64)
declare i64 @rg_list_alloc(i64, i64)
declare i64 @rg_list_at(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_int(i64)
declare i64 @rg_int_of(i64)
declare i64 @rg_box_int(i64)
declare i64 @rg_bool(i1)
declare i1 @rg_bytes_eq(i64, i64, i64)
declare i64 @__rg_rt_make_tuple(i64, i64)
declare i64 @__rg_rt_clone_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare i64 @rg_arg(i64, i64)
declare void @rg_buf_init(i64, i64)
declare void @rg_buf_bytes(i64, i64, i64)
declare i64 @rg_buf_reserve(i64, i64)
declare i64 @rg_buf_str(i64)
declare i64 @rg_builtin_agents(i64, i64, i64)

declare i64 @__rg_pal_write(i64, i64, i64)
declare i64 @__rg_pal_read(i64, i64, i64)
declare i64 @__rg_pal_clock_ns(i64)
declare void @__rg_pal_sleep_ns(i64)
declare i64 @__rg_pal_args(i64, i64)
declare i64 @__rg_pal_env(i64, i64)
declare i64 @__rg_pal_open(i64, i64, i64, i64)
declare i64 @__rg_pal_close(i64)
declare i64 @__rg_pal_mkdir(i64, i64, i64)
declare i64 @__rg_pal_rmdir(i64, i64)
declare i64 @__rg_pal_unlink(i64, i64)
declare i64 @__rg_pal_rename(i64, i64, i64, i64)
declare i64 @__rg_pal_stat(i64, i64, i64)
declare i64 @__rg_pal_readlink(i64, i64, i64, i64)
declare i64 @__rg_pal_list_dir(i64, i64, i64, i64)
declare i64 @__rg_pal_getcwd(i64, i64)
declare i64 @__rg_pal_chdir(i64, i64)

; ── Small helpers ────────────────────────────────────────────

; Take a String argument; gives the String (the caller drops it).
define internal i64 @rg_sarg(i64 %slots, i64 %i) {
  %s = call i64 @rg_arg(i64 %slots, i64 %i)
  ret i64 %s
}

; A tuple of the n values at vals (taken).
define internal i64 @rg_tuple_of(ptr %vals, i64 %n) {
  %a = ptrtoint ptr %vals to i64
  %t = call i64 @__rg_rt_make_tuple(i64 %a, i64 %n)
  ret i64 %t
}

; The empty String.
define internal i64 @rg_empty() {
  %s = call i64 @rg_str_from(i64 0, i64 0)
  ret i64 %s
}

; A List of the NUL-terminated strings in [p, p + n).
define internal i64 @rg_cstr_list(i64 %p, i64 %n) {
entry:
  %end = add i64 %p, %n
  br label %count
count:
  %q = phi i64 [ %p, %entry ], [ %q1, %cnext ]
  %k = phi i64 [ 0, %entry ], [ %k2, %cnext ]
  %more = icmp ult i64 %q, %end
  br i1 %more, label %cbody, label %build
cbody:
  %c = call i64 @rg_ldb(i64 %q)
  %z = icmp eq i64 %c, 0
  %k1 = add i64 %k, 1
  %k2 = select i1 %z, i64 %k1, i64 %k
  br label %cnext
cnext:
  %q1 = add i64 %q, 1
  br label %count
build:
  %xs = call i64 @rg_list_alloc(i64 %k, i64 %k)
  br label %loop
loop:
  %s = phi i64 [ %p, %build ], [ %s1, %put ]
  %i = phi i64 [ 0, %build ], [ %i1, %put ]
  %go = icmp slt i64 %i, %k
  br i1 %go, label %len, label %done
len:
  %l = call i64 @rg_cstrlen2(i64 %s)
  %str = call i64 @rg_str_from(i64 %s, i64 %l)
  %slot = call i64 @rg_list_at(i64 %xs, i64 %i)
  call void @rg_st(i64 %slot, i64 %str)
  br label %put
put:
  %s0 = add i64 %s, %l
  %s1 = add i64 %s0, 1
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %xs
}

define internal i64 @rg_cstrlen2(i64 %p) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %a = add i64 %p, %i
  %c = call i64 @rg_ldb(i64 %a)
  %i1 = add i64 %i, 1
  %z = icmp eq i64 %c, 0
  br i1 %z, label %done, label %loop
done:
  ret i64 %i
}

; Call a PAL function that fills a buffer and gives the size it needs, with
; a buffer large enough; gives the String of the result (kind 0 args, 1 env,
; 2 getcwd).
define internal i64 @rg_pal_fill(i64 %kind, i64 %buf, i64 %cap) {
entry:
  switch i64 %kind, label %cwd [ i64 0, label %args
                                 i64 1, label %env ]
args:
  %a = call i64 @__rg_pal_args(i64 %buf, i64 %cap)
  ret i64 %a
env:
  %e = call i64 @__rg_pal_env(i64 %buf, i64 %cap)
  ret i64 %e
cwd:
  %c = call i64 @__rg_pal_getcwd(i64 %buf, i64 %cap)
  ret i64 %c
}

; The bytes of a PAL buffer result, in a fresh block (freed by the caller);
; the size goes to *n.
define internal i64 @rg_pal_bytes(i64 %kind, ptr %n) {
entry:
  %need = call i64 @rg_pal_fill(i64 %kind, i64 0, i64 0)
  %cap = add i64 %need, 8
  %buf = call i64 @rg_alloc(i64 %cap)
  %got = call i64 @rg_pal_fill(i64 %kind, i64 %buf, i64 %cap)
  store i64 %got, ptr %n, align 8
  ret i64 %buf
}

; ── Arguments, environment, working directory ────────────────

define internal i64 @rg_cli_args() {
  %n = alloca i64, align 8
  %b = call i64 @rg_pal_bytes(i64 0, ptr %n)
  %len = load i64, ptr %n, align 8
  %xs = call i64 @rg_cstr_list(i64 %b, i64 %len)
  call void @rg_free(i64 %b)
  ret i64 %xs
}

define internal i64 @rg_getcwd() {
  %n = alloca i64, align 8
  %b = call i64 @rg_pal_bytes(i64 2, ptr %n)
  %len = load i64, ptr %n, align 8
  %s = call i64 @rg_str_from(i64 %b, i64 %len)
  call void @rg_free(i64 %b)
  ret i64 %s
}

; Variables set by the program (`sys setenv`): a List of (key, value)
; tuples, newest last. They hide the host's environment.
@rg_env_set = internal global i64 0

; The value of the variable whose name is the String k, or 0 when unset.
define internal i64 @rg_env_lookup(i64 %k) {
entry:
  %kd = call i64 @rg_str_data(i64 %k)
  %kl = call i64 @rg_str_len(i64 %k)
  %set = load i64, ptr @rg_env_set, align 8
  %has = icmp ne i64 %set, 0
  br i1 %has, label %own, label %host
own:
  %n = call i64 @rg_list_len(i64 %set)
  br label %oloop
oloop:
  %i = phi i64 [ %n, %own ], [ %i1, %onext ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %obody, label %host
obody:
  %i1 = sub i64 %i, 1
  %ea = call i64 @rg_list_at(i64 %set, i64 %i1)
  %t = call i64 @rg_ld(i64 %ea)
  %kv = call i64 @__rg_rt_tuple_get(i64 %t, i64 0)
  %ok = call i1 @rg_str_is(i64 %kv, i64 %kd, i64 %kl)
  %dk = call i64 @__rg_rt_drop_val(i64 %kv)
  br i1 %ok, label %ohit, label %onext
ohit:
  %v = call i64 @__rg_rt_tuple_get(i64 %t, i64 1)
  ret i64 %v
onext:
  br label %oloop
host:
  %nb = alloca i64, align 8
  %b = call i64 @rg_pal_bytes(i64 1, ptr %nb)
  %len = load i64, ptr %nb, align 8
  %end = add i64 %b, %len
  br label %hloop
hloop:
  %p = phi i64 [ %b, %host ], [ %pn, %hnext ]
  %hm = icmp ult i64 %p, %end
  br i1 %hm, label %hbody, label %hnone
hbody:
  %l = call i64 @rg_cstrlen2(i64 %p)
  %long = icmp sgt i64 %l, %kl
  br i1 %long, label %hcmp, label %hnext
hcmp:
  %same = call i1 @rg_bytes_eq(i64 %p, i64 %kd, i64 %kl)
  %eqa = add i64 %p, %kl
  %eqc = call i64 @rg_ldb(i64 %eqa)
  %iseq = icmp eq i64 %eqc, 61
  %hit = and i1 %same, %iseq
  br i1 %hit, label %hfound, label %hnext
hfound:
  %va = add i64 %eqa, 1
  %vl0 = sub i64 %l, %kl
  %vl = sub i64 %vl0, 1
  %vs = call i64 @rg_str_from(i64 %va, i64 %vl)
  call void @rg_free(i64 %b)
  ret i64 %vs
hnext:
  %pn0 = add i64 %p, %l
  %pn = add i64 %pn0, 1
  br label %hloop
hnone:
  call void @rg_free(i64 %b)
  ret i64 0
}

declare i64 @__rg_rt_tuple_get(i64, i64)

; 1 when the String s holds the n bytes at d.
define internal i1 @rg_str_is(i64 %s, i64 %d, i64 %n) {
entry:
  %isstr = call i1 @rg_has_tag(i64 %s, i64 1)
  br i1 %isstr, label %len, label %no
len:
  %l = call i64 @rg_str_len(i64 %s)
  %le = icmp eq i64 %l, %n
  br i1 %le, label %cmp, label %no
cmp:
  %sd = call i64 @rg_str_data(i64 %s)
  %e = call i1 @rg_bytes_eq(i64 %sd, i64 %d, i64 %n)
  ret i1 %e
no:
  ret i1 false
}

define internal i64 @rg_getenv(i64 %k) {
entry:
  %v = call i64 @rg_env_lookup(i64 %k)
  %none = icmp eq i64 %v, 0
  br i1 %none, label %empty, label %done
empty:
  %e = call i64 @rg_empty()
  ret i64 %e
done:
  ret i64 %v
}

; setenv (key, value): both taken; gives 0.
define internal i64 @rg_setenv(i64 %k, i64 %v) {
entry:
  %pair = alloca [2 x i64], align 8
  store i64 %k, ptr %pair, align 8
  %p1 = getelementptr inbounds [2 x i64], ptr %pair, i64 0, i64 1
  store i64 %v, ptr %p1, align 8
  %t = call i64 @rg_tuple_of(ptr %pair, i64 2)
  %old = load i64, ptr @rg_env_set, align 8
  %has = icmp ne i64 %old, 0
  br i1 %has, label %grow, label %first
first:
  %one = call i64 @rg_list_alloc(i64 1, i64 8)
  %a0 = call i64 @rg_list_at(i64 %one, i64 0)
  call void @rg_st(i64 %a0, i64 %t)
  store i64 %one, ptr @rg_env_set, align 8
  ret i64 1
grow:
  %n = call i64 @rg_list_len(i64 %old)
  %n1 = add i64 %n, 1
  %nx = call i64 @rg_list_alloc(i64 %n1, i64 %n1)
  %src = call i64 @rg_list_at(i64 %old, i64 0)
  %dst = call i64 @rg_list_at(i64 %nx, i64 0)
  %bytes = shl i64 %n, 3
  call void @rg_copy(i64 %dst, i64 %src, i64 %bytes)
  ; the old list gives its items to the new one
  %oh = call i64 @rg_w1x(i64 %old)
  call void @rg_vset_len(i64 %oh, i64 0)
  %d = call i64 @__rg_rt_drop_val(i64 %old)
  %last = call i64 @rg_list_at(i64 %nx, i64 %n)
  call void @rg_st(i64 %last, i64 %t)
  store i64 %nx, ptr @rg_env_set, align 8
  ret i64 1
}

declare i64 @rg_w1(i64)
declare void @rg_vset_len(i64, i64)

define internal i64 @rg_w1x(i64 %o) {
  %h = call i64 @rg_w1(i64 %o)
  ret i64 %h
}

; ── Files ────────────────────────────────────────────────────

; The whole content of the open file fd as a String.
define internal i64 @rg_read_all(i64 %fd) {
entry:
  %buf = alloca [3 x i64], align 8
  %b = ptrtoint ptr %buf to i64
  call void @rg_buf_init(i64 %b, i64 4096)
  br label %loop
loop:
  %la = add i64 %b, 8
  %l0 = call i64 @rg_ld(i64 %la)
  %dst = call i64 @rg_buf_reserve(i64 %b, i64 65536)
  %n = call i64 @__rg_pal_read(i64 %fd, i64 %dst, i64 65536)
  %got = icmp sgt i64 %n, 0
  %k = select i1 %got, i64 %n, i64 0
  %l1 = add i64 %l0, %k
  call void @rg_st(i64 %la, i64 %l1)
  br i1 %got, label %loop, label %done
done:
  %s = call i64 @rg_buf_str(i64 %b)
  ret i64 %s
}

; read file (path): the content, or "" when the file cannot be read.
define i64 @rg_read_file(i64 %path) {
entry:
  %pd = call i64 @rg_str_data(i64 %path)
  %pl = call i64 @rg_str_len(i64 %path)
  %fd = call i64 @__rg_pal_open(i64 %pd, i64 %pl, i64 0, i64 0)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %empty, label %read
empty:
  %e = call i64 @rg_empty()
  ret i64 %e
read:
  %s = call i64 @rg_read_all(i64 %fd)
  %c = call i64 @__rg_pal_close(i64 %fd)
  ret i64 %s
}

; Write all n bytes at d to fd; the bytes written, or -errno.
define i64 @rg_write_fd_all(i64 %fd, i64 %d, i64 %n) {
entry:
  br label %loop
loop:
  %done = phi i64 [ 0, %entry ], [ %done1, %more ]
  %left = sub i64 %n, %done
  %fin = icmp sle i64 %left, 0
  br i1 %fin, label %ok, label %write
write:
  %p = add i64 %d, %done
  %w = call i64 @__rg_pal_write(i64 %fd, i64 %p, i64 %left)
  %bad = icmp sle i64 %w, 0
  br i1 %bad, label %err, label %more
more:
  %done1 = add i64 %done, %w
  br label %loop
err:
  %some = icmp sgt i64 %done, 0
  %zero = icmp eq i64 %w, 0
  %r0 = select i1 %zero, i64 %done, i64 %w
  %r = select i1 %some, i64 %done, i64 %r0
  ret i64 %r
ok:
  ret i64 %done
}

; write file (path, content): replaces the file; gives ().
define internal i64 @rg_write_file(i64 %path, i64 %text) {
entry:
  %pd = call i64 @rg_str_data(i64 %path)
  %pl = call i64 @rg_str_len(i64 %path)
  %fd = call i64 @__rg_pal_open(i64 %pd, i64 %pl, i64 577, i64 420)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %done, label %write
write:
  %td = call i64 @rg_str_data(i64 %text)
  %tl = call i64 @rg_str_len(i64 %text)
  %w = call i64 @rg_write_fd_all(i64 %fd, i64 %td, i64 %tl)
  %c = call i64 @__rg_pal_close(i64 %fd)
  br label %done
done:
  ret i64 0
}

; The flags of a `sys open mode` text: "r", "w", "a", "rw", "w+", "a+".
define internal i64 @rg_mode_flags(i64 %m) {
entry:
  %d = call i64 @rg_str_data(i64 %m)
  %l = call i64 @rg_str_len(i64 %m)
  %c0 = call i64 @rg_ldb(i64 %d)
  %two = icmp sge i64 %l, 2
  %d1 = add i64 %d, 1
  %c1r = call i64 @rg_ldb(i64 %d1)
  %c1 = select i1 %two, i64 %c1r, i64 0
  %plus = icmp eq i64 %c1, 43
  %w2 = icmp eq i64 %c1, 119
  %rw = and i1 %plus, true
  %isr = icmp eq i64 %c0, 114
  %isw = icmp eq i64 %c0, 119
  %isa = icmp eq i64 %c0, 97
  %both = or i1 %plus, %w2
  %acc_w = select i1 %both, i64 2, i64 1
  %acc_r = select i1 %both, i64 2, i64 0
  %wf = or i64 %acc_w, 576
  %af = or i64 %acc_w, 1088
  %r1 = select i1 %isa, i64 %af, i64 %acc_r
  %r2 = select i1 %isw, i64 %wf, i64 %r1
  ret i64 %r2
}

; read fd (fd, max): a String of at most max bytes; "" at the end or on error.
define internal i64 @rg_read_fd(i64 %fd, i64 %max) {
entry:
  %pos = icmp sgt i64 %max, 0
  %m = select i1 %pos, i64 %max, i64 0
  %s = call i64 @rg_str_alloc_n(i64 %m)
  %d = call i64 @rg_str_data(i64 %s)
  %n = call i64 @__rg_pal_read(i64 %fd, i64 %d, i64 %m)
  %neg = icmp slt i64 %n, 0
  %got = select i1 %neg, i64 0, i64 %n
  %h = call i64 @rg_w1(i64 %s)
  call void @rg_vset_len(i64 %h, i64 %got)
  ret i64 %s
}

declare i64 @rg_str_alloc(i64, i64)

define internal i64 @rg_str_alloc_n(i64 %n) {
  %s = call i64 @rg_str_alloc(i64 %n, i64 %n)
  ret i64 %s
}

; ── Folders and status ───────────────────────────────────────

; The names of the folder at path, sorted by bytes; [] when it cannot be read.
define internal i64 @rg_list_dir(i64 %path) {
entry:
  %pd = call i64 @rg_str_data(i64 %path)
  %pl = call i64 @rg_str_len(i64 %path)
  %need = call i64 @__rg_pal_list_dir(i64 %pd, i64 %pl, i64 0, i64 0)
  %bad = icmp slt i64 %need, 0
  br i1 %bad, label %empty, label %read
empty:
  %e = call i64 @rg_list_alloc(i64 0, i64 0)
  ret i64 %e
read:
  %cap = add i64 %need, 8
  %buf = call i64 @rg_alloc(i64 %cap)
  %got = call i64 @__rg_pal_list_dir(i64 %pd, i64 %pl, i64 %buf, i64 %cap)
  %bad2 = icmp slt i64 %got, 0
  %len = select i1 %bad2, i64 0, i64 %got
  %xs = call i64 @rg_cstr_list(i64 %buf, i64 %len)
  call void @rg_free(i64 %buf)
  call void @rg_sort_strs(i64 %xs)
  ret i64 %xs
}

declare i64 @rg_compare(i64, i64)

; Sort a List of Strings in place by bytes (insertion sort).
define internal void @rg_sort_strs(i64 %xs) {
entry:
  %n = call i64 @rg_list_len(i64 %xs)
  br label %outer
outer:
  %i = phi i64 [ 1, %entry ], [ %i1, %onext ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %obody, label %done
obody:
  %ia = call i64 @rg_list_at(i64 %xs, i64 %i)
  %x = call i64 @rg_ld(i64 %ia)
  br label %inner
inner:
  %j = phi i64 [ %i, %obody ], [ %j1, %shift ]
  %pos = icmp sgt i64 %j, 0
  br i1 %pos, label %test, label %place
test:
  %j1 = sub i64 %j, 1
  %pa = call i64 @rg_list_at(i64 %xs, i64 %j1)
  %p = call i64 @rg_ld(i64 %pa)
  %c = call i64 @rg_compare(i64 %p, i64 %x)
  %gt = icmp sgt i64 %c, 0
  br i1 %gt, label %shift, label %place
shift:
  %ja = call i64 @rg_list_at(i64 %xs, i64 %j)
  call void @rg_st(i64 %ja, i64 %p)
  br label %inner
place:
  %ka = call i64 @rg_list_at(i64 %xs, i64 %j)
  call void @rg_st(i64 %ka, i64 %x)
  br label %onext
onext:
  %i1 = add i64 %i, 1
  br label %outer
done:
  ret void
}

@rg_k_file = private constant [4 x i8] c"file"
@rg_k_dir = private constant [3 x i8] c"dir"
@rg_k_link = private constant [4 x i8] c"link"
@rg_k_fifo = private constant [4 x i8] c"fifo"
@rg_k_sock = private constant [4 x i8] c"sock"
@rg_k_block = private constant [5 x i8] c"block"
@rg_k_char = private constant [4 x i8] c"char"

define internal i64 @rg_kind_name(i64 %k) {
entry:
  switch i64 %k, label %none [ i64 1, label %file
                               i64 2, label %dir
                               i64 3, label %link
                               i64 4, label %fifo
                               i64 5, label %sock
                               i64 6, label %block
                               i64 7, label %char ]
file:
  %a = call i64 @rg_str_from(i64 ptrtoint (ptr @rg_k_file to i64), i64 4)
  ret i64 %a
dir:
  %b = call i64 @rg_str_from(i64 ptrtoint (ptr @rg_k_dir to i64), i64 3)
  ret i64 %b
link:
  %c = call i64 @rg_str_from(i64 ptrtoint (ptr @rg_k_link to i64), i64 4)
  ret i64 %c
fifo:
  %d = call i64 @rg_str_from(i64 ptrtoint (ptr @rg_k_fifo to i64), i64 4)
  ret i64 %d
sock:
  %e = call i64 @rg_str_from(i64 ptrtoint (ptr @rg_k_sock to i64), i64 4)
  ret i64 %e
block:
  %f = call i64 @rg_str_from(i64 ptrtoint (ptr @rg_k_block to i64), i64 5)
  ret i64 %f
char:
  %g = call i64 @rg_str_from(i64 ptrtoint (ptr @rg_k_char to i64), i64 4)
  ret i64 %g
none:
  %h = call i64 @rg_empty()
  ret i64 %h
}

; file lstat (path): (exists, kind, mode, links, size, owner, group, mtime,
; link target). Owner and group are "" where the system does not give them.
define internal i64 @rg_lstat(i64 %path) {
entry:
  %st = alloca [5 x i64], align 8
  %vals = alloca [9 x i64], align 8
  %pd = call i64 @rg_str_data(i64 %path)
  %pl = call i64 @rg_str_len(i64 %path)
  %sa = ptrtoint ptr %st to i64
  %r = call i64 @__rg_pal_stat(i64 %pd, i64 %pl, i64 %sa)
  %ok = icmp eq i64 %r, 0
  %k = load i64, ptr %st, align 8
  %p1 = getelementptr inbounds [5 x i64], ptr %st, i64 0, i64 1
  %nl = load i64, ptr %p1, align 8
  %p2 = getelementptr inbounds [5 x i64], ptr %st, i64 0, i64 2
  %sz = load i64, ptr %p2, align 8
  %p3 = getelementptr inbounds [5 x i64], ptr %st, i64 0, i64 3
  %mt = load i64, ptr %p3, align 8
  %p4 = getelementptr inbounds [5 x i64], ptr %st, i64 0, i64 4
  %md = load i64, ptr %p4, align 8
  %kk = select i1 %ok, i64 %k, i64 0
  %nl2 = select i1 %ok, i64 %nl, i64 0
  %sz2 = select i1 %ok, i64 %sz, i64 0
  %mt2 = select i1 %ok, i64 %mt, i64 0
  %md2 = select i1 %ok, i64 %md, i64 0
  %islink = icmp eq i64 %kk, 3
  br i1 %islink, label %target, label %notarget
target:
  %tb = call i64 @rg_alloc(i64 4096)
  %tn = call i64 @__rg_pal_readlink(i64 %pd, i64 %pl, i64 %tb, i64 4096)
  %tneg = icmp slt i64 %tn, 0
  %tl = select i1 %tneg, i64 0, i64 %tn
  %ts = call i64 @rg_str_from(i64 %tb, i64 %tl)
  call void @rg_free(i64 %tb)
  br label %build
notarget:
  %te = call i64 @rg_empty()
  br label %build
build:
  %tgt = phi i64 [ %ts, %target ], [ %te, %notarget ]
  %ex = call i64 @rg_bool(i1 %ok)
  store i64 %ex, ptr %vals, align 8
  %kn = call i64 @rg_kind_name(i64 %kk)
  %v1 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 1
  store i64 %kn, ptr %v1, align 8
  %mdi = call i64 @rg_box_int(i64 %md2)
  %v2 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 2
  store i64 %mdi, ptr %v2, align 8
  %nli = call i64 @rg_box_int(i64 %nl2)
  %v3 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 3
  store i64 %nli, ptr %v3, align 8
  %szi = call i64 @rg_box_int(i64 %sz2)
  %v4 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 4
  store i64 %szi, ptr %v4, align 8
  %ow = call i64 @rg_empty()
  %v5 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 5
  store i64 %ow, ptr %v5, align 8
  %gr = call i64 @rg_empty()
  %v6 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 6
  store i64 %gr, ptr %v6, align 8
  %mti = call i64 @rg_box_int(i64 %mt2)
  %v7 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 7
  store i64 %mti, ptr %v7, align 8
  %v8 = getelementptr inbounds [9 x i64], ptr %vals, i64 0, i64 8
  store i64 %tgt, ptr %v8, align 8
  %t = call i64 @rg_tuple_of(ptr %vals, i64 9)
  ret i64 %t
}

; ── Deadlines (`with timeout`, FR-COMP-007) ──────────────────
; A stack of absolute deadlines in monotonic ms; a nested block keeps the
; earlier of its own deadline and the one around it.
@rg_deadlines = internal global [64 x i64] zeroinitializer
@rg_ndeadlines = internal global i64 0

define internal i64 @rg_now_ms() {
  %ns = call i64 @__rg_pal_clock_ns(i64 0)
  %ms = sdiv i64 %ns, 1000000
  ret i64 %ms
}

define internal i64 @rg_deadline() {
entry:
  %n = load i64, ptr @rg_ndeadlines, align 8
  %has = icmp sgt i64 %n, 0
  br i1 %has, label %top, label %none
top:
  %n1 = sub i64 %n, 1
  %p = getelementptr inbounds [64 x i64], ptr @rg_deadlines, i64 0, i64 %n1
  %d = load i64, ptr %p, align 8
  ret i64 %d
none:
  ret i64 0
}

define internal i64 @rg_timeout_enter(i64 %ms) {
entry:
  %now = call i64 @rg_now_ms()
  %d0 = add i64 %now, %ms
  %cur = call i64 @rg_deadline()
  %hascur = icmp sgt i64 %cur, 0
  %earlier = icmp slt i64 %cur, %d0
  %keep = and i1 %hascur, %earlier
  %d = select i1 %keep, i64 %cur, i64 %d0
  %n = load i64, ptr @rg_ndeadlines, align 8
  %room = icmp slt i64 %n, 64
  br i1 %room, label %push, label %done
push:
  %p = getelementptr inbounds [64 x i64], ptr @rg_deadlines, i64 0, i64 %n
  store i64 %d, ptr %p, align 8
  %n1 = add i64 %n, 1
  store i64 %n1, ptr @rg_ndeadlines, align 8
  br label %done
done:
  ret i64 0
}

define internal void @rg_timeout_exit() {
entry:
  %n = load i64, ptr @rg_ndeadlines, align 8
  %has = icmp sgt i64 %n, 0
  br i1 %has, label %pop, label %done
pop:
  %n1 = sub i64 %n, 1
  store i64 %n1, ptr @rg_ndeadlines, align 8
  br label %done
done:
  ret void
}

; The ms left before the active deadline (at least 0), or -1 without one.
define i64 @rg_remaining_ms() {
entry:
  %d = call i64 @rg_deadline()
  %has = icmp sgt i64 %d, 0
  br i1 %has, label %left, label %none
left:
  %now = call i64 @rg_now_ms()
  %l = sub i64 %d, %now
  %neg = icmp slt i64 %l, 0
  %r = select i1 %neg, i64 0, i64 %l
  ret i64 %r
none:
  ret i64 -1
}

; ── Dispatch ─────────────────────────────────────────────────
; Builtins of this file; any other id goes on to the agents.
declare i64 @__rg_pal_poll(i64, i64, i64)

define i64 @rg_builtin_sys(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %next [ i64 0, label %cli
                                i64 2, label %getcwd
                                i64 14, label %readf
                                i64 15, label %readf
                                i64 18, label %lsdir
                                i64 19, label %lstat
                                i64 22, label %chdir
                                i64 23, label %getenv
                                i64 45, label %writef
                                i64 46, label %mkdir
                                i64 48, label %setenv
                                i64 72, label %deadline
                                i64 73, label %remaining
                                i64 74, label %sleep
                                i64 75, label %openm
                                i64 76, label %open
                                i64 77, label %close
                                i64 78, label %readfd
                                i64 79, label %writefd
                                i64 80, label %poll
                                i64 84, label %tenter
                                i64 85, label %texit
                                i64 100, label %ns
                                i64 101, label %wall
                                i64 102, label %ms
                                i64 122, label %rmfile
                                i64 123, label %rmdir
                                i64 124, label %rename ]
next:
  %r = call i64 @rg_builtin_agents(i64 %id, i64 %slots, i64 %n)
  ret i64 %r
poll:
  %f80v = call i64 @rg_arg(i64 %slots, i64 0)
  %e80v = call i64 @rg_arg(i64 %slots, i64 1)
  %t80v = call i64 @rg_arg(i64 %slots, i64 2)
  %f80 = call i64 @rg_int_of(i64 %f80v)
  %e80 = call i64 @rg_int_of(i64 %e80v)
  %t80 = call i64 @rg_int_of(i64 %t80v)
  %neg80 = icmp slt i64 %t80, 0
  %rem80 = call i64 @rg_remaining_ms()
  %useleft = icmp sge i64 %rem80, 0
  %left80 = and i1 %neg80, %useleft
  %ms80 = select i1 %left80, i64 %rem80, i64 %t80
  %p80 = call i64 @__rg_pal_poll(i64 %f80, i64 %e80, i64 %ms80)
  %r80 = call i64 @rg_int(i64 %p80)
  ret i64 %r80
cli:
  %a0 = call i64 @rg_cli_args()
  ret i64 %a0
getcwd:
  %a2 = call i64 @rg_getcwd()
  ret i64 %a2
readf:
  %p14 = call i64 @rg_sarg(i64 %slots, i64 0)
  %r14 = call i64 @rg_read_file(i64 %p14)
  %d14 = call i64 @__rg_rt_drop_val(i64 %p14)
  ret i64 %r14
lsdir:
  %p18 = call i64 @rg_sarg(i64 %slots, i64 0)
  %r18 = call i64 @rg_list_dir(i64 %p18)
  %d18 = call i64 @__rg_rt_drop_val(i64 %p18)
  ret i64 %r18
lstat:
  %p19 = call i64 @rg_sarg(i64 %slots, i64 0)
  %r19 = call i64 @rg_lstat(i64 %p19)
  %d19 = call i64 @__rg_rt_drop_val(i64 %p19)
  ret i64 %r19
chdir:
  %p22 = call i64 @rg_sarg(i64 %slots, i64 0)
  %pd22 = call i64 @rg_str_data(i64 %p22)
  %pl22 = call i64 @rg_str_len(i64 %p22)
  %c22 = call i64 @__rg_pal_chdir(i64 %pd22, i64 %pl22)
  %d22 = call i64 @__rg_rt_drop_val(i64 %p22)
  %bad22 = icmp slt i64 %c22, 0
  %v22 = select i1 %bad22, i64 -1, i64 0
  %r22 = call i64 @rg_int(i64 %v22)
  ret i64 %r22
getenv:
  %k23 = call i64 @rg_sarg(i64 %slots, i64 0)
  %r23 = call i64 @rg_getenv(i64 %k23)
  %d23 = call i64 @__rg_rt_drop_val(i64 %k23)
  ret i64 %r23
writef:
  %p45 = call i64 @rg_sarg(i64 %slots, i64 0)
  %t45 = call i64 @rg_sarg(i64 %slots, i64 1)
  %r45 = call i64 @rg_write_file(i64 %p45, i64 %t45)
  %d45 = call i64 @__rg_rt_drop_val(i64 %p45)
  %e45 = call i64 @__rg_rt_drop_val(i64 %t45)
  ret i64 %r45
mkdir:
  %p46 = call i64 @rg_sarg(i64 %slots, i64 0)
  %m46v = call i64 @rg_arg(i64 %slots, i64 1)
  %m46 = call i64 @rg_int_of(i64 %m46v)
  %pd46 = call i64 @rg_str_data(i64 %p46)
  %pl46 = call i64 @rg_str_len(i64 %p46)
  %c46 = call i64 @__rg_pal_mkdir(i64 %pd46, i64 %pl46, i64 %m46)
  %d46 = call i64 @__rg_rt_drop_val(i64 %p46)
  %ex46 = icmp eq i64 %c46, -17
  %v46 = select i1 %ex46, i64 0, i64 %c46
  %r46 = call i64 @rg_int(i64 %v46)
  ret i64 %r46
setenv:
  %k48 = call i64 @rg_sarg(i64 %slots, i64 0)
  %v48 = call i64 @rg_sarg(i64 %slots, i64 1)
  %c48 = call i64 @rg_setenv(i64 %k48, i64 %v48)
  %r48 = call i64 @rg_int(i64 0)
  ret i64 %r48
deadline:
  %dl = call i64 @rg_deadline()
  %r72 = call i64 @rg_box_int(i64 %dl)
  ret i64 %r72
remaining:
  %rm = call i64 @rg_remaining_ms()
  %r73 = call i64 @rg_box_int(i64 %rm)
  ret i64 %r73
sleep:
  %s74v = call i64 @rg_arg(i64 %slots, i64 0)
  %s74 = call i64 @rg_int_of(i64 %s74v)
  %ns74 = mul i64 %s74, 1000000
  call void @__rg_pal_sleep_ns(i64 %ns74)
  ret i64 0
openm:
  %p75 = call i64 @rg_sarg(i64 %slots, i64 0)
  %m75 = call i64 @rg_sarg(i64 %slots, i64 1)
  %f75 = call i64 @rg_mode_flags(i64 %m75)
  %pd75 = call i64 @rg_str_data(i64 %p75)
  %pl75 = call i64 @rg_str_len(i64 %p75)
  %c75 = call i64 @__rg_pal_open(i64 %pd75, i64 %pl75, i64 %f75, i64 420)
  %d75 = call i64 @__rg_rt_drop_val(i64 %p75)
  %e75 = call i64 @__rg_rt_drop_val(i64 %m75)
  %r75 = call i64 @rg_int(i64 %c75)
  ret i64 %r75
open:
  %p76 = call i64 @rg_sarg(i64 %slots, i64 0)
  %f76v = call i64 @rg_arg(i64 %slots, i64 1)
  %f76 = call i64 @rg_int_of(i64 %f76v)
  %m76v = call i64 @rg_arg(i64 %slots, i64 2)
  %m76 = call i64 @rg_int_of(i64 %m76v)
  %pd76 = call i64 @rg_str_data(i64 %p76)
  %pl76 = call i64 @rg_str_len(i64 %p76)
  %c76 = call i64 @__rg_pal_open(i64 %pd76, i64 %pl76, i64 %f76, i64 %m76)
  %d76 = call i64 @__rg_rt_drop_val(i64 %p76)
  %r76 = call i64 @rg_int(i64 %c76)
  ret i64 %r76
close:
  %f77v = call i64 @rg_arg(i64 %slots, i64 0)
  %f77 = call i64 @rg_int_of(i64 %f77v)
  %c77 = call i64 @__rg_pal_close(i64 %f77)
  %r77 = call i64 @rg_int(i64 %c77)
  ret i64 %r77
readfd:
  %f78v = call i64 @rg_arg(i64 %slots, i64 0)
  %f78 = call i64 @rg_int_of(i64 %f78v)
  %m78v = call i64 @rg_arg(i64 %slots, i64 1)
  %m78 = call i64 @rg_int_of(i64 %m78v)
  %r78 = call i64 @rg_read_fd(i64 %f78, i64 %m78)
  ret i64 %r78
writefd:
  %f79v = call i64 @rg_arg(i64 %slots, i64 0)
  %f79 = call i64 @rg_int_of(i64 %f79v)
  %s79 = call i64 @rg_sarg(i64 %slots, i64 1)
  %sd79 = call i64 @rg_str_data(i64 %s79)
  %sl79 = call i64 @rg_str_len(i64 %s79)
  %w79 = call i64 @rg_write_fd_all(i64 %f79, i64 %sd79, i64 %sl79)
  %d79 = call i64 @__rg_rt_drop_val(i64 %s79)
  %r79 = call i64 @rg_int(i64 %w79)
  ret i64 %r79
tenter:
  %t84v = call i64 @rg_arg(i64 %slots, i64 0)
  %t84 = call i64 @rg_int_of(i64 %t84v)
  %r84 = call i64 @rg_timeout_enter(i64 %t84)
  ret i64 %r84
texit:
  %v85 = call i64 @rg_arg(i64 %slots, i64 0)
  call void @rg_timeout_exit()
  ret i64 %v85
ns:
  %c100 = call i64 @__rg_pal_clock_ns(i64 0)
  %r100 = call i64 @rg_box_int(i64 %c100)
  ret i64 %r100
wall:
  %c101 = call i64 @__rg_pal_clock_ns(i64 1)
  %m101 = sdiv i64 %c101, 1000000
  %r101 = call i64 @rg_box_int(i64 %m101)
  ret i64 %r101
ms:
  %m102 = call i64 @rg_now_ms()
  %r102 = call i64 @rg_box_int(i64 %m102)
  ret i64 %r102
rmfile:
  %p122 = call i64 @rg_sarg(i64 %slots, i64 0)
  %pd122 = call i64 @rg_str_data(i64 %p122)
  %pl122 = call i64 @rg_str_len(i64 %p122)
  %c122 = call i64 @__rg_pal_unlink(i64 %pd122, i64 %pl122)
  %d122 = call i64 @__rg_rt_drop_val(i64 %p122)
  %r122 = call i64 @rg_int(i64 %c122)
  ret i64 %r122
rmdir:
  %p123 = call i64 @rg_sarg(i64 %slots, i64 0)
  %pd123 = call i64 @rg_str_data(i64 %p123)
  %pl123 = call i64 @rg_str_len(i64 %p123)
  %c123 = call i64 @__rg_pal_rmdir(i64 %pd123, i64 %pl123)
  %d123 = call i64 @__rg_rt_drop_val(i64 %p123)
  %r123 = call i64 @rg_int(i64 %c123)
  ret i64 %r123
rename:
  %p124 = call i64 @rg_sarg(i64 %slots, i64 0)
  %q124 = call i64 @rg_sarg(i64 %slots, i64 1)
  %pd124 = call i64 @rg_str_data(i64 %p124)
  %pl124 = call i64 @rg_str_len(i64 %p124)
  %qd124 = call i64 @rg_str_data(i64 %q124)
  %ql124 = call i64 @rg_str_len(i64 %q124)
  %c124 = call i64 @__rg_pal_rename(i64 %pd124, i64 %pl124, i64 %qd124, i64 %ql124)
  %d124 = call i64 @__rg_rt_drop_val(i64 %p124)
  %e124 = call i64 @__rg_rt_drop_val(i64 %q124)
  %r124 = call i64 @rg_int(i64 %c124)
  ret i64 %r124
}
