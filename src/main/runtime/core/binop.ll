; ============================================================
; src/main/runtime/core/binop.ll
; Binary operators (ADR-0013). Operator ids (compiler `binop id`):
;  0 +  1 -  2 *  3 /  4 %  5 ==  6 !=  7 >  8 <  9 >=  10 <=
;  11 and  12 or  13 xor  14 concat  15 flat join  16 matmul
;  17 shift left  18 shift right  19 rotate right  20 rotate left
; Ints: 64-bit wrap-around; / and % truncate; a zero divisor gives 0;
; MIN / -1 = MIN, MIN % -1 = 0; shifts by b & 63 (right is logical); a
; result outside 63 bits is a boxed Int. Comparisons give True / False.
; ============================================================

declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i64 @rg_ldb(i64)
declare i1 @rg_is_heap(i64)
declare i64 @rg_tag(i64)
declare i1 @rg_has_tag(i64, i64)
declare i64 @rg_w1(i64)
declare i64 @rg_w2(i64)
declare i64 @rg_rc(i64)
declare i64 @rg_obj(i64, i64, i64)
declare i64 @rg_vec(i64, i64, i64)
declare i64 @rg_vcap(i64)
declare i64 @rg_vdata(i64)
declare i64 @rg_vlen(i64)
declare i64 @rg_vrc(i64)
declare void @rg_vset_len(i64, i64)
declare i64 @rg_vec_item(i64, i64)
declare i64 @rg_str_data(i64)
declare i64 @rg_str_len(i64)
declare i64 @rg_str_alloc(i64, i64)
declare i64 @rg_list_at(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_list_alloc(i64, i64)
declare i64 @rg_real(double)
declare i1 @rg_bytes_eq(i64, i64, i64)
declare void @rg_copy(i64, i64, i64)
declare void @rg_fill(i64, i8, i64)
declare void @rg_free(i64)
declare i64 @rg_alloc(i64)
declare i64 @rg_alloc_size(i64)
declare i64 @__rg_rt_clone_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare void @rg_fatal(ptr, i64)
declare i64 @rg_call_binop_user(i64, i64, i64)
declare i64 @llvm.fshr.i64(i64, i64, i64)
declare i64 @llvm.fshl.i64(i64, i64, i64)
declare double @llvm.trunc.f64(double)

; ── Ints ─────────────────────────────────────────────────────

; An Int value from a 64-bit integer: tagged when it fits in 63 bits.
define i64 @rg_box_int(i64 %x) {
entry:
  %s = shl i64 %x, 1
  %back = ashr i64 %s, 1
  %fits = icmp eq i64 %back, %x
  br i1 %fits, label %tag, label %box
tag:
  %t = or i64 %s, 1
  ret i64 %t
box:
  %o = call i64 @rg_obj(i64 -9223372036854775808, i64 %x, i64 0)
  ret i64 %o
}

; 1 when v is a tagged or boxed Int.
define i1 @rg_is_int(i64 %v) {
entry:
  %low = and i64 %v, 1
  %t = icmp eq i64 %low, 1
  br i1 %t, label %yes, label %h
h:
  %hp = call i1 @rg_is_heap(i64 %v)
  br i1 %hp, label %w, label %no
w:
  %word = call i64 @rg_ld(i64 %v)
  %b = icmp eq i64 %word, -9223372036854775808
  ret i1 %b
yes:
  ret i1 true
no:
  ret i1 false
}

; The 64-bit integer of an Int value.
define i64 @rg_int_of(i64 %v) {
entry:
  %low = and i64 %v, 1
  %t = icmp eq i64 %low, 1
  br i1 %t, label %tagged, label %boxed
tagged:
  %n = ashr i64 %v, 1
  ret i64 %n
boxed:
  %p = call i64 @rg_w1(i64 %v)
  ret i64 %p
}

define i64 @rg_cmp_bool(i64 %op, i64 %c) {
entry:
  switch i64 %op, label %no [ i64 5, label %eq
                              i64 6, label %ne
                              i64 7, label %gt
                              i64 8, label %lt
                              i64 9, label %ge
                              i64 10, label %le ]
eq:
  %a = icmp eq i64 %c, 0
  br label %done
ne:
  %b = icmp ne i64 %c, 0
  br label %done
gt:
  %d = icmp sgt i64 %c, 0
  br label %done
lt:
  %e = icmp slt i64 %c, 0
  br label %done
ge:
  %f = icmp sge i64 %c, 0
  br label %done
le:
  %g = icmp sle i64 %c, 0
  br label %done
no:
  br label %done
done:
  %r = phi i1 [ %a, %eq ], [ %b, %ne ], [ %d, %gt ], [ %e, %lt ], [ %f, %ge ], [ %g, %le ], [ false, %no ]
  %w = select i1 %r, i64 6, i64 2
  ret i64 %w
}

; The Int operator op on x and y. Gives -1 (not a value word: odd words
; are Ints, -1 is the Int -1, so the caller checks `rg_int_op_known`).
define i1 @rg_int_op_known(i64 %op) {
  %a = icmp ule i64 %op, 13
  %b = icmp uge i64 %op, 17
  %c = icmp ule i64 %op, 20
  %bc = and i1 %b, %c
  %r = or i1 %a, %bc
  ret i1 %r
}

define i64 @rg_int_op(i64 %op, i64 %x, i64 %y) {
entry:
  switch i64 %op, label %zero [ i64 0, label %add
                                i64 1, label %sub
                                i64 2, label %mul
                                i64 3, label %div
                                i64 4, label %mod
                                i64 11, label %and
                                i64 12, label %or
                                i64 13, label %xor
                                i64 17, label %shl
                                i64 18, label %shr
                                i64 19, label %rotr
                                i64 20, label %rotl ]
add:
  %ra = add i64 %x, %y
  br label %box
sub:
  %rs = sub i64 %x, %y
  br label %box
mul:
  %rm = mul i64 %x, %y
  br label %box
div:
  %dz = icmp eq i64 %y, 0
  %dm1 = icmp eq i64 %y, -1
  %dxm = icmp eq i64 %x, -9223372036854775808
  %dov = and i1 %dm1, %dxm
  %dbad = or i1 %dz, %dov
  br i1 %dbad, label %div_bad, label %div_ok
div_bad:
  %rdb = select i1 %dz, i64 0, i64 -9223372036854775808
  br label %box
div_ok:
  %rd = sdiv i64 %x, %y
  br label %box
mod:
  %mz = icmp eq i64 %y, 0
  %mm1 = icmp eq i64 %y, -1
  %mbad = or i1 %mz, %mm1
  br i1 %mbad, label %zero, label %mod_ok
mod_ok:
  %rmo = srem i64 %x, %y
  br label %box
and:
  %rn = and i64 %x, %y
  br label %box
or:
  %ro = or i64 %x, %y
  br label %box
xor:
  %rx = xor i64 %x, %y
  br label %box
shl:
  %s1 = and i64 %y, 63
  %rl = shl i64 %x, %s1
  br label %box
shr:
  %s2 = and i64 %y, 63
  %rr = lshr i64 %x, %s2
  br label %box
rotr:
  %rtr = call i64 @llvm.fshr.i64(i64 %x, i64 %x, i64 %y)
  br label %box
rotl:
  %rtl = call i64 @llvm.fshl.i64(i64 %x, i64 %x, i64 %y)
  br label %box
zero:
  br label %box
box:
  %raw = phi i64 [ %ra, %add ], [ %rs, %sub ], [ %rm, %mul ], [ %rdb, %div_bad ], [ %rd, %div_ok ], [ %rmo, %mod_ok ], [ %rn, %and ], [ %ro, %or ], [ %rx, %xor ], [ %rl, %shl ], [ %rr, %shr ], [ %rtr, %rotr ], [ %rtl, %rotl ], [ 0, %zero ]
  %v = call i64 @rg_box_int(i64 %raw)
  ret i64 %v
}

; ── Equality and order ───────────────────────────────────────

; Structural equality of two values (both left alone).
define i1 @rg_equal(i64 %a, i64 %b) {
entry:
  %same = icmp eq i64 %a, %b
  br i1 %same, label %yes, label %heaps
heaps:
  %ha = call i1 @rg_is_heap(i64 %a)
  %hb = call i1 @rg_is_heap(i64 %b)
  %both = and i1 %ha, %hb
  br i1 %both, label %tags, label %no
tags:
  %ta = call i64 @rg_tag(i64 %a)
  %tb = call i64 @rg_tag(i64 %b)
  %teq = icmp eq i64 %ta, %tb
  br i1 %teq, label %kind, label %no
kind:
  switch i64 %ta, label %no [ i64 0, label %num
                              i64 1, label %str
                              i64 2, label %list
                              i64 3, label %tuple
                              i64 4, label %adt
                              i64 5, label %tensor ]
num:
  %wa = call i64 @rg_ld(i64 %a)
  %wb = call i64 @rg_ld(i64 %b)
  %pa = call i64 @rg_w1(i64 %a)
  %pb = call i64 @rg_w1(i64 %b)
  %weq = icmp eq i64 %wa, %wb
  %isreal = icmp eq i64 %wa, 0
  %xa = bitcast i64 %pa to double
  %xb = bitcast i64 %pb to double
  %feq = fcmp oeq double %xa, %xb
  %ieq = icmp eq i64 %pa, %pb
  %peq = select i1 %isreal, i1 %feq, i1 %ieq
  %neq = and i1 %weq, %peq
  ret i1 %neq
str:
  %la = call i64 @rg_str_len(i64 %a)
  %lb = call i64 @rg_str_len(i64 %b)
  %leq = icmp eq i64 %la, %lb
  br i1 %leq, label %sbytes, label %no
sbytes:
  %da = call i64 @rg_str_data(i64 %a)
  %db = call i64 @rg_str_data(i64 %b)
  %r = call i1 @rg_bytes_eq(i64 %da, i64 %db, i64 %la)
  ret i1 %r
list:
  %na = call i64 @rg_list_len(i64 %a)
  %nb = call i64 @rg_list_len(i64 %b)
  %neqn = icmp eq i64 %na, %nb
  br i1 %neqn, label %lloop, label %no
lloop:
  %i = phi i64 [ 0, %list ], [ %i1, %lnext ]
  %lmore = icmp slt i64 %i, %na
  br i1 %lmore, label %lbody, label %yes
lbody:
  %ea = call i64 @rg_list_at(i64 %a, i64 %i)
  %eb = call i64 @rg_list_at(i64 %b, i64 %i)
  %va = call i64 @rg_ld(i64 %ea)
  %vb = call i64 @rg_ld(i64 %eb)
  %e = call i1 @rg_equal(i64 %va, i64 %vb)
  br i1 %e, label %lnext, label %no
lnext:
  %i1 = add i64 %i, 1
  br label %lloop
tuple:
  %tha = call i64 @rg_w1(i64 %a)
  %thb = call i64 @rg_w1(i64 %b)
  %r2 = call i1 @rg_vec_equal(i64 %tha, i64 %thb)
  ret i1 %r2
adt:
  %nha = call i64 @rg_w1(i64 %a)
  %nhb = call i64 @rg_w1(i64 %b)
  %nla = call i64 @rg_vlen(i64 %nha)
  %nlb = call i64 @rg_vlen(i64 %nhb)
  %nleq = icmp eq i64 %nla, %nlb
  br i1 %nleq, label %aname, label %no
aname:
  %nda = call i64 @rg_vdata(i64 %nha)
  %ndb = call i64 @rg_vdata(i64 %nhb)
  %nmeq = call i1 @rg_bytes_eq(i64 %nda, i64 %ndb, i64 %nla)
  br i1 %nmeq, label %afields, label %no
afields:
  %fha = call i64 @rg_w2(i64 %a)
  %fhb = call i64 @rg_w2(i64 %b)
  %r3 = call i1 @rg_vec_equal(i64 %fha, i64 %fhb)
  ret i1 %r3
tensor:
  %sha = call i64 @rg_w1(i64 %a)
  %shb = call i64 @rg_w1(i64 %b)
  %s_eq = call i1 @rg_words_equal(i64 %sha, i64 %shb)
  br i1 %s_eq, label %tdata, label %no
tdata:
  %dha = call i64 @rg_w2(i64 %a)
  %dhb = call i64 @rg_w2(i64 %b)
  %r4 = call i1 @rg_words_equal(i64 %dha, i64 %dhb)
  ret i1 %r4
yes:
  ret i1 true
no:
  ret i1 false
}

; Two value vectors with equal items.
define i1 @rg_vec_equal(i64 %ha, i64 %hb) {
entry:
  %na = call i64 @rg_vlen(i64 %ha)
  %nb = call i64 @rg_vlen(i64 %hb)
  %eqn = icmp eq i64 %na, %nb
  br i1 %eqn, label %loop, label %no
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %na
  br i1 %more, label %body, label %yes
body:
  %va = call i64 @rg_vec_item(i64 %ha, i64 %i)
  %vb = call i64 @rg_vec_item(i64 %hb, i64 %i)
  %e = call i1 @rg_equal(i64 %va, i64 %vb)
  br i1 %e, label %next, label %no
next:
  %i1 = add i64 %i, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; Two raw word vectors with equal words.
define i1 @rg_words_equal(i64 %ha, i64 %hb) {
entry:
  %na = call i64 @rg_vlen(i64 %ha)
  %nb = call i64 @rg_vlen(i64 %hb)
  %eqn = icmp eq i64 %na, %nb
  br i1 %eqn, label %loop, label %no
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %na
  br i1 %more, label %body, label %yes
body:
  %va = call i64 @rg_vec_item(i64 %ha, i64 %i)
  %vb = call i64 @rg_vec_item(i64 %hb, i64 %i)
  %e = icmp eq i64 %va, %vb
  br i1 %e, label %next, label %no
next:
  %i1 = add i64 %i, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; 1 when v is a Real.
define i1 @rg_is_realv(i64 %v) {
entry:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %w, label %no
w:
  %word = call i64 @rg_ld(i64 %v)
  %z = icmp eq i64 %word, 0
  ret i1 %z
no:
  ret i1 false
}

; The Real of a number value (an Int is converted).
define double @rg_num_of(i64 %v) {
entry:
  %r = call i1 @rg_is_realv(i64 %v)
  br i1 %r, label %real, label %int
real:
  %b = call i64 @rg_w1(i64 %v)
  %x = bitcast i64 %b to double
  ret double %x
int:
  %n = call i64 @rg_int_of(i64 %v)
  %y = sitofp i64 %n to double
  ret double %y
}

; The order of two values: negative, 0 or positive. Numbers by value;
; Strings by bytes; Lists and Tuples item by item, then by length.
define i64 @rg_compare(i64 %a, i64 %b) {
entry:
  %ia = call i1 @rg_is_int(i64 %a)
  %ib = call i1 @rg_is_int(i64 %b)
  %ii = and i1 %ia, %ib
  br i1 %ii, label %ints, label %nums
ints:
  %x = call i64 @rg_int_of(i64 %a)
  %y = call i64 @rg_int_of(i64 %b)
  %lt = icmp slt i64 %x, %y
  %gt = icmp sgt i64 %x, %y
  %c1 = select i1 %gt, i64 1, i64 0
  %c = select i1 %lt, i64 -1, i64 %c1
  ret i64 %c
nums:
  %ra = call i1 @rg_is_realv(i64 %a)
  %rb = call i1 @rg_is_realv(i64 %b)
  %na = or i1 %ia, %ra
  %nb = or i1 %ib, %rb
  %nn = and i1 %na, %nb
  br i1 %nn, label %reals, label %strs
reals:
  %fa = call double @rg_num_of(i64 %a)
  %fb = call double @rg_num_of(i64 %b)
  %flt = fcmp olt double %fa, %fb
  %fgt = fcmp ogt double %fa, %fb
  %f1 = select i1 %fgt, i64 1, i64 0
  %f = select i1 %flt, i64 -1, i64 %f1
  ret i64 %f
strs:
  %sa = call i1 @rg_has_tag(i64 %a, i64 1)
  %sb = call i1 @rg_has_tag(i64 %b, i64 1)
  %ss = and i1 %sa, %sb
  br i1 %ss, label %str, label %lists
str:
  %la = call i64 @rg_str_len(i64 %a)
  %lb = call i64 @rg_str_len(i64 %b)
  %da = call i64 @rg_str_data(i64 %a)
  %db = call i64 @rg_str_data(i64 %b)
  %short = icmp slt i64 %la, %lb
  %m = select i1 %short, i64 %la, i64 %lb
  br label %sloop
sloop:
  %i = phi i64 [ 0, %str ], [ %i1, %snext ]
  %smore = icmp slt i64 %i, %m
  br i1 %smore, label %sbody, label %slen
sbody:
  %pa = add i64 %da, %i
  %pb = add i64 %db, %i
  %ca = call i64 @rg_ldb(i64 %pa)
  %cb = call i64 @rg_ldb(i64 %pb)
  %d = sub i64 %ca, %cb
  %dz = icmp eq i64 %d, 0
  br i1 %dz, label %snext, label %sdiff
snext:
  %i1 = add i64 %i, 1
  br label %sloop
sdiff:
  ret i64 %d
slen:
  %ld = sub i64 %la, %lb
  ret i64 %ld
lists:
  %qa = call i1 @rg_has_tag(i64 %a, i64 2)
  %qb = call i1 @rg_has_tag(i64 %b, i64 2)
  %qq = and i1 %qa, %qb
  br i1 %qq, label %list, label %tuples
list:
  %lna = call i64 @rg_list_len(i64 %a)
  %lnb = call i64 @rg_list_len(i64 %b)
  %lshort = icmp slt i64 %lna, %lnb
  %lm = select i1 %lshort, i64 %lna, i64 %lnb
  br label %lloop
lloop:
  %j = phi i64 [ 0, %list ], [ %j1, %lnext ]
  %lmore = icmp slt i64 %j, %lm
  br i1 %lmore, label %lbody, label %llen
lbody:
  %eaa = call i64 @rg_list_at(i64 %a, i64 %j)
  %eba = call i64 @rg_list_at(i64 %b, i64 %j)
  %ea = call i64 @rg_ld(i64 %eaa)
  %eb = call i64 @rg_ld(i64 %eba)
  %ec = call i64 @rg_compare(i64 %ea, i64 %eb)
  %ecz = icmp eq i64 %ec, 0
  br i1 %ecz, label %lnext, label %ldiff
lnext:
  %j1 = add i64 %j, 1
  br label %lloop
ldiff:
  ret i64 %ec
llen:
  %lld = sub i64 %lna, %lnb
  ret i64 %lld
tuples:
  %ta = call i1 @rg_has_tag(i64 %a, i64 3)
  %tb = call i1 @rg_has_tag(i64 %b, i64 3)
  %tt = and i1 %ta, %tb
  br i1 %tt, label %tuple, label %other
tuple:
  %tha = call i64 @rg_w1(i64 %a)
  %thb = call i64 @rg_w1(i64 %b)
  %tn = call i64 @rg_vlen(i64 %tha)
  br label %tloop
tloop:
  %k = phi i64 [ 0, %tuple ], [ %k1, %tnext ]
  %tmore = icmp slt i64 %k, %tn
  br i1 %tmore, label %tbody, label %teq
tbody:
  %tva = call i64 @rg_vec_item(i64 %tha, i64 %k)
  %tvb = call i64 @rg_vec_item(i64 %thb, i64 %k)
  %tc = call i64 @rg_compare(i64 %tva, i64 %tvb)
  %tcz = icmp eq i64 %tc, 0
  br i1 %tcz, label %tnext, label %tdiff
tnext:
  %k1 = add i64 %k, 1
  br label %tloop
tdiff:
  ret i64 %tc
teq:
  ret i64 0
other:
  %e = call i1 @rg_equal(i64 %a, i64 %b)
  %oc = select i1 %e, i64 0, i64 1
  ret i64 %oc
}

; ── Concatenation ────────────────────────────────────────────

; 1 when the object and its vector are held only here and the vector owns
; room for `more` items after its end.
define i1 @rg_can_grow(i64 %o, i64 %more) {
entry:
  %rc = call i64 @rg_rc(i64 %o)
  %one = icmp sle i64 %rc, 1
  br i1 %one, label %vec, label %no
vec:
  %h = call i64 @rg_w1(i64 %o)
  %vrc = call i64 @rg_vrc(i64 %h)
  %vone = icmp sle i64 %vrc, 1
  %cap = call i64 @rg_vcap(i64 %h)
  %len = call i64 @rg_vlen(i64 %h)
  %need = add i64 %len, %more
  %room = icmp sle i64 %need, %cap
  %ok = and i1 %vone, %room
  ret i1 %ok
no:
  ret i1 false
}

; String a + b (both taken).
define i64 @rg_str_concat(i64 %a, i64 %b) {
entry:
  %la = call i64 @rg_str_len(i64 %a)
  %lb = call i64 @rg_str_len(i64 %b)
  %db = call i64 @rg_str_data(i64 %b)
  %grow = call i1 @rg_can_grow(i64 %a, i64 %lb)
  br i1 %grow, label %inplace, label %fresh
inplace:
  %da = call i64 @rg_str_data(i64 %a)
  %end = add i64 %da, %la
  call void @rg_copy(i64 %end, i64 %db, i64 %lb)
  %h = call i64 @rg_w1(i64 %a)
  %n = add i64 %la, %lb
  call void @rg_vset_len(i64 %h, i64 %n)
  %x = call i64 @__rg_rt_drop_val(i64 %b)
  ret i64 %a
fresh:
  %tot = add i64 %la, %lb
  %cap = shl i64 %tot, 1
  %o = call i64 @rg_str_alloc(i64 %tot, i64 %cap)
  %d = call i64 @rg_str_data(i64 %o)
  %da2 = call i64 @rg_str_data(i64 %a)
  call void @rg_copy(i64 %d, i64 %da2, i64 %la)
  %d2 = add i64 %d, %la
  call void @rg_copy(i64 %d2, i64 %db, i64 %lb)
  %y = call i64 @__rg_rt_drop_val(i64 %a)
  %z = call i64 @__rg_rt_drop_val(i64 %b)
  ret i64 %o
}

; Put the items of List src into dst at address `at` (taken from src when it
; is held only here, else cloned). src is dropped.
define void @rg_list_give(i64 %src, i64 %at) {
entry:
  %n = call i64 @rg_list_len(i64 %src)
  %rc = call i64 @rg_rc(i64 %src)
  %h = call i64 @rg_w1(i64 %src)
  %vrc = call i64 @rg_vrc(i64 %h)
  %r1 = icmp sle i64 %rc, 1
  %v1 = icmp sle i64 %vrc, 1
  %own = and i1 %r1, %v1
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %put ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ea = call i64 @rg_list_at(i64 %src, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  br i1 %own, label %put, label %clone
clone:
  %c = call i64 @__rg_rt_clone_slot(i64 %e)
  br label %put
put:
  %v = phi i64 [ %e, %body ], [ %c, %clone ]
  %off = shl i64 %i, 3
  %da = add i64 %at, %off
  call void @rg_st(i64 %da, i64 %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  br i1 %own, label %cut, label %drop
cut:
  %s = call i64 @rg_w2(i64 %src)
  call void @rg_vset_len(i64 %h, i64 %s)
  br label %drop
drop:
  %x = call i64 @__rg_rt_drop_val(i64 %src)
  ret void
}

; 1 when List b and its vector are held only here and b has room for
; `more` items before its start index. The slots before the start hold
; items left by list_tail, unreachable once b is the sole holder.
define i1 @rg_can_prepend(i64 %o, i64 %more) {
entry:
  %rc = call i64 @rg_rc(i64 %o)
  %one = icmp sle i64 %rc, 1
  br i1 %one, label %vec, label %no
vec:
  %h = call i64 @rg_w1(i64 %o)
  %vrc = call i64 @rg_vrc(i64 %h)
  %vone = icmp sle i64 %vrc, 1
  %s = call i64 @rg_w2(i64 %o)
  %room = icmp sge i64 %s, %more
  %ok = and i1 %vone, %room
  ret i1 %ok
no:
  ret i1 false
}

; Drop the n values at address p and set them to 0.
define void @rg_drop_words(i64 %p, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %off = shl i64 %i, 3
  %a = add i64 %p, %off
  %v = call i64 @rg_ld(i64 %a)
  %x = call i64 @__rg_rt_drop_val(i64 %v)
  call void @rg_st(i64 %a, i64 0)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

; List a :: b (both taken). Appending to a List held only here with room
; after its end writes in place; so does prepending to a List held only
; here with room before its start. Otherwise a new List with twice the
; room: the room goes after the items when a is the longer side (an
; append), before them when b is (a prepend), so either accumulator
; (`acc :: [x]` or `[x] :: acc`) runs in amortised constant time.
define i64 @rg_list_concat(i64 %a, i64 %b) {
entry:
  %la = call i64 @rg_list_len(i64 %a)
  %lb = call i64 @rg_list_len(i64 %b)
  %grow = call i1 @rg_can_grow(i64 %a, i64 %lb)
  br i1 %grow, label %inplace, label %tryfront
inplace:
  %h = call i64 @rg_w1(i64 %a)
  %vl = call i64 @rg_vlen(i64 %h)
  %d = call i64 @rg_vdata(i64 %h)
  %off = shl i64 %vl, 3
  %at = add i64 %d, %off
  call void @rg_list_give(i64 %b, i64 %at)
  %nl = add i64 %vl, %lb
  call void @rg_vset_len(i64 %h, i64 %nl)
  ret i64 %a
tryfront:
  %front = call i1 @rg_can_prepend(i64 %b, i64 %la)
  br i1 %front, label %prepend, label %fresh
prepend:
  %bh = call i64 @rg_w1(i64 %b)
  %bd = call i64 @rg_vdata(i64 %bh)
  %bs = call i64 @rg_w2(i64 %b)
  %ns = sub i64 %bs, %la
  %noff = shl i64 %ns, 3
  %pat = add i64 %bd, %noff
  call void @rg_drop_words(i64 %pat, i64 %la)
  call void @rg_list_give(i64 %a, i64 %pat)
  %bw2 = add i64 %b, 16
  call void @rg_st(i64 %bw2, i64 %ns)
  ret i64 %b
fresh:
  %tot = add i64 %la, %lb
  %cap0 = shl i64 %tot, 1
  %small = icmp slt i64 %cap0, 4
  %cap = select i1 %small, i64 4, i64 %cap0
  %pre = icmp slt i64 %la, %lb
  br i1 %pre, label %back, label %ahead
ahead:
  %o = call i64 @rg_list_alloc(i64 %tot, i64 %cap)
  br label %fill
back:
  ; vector length cap, the items in [cap - tot, cap), the room zeroed
  %ro = call i64 @rg_list_alloc(i64 %cap, i64 %cap)
  %rs = sub i64 %cap, %tot
  %rh = call i64 @rg_w1(i64 %ro)
  %rd = call i64 @rg_vdata(i64 %rh)
  %rbytes = shl i64 %rs, 3
  call void @rg_fill(i64 %rd, i8 0, i64 %rbytes)
  %rw2 = add i64 %ro, 16
  call void @rg_st(i64 %rw2, i64 %rs)
  br label %fill
fill:
  %n = phi i64 [ %o, %ahead ], [ %ro, %back ]
  %at0 = call i64 @rg_list_at(i64 %n, i64 0)
  call void @rg_list_give(i64 %a, i64 %at0)
  %boff = shl i64 %la, 3
  %at1 = add i64 %at0, %boff
  call void @rg_list_give(i64 %b, i64 %at1)
  ret i64 %n
}

; ── The operator ─────────────────────────────────────────────

@rg_msg_binop = private constant [32 x i8] c"operator on values of wrong type"

; The operator on a and b (both taken).
define i64 @rg_binop(i64 %op, i64 %a, i64 %b) {
entry:
  %la = and i64 %a, 1
  %lb = and i64 %b, 1
  %both = and i64 %la, %lb
  %ints = icmp eq i64 %both, 1
  %known = call i1 @rg_int_op_known(i64 %op)
  %fast = and i1 %ints, %known
  br i1 %fast, label %int_fast, label %slow
int_fast:
  %x = ashr i64 %a, 1
  %y = ashr i64 %b, 1
  %isc = icmp uge i64 %op, 5
  %isc2 = icmp ule i64 %op, 10
  %cmp = and i1 %isc, %isc2
  br i1 %cmp, label %int_cmp, label %int_arith
int_cmp:
  %ilt = icmp slt i64 %x, %y
  %igt = icmp sgt i64 %x, %y
  %ic1 = select i1 %igt, i64 1, i64 0
  %ic = select i1 %ilt, i64 -1, i64 %ic1
  %ib = call i64 @rg_cmp_bool(i64 %op, i64 %ic)
  ret i64 %ib
int_arith:
  %ir = call i64 @rg_int_op(i64 %op, i64 %x, i64 %y)
  ret i64 %ir
slow:
  %isc3 = icmp uge i64 %op, 5
  %isc4 = icmp ule i64 %op, 10
  %iscmp = and i1 %isc3, %isc4
  %isint_a = call i1 @rg_is_int(i64 %a)
  %isint_b = call i1 @rg_is_int(i64 %b)
  %isr_a = call i1 @rg_is_realv(i64 %a)
  %isr_b = call i1 @rg_is_realv(i64 %b)
  %num_a = or i1 %isint_a, %isr_a
  %num_b = or i1 %isint_b, %isr_b
  %nums = and i1 %num_a, %num_b
  br i1 %nums, label %num, label %bools
num:
  %anyreal = or i1 %isr_a, %isr_b
  br i1 %anyreal, label %real, label %bigint
bigint:
  br i1 %iscmp, label %general_cmp, label %bigint_arith
bigint_arith:
  %bx = call i64 @rg_int_of(i64 %a)
  %by = call i64 @rg_int_of(i64 %b)
  %br = call i64 @rg_int_op(i64 %op, i64 %bx, i64 %by)
  %d1 = call i64 @__rg_rt_drop_val(i64 %a)
  %d2 = call i64 @__rg_rt_drop_val(i64 %b)
  ret i64 %br
real:
  br i1 %iscmp, label %real_cmp, label %real_arith
real_cmp:
  ; IEEE 754: every comparison with a NaN is false except `!=`. The three-way compare of
  ; `rg_compare` cannot say "unordered" (it gave 0, equal), so each operator has its own predicate.
  %ca = call double @rg_num_of(i64 %a)
  %cb = call double @rg_num_of(i64 %b)
  %dca = call i64 @__rg_rt_drop_val(i64 %a)
  %dcb = call i64 @__rg_rt_drop_val(i64 %b)
  %p_eq = fcmp oeq double %ca, %cb
  %p_ne = fcmp une double %ca, %cb
  %p_gt = fcmp ogt double %ca, %cb
  %p_lt = fcmp olt double %ca, %cb
  %p_ge = fcmp oge double %ca, %cb
  %p_le = fcmp ole double %ca, %cb
  switch i64 %op, label %real_cmp_no [ i64 5, label %real_cmp_eq
                                       i64 6, label %real_cmp_ne
                                       i64 7, label %real_cmp_gt
                                       i64 8, label %real_cmp_lt
                                       i64 9, label %real_cmp_ge
                                       i64 10, label %real_cmp_le ]
real_cmp_eq:
  %w_eq = select i1 %p_eq, i64 6, i64 2
  ret i64 %w_eq
real_cmp_ne:
  %w_ne = select i1 %p_ne, i64 6, i64 2
  ret i64 %w_ne
real_cmp_gt:
  %w_gt = select i1 %p_gt, i64 6, i64 2
  ret i64 %w_gt
real_cmp_lt:
  %w_lt = select i1 %p_lt, i64 6, i64 2
  ret i64 %w_lt
real_cmp_ge:
  %w_ge = select i1 %p_ge, i64 6, i64 2
  ret i64 %w_ge
real_cmp_le:
  %w_le = select i1 %p_le, i64 6, i64 2
  ret i64 %w_le
real_cmp_no:
  ret i64 2
real_arith:
  %fa = call double @rg_num_of(i64 %a)
  %fb = call double @rg_num_of(i64 %b)
  %d3 = call i64 @__rg_rt_drop_val(i64 %a)
  %d4 = call i64 @__rg_rt_drop_val(i64 %b)
  switch i64 %op, label %bad [ i64 0, label %fadd
                               i64 1, label %fsub
                               i64 2, label %fmul
                               i64 3, label %fdiv
                               i64 4, label %fmod ]
fadd:
  %ra = fadd double %fa, %fb
  br label %freal
fsub:
  %rs = fsub double %fa, %fb
  br label %freal
fmul:
  %rm = fmul double %fa, %fb
  br label %freal
fdiv:
  %rd = fdiv double %fa, %fb
  br label %freal
fmod:
  %q = fdiv double %fa, %fb
  %qt = call double @llvm.trunc.f64(double %q)
  %qy = fmul double %qt, %fb
  %rmo = fsub double %fa, %qy
  br label %freal
freal:
  %fr = phi double [ %ra, %fadd ], [ %rs, %fsub ], [ %rm, %fmul ], [ %rd, %fdiv ], [ %rmo, %fmod ]
  %fo = call i64 @rg_real(double %fr)
  ret i64 %fo
bools:
  %ba = icmp eq i64 %a, 6
  %ba2 = icmp eq i64 %a, 2
  %bb = icmp eq i64 %b, 6
  %bb2 = icmp eq i64 %b, 2
  %boola = or i1 %ba, %ba2
  %boolb = or i1 %bb, %bb2
  %bothb = and i1 %boola, %boolb
  br i1 %bothb, label %boolop, label %general
boolop:
  switch i64 %op, label %general [ i64 11, label %band
                                   i64 12, label %bor
                                   i64 13, label %bxor ]
band:
  %rand = and i1 %ba, %bb
  %wand = select i1 %rand, i64 6, i64 2
  ret i64 %wand
bor:
  %ror = or i1 %ba, %bb
  %wor = select i1 %ror, i64 6, i64 2
  ret i64 %wor
bxor:
  %rxor = xor i1 %ba, %bb
  %wxor = select i1 %rxor, i64 6, i64 2
  ret i64 %wxor
general:
  %iseq = icmp eq i64 %op, 5
  %isne = icmp eq i64 %op, 6
  %eqne = or i1 %iseq, %isne
  br i1 %eqne, label %equality, label %ordq
equality:
  %e = call i1 @rg_equal(i64 %a, i64 %b)
  %ne = xor i1 %e, true
  %res = select i1 %iseq, i1 %e, i1 %ne
  %we = select i1 %res, i64 6, i64 2
  %d5 = call i64 @__rg_rt_drop_val(i64 %a)
  %d6 = call i64 @__rg_rt_drop_val(i64 %b)
  ret i64 %we
ordq:
  br i1 %iscmp, label %general_cmp, label %concatq
general_cmp:
  %gc = call i64 @rg_compare(i64 %a, i64 %b)
  %gw = call i64 @rg_cmp_bool(i64 %op, i64 %gc)
  %d7 = call i64 @__rg_rt_drop_val(i64 %a)
  %d8 = call i64 @__rg_rt_drop_val(i64 %b)
  ret i64 %gw
concatq:
  %plus = icmp eq i64 %op, 0
  %cat = icmp eq i64 %op, 14
  %pc = or i1 %plus, %cat
  br i1 %pc, label %catkind, label %user
catkind:
  %sa = call i1 @rg_has_tag(i64 %a, i64 1)
  %sb = call i1 @rg_has_tag(i64 %b, i64 1)
  %ss = and i1 %sa, %sb
  br i1 %ss, label %scat, label %lcatq
scat:
  %so = call i64 @rg_str_concat(i64 %a, i64 %b)
  ret i64 %so
lcatq:
  %qa = call i1 @rg_has_tag(i64 %a, i64 2)
  %qb = call i1 @rg_has_tag(i64 %b, i64 2)
  %qq = and i1 %qa, %qb
  br i1 %qq, label %lcat, label %user
lcat:
  %lo = call i64 @rg_list_concat(i64 %a, i64 %b)
  ret i64 %lo
user:
  %arith = icmp ule i64 %op, 4
  br i1 %arith, label %overload, label %bad
overload:
  %uo = call i64 @rg_call_binop_user(i64 %op, i64 %a, i64 %b)
  ret i64 %uo
bad:
  call void @rg_fatal(ptr @rg_msg_binop, i64 32)
  unreachable
}

; bin_op (op, left slot address, right value): the left value is taken from
; its slot (the slot is cleared), the right value is taken too.
define i64 @__rg_rt_bin_op(i64 %op, i64 %slot, i64 %b) {
  %a = call i64 @rg_ld(i64 %slot)
  call void @rg_st(i64 %slot, i64 0)
  %r = call i64 @rg_binop(i64 %op, i64 %a, i64 %b)
  ret i64 %r
}
