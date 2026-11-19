; ============================================================
; src/main/runtime/core/fuse.ll
; Fused element-wise expressions (FR-COMP-031, ADR-0013).
;
; `((a_ij + b_ij) xor d_ij) rotl 16` is one program and one pass over the
; elements. The compiler gives the program as text, `K|code`:
;   K     the element kind of every tensor: N 64-bit integers, R Reals,
;         B U8, H U16, W U32 (packed tensors, bytes.ll)
;   code  the expression in postfix, tokens separated by one space:
;           e      the next leaf: a tensor of the shape of the result
;           p      the next leaf: a tensor of the first dimensions of the
;                  result (the same along the others)
;           u      the next leaf: a tensor of the last dimensions
;           s      the next leaf: a number, the same for every element
;           c<n>   the integer n
;           x<id>  a binary operator: 0 + 1 - 2 * 3 / 4 % 11 and 12 or
;                  13 xor 17 shl 18 shr 19 rotr 20 rotl
; The leaves are in consecutive slots, in the order of their tokens, and
; are taken. The result is a new tensor of the shape and kind of the first
; `e` leaf.
;
; Integers wrap at the width of the kind. A shift or rotation count is taken
; modulo the width; shr is logical; / and % by zero give 0; on N, / and %
; are signed. Reals take + - * / (IEEE 754).
;
; rg_fuse is the meaning of a program on every target. The LLVM back end
; writes the same loop in the program itself (llvm.ridgun), where it is
; specialised and vectorised; it uses rg_fuse_like and the accessors below.
; ============================================================

declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i64 @rg_ldb(i64)
declare i1 @rg_has_tag(i64, i64)
declare void @rg_copy(i64, i64, i64)
declare void @rg_fill(i64, i8, i64)
declare void @rg_fatal(ptr, i64) noreturn
declare i64 @rg_t_new(i64, i64)
declare i64 @rg_t_rank(i64)
declare i64 @rg_t_dims(i64)
declare i64 @rg_t_data(i64)
declare i64 @rg_t_len(i64)
declare i64 @rg_word_at(i64, i64)
declare i64 @rg_raw_word(i64)
declare i64 @rg_word_op(i64, i64, i64)
declare void @rg_drop_slots(i64, i64)
declare i64 @rg_u8_rank(i64)
declare i64 @rg_u8_count(i64)
declare i64 @rg_u8_bytes(i64)
declare i64 @rg_rc(i64)
declare i64 @rg_w2(i64)
declare i64 @__rg_rt_make_tuple(i64, i64)

@rg_msg_fuse_t = private constant [37 x i8] c"element-wise expression: not a tensor"
@rg_msg_fuse_s = private constant [42 x i8] c"element-wise expression: the shapes differ"
@rg_msg_fuse_p = private constant [36 x i8] c"element-wise expression: bad program"

; The size of an element of kind k as a power of two: B 0, H 1, W 2, else 3.
define i64 @rg_fuse_lg(i64 %k) {
entry:
  switch i64 %k, label %w8 [ i64 66, label %w1
                             i64 72, label %w2
                             i64 87, label %w4 ]
w1:
  ret i64 0
w2:
  ret i64 1
w4:
  ret i64 2
w8:
  ret i64 3
}

; The number of elements of tensor t (lg < 3: a packed tensor).
define i64 @rg_fuse_len(i64 %t, i64 %lg) {
entry:
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  %n = call i64 @rg_u8_count(i64 %t)
  ret i64 %n
wd:
  %m = call i64 @rg_t_len(i64 %t)
  ret i64 %m
}

; The address of the first element.
define i64 @rg_fuse_data(i64 %t, i64 %lg) {
entry:
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  %a = call i64 @rg_u8_bytes(i64 %t)
  ret i64 %a
wd:
  %d = call i64 @rg_t_data(i64 %t)
  ret i64 %d
}

; A new tensor of the shape of t; its elements are not set.
define i64 @rg_fuse_like(i64 %t, i64 %lg) {
entry:
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  %w = call i64 @rg_t_len(i64 %t)
  %r = call i64 @rg_t_new(i64 1, i64 %w)
  %rd = call i64 @rg_t_dims(i64 %r)
  call void @rg_st(i64 %rd, i64 %w)
  %dst = call i64 @rg_t_data(i64 %r)
  %src = call i64 @rg_t_data(i64 %t)
  ; only the last word can keep bytes past the elements: clear it
  %wz = icmp eq i64 %w, 0
  %wl0 = sub i64 %w, 1
  %wl = select i1 %wz, i64 0, i64 %wl0
  %lo = shl i64 %wl, 3
  %la = add i64 %dst, %lo
  br i1 %wz, label %pk2, label %pk1
pk1:
  call void @rg_st(i64 %la, i64 0)
  br label %pk2
pk2:
  %k = call i64 @rg_u8_rank(i64 %t)
  %h = add i64 %k, 1
  %hb = shl i64 %h, 3
  call void @rg_copy(i64 %dst, i64 %src, i64 %hb)
  ret i64 %r
wd:
  %rank = call i64 @rg_t_rank(i64 %t)
  %n = call i64 @rg_t_len(i64 %t)
  %r2 = call i64 @rg_t_new(i64 %rank, i64 %n)
  %d2 = call i64 @rg_t_dims(i64 %r2)
  %s2 = call i64 @rg_t_dims(i64 %t)
  %rb = shl i64 %rank, 3
  call void @rg_copy(i64 %d2, i64 %s2, i64 %rb)
  ret i64 %r2
}

; 1 when nothing else holds tensor t or its elements.
define i1 @rg_fuse_owned(i64 %t) {
  %rc = call i64 @rg_rc(i64 %t)
  %one = icmp eq i64 %rc, 1
  %dh = call i64 @rg_w2(i64 %t)
  %ra = add i64 %dh, 24
  %vrc = call i64 @rg_ld(i64 %ra)
  %vone = icmp eq i64 %vrc, 1
  %r = and i1 %one, %vone
  ret i1 %r
}

; 1 when tensors a and b (of the same kind) have the same shape.
define i1 @rg_fuse_same_shape(i64 %a, i64 %b, i64 %lg) {
entry:
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  ; the same number of words, and the same rank and dimensions in front
  %wa = call i64 @rg_t_len(i64 %a)
  %wb = call i64 @rg_t_len(i64 %b)
  %weq = icmp eq i64 %wa, %wb
  br i1 %weq, label %pk1, label %no
pk1:
  %ka = call i64 @rg_u8_rank(i64 %a)
  %n1 = add i64 %ka, 1
  %da = call i64 @rg_t_data(i64 %a)
  %db = call i64 @rg_t_data(i64 %b)
  br label %cmp
wd:
  %ra = call i64 @rg_t_rank(i64 %a)
  %rb = call i64 @rg_t_rank(i64 %b)
  %req = icmp eq i64 %ra, %rb
  %la = call i64 @rg_t_len(i64 %a)
  %lb = call i64 @rg_t_len(i64 %b)
  %leq = icmp eq i64 %la, %lb
  %both = and i1 %req, %leq
  br i1 %both, label %wd1, label %no
wd1:
  %sa = call i64 @rg_t_dims(i64 %a)
  %sb = call i64 @rg_t_dims(i64 %b)
  br label %cmp
cmp:
  %x = phi i64 [ %da, %pk1 ], [ %sa, %wd1 ]
  %y = phi i64 [ %db, %pk1 ], [ %sb, %wd1 ]
  %n = phi i64 [ %n1, %pk1 ], [ %ra, %wd1 ]
  br label %loop
loop:
  %i = phi i64 [ 0, %cmp ], [ %i1, %same ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %one, label %yes
one:
  %xv = call i64 @rg_word_at(i64 %x, i64 %i)
  %yv = call i64 @rg_word_at(i64 %y, i64 %i)
  %eq = icmp eq i64 %xv, %yv
  br i1 %eq, label %same, label %no
same:
  %i1 = add i64 %i, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; A tensor for a result, of the shape of model: a leaf that nothing else holds
; and that has that shape is taken from its slot and written in place; without
; one, a new tensor. A program reads element i of every leaf before it writes
; element i of any result (every `o` comes after the last read), so a result
; may be one of the tensors it reads.
define i64 @rg_fuse_take(i64 %slots, i64 %nl, i64 %model, i64 %lg) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, %nl
  br i1 %more, label %body, label %fresh
body:
  %off = shl i64 %i, 3
  %a = add i64 %slots, %off
  %v = call i64 @rg_ld(i64 %a)
  %ist = call i1 @rg_has_tag(i64 %v, i64 5)
  br i1 %ist, label %own, label %next
own:
  %o = call i1 @rg_fuse_owned(i64 %v)
  br i1 %o, label %shape, label %next
shape:
  %s = call i1 @rg_fuse_same_shape(i64 %v, i64 %model, i64 %lg)
  br i1 %s, label %take, label %next
take:
  call void @rg_st(i64 %a, i64 0)
  ret i64 %v
next:
  %i1 = add i64 %i, 1
  br label %loop
fresh:
  %r = call i64 @rg_fuse_like(i64 %model, i64 %lg)
  ret i64 %r
}

; The tensor in a leaf slot, checked; stops when the value is not a tensor.
define i64 @rg_fuse_leaf(i64 %v) {
entry:
  %ok = call i1 @rg_has_tag(i64 %v, i64 5)
  br i1 %ok, label %yes, label %no
yes:
  ret i64 %v
no:
  call void @rg_fatal(ptr @rg_msg_fuse_t, i64 37)
  unreachable
}

; open (v, lg, lenp): the address of the elements of the tensor in a leaf slot,
; and their number in *lenp; stops when the value is not a tensor.
define i64 @rg_fuse_open(i64 %v, i64 %lg, ptr %lenp) {
  %t = call i64 @rg_fuse_leaf(i64 %v)
  %n = call i64 @rg_fuse_len(i64 %t, i64 %lg)
  store i64 %n, ptr %lenp, align 8
  %d = call i64 @rg_fuse_data(i64 %t, i64 %lg)
  ret i64 %d
}

define void @rg_fuse_shapes() noreturn {
  call void @rg_fatal(ptr @rg_msg_fuse_s, i64 42)
  unreachable
}

; The number of the last dimension of t (1 when it has none).
define i64 @rg_fuse_last(i64 %t, i64 %lg) {
entry:
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  %k = call i64 @rg_u8_rank(i64 %t)
  %kz = icmp eq i64 %k, 0
  br i1 %kz, label %one, label %pk1
pk1:
  %d = call i64 @rg_t_data(i64 %t)
  %x = call i64 @rg_word_at(i64 %d, i64 %k)
  ret i64 %x
wd:
  %rank = call i64 @rg_t_rank(i64 %t)
  %rz = icmp eq i64 %rank, 0
  br i1 %rz, label %one, label %wd1
wd1:
  %dims = call i64 @rg_t_dims(i64 %t)
  %li = sub i64 %rank, 1
  %y = call i64 @rg_word_at(i64 %dims, i64 %li)
  ret i64 %y
one:
  ret i64 1
}

; Element i at address d, of size 2^lg bytes, as an unsigned word.
define i64 @rg_fuse_get(i64 %d, i64 %i, i64 %lg) alwaysinline {
entry:
  %off = shl i64 %i, %lg
  %a = add i64 %d, %off
  %p = inttoptr i64 %a to ptr
  switch i64 %lg, label %w8 [ i64 0, label %w1
                              i64 1, label %w2
                              i64 2, label %w4 ]
w1:
  %b1 = load i8, ptr %p, align 1
  %z1 = zext i8 %b1 to i64
  ret i64 %z1
w2:
  %b2 = load i16, ptr %p, align 1
  %z2 = zext i16 %b2 to i64
  ret i64 %z2
w4:
  %b4 = load i32, ptr %p, align 1
  %z4 = zext i32 %b4 to i64
  ret i64 %z4
w8:
  %b8 = load i64, ptr %p, align 8
  ret i64 %b8
}

define void @rg_fuse_put(i64 %d, i64 %i, i64 %lg, i64 %v) alwaysinline {
entry:
  %off = shl i64 %i, %lg
  %a = add i64 %d, %off
  %p = inttoptr i64 %a to ptr
  switch i64 %lg, label %w8 [ i64 0, label %w1
                              i64 1, label %w2
                              i64 2, label %w4 ]
w1:
  %t1 = trunc i64 %v to i8
  store i8 %t1, ptr %p, align 1
  ret void
w2:
  %t2 = trunc i64 %v to i16
  store i16 %t2, ptr %p, align 1
  ret void
w4:
  %t4 = trunc i64 %v to i32
  store i32 %t4, ptr %p, align 1
  ret void
w8:
  store i64 %v, ptr %p, align 8
  ret void
}

; The low 8 * 2^lg bits of v.
define i64 @rg_fuse_wrap(i64 %v, i64 %lg) alwaysinline {
entry:
  %full = icmp uge i64 %lg, 3
  br i1 %full, label %same, label %cut
same:
  ret i64 %v
cut:
  %bits = shl i64 8, %lg
  %one = shl i64 1, %bits
  %mask = sub i64 %one, 1
  %r = and i64 %v, %mask
  ret i64 %r
}

; One operator on two elements of kind k (lg its size).
define i64 @rg_fuse_op(i64 %op, i64 %a, i64 %b, i64 %k, i64 %lg) {
entry:
  %real = icmp eq i64 %k, 82
  br i1 %real, label %fl, label %int
fl:
  %fop = add i64 %op, 100
  %fr = call i64 @rg_word_op(i64 %fop, i64 %a, i64 %b)
  ret i64 %fr
int:
  %full = icmp uge i64 %lg, 3
  br i1 %full, label %word, label %narrow
word:
  %wr = call i64 @rg_word_op(i64 %op, i64 %a, i64 %b)
  ret i64 %wr
narrow:
  %bits = shl i64 8, %lg
  %bm = sub i64 %bits, 1
  %c = and i64 %b, %bm
  %inv = sub i64 %bits, %c
  switch i64 %op, label %plain [ i64 17, label %shl
                                 i64 18, label %shr
                                 i64 19, label %rotr
                                 i64 20, label %rotl ]
shl:
  %s1 = shl i64 %a, %c
  %s1w = call i64 @rg_fuse_wrap(i64 %s1, i64 %lg)
  ret i64 %s1w
shr:
  %s2 = lshr i64 %a, %c
  ret i64 %s2
rotl:
  %l1 = shl i64 %a, %c
  %l2 = lshr i64 %a, %inv
  %l3 = or i64 %l1, %l2
  %l3w = call i64 @rg_fuse_wrap(i64 %l3, i64 %lg)
  ret i64 %l3w
rotr:
  %r1 = lshr i64 %a, %c
  %r2 = shl i64 %a, %inv
  %r3 = or i64 %r1, %r2
  %r3w = call i64 @rg_fuse_wrap(i64 %r3, i64 %lg)
  ret i64 %r3w
plain:
  %pr = call i64 @rg_word_op(i64 %op, i64 %a, i64 %b)
  %prw = call i64 @rg_fuse_wrap(i64 %pr, i64 %lg)
  ret i64 %prw
}

; The integer written at address a (digits, with an optional minus sign); the
; address after it goes to *endp.
define i64 @rg_fuse_num(i64 %a, i64 %end, ptr %endp) {
entry:
  %c0 = call i64 @rg_ldb(i64 %a)
  %neg = icmp eq i64 %c0, 45
  %a1 = add i64 %a, 1
  %start = select i1 %neg, i64 %a1, i64 %a
  br label %loop
loop:
  %p = phi i64 [ %start, %entry ], [ %p1, %body ]
  %n = phi i64 [ 0, %entry ], [ %n2, %body ]
  %in = icmp ult i64 %p, %end
  br i1 %in, label %test, label %done
test:
  %ch = call i64 @rg_ldb(i64 %p)
  %d = sub i64 %ch, 48
  %isd = icmp ult i64 %d, 10
  br i1 %isd, label %body, label %done
body:
  %n1 = mul i64 %n, 10
  %n2 = add i64 %n1, %d
  %p1 = add i64 %p, 1
  br label %loop
done:
  store i64 %p, ptr %endp, align 8
  %m = sub i64 0, %n
  %r = select i1 %neg, i64 %m, i64 %n
  ret i64 %r
}

; fuse (slots, program, length): run the program on its leaves.
; Token tables (at most 2048 tokens and values, 96 results): kind 0 e, 1 p, 2 u (arg: the address of
; the elements, len: their number), 3 a number (arg: its word), 4 an
; operator (arg: its id), 5 w (arg: the value to set), 6 l (arg: the value to
; read), 7 o (arg: the result to write).
define i64 @rg_fuse(i64 %slots, i64 %prog, i64 %plen) {
entry:
  %kinds = alloca [2048 x i64], align 8
  %args = alloca [2048 x i64], align 8
  %lens = alloca [2048 x i64], align 8
  %stack = alloca [96 x i64], align 8
  %locals = alloca [2048 x i64], align 8
  %outs = alloca [96 x i64], align 8
  %outd = alloca [96 x i64], align 8
  %endp = alloca i64, align 8
  %kd = ptrtoint ptr %kinds to i64
  %ar = ptrtoint ptr %args to i64
  %ln = ptrtoint ptr %lens to i64
  %sk = ptrtoint ptr %stack to i64
  %lc = ptrtoint ptr %locals to i64
  %ot = ptrtoint ptr %outs to i64
  %od = ptrtoint ptr %outd to i64
  %k = call i64 @rg_ldb(i64 %prog)
  %lg = call i64 @rg_fuse_lg(i64 %k)
  %end = add i64 %prog, %plen
  %first = add i64 %prog, 2
  br label %scan
scan:
  ; p: the address in the program, nt: tokens read, nl: leaves read, no:
  ; results, model: the first `e` tensor (0: none yet)
  %p = phi i64 [ %first, %entry ], [ %pn, %next ]
  %nt = phi i64 [ 0, %entry ], [ %nt1, %next ]
  %nl = phi i64 [ 0, %entry ], [ %nln, %next ]
  %no = phi i64 [ 0, %entry ], [ %non, %next ]
  %model = phi i64 [ 0, %entry ], [ %modeln, %next ]
  %more = icmp ult i64 %p, %end
  br i1 %more, label %tok, label %scanned
tok:
  %room = icmp ult i64 %nt, 2048
  br i1 %room, label %tok1, label %bad
tok1:
  %ch = call i64 @rg_ldb(i64 %p)
  %p1 = add i64 %p, 1
  %ka = shl i64 %nt, 3
  %kp = add i64 %kd, %ka
  %ap = add i64 %ar, %ka
  %lp = add i64 %ln, %ka
  %lo = shl i64 %nl, 3
  %ls = add i64 %slots, %lo
  switch i64 %ch, label %bad [ i64 101, label %te
                               i64 112, label %tp
                               i64 117, label %tu
                               i64 115, label %ts
                               i64 99, label %tc
                               i64 120, label %tx
                               i64 119, label %tw
                               i64 108, label %tl
                               i64 111, label %to ]
te:
  br label %tens
tp:
  br label %tens
tu:
  br label %tens
tens:
  %tk = phi i64 [ 0, %te ], [ 1, %tp ], [ 2, %tu ]
  %tv0 = call i64 @rg_ld(i64 %ls)
  %tv = call i64 @rg_fuse_leaf(i64 %tv0)
  %td = call i64 @rg_fuse_data(i64 %tv, i64 %lg)
  %tlen = call i64 @rg_fuse_len(i64 %tv, i64 %lg)
  call void @rg_st(i64 %kp, i64 %tk)
  call void @rg_st(i64 %ap, i64 %td)
  call void @rg_st(i64 %lp, i64 %tlen)
  %ise = icmp eq i64 %tk, 0
  %nomodel = icmp eq i64 %model, 0
  %take = and i1 %ise, %nomodel
  %model1 = select i1 %take, i64 %tv, i64 %model
  %nl1 = add i64 %nl, 1
  br label %next
ts:
  %sv = call i64 @rg_ld(i64 %ls)
  %sw = call i64 @rg_raw_word(i64 %sv)
  %sww = call i64 @rg_fuse_wrap(i64 %sw, i64 %lg)
  call void @rg_st(i64 %kp, i64 3)
  call void @rg_st(i64 %ap, i64 %sww)
  %nl2 = add i64 %nl, 1
  br label %next
tc:
  %cv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %cvw = call i64 @rg_fuse_wrap(i64 %cv, i64 %lg)
  %pc = load i64, ptr %endp, align 8
  call void @rg_st(i64 %kp, i64 3)
  call void @rg_st(i64 %ap, i64 %cvw)
  br label %next
tx:
  %xv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %px = load i64, ptr %endp, align 8
  call void @rg_st(i64 %kp, i64 4)
  call void @rg_st(i64 %ap, i64 %xv)
  br label %next
tw:
  %wv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pw = load i64, ptr %endp, align 8
  %wok = icmp ult i64 %wv, 2048
  br i1 %wok, label %tw1, label %bad
tw1:
  call void @rg_st(i64 %kp, i64 5)
  call void @rg_st(i64 %ap, i64 %wv)
  br label %next
tl:
  %lv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pl = load i64, ptr %endp, align 8
  %lok = icmp ult i64 %lv, 2048
  br i1 %lok, label %tl1, label %bad
tl1:
  call void @rg_st(i64 %kp, i64 6)
  call void @rg_st(i64 %ap, i64 %lv)
  br label %next
to:
  %ook = icmp ult i64 %no, 96
  br i1 %ook, label %to1, label %bad
to1:
  call void @rg_st(i64 %kp, i64 7)
  call void @rg_st(i64 %ap, i64 %no)
  %no1 = add i64 %no, 1
  br label %next
next:
  %pa = phi i64 [ %p1, %tens ], [ %p1, %ts ], [ %pc, %tc ], [ %px, %tx ], [ %pw, %tw1 ], [ %pl, %tl1 ], [ %p1, %to1 ]
  %nln = phi i64 [ %nl1, %tens ], [ %nl2, %ts ], [ %nl, %tc ], [ %nl, %tx ], [ %nl, %tw1 ], [ %nl, %tl1 ], [ %nl, %to1 ]
  %non = phi i64 [ %no, %tens ], [ %no, %ts ], [ %no, %tc ], [ %no, %tx ], [ %no, %tw1 ], [ %no, %tl1 ], [ %no1, %to1 ]
  %modeln = phi i64 [ %model1, %tens ], [ %model, %ts ], [ %model, %tc ], [ %model, %tx ], [ %model, %tw1 ], [ %model, %tl1 ], [ %model, %to1 ]
  %nt1 = add i64 %nt, 1
  ; skip the space after the token
  %pn = add i64 %pa, 1
  br label %scan
scanned:
  %hasm = icmp ne i64 %model, 0
  br i1 %hasm, label %shapes, label %bad
shapes:
  %total = call i64 @rg_fuse_len(i64 %model, i64 %lg)
  br label %chk
chk:
  %ci = phi i64 [ 0, %shapes ], [ %ci1, %chknext ]
  %cm = icmp ult i64 %ci, %nt
  br i1 %cm, label %chkone, label %alloc
chkone:
  %co = shl i64 %ci, 3
  %ckp = add i64 %kd, %co
  %clp = add i64 %ln, %co
  %ck = call i64 @rg_ld(i64 %ckp)
  %cl = call i64 @rg_ld(i64 %clp)
  switch i64 %ck, label %chknext [ i64 0, label %ceq
                                   i64 1, label %cdiv
                                   i64 2, label %cdiv ]
ceq:
  %same = icmp eq i64 %cl, %total
  br i1 %same, label %chknext, label %differ
cdiv:
  ; a tensor of the first or of the last dimensions: its length divides the
  ; total (an empty result takes any)
  %tz = icmp eq i64 %total, 0
  br i1 %tz, label %chknext, label %cdiv1
cdiv1:
  %lz = icmp eq i64 %cl, 0
  br i1 %lz, label %differ, label %cdiv2
cdiv2:
  %rem = urem i64 %total, %cl
  %fits = icmp eq i64 %rem, 0
  br i1 %fits, label %chknext, label %differ
chknext:
  %ci1 = add i64 %ci, 1
  br label %chk
differ:
  call void @rg_fuse_shapes()
  unreachable
alloc:
  ; one result tensor for each `o`, or one for the value left on the stack
  %single = icmp eq i64 %no, 0
  %nres = select i1 %single, i64 1, i64 %no
  br label %mk
mk:
  %mi = phi i64 [ 0, %alloc ], [ %mi1, %mkone ]
  %mm = icmp ult i64 %mi, %nres
  br i1 %mm, label %mkone, label %elem
mkone:
  %mr = call i64 @rg_fuse_take(i64 %slots, i64 %nl, i64 %model, i64 %lg)
  %md = call i64 @rg_fuse_data(i64 %mr, i64 %lg)
  %mo = shl i64 %mi, 3
  %mta = add i64 %ot, %mo
  %mda = add i64 %od, %mo
  call void @rg_st(i64 %mta, i64 %mr)
  call void @rg_st(i64 %mda, i64 %md)
  %mi1 = add i64 %mi, 1
  br label %mk
elem:
  %e = phi i64 [ 0, %mk ], [ %e1, %stored ]
  %em = icmp ult i64 %e, %total
  br i1 %em, label %run, label %finish
run:
  br label %step
step:
  %ti = phi i64 [ 0, %run ], [ %ti1, %pushed ]
  %sp = phi i64 [ 0, %run ], [ %spn, %pushed ]
  %tm = icmp ult i64 %ti, %nt
  br i1 %tm, label %one, label %store
one:
  %tof = shl i64 %ti, 3
  %okp = add i64 %kd, %tof
  %oap = add i64 %ar, %tof
  %olp = add i64 %ln, %tof
  %ok = call i64 @rg_ld(i64 %okp)
  %oa = call i64 @rg_ld(i64 %oap)
  %ol = call i64 @rg_ld(i64 %olp)
  %topi = sub i64 %sp, 1
  %topo = shl i64 %topi, 3
  %topa = add i64 %sk, %topo
  %vo = shl i64 %oa, 3
  switch i64 %ok, label %oop [ i64 0, label %oe
                               i64 1, label %op_
                               i64 2, label %ou
                               i64 3, label %on
                               i64 5, label %ow
                               i64 6, label %olg
                               i64 7, label %oo ]
oe:
  %ve = call i64 @rg_fuse_get(i64 %oa, i64 %e, i64 %lg)
  br label %push
op_:
  %per = udiv i64 %total, %ol
  %pi = udiv i64 %e, %per
  %vp = call i64 @rg_fuse_get(i64 %oa, i64 %pi, i64 %lg)
  br label %push
ou:
  %ui = urem i64 %e, %ol
  %vu = call i64 @rg_fuse_get(i64 %oa, i64 %ui, i64 %lg)
  br label %push
on:
  br label %push
olg:
  %lga = add i64 %lc, %vo
  %vl = call i64 @rg_ld(i64 %lga)
  br label %push
push:
  %pv = phi i64 [ %ve, %oe ], [ %vp, %op_ ], [ %vu, %ou ], [ %oa, %on ], [ %vl, %olg ]
  %full = icmp uge i64 %sp, 96
  br i1 %full, label %bad, label %push1
push1:
  %so = shl i64 %sp, 3
  %sa = add i64 %sk, %so
  call void @rg_st(i64 %sa, i64 %pv)
  %sp1 = add i64 %sp, 1
  br label %pushed
ow:
  %whas = icmp uge i64 %sp, 1
  br i1 %whas, label %ow1, label %bad
ow1:
  %wtop = call i64 @rg_ld(i64 %topa)
  %wla = add i64 %lc, %vo
  call void @rg_st(i64 %wla, i64 %wtop)
  br label %pushed
oo:
  %ohas = icmp uge i64 %sp, 1
  br i1 %ohas, label %oo1, label %bad
oo1:
  %otop = call i64 @rg_ld(i64 %topa)
  %oda = add i64 %od, %vo
  %odp = call i64 @rg_ld(i64 %oda)
  call void @rg_fuse_put(i64 %odp, i64 %e, i64 %lg, i64 %otop)
  br label %pushed
oop:
  %two = icmp uge i64 %sp, 2
  br i1 %two, label %oop1, label %bad
oop1:
  %ai = sub i64 %sp, 2
  %ao = shl i64 %ai, 3
  %aa = add i64 %sk, %ao
  %bv = call i64 @rg_ld(i64 %topa)
  %av = call i64 @rg_ld(i64 %aa)
  %rv = call i64 @rg_fuse_op(i64 %oa, i64 %av, i64 %bv, i64 %k, i64 %lg)
  call void @rg_st(i64 %aa, i64 %rv)
  br label %pushed
pushed:
  %spn = phi i64 [ %sp1, %push1 ], [ %topi, %ow1 ], [ %topi, %oo1 ], [ %topi, %oop1 ]
  %ti1 = add i64 %ti, 1
  br label %step
store:
  br i1 %single, label %store1, label %stored
store1:
  %top = call i64 @rg_ld(i64 %sk)
  %rd0 = call i64 @rg_ld(i64 %od)
  call void @rg_fuse_put(i64 %rd0, i64 %e, i64 %lg, i64 %top)
  br label %stored
stored:
  %e1 = add i64 %e, 1
  br label %elem
finish:
  call void @rg_drop_slots(i64 %slots, i64 %nl)
  br i1 %single, label %ret1, label %retn
ret1:
  %res = call i64 @rg_ld(i64 %ot)
  ret i64 %res
retn:
  %tup = call i64 @__rg_rt_make_tuple(i64 %ot, i64 %no)
  ret i64 %tup
bad:
  call void @rg_fatal(ptr @rg_msg_fuse_p, i64 36)
  unreachable
}

; ── The vector instructions of this machine ──────────────────
; The LLVM back end writes each fused loop three times, for the plain
; x86-64 instructions, for AVX2 and for AVX-512, and calls the widest one the
; machine has. cpu_level says which: 2 plain, 3 AVX2, 4 AVX-512 (F, BW, DQ and
; VL). It is read once from the flags the system lists in /proc/cpuinfo (the
; system lists a flag only when it also saves those registers); where the
; file cannot be read the answer is 2.
declare i64 @__rg_pal_open(i64, i64, i64, i64)
declare i64 @__rg_pal_read(i64, i64, i64)
declare i64 @__rg_pal_close(i64)

@rg_cpu = internal global i64 0
@rg_cpuinfo = private constant [13 x i8] c"/proc/cpuinfo"
@rg_flag_avx2 = private constant [6 x i8] c" avx2 "
@rg_flag_512f = private constant [9 x i8] c" avx512f "
@rg_flag_512bw = private constant [10 x i8] c" avx512bw "
@rg_flag_512dq = private constant [10 x i8] c" avx512dq "
@rg_flag_512vl = private constant [10 x i8] c" avx512vl "

; 1 when the n bytes at buf hold the m bytes at pat.
define i64 @rg_has_bytes(i64 %buf, i64 %n, ptr %pat, i64 %m) {
entry:
  %pa = ptrtoint ptr %pat to i64
  %short = icmp ult i64 %n, %m
  br i1 %short, label %no, label %start
start:
  %lastp = sub i64 %n, %m
  br label %at
at:
  %i = phi i64 [ 0, %start ], [ %i1, %miss ]
  %in = icmp ule i64 %i, %lastp
  br i1 %in, label %cmp, label %no
cmp:
  %j = phi i64 [ 0, %at ], [ %j1, %same ]
  %all = icmp eq i64 %j, %m
  br i1 %all, label %yes, label %one
one:
  %ba0 = add i64 %buf, %i
  %ba = add i64 %ba0, %j
  %pb = add i64 %pa, %j
  %x = call i64 @rg_ldb(i64 %ba)
  %y = call i64 @rg_ldb(i64 %pb)
  %eq = icmp eq i64 %x, %y
  br i1 %eq, label %same, label %miss
same:
  %j1 = add i64 %j, 1
  br label %cmp
miss:
  %i1 = add i64 %i, 1
  br label %at
yes:
  ret i64 1
no:
  ret i64 0
}

; RIDGUN_CPU=2 or RIDGUN_CPU=3 in the environment keeps the level at or below
; that number: the same program then runs its other loops, to test them or to
; compare them.
@rg_env_cpu2 = private constant [13 x i8] c"RIDGUN_CPU=2\00"
@rg_env_cpu3 = private constant [13 x i8] c"RIDGUN_CPU=3\00"
declare i64 @__rg_pal_env(i64, i64)
declare i64 @rg_alloc(i64)
declare void @rg_free(i64)

define i64 @rg_cpu_limit() {
entry:
  %need = call i64 @__rg_pal_env(i64 0, i64 0)
  %some = icmp sgt i64 %need, 0
  br i1 %some, label %get, label %none
get:
  %buf = call i64 @rg_alloc(i64 %need)
  %got = call i64 @__rg_pal_env(i64 %buf, i64 %need)
  %l2 = call i64 @rg_has_bytes(i64 %buf, i64 %need, ptr @rg_env_cpu2, i64 13)
  %l3 = call i64 @rg_has_bytes(i64 %buf, i64 %need, ptr @rg_env_cpu3, i64 13)
  call void @rg_free(i64 %buf)
  %is2 = icmp ne i64 %l2, 0
  %is3 = icmp ne i64 %l3, 0
  %a = select i1 %is3, i64 3, i64 4
  %b = select i1 %is2, i64 2, i64 %a
  ret i64 %b
none:
  ret i64 4
}

define i64 @rg_cpu_level() {
entry:
  %c = load i64, ptr @rg_cpu, align 8
  %known = icmp ne i64 %c, 0
  br i1 %known, label %have, label %find
have:
  ret i64 %c
find:
  %d = call i64 @rg_cpu_detect()
  %lim = call i64 @rg_cpu_limit()
  %less = icmp ult i64 %lim, %d
  %lvl = select i1 %less, i64 %lim, i64 %d
  store i64 %lvl, ptr @rg_cpu, align 8
  ret i64 %lvl
}

define i64 @rg_cpu_detect() {
entry:
  br label %detect
detect:
  %bufp = alloca [8192 x i8], align 8
  %buf = ptrtoint ptr %bufp to i64
  %path = ptrtoint ptr @rg_cpuinfo to i64
  %fd = call i64 @__rg_pal_open(i64 %path, i64 13, i64 0, i64 0)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %plain, label %read
read:
  %n = call i64 @__rg_pal_read(i64 %fd, i64 %buf, i64 8192)
  %x = call i64 @__rg_pal_close(i64 %fd)
  %none = icmp sle i64 %n, 0
  br i1 %none, label %plain, label %look
look:
  %a2 = call i64 @rg_has_bytes(i64 %buf, i64 %n, ptr @rg_flag_avx2, i64 6)
  %hasa2 = icmp ne i64 %a2, 0
  br i1 %hasa2, label %wide, label %plain
wide:
  %f = call i64 @rg_has_bytes(i64 %buf, i64 %n, ptr @rg_flag_512f, i64 9)
  %bw = call i64 @rg_has_bytes(i64 %buf, i64 %n, ptr @rg_flag_512bw, i64 10)
  %dq = call i64 @rg_has_bytes(i64 %buf, i64 %n, ptr @rg_flag_512dq, i64 10)
  %vl = call i64 @rg_has_bytes(i64 %buf, i64 %n, ptr @rg_flag_512vl, i64 10)
  %s1 = and i64 %f, %bw
  %s2 = and i64 %dq, %vl
  %s3 = and i64 %s1, %s2
  %lvl = add i64 3, %s3
  ret i64 %lvl
plain:
  ret i64 2
}
