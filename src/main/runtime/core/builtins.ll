; ============================================================
; src/main/runtime/core/builtins.ll
; Builtins called through `builtin (id, slots, count)` (ADR-0013; ids in
; compiler `builtin call id`). A builtin takes its argument slots: it clears
; them and drops the values it does not keep.
; ============================================================

declare i64 @rg_ld(i64)
declare void @rg_buf_write(i64, i64)
declare void @rg_buf_lit(i64, ptr, i64)
declare void @rg_st(i64, i64)
declare i64 @rg_ldb(i64)
declare void @rg_stb(i64, i64)
declare i1 @rg_is_heap(i64)
declare i1 @rg_has_tag(i64, i64)
declare i64 @rg_w1(i64)
declare i64 @rg_rc(i64)
declare i64 @rg_vrc(i64)
declare void @rg_vset_len(i64, i64)
declare i64 @rg_str_data(i64)
declare i64 @rg_str_len(i64)
declare i64 @rg_str_alloc(i64, i64)
declare i64 @rg_str_from(i64, i64)
declare i64 @rg_list_at(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_list_alloc(i64, i64)
declare i1 @rg_bytes_eq(i64, i64, i64)
declare i64 @rg_value_str(i64)
declare i64 @rg_int(i64)
declare i64 @rg_int_of(i64)
declare i1 @rg_is_int(i64)
declare i64 @rg_box_int(i64)
declare i64 @rg_binop(i64, i64, i64)
declare i64 @rg_apply1(i64, i64)
declare i64 @rg_apply2(i64, i64, i64)
declare i64 @__rg_rt_clone_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare void @rg_fatal(ptr, i64)
declare void @__rg_pal_exit(i64)
declare void @rg_buf_init(i64, i64)
declare i64 @rg_builtin_sys(i64, i64, i64)
declare void @rg_buf_byte(i64, i64)
declare void @rg_buf_u64(i64, i64)
declare i64 @rg_buf_str(i64)
declare void @rg_copy(i64, i64, i64)

declare i64 @rg_live_total()
@rg_cond_spared = global i64 0
@rg_cond_freed = global i64 0

; Take the value of argument slot i (the slot is cleared).
define i64 @rg_arg(i64 %slots, i64 %i) alwaysinline {
  %off = shl i64 %i, 3
  %a = add i64 %slots, %off
  %v = call i64 @rg_ld(i64 %a)
  call void @rg_st(i64 %a, i64 0)
  ret i64 %v
}

; ── Strings ──────────────────────────────────────────────────

; The String of one Unicode code point, in UTF-8.
define i64 @rg_char(i64 %c) {
entry:
  %buf = alloca [3 x i64], align 8
  %b = ptrtoint ptr %buf to i64
  call void @rg_buf_init(i64 %b, i64 8)
  %one = icmp ult i64 %c, 128
  br i1 %one, label %b1, label %t2
b1:
  call void @rg_buf_byte(i64 %b, i64 %c)
  br label %done
t2:
  %two = icmp ult i64 %c, 2048
  br i1 %two, label %b2, label %t3
b2:
  %h2 = lshr i64 %c, 6
  %h2b = or i64 %h2, 192
  call void @rg_buf_byte(i64 %b, i64 %h2b)
  br label %last1
t3:
  %three = icmp ult i64 %c, 65536
  br i1 %three, label %b3, label %b4
b3:
  %h3 = lshr i64 %c, 12
  %h3b = or i64 %h3, 224
  call void @rg_buf_byte(i64 %b, i64 %h3b)
  br label %last2
b4:
  %h4 = lshr i64 %c, 18
  %h4m = and i64 %h4, 7
  %h4b = or i64 %h4m, 240
  call void @rg_buf_byte(i64 %b, i64 %h4b)
  %m4 = lshr i64 %c, 12
  %m4a = and i64 %m4, 63
  %m4b = or i64 %m4a, 128
  call void @rg_buf_byte(i64 %b, i64 %m4b)
  br label %last2
last2:
  %m3 = lshr i64 %c, 6
  %m3a = and i64 %m3, 63
  %m3b = or i64 %m3a, 128
  call void @rg_buf_byte(i64 %b, i64 %m3b)
  br label %last1
last1:
  %l = and i64 %c, 63
  %lb = or i64 %l, 128
  call void @rg_buf_byte(i64 %b, i64 %lb)
  br label %done
done:
  %s = call i64 @rg_buf_str(i64 %b)
  ret i64 %s
}

; The Int of text (the contract of str_to_int, compiler.ridgun RG-113):
; trim ASCII whitespace (9..13, 32) at both ends, ignore '_', an optional
; "0x"/"0X" hex prefix before an optional sign, then digits to the end.
; Invalid or out-of-range text gives 0. Accumulates negatively so that
; -2^63 is reachable.
define i1 @rg_is_space(i64 %c) alwaysinline {
  %sp = icmp eq i64 %c, 32
  %c9 = sub i64 %c, 9
  %ct = icmp ult i64 %c9, 5
  %r = or i1 %sp, %ct
  ret i1 %r
}

; The first index >= i in [i, hi) whose byte is not '_'.
define i64 @rg_skip_us(i64 %d, i64 %i, i64 %hi) {
entry:
  br label %loop
loop:
  %j = phi i64 [ %i, %entry ], [ %j1, %next ]
  %more = icmp slt i64 %j, %hi
  br i1 %more, label %test, label %done
test:
  %a = add i64 %d, %j
  %c = call i64 @rg_ldb(i64 %a)
  %us = icmp eq i64 %c, 95
  br i1 %us, label %next, label %done
next:
  %j1 = add i64 %j, 1
  br label %loop
done:
  ret i64 %j
}

define i64 @rg_byte_or(i64 %d, i64 %i, i64 %hi) {
  %in = icmp slt i64 %i, %hi
  %a = add i64 %d, %i
  br i1 %in, label %ld, label %none
ld:
  %c = call i64 @rg_ldb(i64 %a)
  ret i64 %c
none:
  ret i64 -1
}

define i64 @rg_parse_int(i64 %s) {
entry:
  %d = call i64 @rg_str_data(i64 %s)
  %n = call i64 @rg_str_len(i64 %s)
  br label %lo
lo:
  %i = phi i64 [ 0, %entry ], [ %i1, %lon ]
  %lm = icmp slt i64 %i, %n
  br i1 %lm, label %loc, label %hi
loc:
  %la = add i64 %d, %i
  %lc = call i64 @rg_ldb(i64 %la)
  %lsp = call i1 @rg_is_space(i64 %lc)
  br i1 %lsp, label %lon, label %hi
lon:
  %i1 = add i64 %i, 1
  br label %lo
hi:
  %h = phi i64 [ %n, %lo ], [ %h1, %hin ], [ %n, %loc ]
  %hm = icmp sgt i64 %h, %i
  br i1 %hm, label %hic, label %body
hic:
  %hl = sub i64 %h, 1
  %ha = add i64 %d, %hl
  %hc = call i64 @rg_ldb(i64 %ha)
  %hsp = call i1 @rg_is_space(i64 %hc)
  br i1 %hsp, label %hin, label %body
hin:
  %h1 = sub i64 %h, 1
  br label %hi
body:
  %p = call i64 @rg_skip_us(i64 %d, i64 %i, i64 %h)
  %c0 = call i64 @rg_byte_or(i64 %d, i64 %p, i64 %h)
  %z = icmp eq i64 %c0, 48
  %p1 = add i64 %p, 1
  %q = call i64 @rg_skip_us(i64 %d, i64 %p1, i64 %h)
  %cx = call i64 @rg_byte_or(i64 %d, i64 %q, i64 %h)
  %x1 = icmp eq i64 %cx, 120
  %x2 = icmp eq i64 %cx, 88
  %x = or i1 %x1, %x2
  %hex = and i1 %z, %x
  %q1 = add i64 %q, 1
  %qs = call i64 @rg_skip_us(i64 %d, i64 %q1, i64 %h)
  %st = select i1 %hex, i64 %qs, i64 %p
  %base = select i1 %hex, i64 16, i64 10
  %cs = call i64 @rg_byte_or(i64 %d, i64 %st, i64 %h)
  %neg = icmp eq i64 %cs, 45
  %pos = icmp eq i64 %cs, 43
  %hs = or i1 %neg, %pos
  %st1 = add i64 %st, 1
  %sts = call i64 @rg_skip_us(i64 %d, i64 %st1, i64 %h)
  %ds = select i1 %hs, i64 %sts, i64 %st
  br label %dig
dig:
  %j = phi i64 [ %ds, %body ], [ %j1, %dnext ], [ %j1, %dus ]
  %v = phi i64 [ 0, %body ], [ %v1, %dnext ], [ %v, %dus ]
  %dm = icmp slt i64 %j, %h
  br i1 %dm, label %dc, label %done
dc:
  %da = add i64 %d, %j
  %ch = call i64 @rg_ldb(i64 %da)
  %j1 = add i64 %j, 1
  %isus = icmp eq i64 %ch, 95
  br i1 %isus, label %dus, label %dval
dus:
  br label %dig
dval:
  %dv = sub i64 %ch, 48
  %isd = icmp ult i64 %dv, 10
  %ishex = icmp eq i64 %base, 16
  %u = sub i64 %ch, 65
  %uok = icmp ult i64 %u, 6
  %l = sub i64 %ch, 97
  %lok = icmp ult i64 %l, 6
  %hu = add i64 %u, 10
  %hlv = add i64 %l, 10
  %hv0 = select i1 %lok, i64 %hlv, i64 -1
  %hv = select i1 %uok, i64 %hu, i64 %hv0
  %hv1 = select i1 %ishex, i64 %hv, i64 -1
  %dig1 = select i1 %isd, i64 %dv, i64 %hv1
  %bad = icmp slt i64 %dig1, 0
  br i1 %bad, label %zero, label %dchk
dchk:
  ; acc*base - d must stay >= -2^63: acc >= (-2^63 + d) / base
  %mind = add i64 -9223372036854775808, %dig1
  %lim = sdiv i64 %mind, %base
  %ovf = icmp slt i64 %v, %lim
  br i1 %ovf, label %zero, label %dnext
dnext:
  %vb = mul i64 %v, %base
  %v1 = sub i64 %vb, %dig1
  br label %dig
done:
  %empty = icmp eq i64 %j, %ds
  br i1 %empty, label %zero, label %sign
sign:
  br i1 %neg, label %rneg, label %rpos
rneg:
  ret i64 %v
rpos:
  %ismin = icmp eq i64 %v, -9223372036854775808
  %pv = sub i64 0, %v
  %r = select i1 %ismin, i64 0, i64 %pv
  ret i64 %r
zero:
  ret i64 0
}

; 1 when the bytes of p (length pn) occur in s at position i.
define i1 @rg_at(i64 %sd, i64 %sn, i64 %i, i64 %pd, i64 %pn) {
entry:
  %end = add i64 %i, %pn
  %fits = icmp sle i64 %end, %sn
  br i1 %fits, label %cmp, label %no
cmp:
  %a = add i64 %sd, %i
  %r = call i1 @rg_bytes_eq(i64 %a, i64 %pd, i64 %pn)
  ret i1 %r
no:
  ret i1 false
}

define i1 @rg_contains(i64 %s, i64 %p) {
entry:
  %sd = call i64 @rg_str_data(i64 %s)
  %sn = call i64 @rg_str_len(i64 %s)
  %pd = call i64 @rg_str_data(i64 %p)
  %pn = call i64 @rg_str_len(i64 %p)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %last = sub i64 %sn, %pn
  %more = icmp sle i64 %i, %last
  br i1 %more, label %test, label %no
test:
  %hit = call i1 @rg_at(i64 %sd, i64 %sn, i64 %i, i64 %pd, i64 %pn)
  br i1 %hit, label %yes, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; The bytes [a, b) of s, with a and b clamped to 0..length.
define i64 @rg_slice(i64 %s, i64 %a, i64 %b) {
  %n = call i64 @rg_str_len(i64 %s)
  %aneg = icmp slt i64 %a, 0
  %a1 = select i1 %aneg, i64 0, i64 %a
  %abig = icmp sgt i64 %a1, %n
  %a2 = select i1 %abig, i64 %n, i64 %a1
  %bbig = icmp sgt i64 %b, %n
  %b1 = select i1 %bbig, i64 %n, i64 %b
  %bsmall = icmp slt i64 %b1, %a2
  %b2 = select i1 %bsmall, i64 %a2, i64 %b1
  %len = sub i64 %b2, %a2
  %d = call i64 @rg_str_data(i64 %s)
  %src = add i64 %d, %a2
  %r = call i64 @rg_str_from(i64 %src, i64 %len)
  ret i64 %r
}

; ── Lists ────────────────────────────────────────────────────

; Item i of List xs: taken when xs is held only here, else cloned.
define i64 @rg_item(i64 %xs, i64 %i, i1 %own) {
entry:
  %a = call i64 @rg_list_at(i64 %xs, i64 %i)
  %v = call i64 @rg_ld(i64 %a)
  br i1 %own, label %take, label %clone
take:
  call void @rg_st(i64 %a, i64 0)
  ret i64 %v
clone:
  %c = call i64 @__rg_rt_clone_slot(i64 %v)
  ret i64 %c
}

define i1 @rg_sole(i64 %xs) {
  %rc = call i64 @rg_rc(i64 %xs)
  %h = call i64 @rg_w1(i64 %xs)
  %vrc = call i64 @rg_vrc(i64 %h)
  %a = icmp sle i64 %rc, 1
  %b = icmp sle i64 %vrc, 1
  %r = and i1 %a, %b
  ret i1 %r
}

; map (f, xs): [f x | x <- xs]; f and xs are taken.
define i64 @rg_map(i64 %f, i64 %xs) {
entry:
  %n = call i64 @rg_list_len(i64 %xs)
  %own = call i1 @rg_sole(i64 %xs)
  %out = call i64 @rg_list_alloc(i64 %n, i64 %n)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %x = call i64 @rg_item(i64 %xs, i64 %i, i1 %own)
  %y = call i64 @rg_apply1(i64 %f, i64 %x)
  %oa = call i64 @rg_list_at(i64 %out, i64 %i)
  call void @rg_st(i64 %oa, i64 %y)
  %i1 = add i64 %i, 1
  br label %loop
done:
  %d1 = call i64 @__rg_rt_drop_val(i64 %xs)
  %d2 = call i64 @__rg_rt_drop_val(i64 %f)
  ret i64 %out
}

; filter (f, xs): the x of xs for which f x is True; f and xs are taken.
define i64 @rg_filter(i64 %f, i64 %xs) {
entry:
  %n = call i64 @rg_list_len(i64 %xs)
  %out = call i64 @rg_list_alloc(i64 0, i64 %n)
  %h = call i64 @rg_w1(i64 %out)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %k = phi i64 [ 0, %entry ], [ %k1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %x = call i64 @rg_item(i64 %xs, i64 %i, i1 false)
  %xc = call i64 @__rg_rt_clone_slot(i64 %x)
  %t = call i64 @rg_apply1(i64 %f, i64 %xc)
  %keep = icmp eq i64 %t, 6
  %dt = call i64 @__rg_rt_drop_val(i64 %t)
  br i1 %keep, label %put, label %skip
put:
  %oa = call i64 @rg_list_at(i64 %out, i64 %k)
  call void @rg_st(i64 %oa, i64 %x)
  %kp = add i64 %k, 1
  call void @rg_vset_len(i64 %h, i64 %kp)
  br label %next
skip:
  %dx = call i64 @__rg_rt_drop_val(i64 %x)
  br label %next
next:
  %k1 = phi i64 [ %kp, %put ], [ %k, %skip ]
  %i1 = add i64 %i, 1
  br label %loop
done:
  %d1 = call i64 @__rg_rt_drop_val(i64 %xs)
  %d2 = call i64 @__rg_rt_drop_val(i64 %f)
  ret i64 %out
}

; fold (f, acc, xs): acc = f acc x for each x; all taken.
define i64 @rg_fold(i64 %f, i64 %acc0, i64 %xs) {
entry:
  %n = call i64 @rg_list_len(i64 %xs)
  %own = call i1 @rg_sole(i64 %xs)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %acc = phi i64 [ %acc0, %entry ], [ %acc1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %x = call i64 @rg_item(i64 %xs, i64 %i, i1 %own)
  %acc1 = call i64 @rg_apply2(i64 %f, i64 %acc, i64 %x)
  %i1 = add i64 %i, 1
  br label %loop
done:
  %d1 = call i64 @__rg_rt_drop_val(i64 %xs)
  %d2 = call i64 @__rg_rt_drop_val(i64 %f)
  ret i64 %acc
}

; ── Dispatch ─────────────────────────────────────────────────

@rg_msg_nb1 = private constant [23 x i8] c"runtime error: builtin "
@rg_msg_nb2 = private constant [30 x i8] c" not available on this target\0A"

; A builtin this runtime does not have: name its id on stderr, exit 1.
define void @rg_no_builtin(i64 %id) noreturn {
  %buf = alloca [3 x i64], align 8
  %b = ptrtoint ptr %buf to i64
  call void @rg_buf_init(i64 %b, i64 64)
  call void @rg_buf_lit(i64 %b, ptr @rg_msg_nb1, i64 23)
  call void @rg_buf_u64(i64 %b, i64 %id)
  call void @rg_buf_lit(i64 %b, ptr @rg_msg_nb2, i64 30)
  call void @rg_buf_write(i64 %b, i64 2)
  call void @__rg_pal_exit(i64 1)
  unreachable
}

define i64 @__rg_rt_builtin(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %none [ i64 5, label %live
                                i64 6, label %spared
                                i64 7, label %freed
                                i64 10, label %str_len
                                i64 11, label %char
                                i64 12, label %int_to_str
                                i64 13, label %str_to_int
                                i64 24, label %exit
                                i64 40, label %char_at
                                i64 41, label %concat
                                i64 42, label %starts
                                i64 43, label %contains
                                i64 49, label %same
                                i64 53, label %map
                                i64 54, label %map
                                i64 55, label %filter
                                i64 56, label %filter
                                i64 60, label %slice
                                i64 61, label %fold
                                i64 121, label %append ]
live:
  %lv = call i64 @rg_live_total()
  %lr = call i64 @rg_int(i64 %lv)
  ret i64 %lr
spared:
  %sv = load i64, ptr @rg_cond_spared, align 8
  %sr = call i64 @rg_int(i64 %sv)
  ret i64 %sr
freed:
  %fv = load i64, ptr @rg_cond_freed, align 8
  %fr = call i64 @rg_int(i64 %fv)
  ret i64 %fr
str_len:
  %s10 = call i64 @rg_arg(i64 %slots, i64 0)
  %l10 = call i64 @rg_str_len(i64 %s10)
  %d10 = call i64 @__rg_rt_drop_val(i64 %s10)
  %r10 = call i64 @rg_int(i64 %l10)
  ret i64 %r10
char:
  %c11 = call i64 @rg_arg(i64 %slots, i64 0)
  %n11 = call i64 @rg_int_of(i64 %c11)
  %r11 = call i64 @rg_char(i64 %n11)
  ret i64 %r11
int_to_str:
  %v12 = call i64 @rg_arg(i64 %slots, i64 0)
  %r12 = call i64 @rg_value_str(i64 %v12)
  %d12 = call i64 @__rg_rt_drop_val(i64 %v12)
  ret i64 %r12
str_to_int:
  %s13 = call i64 @rg_arg(i64 %slots, i64 0)
  %n13 = call i64 @rg_parse_int(i64 %s13)
  %d13 = call i64 @__rg_rt_drop_val(i64 %s13)
  %r13 = call i64 @rg_int(i64 %n13)
  ret i64 %r13
exit:
  %c24 = call i64 @rg_arg(i64 %slots, i64 0)
  %n24 = call i64 @rg_int_of(i64 %c24)
  call void @__rg_pal_exit(i64 %n24)
  unreachable
char_at:
  %s40 = call i64 @rg_arg(i64 %slots, i64 0)
  %i40v = call i64 @rg_arg(i64 %slots, i64 1)
  %i40 = call i64 @rg_int_of(i64 %i40v)
  %l40 = call i64 @rg_str_len(i64 %s40)
  %ok40 = icmp ult i64 %i40, %l40
  %d40 = call i64 @rg_str_data(i64 %s40)
  %a40 = add i64 %d40, %i40
  br i1 %ok40, label %char_at_ok, label %char_at_bad
char_at_ok:
  %b40 = call i64 @rg_ldb(i64 %a40)
  %x40 = call i64 @__rg_rt_drop_val(i64 %s40)
  %r40 = call i64 @rg_int(i64 %b40)
  ret i64 %r40
char_at_bad:
  %y40 = call i64 @__rg_rt_drop_val(i64 %s40)
  ret i64 -1
concat:
  %a41 = call i64 @rg_arg(i64 %slots, i64 0)
  %b41 = call i64 @rg_arg(i64 %slots, i64 1)
  %r41 = call i64 @rg_binop(i64 14, i64 %a41, i64 %b41)
  ret i64 %r41
starts:
  %s42 = call i64 @rg_arg(i64 %slots, i64 0)
  %p42 = call i64 @rg_arg(i64 %slots, i64 1)
  %sd42 = call i64 @rg_str_data(i64 %s42)
  %sn42 = call i64 @rg_str_len(i64 %s42)
  %pd42 = call i64 @rg_str_data(i64 %p42)
  %pn42 = call i64 @rg_str_len(i64 %p42)
  %h42 = call i1 @rg_at(i64 %sd42, i64 %sn42, i64 0, i64 %pd42, i64 %pn42)
  %x42 = call i64 @__rg_rt_drop_val(i64 %s42)
  %y42 = call i64 @__rg_rt_drop_val(i64 %p42)
  %r42 = select i1 %h42, i64 6, i64 2
  ret i64 %r42
contains:
  %s43 = call i64 @rg_arg(i64 %slots, i64 0)
  %p43 = call i64 @rg_arg(i64 %slots, i64 1)
  %h43 = call i1 @rg_contains(i64 %s43, i64 %p43)
  %x43 = call i64 @__rg_rt_drop_val(i64 %s43)
  %y43 = call i64 @__rg_rt_drop_val(i64 %p43)
  %r43 = select i1 %h43, i64 6, i64 2
  ret i64 %r43
same:
  %a49 = call i64 @rg_arg(i64 %slots, i64 0)
  %b49 = call i64 @rg_arg(i64 %slots, i64 1)
  %e49 = icmp eq i64 %a49, %b49
  %h49 = call i1 @rg_is_heap(i64 %a49)
  %s49 = and i1 %e49, %h49
  %x49 = call i64 @__rg_rt_drop_val(i64 %a49)
  %y49 = call i64 @__rg_rt_drop_val(i64 %b49)
  %r49 = select i1 %s49, i64 6, i64 2
  ret i64 %r49
map:
  %f53 = call i64 @rg_arg(i64 %slots, i64 0)
  %xs53 = call i64 @rg_arg(i64 %slots, i64 1)
  %r53 = call i64 @rg_map(i64 %f53, i64 %xs53)
  ret i64 %r53
filter:
  %f55 = call i64 @rg_arg(i64 %slots, i64 0)
  %xs55 = call i64 @rg_arg(i64 %slots, i64 1)
  %r55 = call i64 @rg_filter(i64 %f55, i64 %xs55)
  ret i64 %r55
slice:
  %s60 = call i64 @rg_arg(i64 %slots, i64 0)
  %a60v = call i64 @rg_arg(i64 %slots, i64 1)
  %b60v = call i64 @rg_arg(i64 %slots, i64 2)
  %a60 = call i64 @rg_int_of(i64 %a60v)
  %b60 = call i64 @rg_int_of(i64 %b60v)
  %r60 = call i64 @rg_slice(i64 %s60, i64 %a60, i64 %b60)
  %x60 = call i64 @__rg_rt_drop_val(i64 %s60)
  ret i64 %r60
fold:
  %f61 = call i64 @rg_arg(i64 %slots, i64 0)
  %a61 = call i64 @rg_arg(i64 %slots, i64 1)
  %xs61 = call i64 @rg_arg(i64 %slots, i64 2)
  %r61 = call i64 @rg_fold(i64 %f61, i64 %a61, i64 %xs61)
  ret i64 %r61
append:
  %r121 = call i64 @rg_append_in_place(i64 %slots)
  ret i64 %r121
none:
  %rs = call i64 @rg_builtin_sys(i64 %id, i64 %slots, i64 %n)
  ret i64 %rs
}

; char_at (String, index): `str char at s i` on a local s (builtin 91); s is
; left alone. The byte as an Int, or the raw word -1 out of range.
define i64 @__rg_rt_char_at(i64 %s, i64 %iv) {
entry:
  %isstr = call i1 @rg_has_tag(i64 %s, i64 1)
  br i1 %isstr, label %idx, label %bad
idx:
  %i = call i64 @rg_int_of(i64 %iv)
  %l = call i64 @rg_str_len(i64 %s)
  %ok = icmp ult i64 %i, %l
  br i1 %ok, label %get, label %bad
get:
  %d = call i64 @rg_str_data(i64 %s)
  %a = add i64 %d, %i
  %b = call i64 @rg_ldb(i64 %a)
  %r = call i64 @rg_int(i64 %b)
  ret i64 %r
bad:
  ret i64 -1
}

; 121 (left String, right String), OPT-020: when the left String is the
; only owner of its bytes, appends the right one in place and gives the left
; String (both slots taken). Otherwise gives 0 and leaves both slots alone.
define i64 @rg_append_in_place(i64 %slots) {
entry:
  %a = call i64 @rg_ld(i64 %slots)
  %s1 = add i64 %slots, 8
  %b = call i64 @rg_ld(i64 %s1)
  %sa = call i1 @rg_has_tag(i64 %a, i64 1)
  %sb = call i1 @rg_has_tag(i64 %b, i64 1)
  %both = and i1 %sa, %sb
  br i1 %both, label %owner, label %no
owner:
  %rc = call i64 @rg_rc(i64 %a)
  %h = call i64 @rg_w1(i64 %a)
  %vrc = call i64 @rg_vrc(i64 %h)
  %one = icmp eq i64 %rc, 1
  %vone = icmp eq i64 %vrc, 1
  %sole = and i1 %one, %vone
  br i1 %sole, label %go, label %no
go:
  call void @rg_st(i64 %slots, i64 0)
  call void @rg_st(i64 %s1, i64 0)
  %r = call i64 @rg_str_concat(i64 %a, i64 %b)
  ret i64 %r
no:
  ret i64 0
}

declare i64 @rg_str_concat(i64, i64)
