; ============================================================
; src/main/runtime/core/format.ll
; Text of values, echo, out and string interpolation (ADR-0013).
; The text of a value: an Int in decimal; True / False; () for Unit; a
; String as its bytes; a Real with up to six decimals (rounded, trailing
; zeros removed, at least one); [a, b] for a List; (a, b) for a Tuple; a
; constructor by its name, or (Name f1 f2) with fields.
; ============================================================

declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare void @rg_copy(i64, i64, i64)
declare i64 @rg_alloc_size(i64)
declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare void @rg_stb(i64, i64)
declare i1 @rg_is_heap(i64)
declare i64 @rg_tag(i64)
declare i64 @rg_w1(i64)
declare i64 @rg_w2(i64)
declare i64 @rg_vdata(i64)
declare i64 @rg_vlen(i64)
declare i64 @rg_vec_item(i64, i64)
declare i64 @rg_str_data(i64)
declare i64 @rg_str_len(i64)
declare i64 @rg_list_at(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_vec(i64, i64, i64)
declare i64 @rg_obj(i64, i64, i64)
declare i64 @__rg_rt_drop_val(i64)
declare i64 @__rg_pal_write(i64, i64, i64)

; ── Byte buffers ─────────────────────────────────────────────
; A buffer is three words at an address: {data, len, cap}.

define void @rg_buf_init(i64 %b, i64 %cap) {
  %d = call i64 @rg_alloc(i64 %cap)
  call void @rg_st(i64 %b, i64 %d)
  %la = add i64 %b, 8
  call void @rg_st(i64 %la, i64 0)
  %ca = add i64 %b, 16
  %real = call i64 @rg_alloc_size(i64 %d)
  call void @rg_st(i64 %ca, i64 %real)
  ret void
}

; Make room for n more bytes; gives the address where they go.
define i64 @rg_buf_reserve(i64 %b, i64 %n) {
entry:
  %d = call i64 @rg_ld(i64 %b)
  %la = add i64 %b, 8
  %l = call i64 @rg_ld(i64 %la)
  %ca = add i64 %b, 16
  %c = call i64 @rg_ld(i64 %ca)
  %need = add i64 %l, %n
  %fits = icmp sle i64 %need, %c
  br i1 %fits, label %ok, label %grow
grow:
  %c2 = shl i64 %c, 1
  %big = icmp sgt i64 %need, %c2
  %nc0 = select i1 %big, i64 %need, i64 %c2
  %nd = call i64 @rg_alloc(i64 %nc0)
  call void @rg_copy(i64 %nd, i64 %d, i64 %l)
  call void @rg_free(i64 %d)
  call void @rg_st(i64 %b, i64 %nd)
  %nc = call i64 @rg_alloc_size(i64 %nd)
  call void @rg_st(i64 %ca, i64 %nc)
  br label %ok
ok:
  %dd = call i64 @rg_ld(i64 %b)
  %at = add i64 %dd, %l
  call void @rg_st(i64 %la, i64 %need)
  ret i64 %at
}

define void @rg_buf_byte(i64 %b, i64 %c) {
  %at = call i64 @rg_buf_reserve(i64 %b, i64 1)
  call void @rg_stb(i64 %at, i64 %c)
  ret void
}

define void @rg_buf_bytes(i64 %b, i64 %src, i64 %n) {
  %at = call i64 @rg_buf_reserve(i64 %b, i64 %n)
  call void @rg_copy(i64 %at, i64 %src, i64 %n)
  ret void
}

; The buffer's bytes as a new String; the buffer is given up.
define i64 @rg_buf_str(i64 %b) {
  %d = call i64 @rg_ld(i64 %b)
  %la = add i64 %b, 8
  %l = call i64 @rg_ld(i64 %la)
  %ca = add i64 %b, 16
  %c = call i64 @rg_ld(i64 %ca)
  %h = call i64 @rg_vec(i64 0, i64 %l, i64 1)
  call void @rg_st(i64 %h, i64 %c)
  %da = add i64 %h, 8
  call void @rg_st(i64 %da, i64 %d)
  %o = call i64 @rg_obj(i64 1, i64 %h, i64 0)
  ret i64 %o
}

; Write the buffer to fd and free it.
define void @rg_buf_write(i64 %b, i64 %fd) {
  %d = call i64 @rg_ld(i64 %b)
  %la = add i64 %b, 8
  %l = call i64 @rg_ld(i64 %la)
  %w = call i64 @rg_write_all(i64 %fd, i64 %d, i64 %l)
  call void @rg_free(i64 %d)
  ret void
}

define i64 @rg_write_all(i64 %fd, i64 %d, i64 %n) {
entry:
  br label %loop
loop:
  %off = phi i64 [ 0, %entry ], [ %off1, %more ]
  %left = sub i64 %n, %off
  %go = icmp sgt i64 %left, 0
  br i1 %go, label %write, label %done
write:
  %a = add i64 %d, %off
  %w = call i64 @__rg_pal_write(i64 %fd, i64 %a, i64 %left)
  %ok = icmp sgt i64 %w, 0
  br i1 %ok, label %more, label %done
more:
  %off1 = add i64 %off, %w
  br label %loop
done:
  ret i64 %off
}

; ── Numbers ──────────────────────────────────────────────────

; The decimal digits of an unsigned word.
define void @rg_buf_u64(i64 %b, i64 %u) {
entry:
  %tmp = alloca [24 x i8], align 8
  br label %loop
loop:
  %v = phi i64 [ %u, %entry ], [ %q, %loop ]
  %i = phi i64 [ 24, %entry ], [ %i1, %loop ]
  %q = udiv i64 %v, 10
  %r = urem i64 %v, 10
  %c = add i64 %r, 48
  %i1 = sub i64 %i, 1
  %p = getelementptr inbounds [24 x i8], ptr %tmp, i64 0, i64 %i1
  %c8 = trunc i64 %c to i8
  store i8 %c8, ptr %p, align 1
  %more = icmp ne i64 %q, 0
  br i1 %more, label %loop, label %done
done:
  %start = getelementptr inbounds [24 x i8], ptr %tmp, i64 0, i64 %i1
  %sa = ptrtoint ptr %start to i64
  %n = sub i64 24, %i1
  call void @rg_buf_bytes(i64 %b, i64 %sa, i64 %n)
  ret void
}

define void @rg_buf_i64(i64 %b, i64 %n) {
entry:
  %neg = icmp slt i64 %n, 0
  br i1 %neg, label %minus, label %pos
minus:
  call void @rg_buf_byte(i64 %b, i64 45)
  %m = sub i64 0, %n
  call void @rg_buf_u64(i64 %b, i64 %m)
  ret void
pos:
  call void @rg_buf_u64(i64 %b, i64 %n)
  ret void
}

; A Real: sign, integer part, point, up to six decimals.
define void @rg_buf_real(i64 %b, double %x) {
entry:
  %isnan = fcmp uno double %x, %x
  br i1 %isnan, label %nan, label %num
nan:
  call void @rg_buf_byte(i64 %b, i64 110)
  call void @rg_buf_byte(i64 %b, i64 97)
  call void @rg_buf_byte(i64 %b, i64 110)
  ret void
num:
  %bits = bitcast double %x to i64
  %neg = icmp slt i64 %bits, 0
  br i1 %neg, label %minus, label %abs
minus:
  call void @rg_buf_byte(i64 %b, i64 45)
  br label %abs
abs:
  %a = call double @llvm.fabs.f64(double %x)
  %isinf = fcmp oeq double %a, 0x7FF0000000000000
  br i1 %isinf, label %inf, label %fin
inf:
  ; an infinity is `inf` (after the sign), as a NaN is `nan`
  call void @rg_buf_byte(i64 %b, i64 105)
  call void @rg_buf_byte(i64 %b, i64 110)
  call void @rg_buf_byte(i64 %b, i64 102)
  ret void
fin:
  %big = fcmp oge double %a, 0x43F0000000000000
  %ip0 = fptoui double %a to i64
  %ip = select i1 %big, i64 -1, i64 %ip0
  %ipf = uitofp i64 %ip0 to double
  %f = fsub double %a, %ipf
  %f6 = fmul double %f, 1.0e6
  %f6h = fadd double %f6, 0.5
  %fr0 = fptoui double %f6h to i64
  %fr0b = select i1 %big, i64 0, i64 %fr0
  %carry = icmp uge i64 %fr0b, 1000000
  %ip1 = add i64 %ip, 1
  %ipx = select i1 %carry, i64 %ip1, i64 %ip
  %frm = sub i64 %fr0b, 1000000
  %fr = select i1 %carry, i64 %frm, i64 %fr0b
  call void @rg_buf_u64(i64 %b, i64 %ipx)
  call void @rg_buf_byte(i64 %b, i64 46)
  br label %trim
trim:
  %v = phi i64 [ %fr, %fin ], [ %v10, %cut ]
  %digits = phi i64 [ 6, %fin ], [ %d1, %cut ]
  %r = urem i64 %v, 10
  %z = icmp eq i64 %r, 0
  %keep = icmp sgt i64 %digits, 1
  %go = and i1 %z, %keep
  br i1 %go, label %cut, label %emit
cut:
  %v10 = udiv i64 %v, 10
  %d1 = sub i64 %digits, 1
  br label %trim
emit:
  br label %dloop
dloop:
  %k = phi i64 [ %digits, %emit ], [ %k1, %dbody ]
  %go2 = icmp sgt i64 %k, 0
  br i1 %go2, label %dbody, label %done
dbody:
  %k1 = sub i64 %k, 1
  %p = call i64 @rg_pow10(i64 %k1)
  %dq = udiv i64 %v, %p
  %dr = urem i64 %dq, 10
  %c = add i64 %dr, 48
  call void @rg_buf_byte(i64 %b, i64 %c)
  br label %dloop
done:
  ret void
}

define i64 @rg_pow10(i64 %k) {
entry:
  br label %loop
loop:
  %i = phi i64 [ %k, %entry ], [ %i1, %body ]
  %p = phi i64 [ 1, %entry ], [ %p1, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %p1 = mul i64 %p, 10
  %i1 = sub i64 %i, 1
  br label %loop
done:
  ret i64 %p
}

declare double @llvm.fabs.f64(double)

; ── Values ───────────────────────────────────────────────────

@rg_s_true = private constant [4 x i8] c"True"
@rg_s_false = private constant [5 x i8] c"False"
@rg_s_unit = private constant [2 x i8] c"()"
@rg_s_sep = private constant [2 x i8] c", "
@rg_s_tshape = private constant [14 x i8] c"Tensor(shape=["
@rg_s_tdata = private constant [9 x i8] c"], data=["

define void @rg_buf_lit(i64 %b, ptr %s, i64 %n) {
  %a = ptrtoint ptr %s to i64
  call void @rg_buf_bytes(i64 %b, i64 %a, i64 %n)
  ret void
}

; Append the text of a value.
define void @rg_buf_value(i64 %b, i64 %v) {
entry:
  %low = and i64 %v, 1
  %isint = icmp eq i64 %low, 1
  br i1 %isint, label %int, label %notint
int:
  %n = ashr i64 %v, 1
  call void @rg_buf_i64(i64 %b, i64 %n)
  ret void
notint:
  switch i64 %v, label %heapq [ i64 6, label %true
                                i64 2, label %false
                                i64 0, label %unit ]
true:
  call void @rg_buf_lit(i64 %b, ptr @rg_s_true, i64 4)
  ret void
false:
  call void @rg_buf_lit(i64 %b, ptr @rg_s_false, i64 5)
  ret void
unit:
  call void @rg_buf_lit(i64 %b, ptr @rg_s_unit, i64 2)
  ret void
heapq:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %heap, label %other
other:
  call void @rg_buf_i64(i64 %b, i64 %v)
  ret void
heap:
  %t = call i64 @rg_tag(i64 %v)
  switch i64 %t, label %other [ i64 0, label %num
                                i64 1, label %str
                                i64 2, label %list
                                i64 3, label %tuple
                                i64 4, label %adt
                                i64 5, label %tensor ]
tensor:
  call void @rg_buf_tensor(i64 %b, i64 %v)
  ret void
num:
  %w = call i64 @rg_ld(i64 %v)
  %pay = call i64 @rg_w1(i64 %v)
  %isreal = icmp eq i64 %w, 0
  br i1 %isreal, label %real, label %boxed
real:
  %x = bitcast i64 %pay to double
  call void @rg_buf_real(i64 %b, double %x)
  ret void
boxed:
  call void @rg_buf_i64(i64 %b, i64 %pay)
  ret void
str:
  %sd = call i64 @rg_str_data(i64 %v)
  %sl = call i64 @rg_str_len(i64 %v)
  call void @rg_buf_bytes(i64 %b, i64 %sd, i64 %sl)
  ret void
list:
  call void @rg_buf_byte(i64 %b, i64 91)
  %ln = call i64 @rg_list_len(i64 %v)
  br label %lloop
lloop:
  %i = phi i64 [ 0, %list ], [ %i1, %lbody ]
  %lmore = icmp slt i64 %i, %ln
  br i1 %lmore, label %lsep, label %lend
lsep:
  %first = icmp eq i64 %i, 0
  br i1 %first, label %lbody, label %lcomma
lcomma:
  call void @rg_buf_lit(i64 %b, ptr @rg_s_sep, i64 2)
  br label %lbody
lbody:
  %ea = call i64 @rg_list_at(i64 %v, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  call void @rg_buf_value(i64 %b, i64 %e)
  %i1 = add i64 %i, 1
  br label %lloop
lend:
  call void @rg_buf_byte(i64 %b, i64 93)
  ret void
tuple:
  call void @rg_buf_byte(i64 %b, i64 40)
  %th = call i64 @rg_w1(i64 %v)
  %tn = call i64 @rg_vlen(i64 %th)
  br label %tloop
tloop:
  %j = phi i64 [ 0, %tuple ], [ %j1, %tbody ]
  %tmore = icmp slt i64 %j, %tn
  br i1 %tmore, label %tsep, label %tend
tsep:
  %tfirst = icmp eq i64 %j, 0
  br i1 %tfirst, label %tbody, label %tcomma
tcomma:
  call void @rg_buf_lit(i64 %b, ptr @rg_s_sep, i64 2)
  br label %tbody
tbody:
  %te = call i64 @rg_vec_item(i64 %th, i64 %j)
  call void @rg_buf_value(i64 %b, i64 %te)
  %j1 = add i64 %j, 1
  br label %tloop
tend:
  call void @rg_buf_byte(i64 %b, i64 41)
  ret void
adt:
  %nh = call i64 @rg_w1(i64 %v)
  %nd = call i64 @rg_vdata(i64 %nh)
  %nl = call i64 @rg_vlen(i64 %nh)
  %fh = call i64 @rg_w2(i64 %v)
  %fn = call i64 @rg_vlen(i64 %fh)
  %bare = icmp eq i64 %fn, 0
  br i1 %bare, label %name, label %open
name:
  call void @rg_buf_bytes(i64 %b, i64 %nd, i64 %nl)
  ret void
open:
  call void @rg_buf_byte(i64 %b, i64 40)
  call void @rg_buf_bytes(i64 %b, i64 %nd, i64 %nl)
  br label %floop
floop:
  %k = phi i64 [ 0, %open ], [ %k1, %fbody ]
  %fmore = icmp slt i64 %k, %fn
  br i1 %fmore, label %fbody, label %fend
fbody:
  call void @rg_buf_byte(i64 %b, i64 32)
  %fe = call i64 @rg_vec_item(i64 %fh, i64 %k)
  call void @rg_buf_value(i64 %b, i64 %fe)
  %k1 = add i64 %k, 1
  br label %floop
fend:
  call void @rg_buf_byte(i64 %b, i64 41)
  ret void
}

; The text of a value as a new String (the value is left alone).
define i64 @rg_value_str(i64 %v) {
  %buf = alloca [3 x i64], align 8
  %b = ptrtoint ptr %buf to i64
  call void @rg_buf_init(i64 %b, i64 32)
  call void @rg_buf_value(i64 %b, i64 %v)
  %s = call i64 @rg_buf_str(i64 %b)
  ret i64 %s
}

; ── Entries ──────────────────────────────────────────────────

; out (value): write its text and a newline; the value is dropped.
define i64 @__rg_rt_out(i64 %v) {
  %buf = alloca [3 x i64], align 8
  %b = ptrtoint ptr %buf to i64
  call void @rg_buf_init(i64 %b, i64 64)
  call void @rg_buf_value(i64 %b, i64 %v)
  call void @rg_buf_byte(i64 %b, i64 10)
  call void @rg_buf_write(i64 %b, i64 1)
  %d = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 0
}

; echo (slots, n): write the texts of the n slot values, separated by spaces,
; and a newline. The values are taken (slots cleared and dropped).
define i64 @__rg_rt_echo(i64 %slots, i64 %n) {
entry:
  %buf = alloca [3 x i64], align 8
  %b = ptrtoint ptr %buf to i64
  call void @rg_buf_init(i64 %b, i64 64)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %sep, label %done
sep:
  %first = icmp eq i64 %i, 0
  br i1 %first, label %body, label %space
space:
  call void @rg_buf_byte(i64 %b, i64 32)
  br label %body
body:
  %off = shl i64 %i, 3
  %sa = add i64 %slots, %off
  %v = call i64 @rg_ld(i64 %sa)
  call void @rg_buf_value(i64 %b, i64 %v)
  call void @rg_st(i64 %sa, i64 0)
  %d = call i64 @__rg_rt_drop_val(i64 %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  call void @rg_buf_byte(i64 %b, i64 10)
  call void @rg_buf_write(i64 %b, i64 1)
  ret i64 0
}

; str_interp (slots, n): the texts of the n slot values joined into a new
; String. The values are taken.
define i64 @__rg_rt_str_interp(i64 %slots, i64 %n) {
entry:
  %buf = alloca [3 x i64], align 8
  %b = ptrtoint ptr %buf to i64
  call void @rg_buf_init(i64 %b, i64 64)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %off = shl i64 %i, 3
  %sa = add i64 %slots, %off
  %v = call i64 @rg_ld(i64 %sa)
  call void @rg_buf_value(i64 %b, i64 %v)
  call void @rg_st(i64 %sa, i64 0)
  %d = call i64 @__rg_rt_drop_val(i64 %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  %s = call i64 @rg_buf_str(i64 %b)
  ret i64 %s
}

; A numeric tensor: Tensor(shape=[d1, d2], data=[w1, w2, ...]), the words
; as Ints (the show helpers of the compiler give Reals their own text).
define void @rg_buf_tensor(i64 %b, i64 %v) {
entry:
  call void @rg_buf_lit(i64 %b, ptr @rg_s_tshape, i64 14)
  %sh = call i64 @rg_w1(i64 %v)
  call void @rg_buf_words(i64 %b, i64 %sh, i1 false)
  call void @rg_buf_lit(i64 %b, ptr @rg_s_tdata, i64 9)
  %dh = call i64 @rg_w2(i64 %v)
  call void @rg_buf_words(i64 %b, i64 %dh, i1 true)
  call void @rg_buf_byte(i64 %b, i64 93)
  call void @rg_buf_byte(i64 %b, i64 41)
  ret void
}

; The raw words of a vector, separated by ", ": as Ints, or (real) each
; word converted to a Real. An untyped `echo` of a numeric tensor shows its
; data that way (the typed echo goes through __rg_tensor_show_int/_real).
define void @rg_buf_words(i64 %b, i64 %h, i1 %real) {
entry:
  %n = call i64 @rg_vlen(i64 %h)
  %d = call i64 @rg_vdata(i64 %h)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %sep, label %done
sep:
  %first = icmp eq i64 %i, 0
  br i1 %first, label %body, label %comma
comma:
  call void @rg_buf_lit(i64 %b, ptr @rg_s_sep, i64 2)
  br label %body
body:
  %off = shl i64 %i, 3
  %a = add i64 %d, %off
  %w = call i64 @rg_ld(i64 %a)
  br i1 %real, label %asreal, label %asint
asreal:
  %f = sitofp i64 %w to double
  call void @rg_buf_real(i64 %b, double %f)
  br label %next
asint:
  call void @rg_buf_i64(i64 %b, i64 %w)
  br label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}
