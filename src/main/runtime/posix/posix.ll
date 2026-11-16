; ============================================================
; src/main/runtime/posix/posix.ll
; The builtins that need a POSIX system (TASK-0096, FR-VM-002, FR-COMP-022):
; `sys call`, the process builtins and `execve`. They run on one primitive of
; the PAL, `__rg_pal_syscall(nr, a1 .. a6)`, with Linux x86-64 numbers; a PAL
; for another system translates the numbers. Targets without a POSIX system
; (wasm32) do not link this file and keep the stub of core/builtins.ll.
; ============================================================

declare i64 @__rg_pal_syscall(i64, i64, i64, i64, i64, i64, i64)
declare i64 @rg_env_table(i64)
declare i64 @rg_str_from(i64, i64)
declare i64 @rg_list_alloc(i64, i64)
declare void @__rg_pal_exit(i64)
declare i64 @__rg_pal_clock_ns(i64)
declare void @rg_no_builtin(i64) noreturn
declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i64 @rg_ldb(i64)
declare void @rg_stb(i64, i64)
declare void @rg_copy(i64, i64, i64)
declare i64 @rg_arg(i64, i64)
declare i64 @rg_int(i64)
declare i64 @rg_int_of(i64)
declare i64 @rg_box_int(i64)
declare i1 @rg_bytes_of(i64, ptr, ptr)
declare i1 @rg_has_tag(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_list_at(i64, i64)
declare void @rg_drop_slots(i64, i64)
declare i64 @__rg_rt_drop_val(i64)
declare i64 @__rg_rt_make_tuple(i64, i64)

define internal i64 @rgp_sc(i64 %nr, i64 %a, i64 %b, i64 %c) {
  %r = call i64 @__rg_pal_syscall(i64 %nr, i64 %a, i64 %b, i64 %c, i64 0, i64 0, i64 0)
  ret i64 %r
}

; The address of the bytes of a String or Tensor[U8] value (0 when it has none).
define i64 @rgp_addr(i64 %v) {
  %d = alloca i64, align 8
  %l = alloca i64, align 8
  %ok = call i1 @rg_bytes_of(i64 %v, ptr %d, ptr %l)
  %a = load i64, ptr %d, align 8
  ret i64 %a
}

define i64 @rgp_len(i64 %v) {
  %d = alloca i64, align 8
  %l = alloca i64, align 8
  %ok = call i1 @rg_bytes_of(i64 %v, ptr %d, ptr %l)
  %n = load i64, ptr %l, align 8
  ret i64 %n
}

; A NUL-terminated copy of a String value, in a fresh block.
define i64 @rgp_cstr(i64 %v) {
  %a = call i64 @rgp_addr(i64 %v)
  %n = call i64 @rgp_len(i64 %v)
  %n1 = add i64 %n, 1
  %b = call i64 @rg_alloc(i64 %n1)
  call void @rg_copy(i64 %b, i64 %a, i64 %n)
  %e = add i64 %b, %n
  call void @rg_stb(i64 %e, i64 0)
  ret i64 %b
}

; A table of C strings, NUL-terminated, in one fresh block: the strings of the
; list (and `first` before them when it is not 0).
define internal i64 @rgp_table(i64 %list, i64 %first) {
entry:
  %n = call i64 @rg_list_len(i64 %list)
  %has = icmp ne i64 %first, 0
  %extra = select i1 %has, i64 1, i64 0
  %count = add i64 %n, %extra
  %fl = call i64 @rgp_len(i64 %first)
  %fs = select i1 %has, i64 %fl, i64 0
  br label %sz
sz:
  %i = phi i64 [ 0, %entry ], [ %i1, %sz2 ]
  %tot = phi i64 [ %fs, %entry ], [ %tot2, %sz2 ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %szb, label %alloc
szb:
  %ia = call i64 @rg_list_at(i64 %list, i64 %i)
  %iv = call i64 @rg_ld(i64 %ia)
  %il = call i64 @rgp_len(i64 %iv)
  %tot2 = add i64 %tot, %il
  br label %sz2
sz2:
  %i1 = add i64 %i, 1
  br label %sz
alloc:
  %strs = add i64 %tot, %count
  %tab = shl i64 %count, 3
  %tab1 = add i64 %tab, 8
  %all = add i64 %tab1, %strs
  %blk = call i64 @rg_alloc(i64 %all)
  %sp0 = add i64 %blk, %tab1
  br i1 %has, label %putfirst, label %items
putfirst:
  %fa = call i64 @rgp_addr(i64 %first)
  call void @rg_copy(i64 %sp0, i64 %fa, i64 %fl)
  %fe = add i64 %sp0, %fl
  call void @rg_stb(i64 %fe, i64 0)
  call void @rg_st(i64 %blk, i64 %sp0)
  %sp1 = add i64 %fe, 1
  br label %items
items:
  %sp = phi i64 [ %sp0, %alloc ], [ %sp1, %putfirst ]
  br label %fill
fill:
  %j = phi i64 [ 0, %items ], [ %j1, %fillb ]
  %cur = phi i64 [ %sp, %items ], [ %cur2, %fillb ]
  %jm = icmp slt i64 %j, %n
  br i1 %jm, label %fillb, label %done
fillb:
  %ja = call i64 @rg_list_at(i64 %list, i64 %j)
  %jv = call i64 @rg_ld(i64 %ja)
  %jd = call i64 @rgp_addr(i64 %jv)
  %jl = call i64 @rgp_len(i64 %jv)
  call void @rg_copy(i64 %cur, i64 %jd, i64 %jl)
  %je = add i64 %cur, %jl
  call void @rg_stb(i64 %je, i64 0)
  %jx = add i64 %j, %extra
  %jo = shl i64 %jx, 3
  %jp = add i64 %blk, %jo
  call void @rg_st(i64 %jp, i64 %cur)
  %cur2 = add i64 %je, 1
  %j1 = add i64 %j, 1
  br label %fill
done:
  %co = shl i64 %count, 3
  %cp = add i64 %blk, %co
  call void @rg_st(i64 %cp, i64 0)
  ret i64 %blk
}

; ── sys call (83) and sys call with buffers (116) ────────────
; nr, a1 .. a6: a String or Tensor[U8] argument passes the address of its
; first byte, any other the Int; the arguments stay alive during the call.
define internal i64 @rgp_syscall(i64 %slots, i64 %n) {
entry:
  %a = alloca [7 x i64], align 8
  %ap = ptrtoint ptr %a to i64
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %m = icmp slt i64 %i, 7
  %in = icmp slt i64 %i, %n
  %go = and i1 %m, %in
  %slot = getelementptr inbounds [7 x i64], ptr %a, i64 0, i64 0
  br i1 %go, label %arg, label %zero
arg:
  %v = call i64 @rg_arg(i64 %slots, i64 %i)
  %isb = call i1 @rgp_is_buf(i64 %v)
  %ad = call i64 @rgp_addr(i64 %v)
  %iv = call i64 @rg_int_of(i64 %v)
  %x = select i1 %isb, i64 %ad, i64 %iv
  br label %store
zero:
  br label %store
store:
  %val = phi i64 [ %x, %arg ], [ 0, %zero ]
  %off = shl i64 %i, 3
  %p = add i64 %ap, %off
  call void @rg_st(i64 %p, i64 %val)
  %i1 = add i64 %i, 1
  br label %next
next:
  %done = icmp sge i64 %i1, 7
  br i1 %done, label %call, label %loop
call:
  %a0 = call i64 @rg_ld(i64 %ap)
  %p1 = add i64 %ap, 8
  %a1 = call i64 @rg_ld(i64 %p1)
  %p2 = add i64 %ap, 16
  %a2 = call i64 @rg_ld(i64 %p2)
  %p3 = add i64 %ap, 24
  %a3 = call i64 @rg_ld(i64 %p3)
  %p4 = add i64 %ap, 32
  %a4 = call i64 @rg_ld(i64 %p4)
  %p5 = add i64 %ap, 40
  %a5 = call i64 @rg_ld(i64 %p5)
  %p6 = add i64 %ap, 48
  %a6 = call i64 @rg_ld(i64 %p6)
  %r = call i64 @__rg_pal_syscall(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5, i64 %a6)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %res = call i64 @rg_box_int(i64 %r)
  ret i64 %res
}

; 1 when the value is a String or a Tensor[U8].
define internal i1 @rgp_is_buf(i64 %v) {
  %s = call i1 @rg_has_tag(i64 %v, i64 1)
  %t = call i1 @rg_has_tag(i64 %v, i64 5)
  %r = or i1 %s, %t
  ret i1 %r
}

; ── Processes ────────────────────────────────────────────────
; The exit code of a wait status: the status byte, or 128 + the signal.
define internal i64 @rgp_code(i64 %st) {
  %sig = and i64 %st, 127
  %sh = lshr i64 %st, 8
  %ex = and i64 %sh, 255
  %sc = add i64 %sig, 128
  %was = icmp ne i64 %sig, 0
  %r = select i1 %was, i64 %sc, i64 %ex
  ret i64 %r
}

; The first byte after "PATH=" in the table of C strings, or the default path.
@rgp_default_path = private constant [29 x i8] c"/usr/local/bin:/usr/bin:/bin\00"

define internal i64 @rgp_path_of(i64 %envp) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %pa = shl i64 %i, 3
  %pp = add i64 %envp, %pa
  %e = call i64 @rg_ld(i64 %pp)
  %end = icmp eq i64 %e, 0
  br i1 %end, label %dflt, label %test
test:
  %c0 = call i64 @rg_ldb(i64 %e)
  %a1 = add i64 %e, 1
  %c1 = call i64 @rg_ldb(i64 %a1)
  %a2 = add i64 %e, 2
  %c2 = call i64 @rg_ldb(i64 %a2)
  %a3 = add i64 %e, 3
  %c3 = call i64 @rg_ldb(i64 %a3)
  %a4 = add i64 %e, 4
  %c4 = call i64 @rg_ldb(i64 %a4)
  %t0 = icmp eq i64 %c0, 80
  %t1 = icmp eq i64 %c1, 65
  %t2 = icmp eq i64 %c2, 84
  %t3 = icmp eq i64 %c3, 72
  %t4 = icmp eq i64 %c4, 61
  %u0 = and i1 %t0, %t1
  %u1 = and i1 %t2, %t3
  %u2 = and i1 %u0, %u1
  %u3 = and i1 %u2, %t4
  br i1 %u3, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
found:
  %v = add i64 %e, 5
  ret i64 %v
dflt:
  %d = ptrtoint ptr @rgp_default_path to i64
  ret i64 %d
}

; The length of the C string at p up to a ':' or the NUL.
define internal i64 @rgp_seg(i64 %p) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %a = add i64 %p, %i
  %c = call i64 @rg_ldb(i64 %a)
  %z = icmp eq i64 %c, 0
  %col = icmp eq i64 %c, 58
  %stop = or i1 %z, %col
  %i1 = add i64 %i, 1
  br i1 %stop, label %done, label %loop
done:
  ret i64 %i
}

; Runs the program: a name with a '/' as it is, any other name through the
; directories of PATH. Gives only when every attempt failed.
define internal void @rgp_run(i64 %name, i64 %nlen, i64 %argv, i64 %envp) {
entry:
  %slash = call i1 @rgp_has_slash(i64 %name, i64 %nlen)
  br i1 %slash, label %direct, label %search
direct:
  %x = call i64 @rgp_sc(i64 59, i64 %name, i64 %argv, i64 %envp)
  ret void
search:
  %path = call i64 @rgp_path_of(i64 %envp)
  br label %seg
seg:
  %p = phi i64 [ %path, %search ], [ %pn, %next ]
  %sl = call i64 @rgp_seg(i64 %p)
  %need0 = add i64 %sl, %nlen
  %need = add i64 %need0, 2
  %buf = call i64 @rg_alloc(i64 %need)
  call void @rg_copy(i64 %buf, i64 %p, i64 %sl)
  %sp = add i64 %buf, %sl
  call void @rg_stb(i64 %sp, i64 47)
  %np = add i64 %sp, 1
  %nl1 = add i64 %nlen, 1
  call void @rg_copy(i64 %np, i64 %name, i64 %nl1)
  %r = call i64 @rgp_sc(i64 59, i64 %buf, i64 %argv, i64 %envp)
  call void @rg_free(i64 %buf)
  %ea = add i64 %p, %sl
  %ec = call i64 @rg_ldb(i64 %ea)
  %last = icmp eq i64 %ec, 0
  br i1 %last, label %fail, label %next
next:
  %pn = add i64 %ea, 1
  br label %seg
fail:
  ret void
}

define internal i1 @rgp_has_slash(i64 %p, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %m = icmp slt i64 %i, %n
  br i1 %m, label %body, label %no
body:
  %a = add i64 %p, %i
  %c = call i64 @rg_ldb(i64 %a)
  %s = icmp eq i64 %c, 47
  br i1 %s, label %yes, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; sys exec (prog, args, env): runs prog with args (argv[0] is prog), waits and
; gives its exit code; -1 when it cannot be started. No shell.
define internal i64 @rgp_sys_exec(i64 %prog, i64 %args, i64 %env) {
entry:
  %path = call i64 @rgp_cstr(i64 %prog)
  %argv = call i64 @rgp_table(i64 %args, i64 %prog)
  %nlen = call i64 @rgp_len(i64 %prog)
  %envp = call i64 @rg_env_table(i64 %env)
  %pid = call i64 @rgp_sc(i64 57, i64 0, i64 0, i64 0)
  %child = icmp eq i64 %pid, 0
  br i1 %child, label %run, label %parent
run:
  call void @rgp_run(i64 %path, i64 %nlen, i64 %argv, i64 %envp)
  call void @__rg_pal_exit(i64 127)
  unreachable
parent:
  %bad = icmp slt i64 %pid, 0
  br i1 %bad, label %fail, label %wait
wait:
  %st = alloca i64, align 8
  store i64 0, ptr %st, align 8
  %sa = ptrtoint ptr %st to i64
  %w = call i64 @__rg_pal_syscall(i64 61, i64 %pid, i64 %sa, i64 0, i64 0, i64 0, i64 0)
  %s = load i64, ptr %st, align 8
  %sh = lshr i64 %s, 8
  %code = and i64 %sh, 255
  call void @rg_free(i64 %path)
  call void @rg_free(i64 %argv)
  call void @rg_free(i64 %envp)
  ret i64 %code
fail:
  call void @rg_free(i64 %path)
  call void @rg_free(i64 %argv)
  call void @rg_free(i64 %envp)
  ret i64 -1
}

; sys execve (path, argv, envp): replaces the process; gives -errno when it fails.
define internal i64 @rgp_execve(i64 %prog, i64 %argv, i64 %envp) {
  %path = call i64 @rgp_cstr(i64 %prog)
  %av = call i64 @rgp_table(i64 %argv, i64 0)
  %ev = call i64 @rgp_table(i64 %envp, i64 0)
  %r = call i64 @rgp_sc(i64 59, i64 %path, i64 %av, i64 %ev)
  call void @rg_free(i64 %path)
  call void @rg_free(i64 %av)
  call void @rg_free(i64 %ev)
  ret i64 %r
}

; The Int of slot i.
define internal i64 @rgp_iarg(i64 %slots, i64 %i) {
  %v = call i64 @rg_arg(i64 %slots, i64 %i)
  %n = call i64 @rg_int_of(i64 %v)
  %d = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 %n
}

define i64 @rg_builtin_posix(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %none [ i64 83, label %syscall
                                i64 116, label %syscall
                                i64 70, label %getpid
                                i64 47, label %chmod
                                i64 81, label %terminate
                                i64 82, label %kill
                                i64 86, label %pipe
                                i64 87, label %waitpid
                                i64 62, label %exec
                                i64 120, label %execve
                                i64 3, label %getuid
                                i64 4, label %getgid
                                i64 17, label %shell
                                i64 25, label %users
                                i64 26, label %users
                                i64 27, label %users
                                i64 28, label %users
                                i64 29, label %users
                                i64 30, label %users
                                i64 31, label %users
                                i64 125, label %net
                                i64 126, label %net
                                i64 127, label %net
                                i64 128, label %net
                                i64 129, label %net
                                i64 130, label %net
                                i64 131, label %net
                                i64 132, label %net
                                i64 133, label %net
                                i64 134, label %net
                                i64 135, label %net ]
none:
  call void @rg_no_builtin(i64 %id)
  unreachable
getuid:
  %gu = call i64 @rgp_sc(i64 102, i64 0, i64 0, i64 0)
  %gui = call i64 @rg_int(i64 %gu)
  ret i64 %gui
getgid:
  %gg = call i64 @rgp_sc(i64 104, i64 0, i64 0, i64 0)
  %ggi = call i64 @rg_int(i64 %gg)
  ret i64 %ggi
shell:
  %cmd = call i64 @rg_arg(i64 %slots, i64 0)
  %shp = ptrtoint ptr @rgp_bin_sh to i64
  %shs = call i64 @rg_str_from(i64 %shp, i64 7)
  %dc = ptrtoint ptr @rgp_dash_c to i64
  %dcs = call i64 @rg_str_from(i64 %dc, i64 2)
  %sargs = call i64 @rg_list_alloc(i64 2, i64 2)
  %sa0 = call i64 @rg_list_at(i64 %sargs, i64 0)
  call void @rg_st(i64 %sa0, i64 %dcs)
  %sa1 = call i64 @rg_list_at(i64 %sargs, i64 1)
  call void @rg_st(i64 %sa1, i64 %cmd)
  %senv = call i64 @rg_list_alloc(i64 0, i64 0)
  %sr = call i64 @rgp_sys_exec(i64 %shs, i64 %sargs, i64 %senv)
  %sd1 = call i64 @__rg_rt_drop_val(i64 %shs)
  %sd2 = call i64 @__rg_rt_drop_val(i64 %sargs)
  %sd3 = call i64 @__rg_rt_drop_val(i64 %senv)
  %sri = call i64 @rg_int(i64 %sr)
  ret i64 %sri
users:
  %ur = call i64 @rgu_builtin(i64 %id, i64 %slots, i64 %n)
  ret i64 %ur
net:
  %nr = call i64 @rgn_builtin(i64 %id, i64 %slots, i64 %n)
  ret i64 %nr
syscall:
  %rs = call i64 @rgp_syscall(i64 %slots, i64 %n)
  ret i64 %rs
getpid:
  %p = call i64 @rgp_sc(i64 39, i64 0, i64 0, i64 0)
  %rp = call i64 @rg_int(i64 %p)
  ret i64 %rp
chmod:
  %cp = call i64 @rg_arg(i64 %slots, i64 0)
  %cm = call i64 @rgp_iarg(i64 %slots, i64 1)
  %cs = call i64 @rgp_cstr(i64 %cp)
  %cr = call i64 @rgp_sc(i64 90, i64 %cs, i64 %cm, i64 0)
  call void @rg_free(i64 %cs)
  %cd = call i64 @__rg_rt_drop_val(i64 %cp)
  %cneg = icmp slt i64 %cr, 0
  %cv = select i1 %cneg, i64 -1, i64 0
  %rc = call i64 @rg_int(i64 %cv)
  ret i64 %rc
terminate:
  %tp = call i64 @rgp_iarg(i64 %slots, i64 0)
  %tf = call i64 @rg_arg(i64 %slots, i64 1)
  %force = icmp eq i64 %tf, 6
  %sig = select i1 %force, i64 9, i64 15
  %td = call i64 @__rg_rt_drop_val(i64 %tf)
  %tr = call i64 @rgp_sc(i64 62, i64 %tp, i64 %sig, i64 0)
  %rt = call i64 @rg_int(i64 %tr)
  ret i64 %rt
kill:
  %kp = call i64 @rgp_iarg(i64 %slots, i64 0)
  %ks = call i64 @rgp_iarg(i64 %slots, i64 1)
  %kr = call i64 @rgp_sc(i64 62, i64 %kp, i64 %ks, i64 0)
  %rk = call i64 @rg_int(i64 %kr)
  ret i64 %rk
pipe:
  %fds = alloca [2 x i32], align 8
  %fa = ptrtoint ptr %fds to i64
  call void @rg_st(i64 %fa, i64 -1)
  %pr = call i64 @rgp_sc(i64 22, i64 %fa, i64 0, i64 0)
  %f0p = bitcast ptr %fds to ptr
  %f0 = load i32, ptr %f0p, align 4
  %f1q = getelementptr inbounds [2 x i32], ptr %fds, i64 0, i64 1
  %f1 = load i32, ptr %f1q, align 4
  %f0w = sext i32 %f0 to i64
  %f1w = sext i32 %f1 to i64
  %t0 = call i64 @rg_int(i64 %f0w)
  %t1 = call i64 @rg_int(i64 %f1w)
  %tv = alloca [2 x i64], align 8
  %tva = ptrtoint ptr %tv to i64
  call void @rg_st(i64 %tva, i64 %t0)
  %tvb = add i64 %tva, 8
  call void @rg_st(i64 %tvb, i64 %t1)
  %tp2 = call i64 @__rg_rt_make_tuple(i64 %tva, i64 2)
  ret i64 %tp2
waitpid:
  %wp = call i64 @rgp_iarg(i64 %slots, i64 0)
  %wo = call i64 @rgp_iarg(i64 %slots, i64 1)
  %wst = alloca i64, align 8
  store i64 0, ptr %wst, align 8
  %wsa = ptrtoint ptr %wst to i64
  %wr = call i64 @__rg_pal_syscall(i64 61, i64 %wp, i64 %wsa, i64 %wo, i64 0, i64 0, i64 0)
  %ws = load i64, ptr %wst, align 8
  %wc = call i64 @rgp_code(i64 %ws)
  %wneg = icmp slt i64 %wr, 0
  %wpid = select i1 %wneg, i64 -1, i64 %wr
  %w0 = call i64 @rg_int(i64 %wpid)
  %w1 = call i64 @rg_int(i64 %wc)
  %wt = alloca [2 x i64], align 8
  %wta = ptrtoint ptr %wt to i64
  call void @rg_st(i64 %wta, i64 %w0)
  %wtb = add i64 %wta, 8
  call void @rg_st(i64 %wtb, i64 %w1)
  %wtup = call i64 @__rg_rt_make_tuple(i64 %wta, i64 2)
  ret i64 %wtup
exec:
  %ep = call i64 @rg_arg(i64 %slots, i64 0)
  %ea = call i64 @rg_arg(i64 %slots, i64 1)
  %ee = call i64 @rg_arg(i64 %slots, i64 2)
  %er = call i64 @rgp_sys_exec(i64 %ep, i64 %ea, i64 %ee)
  %e1 = call i64 @__rg_rt_drop_val(i64 %ep)
  %e2 = call i64 @__rg_rt_drop_val(i64 %ea)
  %e3 = call i64 @__rg_rt_drop_val(i64 %ee)
  %re = call i64 @rg_int(i64 %er)
  ret i64 %re
execve:
  %xp = call i64 @rg_arg(i64 %slots, i64 0)
  %xa = call i64 @rg_arg(i64 %slots, i64 1)
  %xe = call i64 @rg_arg(i64 %slots, i64 2)
  %xr = call i64 @rgp_execve(i64 %xp, i64 %xa, i64 %xe)
  %x1 = call i64 @__rg_rt_drop_val(i64 %xp)
  %x2 = call i64 @__rg_rt_drop_val(i64 %xa)
  %x3 = call i64 @__rg_rt_drop_val(i64 %xe)
  %rx = call i64 @rg_int(i64 %xr)
  ret i64 %rx
}


; ============================================================
; TCP sockets (FR-VM-003, ADR-0008): builtins 125 .. 135. Results are a
; value >= 0 or -errno. The code keeps its variables in stack slots (llc
; turns them into registers); strings are C strings in fresh blocks.
; ============================================================
declare i64 @rg_remaining_ms()
declare i64 @rg_now_ms()
declare void @rg_fill(i64, i8, i64)

@rgp_bin_sh = private constant [8 x i8] c"/bin/sh\00"
@rgp_dash_c = private constant [3 x i8] c"-c\00"

; A limit in ms: t >= 0 as given; below 0 the time left in a `with timeout`
; block, or -1 (no limit) outside one.
define internal i64 @rgn_limit(i64 %t) {
entry:
  %ok = icmp sge i64 %t, 0
  br i1 %ok, label %given, label %rem
given:
  ret i64 %t
rem:
  %r = call i64 @rg_remaining_ms()
  %has = icmp sge i64 %r, 0
  %v = select i1 %has, i64 %r, i64 -1
  ret i64 %v
}

; The revents of one descriptor, -110 when the time ends, or -errno.
define internal i64 @rgn_poll1(i64 %fd, i64 %ev, i64 %ms) {
entry:
  %bad0 = icmp slt i64 %fd, 0
  %bad1 = icmp sgt i64 %fd, 2147483647
  %bad = or i1 %bad0, %bad1
  br i1 %bad, label %ebadf, label %go
ebadf:
  ret i64 -9
go:
  %p = alloca [2 x i32], align 4
  %pa = ptrtoint ptr %p to i64
  %fd32 = trunc i64 %fd to i32
  %ev32 = trunc i64 %ev to i32
  %evm = and i32 %ev32, 65535
  %w0 = getelementptr inbounds [2 x i32], ptr %p, i64 0, i64 0
  %w1 = getelementptr inbounds [2 x i32], ptr %p, i64 0, i64 1
  store i32 %fd32, ptr %w0, align 4
  store i32 %evm, ptr %w1, align 4
  br label %again
again:
  %r = call i64 @rgp_sc(i64 7, i64 %pa, i64 1, i64 %ms)
  %intr = icmp eq i64 %r, -4
  br i1 %intr, label %reset, label %check
reset:
  store i32 %evm, ptr %w1, align 4
  br label %again
check:
  %neg = icmp slt i64 %r, 0
  br i1 %neg, label %fail, label %zero
fail:
  ret i64 %r
zero:
  %z = icmp eq i64 %r, 0
  br i1 %z, label %timeout, label %rev
timeout:
  ret i64 -110
rev:
  %v = load i32, ptr %w1, align 4
  %rv = lshr i32 %v, 16
  %rz = zext i32 %rv to i64
  ret i64 %rz
}

; What is left of a limit of lim ms started at start; -1 without limit.
define internal i64 @rgn_left(i64 %lim, i64 %start) {
entry:
  %nolim = icmp slt i64 %lim, 0
  br i1 %nolim, label %inf, label %calc
inf:
  ret i64 -1
calc:
  %now = call i64 @rg_now_ms()
  %el = sub i64 %now, %start
  %left = sub i64 %lim, %el
  %neg = icmp slt i64 %left, 0
  %r = select i1 %neg, i64 0, i64 %left
  ret i64 %r
}

define internal void @rgn_sa_fill(i64 %sa, i64 %ip, i64 %port) {
  call void @rg_fill(i64 %sa, i8 0, i64 16)
  call void @rg_stb(i64 %sa, i64 2)
  %a2 = add i64 %sa, 2
  %ph = lshr i64 %port, 8
  call void @rg_stb(i64 %a2, i64 %ph)
  %a3 = add i64 %sa, 3
  call void @rg_stb(i64 %a3, i64 %port)
  %a4 = add i64 %sa, 4
  %i3 = lshr i64 %ip, 24
  call void @rg_stb(i64 %a4, i64 %i3)
  %a5 = add i64 %sa, 5
  %i2 = lshr i64 %ip, 16
  call void @rg_stb(i64 %a5, i64 %i2)
  %a6 = add i64 %sa, 6
  %i1 = lshr i64 %ip, 8
  call void @rg_stb(i64 %a6, i64 %i1)
  %a7 = add i64 %sa, 7
  call void @rg_stb(i64 %a7, i64 %ip)
  ret void
}

define internal i64 @rgn_sa_ip(i64 %sa) {
  %a4 = add i64 %sa, 4
  %b4 = call i64 @rg_ldb(i64 %a4)
  %a5 = add i64 %sa, 5
  %b5 = call i64 @rg_ldb(i64 %a5)
  %a6 = add i64 %sa, 6
  %b6 = call i64 @rg_ldb(i64 %a6)
  %a7 = add i64 %sa, 7
  %b7 = call i64 @rg_ldb(i64 %a7)
  %s4 = shl i64 %b4, 24
  %s5 = shl i64 %b5, 16
  %s6 = shl i64 %b6, 8
  %r0 = or i64 %s4, %s5
  %r1 = or i64 %r0, %s6
  %r2 = or i64 %r1, %b7
  ret i64 %r2
}

; An IPv4 address in dotted text at s: 1 and the address at out, or 0.
define internal i1 @rgn_ip4_parse(i64 %s, i64 %out) {
entry:
  %v = alloca i64, align 8
  %parts = alloca i64, align 8
  %p = alloca i64, align 8
  %n = alloca i64, align 8
  %digits = alloca i64, align 8
  store i64 0, ptr %v, align 8
  store i64 0, ptr %parts, align 8
  store i64 %s, ptr %p, align 8
  br label %part
part:
  store i64 0, ptr %n, align 8
  store i64 0, ptr %digits, align 8
  br label %digit
digit:
  %pp = load i64, ptr %p, align 8
  %c = call i64 @rg_ldb(i64 %pp)
  %ge = icmp sge i64 %c, 48
  %le = icmp sle i64 %c, 57
  %isd = and i1 %ge, %le
  br i1 %isd, label %acc, label %enddigits
acc:
  %n0 = load i64, ptr %n, align 8
  %n10 = mul i64 %n0, 10
  %dv = sub i64 %c, 48
  %n1 = add i64 %n10, %dv
  store i64 %n1, ptr %n, align 8
  %pn = add i64 %pp, 1
  store i64 %pn, ptr %p, align 8
  %d0 = load i64, ptr %digits, align 8
  %d1 = add i64 %d0, 1
  store i64 %d1, ptr %digits, align 8
  %dbig = icmp sgt i64 %d1, 3
  %nbig = icmp sgt i64 %n1, 255
  %bad = or i1 %dbig, %nbig
  br i1 %bad, label %no, label %digit
enddigits:
  %dg = load i64, ptr %digits, align 8
  %nod = icmp eq i64 %dg, 0
  br i1 %nod, label %no, label %store
store:
  %nv = load i64, ptr %n, align 8
  %v0 = load i64, ptr %v, align 8
  %vs = shl i64 %v0, 8
  %v1 = or i64 %vs, %nv
  %v32 = and i64 %v1, 4294967295
  store i64 %v32, ptr %v, align 8
  %pt0 = load i64, ptr %parts, align 8
  %pt1 = add i64 %pt0, 1
  store i64 %pt1, ptr %parts, align 8
  %four = icmp eq i64 %pt1, 4
  br i1 %four, label %tail, label %dot
dot:
  %pd = load i64, ptr %p, align 8
  %dc = call i64 @rg_ldb(i64 %pd)
  %pd1 = add i64 %pd, 1
  store i64 %pd1, ptr %p, align 8
  %isdot = icmp eq i64 %dc, 46
  br i1 %isdot, label %part, label %no
tail:
  %pe = load i64, ptr %p, align 8
  %ec = call i64 @rg_ldb(i64 %pe)
  %more = icmp ne i64 %ec, 0
  br i1 %more, label %no, label %yes
yes:
  %vf = load i64, ptr %v, align 8
  call void @rg_st(i64 %out, i64 %vf)
  ret i1 true
no:
  ret i1 false
}

; The dotted text of an address at d (up to 15 bytes): its length.
define internal i64 @rgn_ip4_text(i64 %v, i64 %d) {
entry:
  %k = alloca i64, align 8
  %i = alloca i64, align 8
  store i64 0, ptr %k, align 8
  store i64 3, ptr %i, align 8
  br label %loop
loop:
  %iv = load i64, ptr %i, align 8
  %sh0 = shl i64 %iv, 3
  %sh = lshr i64 %v, %sh0
  %b = and i64 %sh, 255
  %ge100 = icmp sge i64 %b, 100
  br i1 %ge100, label %h, label %t
h:
  %hd = udiv i64 %b, 100
  %hc = add i64 %hd, 48
  %kh = load i64, ptr %k, align 8
  %ha = add i64 %d, %kh
  call void @rg_stb(i64 %ha, i64 %hc)
  %kh1 = add i64 %kh, 1
  store i64 %kh1, ptr %k, align 8
  br label %t
t:
  %ge10 = icmp sge i64 %b, 10
  br i1 %ge10, label %tt, label %o
tt:
  %td0 = udiv i64 %b, 10
  %td = urem i64 %td0, 10
  %tc = add i64 %td, 48
  %kt = load i64, ptr %k, align 8
  %ta = add i64 %d, %kt
  call void @rg_stb(i64 %ta, i64 %tc)
  %kt1 = add i64 %kt, 1
  store i64 %kt1, ptr %k, align 8
  br label %o
o:
  %od = urem i64 %b, 10
  %oc = add i64 %od, 48
  %ko = load i64, ptr %k, align 8
  %oa = add i64 %d, %ko
  call void @rg_stb(i64 %oa, i64 %oc)
  %ko1 = add i64 %ko, 1
  store i64 %ko1, ptr %k, align 8
  %more = icmp ne i64 %iv, 0
  br i1 %more, label %dot, label %done
dot:
  %kd = load i64, ptr %k, align 8
  %da = add i64 %d, %kd
  call void @rg_stb(i64 %da, i64 46)
  %kd1 = add i64 %kd, 1
  store i64 %kd1, ptr %k, align 8
  %i2 = sub i64 %iv, 1
  store i64 %i2, ptr %i, align 8
  br label %loop
done:
  %kr = load i64, ptr %k, align 8
  ret i64 %kr
}

define internal i64 @rgn_lower(i64 %c) {
  %ge = icmp sge i64 %c, 65
  %le = icmp sle i64 %c, 90
  %up = and i1 %ge, %le
  %l = add i64 %c, 32
  %r = select i1 %up, i64 %l, i64 %c
  ret i64 %r
}

; 1 when the C strings x and y are equal, ignoring case.
define internal i1 @rgn_name_eq(i64 %x, i64 %y) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %xa = add i64 %x, %i
  %ya = add i64 %y, %i
  %xc = call i64 @rg_ldb(i64 %xa)
  %yc = call i64 @rg_ldb(i64 %ya)
  %xl = call i64 @rgn_lower(i64 %xc)
  %yl = call i64 @rgn_lower(i64 %yc)
  %eq = icmp eq i64 %xl, %yl
  %nz = icmp ne i64 %xc, 0
  %both = and i1 %eq, %nz
  br i1 %both, label %next, label %done
next:
  %i1 = add i64 %i, 1
  br label %loop
done:
  %same = icmp eq i64 %xl, %yl
  ret i1 %same
}

; Reads a small file into buf (NUL-terminated): the bytes, or 0 when missing.
define internal i64 @rgn_read_small(i64 %path, i64 %buf, i64 %cap) {
entry:
  %fd = call i64 @rgp_sc(i64 257, i64 -100, i64 %path, i64 524288)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %none, label %rd
none:
  ret i64 0
rd:
  %got = alloca i64, align 8
  store i64 0, ptr %got, align 8
  %room0 = sub i64 %cap, 1
  br label %loop
loop:
  %n = load i64, ptr %got, align 8
  %left = sub i64 %room0, %n
  %full = icmp sle i64 %left, 0
  br i1 %full, label %done, label %rdc
rdc:
  %dst = add i64 %buf, %n
  %r = call i64 @rgp_sc(i64 0, i64 %fd, i64 %dst, i64 %left)
  %stop = icmp sle i64 %r, 0
  br i1 %stop, label %done, label %more
more:
  %n2 = add i64 %n, %r
  store i64 %n2, ptr %got, align 8
  br label %loop
done:
  %c = call i64 @rgp_sc(i64 3, i64 %fd, i64 0, i64 0)
  %nf = load i64, ptr %got, align 8
  %ea = add i64 %buf, %nf
  call void @rg_stb(i64 %ea, i64 0)
  ret i64 %nf
}

; The address of `name` in the hosts table text t (NUL-terminated), line by line:
; 1 and the address at out, or 0.
define internal i1 @rgn_hosts_lookup(i64 %t, i64 %name, i64 %out) {
entry:
  %tok = alloca [256 x i8], align 1
  %toka = ptrtoint ptr %tok to i64
  %line = alloca i64, align 8
  %e = alloca i64, align 8
  %q = alloca i64, align 8
  %first = alloca i64, align 8
  %addr = alloca i64, align 8
  %k = alloca i64, align 8
  store i64 %t, ptr %line, align 8
  br label %lines
lines:
  %l = load i64, ptr %line, align 8
  %lc = call i64 @rg_ldb(i64 %l)
  %end = icmp eq i64 %lc, 0
  br i1 %end, label %no, label %findend
findend:
  store i64 %l, ptr %e, align 8
  br label %fe
fe:
  %ev = load i64, ptr %e, align 8
  %ec = call i64 @rg_ldb(i64 %ev)
  %z = icmp eq i64 %ec, 0
  %nl = icmp eq i64 %ec, 10
  %stop = or i1 %z, %nl
  br i1 %stop, label %scan, label %fenext
fenext:
  %ev1 = add i64 %ev, 1
  store i64 %ev1, ptr %e, align 8
  br label %fe
scan:
  store i64 %l, ptr %q, align 8
  store i64 1, ptr %first, align 8
  store i64 0, ptr %addr, align 8
  br label %toks
toks:
  %qv = load i64, ptr %q, align 8
  %ee = load i64, ptr %e, align 8
  %inl = icmp ult i64 %qv, %ee
  %qc = call i64 @rg_ldb(i64 %qv)
  %nohash = icmp ne i64 %qc, 35
  %cont = and i1 %inl, %nohash
  br i1 %cont, label %skipws, label %nextline
skipws:
  %sq = load i64, ptr %q, align 8
  %sc = call i64 @rg_ldb(i64 %sq)
  %isw0 = icmp eq i64 %sc, 32
  %isw1 = icmp eq i64 %sc, 9
  %isw2 = icmp eq i64 %sc, 13
  %isw3 = or i1 %isw0, %isw1
  %isw = or i1 %isw3, %isw2
  %se = load i64, ptr %e, align 8
  %sin = icmp ult i64 %sq, %se
  %skip = and i1 %isw, %sin
  br i1 %skip, label %skipone, label %aftersk
skipone:
  %sq1 = add i64 %sq, 1
  store i64 %sq1, ptr %q, align 8
  br label %skipws
aftersk:
  %aq = load i64, ptr %q, align 8
  %ae = load i64, ptr %e, align 8
  %aend = icmp uge i64 %aq, %ae
  %ac = call i64 @rg_ldb(i64 %aq)
  %ahash = icmp eq i64 %ac, 35
  %abrk = or i1 %aend, %ahash
  br i1 %abrk, label %nextline, label %token
token:
  store i64 0, ptr %k, align 8
  br label %tk
tk:
  %tq = load i64, ptr %q, align 8
  %te = load i64, ptr %e, align 8
  %tin = icmp ult i64 %tq, %te
  %tc = call i64 @rg_ldb(i64 %tq)
  %t0 = icmp ne i64 %tc, 32
  %t1 = icmp ne i64 %tc, 9
  %t2 = icmp ne i64 %tc, 13
  %t3 = icmp ne i64 %tc, 35
  %tn0 = and i1 %t0, %t1
  %tn1 = and i1 %t2, %t3
  %tn2 = and i1 %tn0, %tn1
  %tgo = and i1 %tin, %tn2
  br i1 %tgo, label %tkput, label %tkend
tkput:
  %kv = load i64, ptr %k, align 8
  %small = icmp slt i64 %kv, 255
  br i1 %small, label %tkstore, label %tkadv
tkstore:
  %ka = add i64 %toka, %kv
  call void @rg_stb(i64 %ka, i64 %tc)
  %kv1 = add i64 %kv, 1
  store i64 %kv1, ptr %k, align 8
  br label %tkadv
tkadv:
  %tq1 = add i64 %tq, 1
  store i64 %tq1, ptr %q, align 8
  br label %tk
tkend:
  %kz = load i64, ptr %k, align 8
  %kza = add i64 %toka, %kz
  call void @rg_stb(i64 %kza, i64 0)
  %fv = load i64, ptr %first, align 8
  %isfirst = icmp ne i64 %fv, 0
  br i1 %isfirst, label %parseaddr, label %cmpname
parseaddr:
  %pok = call i1 @rgn_ip4_parse(i64 %toka, i64 %out)
  br i1 %pok, label %keepaddr, label %nextline
keepaddr:
  %av = call i64 @rg_ld(i64 %out)
  store i64 %av, ptr %addr, align 8
  store i64 0, ptr %first, align 8
  br label %toks
cmpname:
  %same = call i1 @rgn_name_eq(i64 %toka, i64 %name)
  br i1 %same, label %hit, label %toks
hit:
  %ha = load i64, ptr %addr, align 8
  call void @rg_st(i64 %out, i64 %ha)
  ret i1 true
nextline:
  %ne = load i64, ptr %e, align 8
  %nc = call i64 @rg_ldb(i64 %ne)
  %nz = icmp eq i64 %nc, 0
  %ne1 = add i64 %ne, 1
  %nx = select i1 %nz, i64 %ne, i64 %ne1
  store i64 %nx, ptr %line, align 8
  br label %lines
no:
  ret i1 false
}

; The first `nameserver` IPv4 address of resolv.conf text: 1 and the address at out.
define internal i1 @rgn_resolv_server(i64 %t, i64 %out) {
entry:
  %tok = alloca [64 x i8], align 1
  %toka = ptrtoint ptr %tok to i64
  %line = alloca i64, align 8
  %e = alloca i64, align 8
  %q = alloca i64, align 8
  %n = alloca i64, align 8
  store i64 %t, ptr %line, align 8
  br label %lines
lines:
  %l = load i64, ptr %line, align 8
  %lc = call i64 @rg_ldb(i64 %l)
  %end = icmp eq i64 %lc, 0
  br i1 %end, label %no, label %findend
findend:
  store i64 %l, ptr %e, align 8
  br label %fe
fe:
  %ev = load i64, ptr %e, align 8
  %ec = call i64 @rg_ldb(i64 %ev)
  %z = icmp eq i64 %ec, 0
  %nl = icmp eq i64 %ec, 10
  %stop = or i1 %z, %nl
  br i1 %stop, label %kw, label %fenext
fenext:
  %ev1 = add i64 %ev, 1
  store i64 %ev1, ptr %e, align 8
  br label %fe
kw:
  ; "nameserver" followed by a blank
  store i64 %l, ptr %q, align 8
  %kwp = ptrtoint ptr @rgn_kw_ns to i64
  br label %kwloop
kwloop:
  %i = phi i64 [ 0, %kw ], [ %i1, %kwnext ]
  %kc = call i64 @rg_ldb2(i64 %kwp, i64 %i)
  %kz = icmp eq i64 %kc, 0
  br i1 %kz, label %kwdone, label %kwtest
kwtest:
  %qa = add i64 %l, %i
  %ee = load i64, ptr %e, align 8
  %qin = icmp ult i64 %qa, %ee
  %qc = call i64 @rg_ldb(i64 %qa)
  %qeq = icmp eq i64 %qc, %kc
  %ok = and i1 %qin, %qeq
  br i1 %ok, label %kwnext, label %nextline
kwnext:
  %i1 = add i64 %i, 1
  br label %kwloop
kwdone:
  %pa = add i64 %l, %i
  %ee2 = load i64, ptr %e, align 8
  %pin = icmp ult i64 %pa, %ee2
  %pc = call i64 @rg_ldb(i64 %pa)
  %bl0 = icmp eq i64 %pc, 32
  %bl1 = icmp eq i64 %pc, 9
  %bl = or i1 %bl0, %bl1
  %okb = and i1 %pin, %bl
  br i1 %okb, label %skipb, label %nextline
skipb:
  store i64 %pa, ptr %q, align 8
  br label %sb
sb:
  %sq = load i64, ptr %q, align 8
  %se = load i64, ptr %e, align 8
  %sin = icmp ult i64 %sq, %se
  %sc = call i64 @rg_ldb(i64 %sq)
  %s0 = icmp eq i64 %sc, 32
  %s1 = icmp eq i64 %sc, 9
  %sw = or i1 %s0, %s1
  %sgo = and i1 %sin, %sw
  br i1 %sgo, label %sbnext, label %tok0
sbnext:
  %sq1 = add i64 %sq, 1
  store i64 %sq1, ptr %q, align 8
  br label %sb
tok0:
  store i64 0, ptr %n, align 8
  br label %tk
tk:
  %tq = load i64, ptr %q, align 8
  %te = load i64, ptr %e, align 8
  %tin = icmp ult i64 %tq, %te
  %nv = load i64, ptr %n, align 8
  %nsm = icmp slt i64 %nv, 63
  %tc = call i64 @rg_ldb(i64 %tq)
  %c0 = icmp ne i64 %tc, 32
  %c1 = icmp ne i64 %tc, 9
  %c2 = icmp ne i64 %tc, 13
  %cc0 = and i1 %c0, %c1
  %cc1 = and i1 %cc0, %c2
  %g0 = and i1 %tin, %nsm
  %tgo = and i1 %g0, %cc1
  br i1 %tgo, label %tkput, label %tkend
tkput:
  %ta = add i64 %toka, %nv
  call void @rg_stb(i64 %ta, i64 %tc)
  %nv1 = add i64 %nv, 1
  store i64 %nv1, ptr %n, align 8
  %tq1 = add i64 %tq, 1
  store i64 %tq1, ptr %q, align 8
  br label %tk
tkend:
  %nz2 = load i64, ptr %n, align 8
  %za = add i64 %toka, %nz2
  call void @rg_stb(i64 %za, i64 0)
  %pok = call i1 @rgn_ip4_parse(i64 %toka, i64 %out)
  br i1 %pok, label %yes, label %nextline
yes:
  ret i1 true
nextline:
  %ne = load i64, ptr %e, align 8
  %nc = call i64 @rg_ldb(i64 %ne)
  %nz = icmp eq i64 %nc, 0
  %ne1 = add i64 %ne, 1
  %nx = select i1 %nz, i64 %ne, i64 %ne1
  store i64 %nx, ptr %line, align 8
  br label %lines
no:
  ret i1 false
}

@rgn_kw_ns = private constant [11 x i8] c"nameserver\00"

define internal i64 @rg_ldb2(i64 %p, i64 %i) {
  %a = add i64 %p, %i
  %c = call i64 @rg_ldb(i64 %a)
  ret i64 %c
}

; Skips a DNS name at off in the message m of n bytes; -1 when it runs out.
define internal i64 @rgn_dns_skip(i64 %m, i64 %n, i64 %off0) {
entry:
  %off = alloca i64, align 8
  store i64 %off0, ptr %off, align 8
  br label %loop
loop:
  %o = load i64, ptr %off, align 8
  %more = icmp slt i64 %o, %n
  br i1 %more, label %body, label %fail
body:
  %a = add i64 %m, %o
  %c = call i64 @rg_ldb(i64 %a)
  %z = icmp eq i64 %c, 0
  br i1 %z, label %end0, label %ptr
end0:
  %r0 = add i64 %o, 1
  ret i64 %r0
ptr:
  %hi = and i64 %c, 192
  %isp = icmp eq i64 %hi, 192
  br i1 %isp, label %ptrok, label %step
ptrok:
  %o2 = add i64 %o, 2
  %fits = icmp sle i64 %o2, %n
  %r1 = select i1 %fits, i64 %o2, i64 -1
  ret i64 %r1
step:
  %s1 = add i64 %o, 1
  %s2 = add i64 %s1, %c
  store i64 %s2, ptr %off, align 8
  br label %loop
fail:
  ret i64 -1
}

; One A query over UDP to the server: 1 and the address at out, or 0.
define internal i1 @rgn_dns_query(i64 %server, i64 %name, i64 %out, i64 %ms) {
entry:
  %q = alloca [300 x i8], align 1
  %r = alloca [512 x i8], align 1
  %sa = alloca [16 x i8], align 1
  %qa = ptrtoint ptr %q to i64
  %ra = ptrtoint ptr %r to i64
  %saa = ptrtoint ptr %sa to i64
  %n = alloca i64, align 8
  %s = alloca i64, align 8
  %e = alloca i64, align 8
  call void @rg_fill(i64 %qa, i8 0, i64 12)
  %t = call i64 @__rg_pal_clock_ns(i64 0)
  %idh = lshr i64 %t, 8
  %id = and i64 %t, 65535
  %idhi = lshr i64 %id, 8
  call void @rg_stb(i64 %qa, i64 %idhi)
  %q1 = add i64 %qa, 1
  call void @rg_stb(i64 %q1, i64 %id)
  %q2 = add i64 %qa, 2
  call void @rg_stb(i64 %q2, i64 1)
  %q5 = add i64 %qa, 5
  call void @rg_stb(i64 %q5, i64 1)
  store i64 12, ptr %n, align 8
  store i64 %name, ptr %s, align 8
  br label %labels
labels:
  %sv = load i64, ptr %s, align 8
  %sc = call i64 @rg_ldb(i64 %sv)
  %sz = icmp eq i64 %sc, 0
  br i1 %sz, label %tail, label %lab
lab:
  store i64 %sv, ptr %e, align 8
  br label %le
le:
  %ev = load i64, ptr %e, align 8
  %ec = call i64 @rg_ldb(i64 %ev)
  %e0 = icmp eq i64 %ec, 0
  %e1 = icmp eq i64 %ec, 46
  %estop = or i1 %e0, %e1
  br i1 %estop, label %lend, label %lenext
lenext:
  %ev1 = add i64 %ev, 1
  store i64 %ev1, ptr %e, align 8
  br label %le
lend:
  %len = sub i64 %ev, %sv
  %lshort = icmp slt i64 %len, 1
  %llong = icmp sgt i64 %len, 63
  %nv = load i64, ptr %n, align 8
  %room0 = add i64 %nv, %len
  %room = add i64 %room0, 6
  %lroom = icmp sgt i64 %room, 300
  %b0 = or i1 %lshort, %llong
  %bad = or i1 %b0, %lroom
  br i1 %bad, label %no, label %emit
emit:
  %na = add i64 %qa, %nv
  call void @rg_stb(i64 %na, i64 %len)
  %na1 = add i64 %na, 1
  call void @rg_copy(i64 %na1, i64 %sv, i64 %len)
  %nv2 = add i64 %nv, 1
  %nv3 = add i64 %nv2, %len
  store i64 %nv3, ptr %n, align 8
  %at = icmp ne i64 %ec, 0
  %ev2 = add i64 %ev, 1
  %sn = select i1 %at, i64 %ev2, i64 %ev
  store i64 %sn, ptr %s, align 8
  br label %labels
tail:
  %nt = load i64, ptr %n, align 8
  %ta = add i64 %qa, %nt
  call void @rg_stb(i64 %ta, i64 0)
  %ta1 = add i64 %ta, 1
  call void @rg_stb(i64 %ta1, i64 0)
  %ta2 = add i64 %ta, 2
  call void @rg_stb(i64 %ta2, i64 1)
  %ta3 = add i64 %ta, 3
  call void @rg_stb(i64 %ta3, i64 0)
  %ta4 = add i64 %ta, 4
  call void @rg_stb(i64 %ta4, i64 1)
  %qn = add i64 %nt, 5
  %fd = call i64 @rgp_sc(i64 41, i64 2, i64 524290, i64 0)
  %fbad = icmp slt i64 %fd, 0
  br i1 %fbad, label %no, label %conn
conn:
  call void @rgn_sa_fill(i64 %saa, i64 %server, i64 53)
  %cr = call i64 @rgp_sc(i64 42, i64 %fd, i64 %saa, i64 16)
  %cok = icmp eq i64 %cr, 0
  br i1 %cok, label %send, label %closeno
send:
  %sr = call i64 @__rg_pal_syscall(i64 44, i64 %fd, i64 %qa, i64 %qn, i64 16384, i64 0, i64 0)
  %sok = icmp eq i64 %sr, %qn
  br i1 %sok, label %wait, label %closeno
wait:
  %pr = call i64 @rgn_poll1(i64 %fd, i64 1, i64 %ms)
  %pok = icmp sgt i64 %pr, 0
  br i1 %pok, label %recv, label %closeno
recv:
  %got = call i64 @__rg_pal_syscall(i64 45, i64 %fd, i64 %ra, i64 512, i64 64, i64 0, i64 0)
  %gok = icmp sge i64 %got, 12
  br i1 %gok, label %hdr, label %closeno
hdr:
  %r0 = call i64 @rg_ldb(i64 %ra)
  %r1a = add i64 %ra, 1
  %r1 = call i64 @rg_ldb(i64 %r1a)
  %qq0 = call i64 @rg_ldb(i64 %qa)
  %qq1 = call i64 @rg_ldb(i64 %q1)
  %same0 = icmp eq i64 %r0, %qq0
  %same1 = icmp eq i64 %r1, %qq1
  %r3a = add i64 %ra, 3
  %r3 = call i64 @rg_ldb(i64 %r3a)
  %rc = and i64 %r3, 15
  %rcok = icmp eq i64 %rc, 0
  %h0 = and i1 %same0, %same1
  %h1 = and i1 %h0, %rcok
  br i1 %h1, label %answers, label %closeno
answers:
  %r6a = add i64 %ra, 6
  %r6 = call i64 @rg_ldb(i64 %r6a)
  %r7a = add i64 %ra, 7
  %r7 = call i64 @rg_ldb(i64 %r7a)
  %an0 = shl i64 %r6, 8
  %an = or i64 %an0, %r7
  %off0 = call i64 @rgn_dns_skip(i64 %ra, i64 %got, i64 12)
  %offneg = icmp slt i64 %off0, 0
  %off4 = add i64 %off0, 4
  %offs = select i1 %offneg, i64 %off0, i64 %off4
  %off = alloca i64, align 8
  %i = alloca i64, align 8
  store i64 %offs, ptr %off, align 8
  store i64 0, ptr %i, align 8
  br label %aloop
aloop:
  %iv = load i64, ptr %i, align 8
  %ov = load i64, ptr %off, align 8
  %c0 = icmp slt i64 %iv, %an
  %c1 = icmp sge i64 %ov, 0
  %c2 = icmp slt i64 %ov, %got
  %c01 = and i1 %c0, %c1
  %c012 = and i1 %c01, %c2
  br i1 %c012, label %abody, label %closeno
abody:
  %o1 = call i64 @rgn_dns_skip(i64 %ra, i64 %got, i64 %ov)
  %o1neg = icmp slt i64 %o1, 0
  %o1e = add i64 %o1, 10
  %o1big = icmp sgt i64 %o1e, %got
  %o1bad = or i1 %o1neg, %o1big
  br i1 %o1bad, label %closeno, label %arec
arec:
  %ta0 = add i64 %ra, %o1
  %tb0 = call i64 @rg_ldb(i64 %ta0)
  %ta1b = add i64 %ta0, 1
  %tb1 = call i64 @rg_ldb(i64 %ta1b)
  %ty0 = shl i64 %tb0, 8
  %type = or i64 %ty0, %tb1
  %la = add i64 %ta0, 8
  %lb0 = call i64 @rg_ldb(i64 %la)
  %la1 = add i64 %ta0, 9
  %lb1 = call i64 @rg_ldb(i64 %la1)
  %rl0 = shl i64 %lb0, 8
  %rdlen = or i64 %rl0, %lb1
  %o2 = add i64 %o1, 10
  %o3 = add i64 %o2, %rdlen
  %o3big = icmp sgt i64 %o3, %got
  br i1 %o3big, label %closeno, label %typechk
typechk:
  %isa = icmp eq i64 %type, 1
  %is4 = icmp eq i64 %rdlen, 4
  %isa4 = and i1 %isa, %is4
  br i1 %isa4, label %found, label %anext
found:
  %ipa = sub i64 %o3, 4
  %ipp = add i64 %ra, %ipa
  %ipv = alloca [8 x i8], align 8
  %ipva = ptrtoint ptr %ipv to i64
  call void @rg_fill(i64 %ipva, i8 0, i64 8)
  %ip = call i64 @rgn_sa_ip4(i64 %ipp)
  call void @rg_st(i64 %out, i64 %ip)
  %c = call i64 @rgp_sc(i64 3, i64 %fd, i64 0, i64 0)
  ret i1 true
anext:
  store i64 %o3, ptr %off, align 8
  %iv1 = add i64 %iv, 1
  store i64 %iv1, ptr %i, align 8
  br label %aloop
closeno:
  %c2x = call i64 @rgp_sc(i64 3, i64 %fd, i64 0, i64 0)
  ret i1 false
no:
  ret i1 false
}

; The address in four bytes at p.
define internal i64 @rgn_sa_ip4(i64 %p) {
  %b0 = call i64 @rg_ldb(i64 %p)
  %a1 = add i64 %p, 1
  %b1 = call i64 @rg_ldb(i64 %a1)
  %a2 = add i64 %p, 2
  %b2 = call i64 @rg_ldb(i64 %a2)
  %a3 = add i64 %p, 3
  %b3 = call i64 @rg_ldb(i64 %a3)
  %s0 = shl i64 %b0, 24
  %s1 = shl i64 %b1, 16
  %s2 = shl i64 %b2, 8
  %r0 = or i64 %s0, %s1
  %r1 = or i64 %r0, %s2
  %r2 = or i64 %r1, %b3
  ret i64 %r2
}

@rgn_hosts_path = private constant [11 x i8] c"/etc/hosts\00"
@rgn_resolv_path = private constant [17 x i8] c"/etc/resolv.conf\00"
@rgn_localhost = private constant [10 x i8] c"localhost\00"

; A host name: /etc/hosts, then `localhost`, then the DNS server of resolv.conf.
; 1 and the address at out, or 0.
define internal i1 @rgn_os_resolve(i64 %name, i64 %out) {
entry:
  %buf = call i64 @rg_alloc(i64 65536)
  %hp = ptrtoint ptr @rgn_hosts_path to i64
  %n = call i64 @rgn_read_small(i64 %hp, i64 %buf, i64 65536)
  %have = icmp ne i64 %n, 0
  br i1 %have, label %lookup, label %local
lookup:
  %h = call i1 @rgn_hosts_lookup(i64 %buf, i64 %name, i64 %out)
  br i1 %h, label %yes, label %local
local:
  %lh = ptrtoint ptr @rgn_localhost to i64
  %isl = call i1 @rgn_name_eq(i64 %name, i64 %lh)
  br i1 %isl, label %loc, label %dns
loc:
  call void @rg_st(i64 %out, i64 2130706433)
  br label %yes
dns:
  %rp = ptrtoint ptr @rgn_resolv_path to i64
  %rn = call i64 @rgn_read_small(i64 %rp, i64 %buf, i64 65536)
  %rhave = icmp ne i64 %rn, 0
  br i1 %rhave, label %srv, label %no
srv:
  %sv = alloca i64, align 8
  %sva = ptrtoint ptr %sv to i64
  %ok = call i1 @rgn_resolv_server(i64 %buf, i64 %sva)
  br i1 %ok, label %query, label %no
query:
  %server = load i64, ptr %sv, align 8
  %lim = call i64 @rgn_limit(i64 -1)
  %lneg = icmp slt i64 %lim, 0
  %lbig = icmp sgt i64 %lim, 5000
  %lcap = or i1 %lneg, %lbig
  %ms = select i1 %lcap, i64 5000, i64 %lim
  %r = call i1 @rgn_dns_query(i64 %server, i64 %name, i64 %out, i64 %ms)
  call void @rg_free(i64 %buf)
  ret i1 %r
yes:
  call void @rg_free(i64 %buf)
  ret i1 true
no:
  call void @rg_free(i64 %buf)
  ret i1 false
}

; An IPv4 address in text, or a host name the system resolves.
define internal i1 @rgn_resolve4(i64 %name, i64 %out) {
entry:
  %c = call i64 @rg_ldb(i64 %name)
  %empty = icmp eq i64 %c, 0
  br i1 %empty, label %no, label %try
try:
  %p = call i1 @rgn_ip4_parse(i64 %name, i64 %out)
  br i1 %p, label %yes, label %os
os:
  %r = call i1 @rgn_os_resolve(i64 %name, i64 %out)
  ret i1 %r
yes:
  ret i1 true
no:
  ret i1 false
}

define internal i64 @rgn_connect(i64 %ip, i64 %port, i64 %lim) {
entry:
  %sa = alloca [16 x i8], align 1
  %saa = ptrtoint ptr %sa to i64
  call void @rgn_sa_fill(i64 %saa, i64 %ip, i64 %port)
  %fd = call i64 @rgp_sc(i64 41, i64 2, i64 526337, i64 0)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %fail, label %conn
fail:
  ret i64 %fd
conn:
  %r0 = call i64 @rgp_sc(i64 42, i64 %fd, i64 %saa, i64 16)
  %r = alloca i64, align 8
  store i64 %r0, ptr %r, align 8
  %inprog = icmp eq i64 %r0, -115
  br i1 %inprog, label %wait, label %done
wait:
  %ev = call i64 @rgn_poll1(i64 %fd, i64 4, i64 %lim)
  %evneg = icmp slt i64 %ev, 0
  br i1 %evneg, label %evfail, label %sockerr
evfail:
  store i64 %ev, ptr %r, align 8
  br label %done
sockerr:
  %eb = alloca [2 x i32], align 4
  %eba = ptrtoint ptr %eb to i64
  %e0 = getelementptr inbounds [2 x i32], ptr %eb, i64 0, i64 0
  %e1 = getelementptr inbounds [2 x i32], ptr %eb, i64 0, i64 1
  store i32 0, ptr %e0, align 4
  store i32 4, ptr %e1, align 4
  %lenp = ptrtoint ptr %e1 to i64
  %g = call i64 @__rg_pal_syscall(i64 55, i64 %fd, i64 1, i64 4, i64 %eba, i64 %lenp, i64 0)
  %gneg = icmp slt i64 %g, 0
  %errv = load i32, ptr %e0, align 4
  %err = zext i32 %errv to i64
  %nerr = sub i64 0, %err
  %rr = select i1 %gneg, i64 %g, i64 %nerr
  store i64 %rr, ptr %r, align 8
  br label %done
done:
  %rv = load i64, ptr %r, align 8
  %rneg = icmp slt i64 %rv, 0
  br i1 %rneg, label %closefail, label %block
closefail:
  %c = call i64 @rgp_sc(i64 3, i64 %fd, i64 0, i64 0)
  ret i64 %rv
block:
  %f = call i64 @rgp_sc(i64 72, i64 %fd, i64 4, i64 2)
  ret i64 %fd
}

define internal i64 @rgn_listen(i64 %ip, i64 %port, i64 %backlog) {
entry:
  %sa = alloca [16 x i8], align 1
  %saa = ptrtoint ptr %sa to i64
  %one = alloca i32, align 4
  store i32 1, ptr %one, align 4
  %onea = ptrtoint ptr %one to i64
  %fd = call i64 @rgp_sc(i64 41, i64 2, i64 524289, i64 0)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %fail, label %opt
fail:
  ret i64 %fd
opt:
  %so = call i64 @__rg_pal_syscall(i64 54, i64 %fd, i64 1, i64 2, i64 %onea, i64 4, i64 0)
  call void @rgn_sa_fill(i64 %saa, i64 %ip, i64 %port)
  %b = call i64 @rgp_sc(i64 49, i64 %fd, i64 %saa, i64 16)
  %bneg = icmp slt i64 %b, 0
  br i1 %bneg, label %closefail, label %lst
lst:
  %l = call i64 @rgp_sc(i64 50, i64 %fd, i64 %backlog, i64 0)
  %lneg = icmp slt i64 %l, 0
  br i1 %lneg, label %closefail2, label %ok
closefail:
  %c1 = call i64 @rgp_sc(i64 3, i64 %fd, i64 0, i64 0)
  ret i64 %b
closefail2:
  %c2 = call i64 @rgp_sc(i64 3, i64 %fd, i64 0, i64 0)
  ret i64 %l
ok:
  ret i64 %fd
}

define internal i64 @rgn_accept(i64 %fd, i64 %lim) {
  %ev = call i64 @rgn_poll1(i64 %fd, i64 1, i64 %lim)
  %neg = icmp slt i64 %ev, 0
  br i1 %neg, label %fail, label %go
fail:
  ret i64 %ev
go:
  %r = call i64 @__rg_pal_syscall(i64 288, i64 %fd, i64 0, i64 0, i64 524288, i64 0, i64 0)
  ret i64 %r
}

define internal i64 @rgn_send(i64 %fd, i64 %d, i64 %n, i64 %lim) {
entry:
  %start = call i64 @rg_now_ms()
  %sent = alloca i64, align 8
  store i64 0, ptr %sent, align 8
  br label %loop
loop:
  %s = load i64, ptr %sent, align 8
  %more = icmp slt i64 %s, %n
  br i1 %more, label %wait, label %done
wait:
  %left = call i64 @rgn_left(i64 %lim, i64 %start)
  %ev = call i64 @rgn_poll1(i64 %fd, i64 4, i64 %left)
  %evneg = icmp slt i64 %ev, 0
  br i1 %evneg, label %evfail, label %snd
evfail:
  %anysent = icmp ne i64 %s, 0
  %rv = select i1 %anysent, i64 %s, i64 %ev
  ret i64 %rv
snd:
  %p = add i64 %d, %s
  %rest = sub i64 %n, %s
  %r = call i64 @__rg_pal_syscall(i64 44, i64 %fd, i64 %p, i64 %rest, i64 16448, i64 0, i64 0)
  %again = icmp eq i64 %r, -11
  %intr = icmp eq i64 %r, -4
  %retry = or i1 %again, %intr
  br i1 %retry, label %loop, label %chk
chk:
  %neg = icmp slt i64 %r, 0
  br i1 %neg, label %sfail, label %adv
sfail:
  %any2 = icmp ne i64 %s, 0
  %rv2 = select i1 %any2, i64 %s, i64 %r
  ret i64 %rv2
adv:
  %s2 = add i64 %s, %r
  store i64 %s2, ptr %sent, align 8
  br label %loop
done:
  %sf = load i64, ptr %sent, align 8
  ret i64 %sf
}

define internal i64 @rgn_recv(i64 %fd, i64 %d, i64 %n, i64 %lim) {
entry:
  %start = call i64 @rg_now_ms()
  br label %loop
loop:
  %left = call i64 @rgn_left(i64 %lim, i64 %start)
  %ev = call i64 @rgn_poll1(i64 %fd, i64 1, i64 %left)
  %evneg = icmp slt i64 %ev, 0
  br i1 %evneg, label %fail, label %rcv
fail:
  ret i64 %ev
rcv:
  %r = call i64 @__rg_pal_syscall(i64 45, i64 %fd, i64 %d, i64 %n, i64 64, i64 0, i64 0)
  %again = icmp eq i64 %r, -11
  %intr = icmp eq i64 %r, -4
  %retry = or i1 %again, %intr
  br i1 %retry, label %loop, label %done
done:
  ret i64 %r
}

; Socket option by index: 0 nodelay, 1 keepalive, 2 reuseport, 3 broadcast,
; 4 rcvbuf, 5 sndbuf.
define internal i64 @rgn_option(i64 %fd, i64 %idx, i64 %value) {
entry:
  %v = alloca i32, align 4
  %v32 = trunc i64 %value to i32
  store i32 %v32, ptr %v, align 4
  %va = ptrtoint ptr %v to i64
  switch i64 %idx, label %unknown [ i64 0, label %nodelay
                                    i64 1, label %keepalive
                                    i64 2, label %reuseport
                                    i64 3, label %broadcast
                                    i64 4, label %rcvbuf
                                    i64 5, label %sndbuf ]
unknown:
  ret i64 -92
nodelay:
  %r0 = call i64 @__rg_pal_syscall(i64 54, i64 %fd, i64 6, i64 1, i64 %va, i64 4, i64 0)
  ret i64 %r0
keepalive:
  %r1 = call i64 @__rg_pal_syscall(i64 54, i64 %fd, i64 1, i64 9, i64 %va, i64 4, i64 0)
  ret i64 %r1
reuseport:
  %r2 = call i64 @__rg_pal_syscall(i64 54, i64 %fd, i64 1, i64 15, i64 %va, i64 4, i64 0)
  ret i64 %r2
broadcast:
  %r3 = call i64 @__rg_pal_syscall(i64 54, i64 %fd, i64 1, i64 6, i64 %va, i64 4, i64 0)
  ret i64 %r3
rcvbuf:
  %r4 = call i64 @__rg_pal_syscall(i64 54, i64 %fd, i64 1, i64 8, i64 %va, i64 4, i64 0)
  ret i64 %r4
sndbuf:
  %r5 = call i64 @__rg_pal_syscall(i64 54, i64 %fd, i64 1, i64 7, i64 %va, i64 4, i64 0)
  ret i64 %r5
}

; The local port (peer 0) or the peer's IPv4 address (peer 1) of a socket.
define internal i64 @rgn_name(i64 %fd, i64 %peer) {
entry:
  %sa = alloca [16 x i8], align 1
  %saa = ptrtoint ptr %sa to i64
  %len = alloca i32, align 4
  store i32 16, ptr %len, align 4
  %lena = ptrtoint ptr %len to i64
  call void @rg_fill(i64 %saa, i8 0, i64 16)
  %isp = icmp ne i64 %peer, 0
  %nr = select i1 %isp, i64 52, i64 51
  %r = call i64 @rgp_sc(i64 %nr, i64 %fd, i64 %saa, i64 %lena)
  %neg = icmp slt i64 %r, 0
  br i1 %neg, label %fail, label %fam
fail:
  ret i64 %r
fam:
  %f = call i64 @rg_ldb(i64 %saa)
  %inet = icmp eq i64 %f, 2
  br i1 %inet, label %ok, label %inval
inval:
  ret i64 -22
ok:
  br i1 %isp, label %pip, label %pport
pip:
  %ip = call i64 @rgn_sa_ip(i64 %saa)
  ret i64 %ip
pport:
  %a2 = add i64 %saa, 2
  %hi = call i64 @rg_ldb(i64 %a2)
  %a3 = add i64 %saa, 3
  %lo = call i64 @rg_ldb(i64 %a3)
  %h8 = shl i64 %hi, 8
  %p = or i64 %h8, %lo
  ret i64 %p
}

; The String value of n bytes at p (n <= 0: the empty String).
define internal i64 @rgn_str(i64 %p, i64 %n) {
  %neg = icmp slt i64 %n, 0
  %m = select i1 %neg, i64 0, i64 %n
  %s = call i64 @rg_str_from(i64 %p, i64 %m)
  ret i64 %s
}

; The Int of slot i, left alone (the value is dropped by the caller).
define internal i64 @rgn_iarg(i64 %slots, i64 %i) {
  %v = call i64 @rg_arg(i64 %slots, i64 %i)
  %n = call i64 @rg_int_of(i64 %v)
  ret i64 %n
}

; The builtin: a list of 125 .. 135.
define internal i64 @rgn_builtin(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %bad [ i64 125, label %connect
                               i64 126, label %listen
                               i64 127, label %accept
                               i64 128, label %send
                               i64 129, label %recvinto
                               i64 130, label %recv
                               i64 131, label %shutdown
                               i64 132, label %option
                               i64 133, label %lport
                               i64 134, label %peerip
                               i64 135, label %resolve ]
bad:
  call void @rg_no_builtin(i64 %id)
  unreachable
connect:
  %hv = call i64 @rg_arg(i64 %slots, i64 0)
  %port = call i64 @rgn_iarg(i64 %slots, i64 1)
  %tmo = call i64 @rgn_iarg(i64 %slots, i64 2)
  %h = call i64 @rgp_cstr(i64 %hv)
  %hl = call i64 @rgp_len(i64 %hv)
  %ip = alloca i64, align 8
  %ipa = ptrtoint ptr %ip to i64
  %pbad0 = icmp slt i64 %port, 0
  %pbad1 = icmp sgt i64 %port, 65535
  %pbad = or i1 %pbad0, %pbad1
  %hlong = icmp sge i64 %hl, 256
  %abad = or i1 %pbad, %hlong
  br i1 %abad, label %cinval, label %cres
cinval:
  call void @rg_free(i64 %h)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ci = call i64 @rg_int(i64 -22)
  ret i64 %ci
cres:
  %rok = call i1 @rgn_resolve4(i64 %h, i64 %ipa)
  call void @rg_free(i64 %h)
  br i1 %rok, label %cdo, label %cnoent
cnoent:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %cn = call i64 @rg_int(i64 -2)
  ret i64 %cn
cdo:
  %ipv = load i64, ptr %ip, align 8
  %lim = call i64 @rgn_limit(i64 %tmo)
  %cr = call i64 @rgn_connect(i64 %ipv, i64 %port, i64 %lim)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %crv = call i64 @rg_int(i64 %cr)
  ret i64 %crv
listen:
  %lh = call i64 @rg_arg(i64 %slots, i64 0)
  %lport0 = call i64 @rgn_iarg(i64 %slots, i64 1)
  %lback = call i64 @rgn_iarg(i64 %slots, i64 2)
  %lc = call i64 @rgp_cstr(i64 %lh)
  %llen = call i64 @rgp_len(i64 %lh)
  %lp0 = icmp slt i64 %lport0, 0
  %lp1 = icmp sgt i64 %lport0, 65535
  %lp = or i1 %lp0, %lp1
  %lb = icmp slt i64 %lback, 1
  %lhl = icmp sge i64 %llen, 256
  %lbad0 = or i1 %lp, %lb
  %lbad = or i1 %lbad0, %lhl
  br i1 %lbad, label %linval, label %lres
linval:
  call void @rg_free(i64 %lc)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %li = call i64 @rg_int(i64 -22)
  ret i64 %li
lres:
  %lip = alloca i64, align 8
  store i64 0, ptr %lip, align 8
  %lipa = ptrtoint ptr %lip to i64
  %lfirst = call i64 @rg_ldb(i64 %lc)
  %lhas = icmp ne i64 %lfirst, 0
  br i1 %lhas, label %lresolve, label %ldo
lresolve:
  %lrok = call i1 @rgn_resolve4(i64 %lc, i64 %lipa)
  br i1 %lrok, label %ldo, label %lnoent
lnoent:
  call void @rg_free(i64 %lc)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ln = call i64 @rg_int(i64 -2)
  ret i64 %ln
ldo:
  call void @rg_free(i64 %lc)
  %lipv = load i64, ptr %lip, align 8
  %lr = call i64 @rgn_listen(i64 %lipv, i64 %lport0, i64 %lback)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %lrv = call i64 @rg_int(i64 %lr)
  ret i64 %lrv
accept:
  %afd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %atmo = call i64 @rgn_iarg(i64 %slots, i64 1)
  %alim = call i64 @rgn_limit(i64 %atmo)
  %ar = call i64 @rgn_accept(i64 %afd, i64 %alim)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %arv = call i64 @rg_int(i64 %ar)
  ret i64 %arv
send:
  %sfd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %sdata = call i64 @rg_arg(i64 %slots, i64 1)
  %stmo = call i64 @rgn_iarg(i64 %slots, i64 2)
  %sd = alloca i64, align 8
  %sl = alloca i64, align 8
  %sok = call i1 @rg_bytes_of(i64 %sdata, ptr %sd, ptr %sl)
  %sdv = load i64, ptr %sd, align 8
  %slv = load i64, ptr %sl, align 8
  br i1 %sok, label %sgo, label %sinval
sinval:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %si = call i64 @rg_int(i64 -22)
  ret i64 %si
sgo:
  %szero = icmp eq i64 %slv, 0
  br i1 %szero, label %sz, label %ssend
sz:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %szr = call i64 @rg_int(i64 0)
  ret i64 %szr
ssend:
  %slim = call i64 @rgn_limit(i64 %stmo)
  %sr = call i64 @rgn_send(i64 %sfd, i64 %sdv, i64 %slv, i64 %slim)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %srv = call i64 @rg_int(i64 %sr)
  ret i64 %srv
recvinto:
  %rfd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %rt = call i64 @rg_arg(i64 %slots, i64 1)
  %rfrom = call i64 @rgn_iarg(i64 %slots, i64 2)
  %rcount = call i64 @rgn_iarg(i64 %slots, i64 3)
  %rtmo = call i64 @rgn_iarg(i64 %slots, i64 4)
  %rd = alloca i64, align 8
  %rl = alloca i64, align 8
  %rbok = call i1 @rg_bytes_of(i64 %rt, ptr %rd, ptr %rl)
  %rdv = load i64, ptr %rd, align 8
  %rlv = load i64, ptr %rl, align 8
  %rb0 = xor i1 %rbok, true
  %rb1 = icmp slt i64 %rfrom, 0
  %rb2 = icmp slt i64 %rcount, 0
  %rb3 = icmp sgt i64 %rfrom, %rlv
  %room = sub i64 %rlv, %rfrom
  %rb4 = icmp sgt i64 %rcount, %room
  %rb01 = or i1 %rb0, %rb1
  %rb23 = or i1 %rb2, %rb3
  %rb234 = or i1 %rb23, %rb4
  %rbad = or i1 %rb01, %rb234
  br i1 %rbad, label %rinval, label %rzero
rinval:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ri = call i64 @rg_int(i64 -22)
  ret i64 %ri
rzero:
  %rz = icmp eq i64 %rcount, 0
  br i1 %rz, label %rz0, label %rrecv
rz0:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %rzv = call i64 @rg_int(i64 0)
  ret i64 %rzv
rrecv:
  %rdst = add i64 %rdv, %rfrom
  %rlim = call i64 @rgn_limit(i64 %rtmo)
  %rr = call i64 @rgn_recv(i64 %rfd, i64 %rdst, i64 %rcount, i64 %rlim)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %rrv = call i64 @rg_int(i64 %rr)
  ret i64 %rrv
recv:
  %vfd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %vmax = call i64 @rgn_iarg(i64 %slots, i64 1)
  %vtmo = call i64 @rgn_iarg(i64 %slots, i64 2)
  %vsmall = icmp slt i64 %vmax, 1
  br i1 %vsmall, label %vempty, label %vgo
vempty:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ve = call i64 @rgn_str(i64 0, i64 0)
  ret i64 %ve
vgo:
  %vbuf = call i64 @rg_alloc(i64 %vmax)
  %vlim = call i64 @rgn_limit(i64 %vtmo)
  %vr = call i64 @rgn_recv(i64 %vfd, i64 %vbuf, i64 %vmax, i64 %vlim)
  %vs = call i64 @rgn_str(i64 %vbuf, i64 %vr)
  call void @rg_free(i64 %vbuf)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %vs
shutdown:
  %hfd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %how = call i64 @rgn_iarg(i64 %slots, i64 1)
  %hr = call i64 @rgp_sc(i64 48, i64 %hfd, i64 %how, i64 0)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %hrv = call i64 @rg_int(i64 %hr)
  ret i64 %hrv
option:
  %ofd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %onm = call i64 @rg_arg(i64 %slots, i64 1)
  %oval = call i64 @rgn_iarg(i64 %slots, i64 2)
  %oname = call i64 @rgp_cstr(i64 %onm)
  %olen = call i64 @rgp_len(i64 %onm)
  %olong = icmp sge i64 %olen, 32
  br i1 %olong, label %oinval, label %oidx
oinval:
  call void @rg_free(i64 %oname)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %oi = call i64 @rg_int(i64 -22)
  ret i64 %oi
oidx:
  %oi0 = call i64 @rgn_opt_index(i64 %oname)
  call void @rg_free(i64 %oname)
  %oneg = icmp slt i64 %oi0, 0
  br i1 %oneg, label %ounk, label %oset
ounk:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ou = call i64 @rg_int(i64 -92)
  ret i64 %ou
oset:
  %or = call i64 @rgn_option(i64 %ofd, i64 %oi0, i64 %oval)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %orv = call i64 @rg_int(i64 %or)
  ret i64 %orv
lport:
  %pfd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %pr = call i64 @rgn_name(i64 %pfd, i64 0)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %prv = call i64 @rg_int(i64 %pr)
  ret i64 %prv
peerip:
  %qfd = call i64 @rgn_iarg(i64 %slots, i64 0)
  %qip = call i64 @rgn_name(i64 %qfd, i64 1)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %qneg = icmp slt i64 %qip, 0
  br i1 %qneg, label %qempty, label %qtext
qempty:
  %qe = call i64 @rgn_str(i64 0, i64 0)
  ret i64 %qe
qtext:
  %qb = alloca [16 x i8], align 1
  %qba = ptrtoint ptr %qb to i64
  %ql = call i64 @rgn_ip4_text(i64 %qip, i64 %qba)
  %qs = call i64 @rgn_str(i64 %qba, i64 %ql)
  ret i64 %qs
resolve:
  %nv = call i64 @rg_arg(i64 %slots, i64 0)
  %nc = call i64 @rgp_cstr(i64 %nv)
  %nl = call i64 @rgp_len(i64 %nv)
  %nlong = icmp sge i64 %nl, 256
  %nip = alloca i64, align 8
  %nipa = ptrtoint ptr %nip to i64
  br i1 %nlong, label %nempty, label %nres
nres:
  %nok = call i1 @rgn_resolve4(i64 %nc, i64 %nipa)
  br i1 %nok, label %ntext, label %nempty
nempty:
  call void @rg_free(i64 %nc)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ne = call i64 @rgn_str(i64 0, i64 0)
  ret i64 %ne
ntext:
  call void @rg_free(i64 %nc)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %nipv = load i64, ptr %nip, align 8
  %nb = alloca [16 x i8], align 1
  %nba = ptrtoint ptr %nb to i64
  %nlen = call i64 @rgn_ip4_text(i64 %nipv, i64 %nba)
  %ns = call i64 @rgn_str(i64 %nba, i64 %nlen)
  ret i64 %ns
}

@rgn_opt_names = private constant [76 x i8] c"nodelay\00keepalive\00reuseport\00broadcast\00rcvbuf\00sndbuf\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"

; The index of an option name (0 nodelay ... 5 sndbuf), or -1.
define internal i64 @rgn_opt_index(i64 %name) {
entry:
  %tab = ptrtoint ptr @rgn_opt_names to i64
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %off = phi i64 [ 0, %entry ], [ %off2, %next ]
  %m = icmp slt i64 %i, 6
  br i1 %m, label %cmp, label %none
cmp:
  %cand = add i64 %tab, %off
  %same = call i1 @rgn_cstr_eq(i64 %name, i64 %cand)
  br i1 %same, label %hit, label %next
next:
  %cl = call i64 @rgn_cstrlen(i64 %cand)
  %off1 = add i64 %off, %cl
  %off2 = add i64 %off1, 1
  %i1 = add i64 %i, 1
  br label %loop
hit:
  ret i64 %i
none:
  ret i64 -1
}

define internal i64 @rgn_cstrlen(i64 %p) {
entry:
  br label %loop
loop:
  %n = phi i64 [ 0, %entry ], [ %n2, %loop ]
  %a = add i64 %p, %n
  %c = call i64 @rg_ldb(i64 %a)
  %n2 = add i64 %n, 1
  %z = icmp eq i64 %c, 0
  br i1 %z, label %done, label %loop
done:
  ret i64 %n
}

define internal i1 @rgn_cstr_eq(i64 %x, i64 %y) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %xa = add i64 %x, %i
  %ya = add i64 %y, %i
  %xc = call i64 @rg_ldb(i64 %xa)
  %yc = call i64 @rg_ldb(i64 %ya)
  %eq = icmp eq i64 %xc, %yc
  br i1 %eq, label %next, label %no
next:
  %z = icmp eq i64 %xc, 0
  %i1 = add i64 %i, 1
  br i1 %z, label %yes, label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; ============================================================
; Users and privileges (FR-VM-002 §3): builtins 25 .. 31.
; ============================================================

@rgu_passwd = private constant [12 x i8] c"/etc/passwd\00"
@rgu_group = private constant [11 x i8] c"/etc/group\00"
@rgu_tty = private constant [9 x i8] c"/dev/tty\00"

; The text of a small file in a fresh block (NUL-terminated), 0 when missing.
define internal i64 @rgu_load(i64 %path) {
  %buf = call i64 @rg_alloc(i64 1048576)
  %n = call i64 @rgn_read_small(i64 %path, i64 %buf, i64 1048576)
  %has = icmp ne i64 %n, 0
  br i1 %has, label %ok, label %none
ok:
  ret i64 %buf
none:
  call void @rg_free(i64 %buf)
  ret i64 0
}

; The end of the line at p (the address of its '\n' or NUL).
define internal i64 @rgu_eol(i64 %p) {
entry:
  br label %loop
loop:
  %q = phi i64 [ %p, %entry ], [ %q1, %loop ]
  %c = call i64 @rg_ldb(i64 %q)
  %z = icmp eq i64 %c, 0
  %nl = icmp eq i64 %c, 10
  %stop = or i1 %z, %nl
  %q1 = add i64 %q, 1
  br i1 %stop, label %done, label %loop
done:
  ret i64 %q
}

; The end of the field at p: the address of its ':' or of the line end e.
define internal i64 @rgu_field_end(i64 %p, i64 %e) {
entry:
  br label %loop
loop:
  %q = phi i64 [ %p, %entry ], [ %q1, %next ]
  %in = icmp ult i64 %q, %e
  br i1 %in, label %test, label %done
test:
  %c = call i64 @rg_ldb(i64 %q)
  %col = icmp eq i64 %c, 58
  br i1 %col, label %done, label %next
next:
  %q1 = add i64 %q, 1
  br label %loop
done:
  ret i64 %q
}

; The decimal number in [p, e): its value, or -1 when it is empty or not a number.
define internal i64 @rgu_num(i64 %p, i64 %e) {
entry:
  %empty = icmp uge i64 %p, %e
  br i1 %empty, label %bad, label %loop
loop:
  %q = phi i64 [ %p, %entry ], [ %q1, %next ]
  %v = phi i64 [ 0, %entry ], [ %v2, %next ]
  %in = icmp ult i64 %q, %e
  br i1 %in, label %digit, label %done
digit:
  %c = call i64 @rg_ldb(i64 %q)
  %ge = icmp sge i64 %c, 48
  %le = icmp sle i64 %c, 57
  %ok = and i1 %ge, %le
  br i1 %ok, label %next, label %bad
next:
  %v10 = mul i64 %v, 10
  %dv = sub i64 %c, 48
  %v2 = add i64 %v10, %dv
  %q1 = add i64 %q, 1
  br label %loop
done:
  ret i64 %v
bad:
  ret i64 -1
}

; The text at [p, e) equals the bytes at k (n bytes).
define internal i1 @rgu_eq(i64 %p, i64 %e, i64 %k, i64 %n) {
  %len = sub i64 %e, %p
  %same = icmp eq i64 %len, %n
  br i1 %same, label %cmp, label %no
cmp:
  %r = call i1 @rg_bytes_eq(i64 %p, i64 %k, i64 %n)
  ret i1 %r
no:
  ret i1 false
}

declare i1 @rg_bytes_eq(i64, i64, i64)

; Scans passwd text: mode 0 finds the user named (key, klen) and writes uid,
; gid at out; mode 1 finds uid `kint` and writes the address and length of
; its name at out. 1 when found.
define internal i1 @rgu_pw_scan(i64 %buf, i64 %mode, i64 %key, i64 %klen, i64 %kint, i64 %out) {
entry:
  %line = alloca i64, align 8
  store i64 %buf, ptr %line, align 8
  br label %lines
lines:
  %l = load i64, ptr %line, align 8
  %lc = call i64 @rg_ldb(i64 %l)
  %end = icmp eq i64 %lc, 0
  br i1 %end, label %no, label %parse
parse:
  %e = call i64 @rgu_eol(i64 %l)
  %n_end = call i64 @rgu_field_end(i64 %l, i64 %e)
  %p1 = add i64 %n_end, 1
  %pw_end = call i64 @rgu_field_end(i64 %p1, i64 %e)
  %u0 = add i64 %pw_end, 1
  %u_end = call i64 @rgu_field_end(i64 %u0, i64 %e)
  %g0 = add i64 %u_end, 1
  %g_end = call i64 @rgu_field_end(i64 %g0, i64 %e)
  %uid = call i64 @rgu_num(i64 %u0, i64 %u_end)
  %gid = call i64 @rgu_num(i64 %g0, i64 %g_end)
  %m0 = icmp eq i64 %mode, 0
  br i1 %m0, label %byname, label %byuid
byname:
  %same = call i1 @rgu_eq(i64 %l, i64 %n_end, i64 %key, i64 %klen)
  %ok = icmp sge i64 %gid, 0
  %hit = and i1 %same, %ok
  br i1 %hit, label %fillname, label %next
fillname:
  call void @rg_st(i64 %out, i64 %uid)
  %o1 = add i64 %out, 8
  call void @rg_st(i64 %o1, i64 %gid)
  ret i1 true
byuid:
  %same2 = icmp eq i64 %uid, %kint
  br i1 %same2, label %filluid, label %next
filluid:
  call void @rg_st(i64 %out, i64 %l)
  %nl = sub i64 %n_end, %l
  %o2 = add i64 %out, 8
  call void @rg_st(i64 %o2, i64 %nl)
  ret i1 true
next:
  %ec = call i64 @rg_ldb(i64 %e)
  %ez = icmp eq i64 %ec, 0
  %e1 = add i64 %e, 1
  %nx = select i1 %ez, i64 %e, i64 %e1
  store i64 %nx, ptr %line, align 8
  br label %lines
no:
  ret i1 false
}

; 1 when the comma separated list [p, e) holds the bytes at k (n bytes).
define internal i1 @rgu_member(i64 %p, i64 %e, i64 %k, i64 %n) {
entry:
  %s = alloca i64, align 8
  store i64 %p, ptr %s, align 8
  br label %loop
loop:
  %a = load i64, ptr %s, align 8
  %more = icmp ule i64 %a, %e
  br i1 %more, label %item, label %no
item:
  br label %find
find:
  %q = phi i64 [ %a, %item ], [ %q1, %findnext ]
  %in = icmp ult i64 %q, %e
  br i1 %in, label %ft, label %itemend
ft:
  %c = call i64 @rg_ldb(i64 %q)
  %comma = icmp eq i64 %c, 44
  br i1 %comma, label %itemend, label %findnext
findnext:
  %q1 = add i64 %q, 1
  br label %find
itemend:
  %same = call i1 @rgu_eq(i64 %a, i64 %q, i64 %k, i64 %n)
  br i1 %same, label %yes, label %adv
adv:
  %nx = add i64 %q, 1
  store i64 %nx, ptr %s, align 8
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; The group lines that match: a group whose gid is `primary` or whose member
; list holds the user. With fill = 0 the count; with fill = 1 the names go
; into the list at `list` (a List of the right length).
define internal i64 @rgu_gr_scan(i64 %buf, i64 %user, i64 %ulen, i64 %primary, i64 %fill, i64 %list) {
entry:
  %line = alloca i64, align 8
  %cnt = alloca i64, align 8
  store i64 %buf, ptr %line, align 8
  store i64 0, ptr %cnt, align 8
  br label %lines
lines:
  %l = load i64, ptr %line, align 8
  %lc = call i64 @rg_ldb(i64 %l)
  %end = icmp eq i64 %lc, 0
  br i1 %end, label %done, label %parse
parse:
  %e = call i64 @rgu_eol(i64 %l)
  %n_end = call i64 @rgu_field_end(i64 %l, i64 %e)
  %p1 = add i64 %n_end, 1
  %pw_end = call i64 @rgu_field_end(i64 %p1, i64 %e)
  %g0 = add i64 %pw_end, 1
  %g_end = call i64 @rgu_field_end(i64 %g0, i64 %e)
  %m0 = add i64 %g_end, 1
  %gid = call i64 @rgu_num(i64 %g0, i64 %g_end)
  %isprim = icmp eq i64 %gid, %primary
  %mem = call i1 @rgu_member(i64 %m0, i64 %e, i64 %user, i64 %ulen)
  %valid = icmp sge i64 %gid, 0
  %pm = or i1 %isprim, %mem
  %hit = and i1 %pm, %valid
  br i1 %hit, label %match, label %next
match:
  %c0 = load i64, ptr %cnt, align 8
  %isfill = icmp ne i64 %fill, 0
  br i1 %isfill, label %put, label %bump
put:
  %nlen = sub i64 %n_end, %l
  %s = call i64 @rg_str_from(i64 %l, i64 %nlen)
  %slot = call i64 @rg_list_at(i64 %list, i64 %c0)
  call void @rg_st(i64 %slot, i64 %s)
  br label %bump
bump:
  %c1 = add i64 %c0, 1
  store i64 %c1, ptr %cnt, align 8
  br label %next
next:
  %ec = call i64 @rg_ldb(i64 %e)
  %ez = icmp eq i64 %ec, 0
  %e1 = add i64 %e, 1
  %nx = select i1 %ez, i64 %e, i64 %e1
  store i64 %nx, ptr %line, align 8
  br label %lines
done:
  %r = load i64, ptr %cnt, align 8
  ret i64 %r
}

; The decimal text of a signed number, as a String.
define internal i64 @rgu_dec(i64 %v) {
entry:
  %buf = alloca [24 x i8], align 1
  %ba = ptrtoint ptr %buf to i64
  %neg = icmp slt i64 %v, 0
  %nv = sub i64 0, %v
  %abs = select i1 %neg, i64 %nv, i64 %v
  %k = alloca i64, align 8
  %x = alloca i64, align 8
  store i64 23, ptr %k, align 8
  store i64 %abs, ptr %x, align 8
  br label %loop
loop:
  %xv = load i64, ptr %x, align 8
  %kv = load i64, ptr %k, align 8
  %d = urem i64 %xv, 10
  %c = add i64 %d, 48
  %a = add i64 %ba, %kv
  call void @rg_stb(i64 %a, i64 %c)
  %q = udiv i64 %xv, 10
  store i64 %q, ptr %x, align 8
  %k1 = sub i64 %kv, 1
  store i64 %k1, ptr %k, align 8
  %more = icmp ne i64 %q, 0
  br i1 %more, label %loop, label %sign
sign:
  %kk = load i64, ptr %k, align 8
  br i1 %neg, label %minus, label %emit
minus:
  %ma = add i64 %ba, %kk
  call void @rg_stb(i64 %ma, i64 45)
  %kk2 = sub i64 %kk, 1
  br label %emit
emit:
  %start0 = phi i64 [ %kk, %sign ], [ %kk2, %minus ]
  %start = add i64 %start0, 1
  %p = add i64 %ba, %start
  %n = sub i64 24, %start
  %s = call i64 @rg_str_from(i64 %p, i64 %n)
  ret i64 %s
}

define internal i64 @rgu_username(i64 %uid) {
entry:
  %pw = alloca [12 x i8], align 1
  %pwa = ptrtoint ptr @rgu_passwd to i64
  %buf = call i64 @rgu_load(i64 %pwa)
  %has = icmp ne i64 %buf, 0
  br i1 %has, label %scan, label %dec
scan:
  %out = alloca [2 x i64], align 8
  %oa = ptrtoint ptr %out to i64
  %f = call i1 @rgu_pw_scan(i64 %buf, i64 1, i64 0, i64 0, i64 %uid, i64 %oa)
  br i1 %f, label %found, label %free
found:
  %np = call i64 @rg_ld(i64 %oa)
  %o1 = add i64 %oa, 8
  %nl = call i64 @rg_ld(i64 %o1)
  %s = call i64 @rg_str_from(i64 %np, i64 %nl)
  call void @rg_free(i64 %buf)
  ret i64 %s
free:
  call void @rg_free(i64 %buf)
  br label %dec
dec:
  %d = call i64 @rgu_dec(i64 %uid)
  ret i64 %d
}

define internal i64 @rgu_lookup(i64 %name, i64 %nlen, i64 %outuid, i64 %outgid) {
entry:
  %pwa = ptrtoint ptr @rgu_passwd to i64
  %buf = call i64 @rgu_load(i64 %pwa)
  %has = icmp ne i64 %buf, 0
  br i1 %has, label %scan, label %none
none:
  call void @rg_st(i64 %outuid, i64 -1)
  call void @rg_st(i64 %outgid, i64 -1)
  ret i64 0
scan:
  %out = alloca [2 x i64], align 8
  %oa = ptrtoint ptr %out to i64
  %f = call i1 @rgu_pw_scan(i64 %buf, i64 0, i64 %name, i64 %nlen, i64 0, i64 %oa)
  call void @rg_free(i64 %buf)
  br i1 %f, label %found, label %none
found:
  %u = call i64 @rg_ld(i64 %oa)
  %o1 = add i64 %oa, 8
  %g = call i64 @rg_ld(i64 %o1)
  call void @rg_st(i64 %outuid, i64 %u)
  call void @rg_st(i64 %outgid, i64 %g)
  ret i64 1
}

; The names of the groups of a user, as a List of Strings.
define internal i64 @rgu_groups(i64 %name, i64 %nlen) {
entry:
  %u = alloca i64, align 8
  %g = alloca i64, align 8
  %ua = ptrtoint ptr %u to i64
  %ga = ptrtoint ptr %g to i64
  %found = call i64 @rgu_lookup(i64 %name, i64 %nlen, i64 %ua, i64 %ga)
  %ok = icmp ne i64 %found, 0
  br i1 %ok, label %have, label %empty
empty:
  %e = call i64 @rg_list_alloc(i64 0, i64 0)
  ret i64 %e
have:
  %gid = load i64, ptr %g, align 8
  %pa = ptrtoint ptr @rgu_group to i64
  %buf = call i64 @rgu_load(i64 %pa)
  %hasg = icmp ne i64 %buf, 0
  br i1 %hasg, label %count, label %empty
count:
  %n = call i64 @rgu_gr_scan(i64 %buf, i64 %name, i64 %nlen, i64 %gid, i64 0, i64 0)
  %list = call i64 @rg_list_alloc(i64 %n, i64 %n)
  %f = call i64 @rgu_gr_scan(i64 %buf, i64 %name, i64 %nlen, i64 %gid, i64 1, i64 %list)
  call void @rg_free(i64 %buf)
  ret i64 %list
}

; Reads a password: the prompt goes to the terminal with echo off; without a
; terminal the line comes from standard input and no prompt is printed.
define internal i64 @rgu_read_pass(i64 %prompt, i64 %plen) {
entry:
  %tty = ptrtoint ptr @rgu_tty to i64
  %fd = call i64 @rgp_sc(i64 2, i64 %tty, i64 2, i64 0)
  %hastty = icmp sge i64 %fd, 0
  %tio = alloca [64 x i8], align 8
  %tioa = ptrtoint ptr %tio to i64
  %old = alloca [64 x i8], align 8
  %olda = ptrtoint ptr %old to i64
  br i1 %hastty, label %raw, label %read
raw:
  %w = call i64 @rgp_sc(i64 1, i64 %fd, i64 %prompt, i64 %plen)
  %g = call i64 @rgp_sc(i64 16, i64 %fd, i64 21505, i64 %olda)
  call void @rg_copy(i64 %tioa, i64 %olda, i64 60)
  %lf = add i64 %tioa, 12
  %lv = call i64 @rg_ld32x(i64 %lf)
  %noecho = and i64 %lv, -9
  call void @rg_st32x(i64 %lf, i64 %noecho)
  %s = call i64 @rgp_sc(i64 16, i64 %fd, i64 21506, i64 %tioa)
  br label %read
read:
  %rfd = phi i64 [ 0, %entry ], [ %fd, %raw ]
  %buf = call i64 @rg_alloc(i64 4096)
  %n = alloca i64, align 8
  store i64 0, ptr %n, align 8
  %ch = alloca i64, align 8
  %cha = ptrtoint ptr %ch to i64
  br label %loop
loop:
  %nv = load i64, ptr %n, align 8
  %full = icmp sge i64 %nv, 4095
  br i1 %full, label %fin, label %rd
rd:
  store i64 0, ptr %ch, align 8
  %r = call i64 @rgp_sc(i64 0, i64 %rfd, i64 %cha, i64 1)
  %got = icmp eq i64 %r, 1
  br i1 %got, label %chk, label %fin
chk:
  %c = call i64 @rg_ldb(i64 %cha)
  %nl = icmp eq i64 %c, 10
  br i1 %nl, label %fin, label %put
put:
  %a = add i64 %buf, %nv
  call void @rg_stb(i64 %a, i64 %c)
  %n1 = add i64 %nv, 1
  store i64 %n1, ptr %n, align 8
  br label %loop
fin:
  br i1 %hastty, label %restore, label %str
restore:
  %rs = call i64 @rgp_sc(i64 16, i64 %fd, i64 21506, i64 %olda)
  %nlp = ptrtoint ptr @rgu_newline to i64
  %nlw = call i64 @rgp_sc(i64 1, i64 %fd, i64 %nlp, i64 1)
  %cl = call i64 @rgp_sc(i64 3, i64 %fd, i64 0, i64 0)
  br label %str
str:
  %nf = load i64, ptr %n, align 8
  %s2 = call i64 @rg_str_from(i64 %buf, i64 %nf)
  call void @rg_free(i64 %buf)
  ret i64 %s2
}

@rgu_newline = private constant [1 x i8] c"\0A"

define internal i64 @rg_ld32x(i64 %a) {
  %p = inttoptr i64 %a to ptr
  %v = load i32, ptr %p, align 1
  %z = zext i32 %v to i64
  ret i64 %z
}

define internal void @rg_st32x(i64 %a, i64 %v) {
  %p = inttoptr i64 %a to ptr
  %t = trunc i64 %v to i32
  store i32 %t, ptr %p, align 1
  ret void
}

define internal i64 @rgu_builtin(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %bad [ i64 25, label %username
                               i64 26, label %lookup
                               i64 27, label %groups
                               i64 28, label %setresgid
                               i64 29, label %setgroups
                               i64 30, label %setresuid
                               i64 31, label %readpass ]
bad:
  call void @rg_no_builtin(i64 %id)
  unreachable
username:
  %uid = call i64 @rgp_iarg(i64 %slots, i64 0)
  %un = call i64 @rgu_username(i64 %uid)
  ret i64 %un
lookup:
  %lv = call i64 @rg_arg(i64 %slots, i64 0)
  %la = call i64 @rgp_addr(i64 %lv)
  %ll = call i64 @rgp_len(i64 %lv)
  %lo = alloca [2 x i64], align 8
  %loa = ptrtoint ptr %lo to i64
  %lo1 = add i64 %loa, 8
  %lf = call i64 @rgu_lookup(i64 %la, i64 %ll, i64 %loa, i64 %lo1)
  %lu = call i64 @rg_ld(i64 %loa)
  %lg = call i64 @rg_ld(i64 %lo1)
  %ld = call i64 @__rg_rt_drop_val(i64 %lv)
  %lt = alloca [2 x i64], align 8
  %lta = ptrtoint ptr %lt to i64
  %lui = call i64 @rg_box_int(i64 %lu)
  %lgi = call i64 @rg_box_int(i64 %lg)
  call void @rg_st(i64 %lta, i64 %lui)
  %lta1 = add i64 %lta, 8
  call void @rg_st(i64 %lta1, i64 %lgi)
  %ltup = call i64 @__rg_rt_make_tuple(i64 %lta, i64 2)
  ret i64 %ltup
groups:
  %gv = call i64 @rg_arg(i64 %slots, i64 0)
  %ga = call i64 @rgp_addr(i64 %gv)
  %gl = call i64 @rgp_len(i64 %gv)
  %gr = call i64 @rgu_groups(i64 %ga, i64 %gl)
  %gd = call i64 @__rg_rt_drop_val(i64 %gv)
  ret i64 %gr
setresgid:
  %sg = call i64 @rgp_iarg(i64 %slots, i64 0)
  %sgr = call i64 @__rg_pal_syscall(i64 119, i64 %sg, i64 %sg, i64 %sg, i64 0, i64 0, i64 0)
  %sgn = icmp slt i64 %sgr, 0
  %sgv = select i1 %sgn, i64 -1, i64 0
  %sgi = call i64 @rg_int(i64 %sgv)
  ret i64 %sgi
setresuid:
  %su = call i64 @rgp_iarg(i64 %slots, i64 0)
  %sur = call i64 @__rg_pal_syscall(i64 117, i64 %su, i64 %su, i64 %su, i64 0, i64 0, i64 0)
  %sun = icmp slt i64 %sur, 0
  %suv = select i1 %sun, i64 -1, i64 0
  %sui = call i64 @rg_int(i64 %suv)
  ret i64 %sui
setgroups:
  %hl = call i64 @rg_arg(i64 %slots, i64 0)
  %hn = call i64 @rg_list_len(i64 %hl)
  %hb = shl i64 %hn, 2
  %hb1 = add i64 %hb, 8
  %hbuf = call i64 @rg_alloc(i64 %hb1)
  br label %hloop
hloop:
  %hi = phi i64 [ 0, %setgroups ], [ %hi1, %hbody ]
  %hm = icmp slt i64 %hi, %hn
  br i1 %hm, label %hbody, label %hdone
hbody:
  %ha = call i64 @rg_list_at(i64 %hl, i64 %hi)
  %hv = call i64 @rg_ld(i64 %ha)
  %hint = call i64 @rg_int_of(i64 %hv)
  %ho = shl i64 %hi, 2
  %hp = add i64 %hbuf, %ho
  call void @rg_st32x(i64 %hp, i64 %hint)
  %hi1 = add i64 %hi, 1
  br label %hloop
hdone:
  %hr = call i64 @__rg_pal_syscall(i64 116, i64 %hn, i64 %hbuf, i64 0, i64 0, i64 0, i64 0)
  call void @rg_free(i64 %hbuf)
  %hd = call i64 @__rg_rt_drop_val(i64 %hl)
  %hneg = icmp slt i64 %hr, 0
  %hv2 = select i1 %hneg, i64 -1, i64 0
  %hi2 = call i64 @rg_int(i64 %hv2)
  ret i64 %hi2
readpass:
  %pv = call i64 @rg_arg(i64 %slots, i64 0)
  %pa = call i64 @rgp_addr(i64 %pv)
  %pl = call i64 @rgp_len(i64 %pv)
  %pr = call i64 @rgu_read_pass(i64 %pa, i64 %pl)
  %pd = call i64 @__rg_rt_drop_val(i64 %pv)
  ret i64 %pr
}
