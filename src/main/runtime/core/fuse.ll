; ============================================================
; src/main/runtime/core/fuse.ll
; Fused element-wise expressions (FR-COMP-031, ADR-0013).
;
; `((a_ij + b_ij) xor d_ij) rotl 16` is one program and one pass over the
; elements. The compiler gives the program as text, the expression in
; postfix, its tokens separated by one space:
;   e      the next leaf: a tensor of the shape of the result
;   p      the next leaf: a tensor of the first dimensions of the result
;          (the same along the others)
;   u      the next leaf: a tensor of the last dimensions
;   s      the next leaf: a number, the same for every element
;   c<n>   the integer n
;   x<id>  a binary operator: 0 + 1 - 2 * 3 / 4 % 11 and 12 or 13 xor
;          17 shl 18 shr 19 rotr 20 rotl 21 mulhi (the high half of the
;          product at the width of the kind) 22 clmul 23 clmulhi (the
;          low and the high half of the product without carries)
;   g      the next leaf: a tensor of any shape; the value on top is an
;          index into its elements, and its element there replaces it
;   w<k>   take the value on top as value k
;   l<k>   value k
;   o      take the value on top as the next result
;   f<k>   after `o`: that result is what leaf k holds the next time round
;   n      the next leaf: a number; the program runs that many times (at
;          least once), each time on the results of the time before
;   y      the last token; the next leaf: a tensor of any shape. Under the
;          index on top is a value: the tensor gets it at that index, in the
;          order of the elements. The program gives 0.
;   k<d>   the value on top as an integer of kind d (1, 3, 4 or 5): cut to
;          its width; a narrower value is already below it
;   v<c>   the next leaf: a number that moves by c each time the program
;          runs (the leaf holds its value the first time)
;   r<id>  the last token: the program gives one number, the values of all
;          the elements joined: 0 their sum, 30 the smallest, 31 the largest
;          (0 when there is no element). Integers are joined as 64-bit
;          numbers (the sum wraps at 2^64), Reals as Reals.
; The leaves are in consecutive slots, in the order of their tokens, and
; are taken. A program without `o` gives one tensor, the value left; with
; `o`, a tuple of tensors. A result has the shape of the first `e` leaf.
;
; The element kind of each tensor leaf comes apart, as a number: one digit
; of 3 bits per tensor leaf, the first leaf lowest: 1 N (64-bit integers),
; 2 R (Reals), 3 B (U8), 4 H (U16), 5 W (U32) (B, H, W: packed tensors,
; bytes.ll). Leaves after the 20th have the kind of the 20th. A value has the
; kind of the tensor it was read from; a number takes the kind of the value
; it meets; the result of an operator has the kind of its operands.
;
; Integers wrap at the width of the kind. A shift or rotation count is taken
; modulo the width; shr is logical; / and % by zero give 0; on N, / and %
; are signed. Reals take + - * / (IEEE 754). An index outside its tensor
; stops the program.
;
; Every program reads element i of each `e` leaf before it writes element i
; of any result (every `o` comes after the last read), so a result may be
; one of those tensors (rg_fuse_take).
;
; rg_fuse is the meaning of a program on every target. The LLVM back end
; writes the same loop in the program itself (llvm.ridgun), where it is
; specialised and vectorised; it uses rg_fuse_take and the accessors below.
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
declare i64 @rg_pk_new(i64, i64, i64, i64)
declare void @rg_oob() noreturn
declare i64 @rg_real(double)
declare i64 @rg_box_int(i64)
declare i64 @rg_clmul_soft(i64, i64, i64)
declare i64 @rg_w2(i64)
declare i64 @__rg_rt_make_tuple(i64, i64)

@rg_msg_fuse_t = private constant [37 x i8] c"element-wise expression: not a tensor"
@rg_msg_fuse_s = private constant [42 x i8] c"element-wise expression: the shapes differ"
@rg_msg_fuse_p = private constant [36 x i8] c"element-wise expression: bad program"

; The size of an element of kind code k as a power of two: 3 B 0, 4 H 1,
; 5 W 2, else 3.
define i64 @rg_fuse_klg(i64 %k) {
entry:
  switch i64 %k, label %w8 [ i64 3, label %w1
                             i64 4, label %w2
                             i64 5, label %w4 ]
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

; The rank of tensor t and the address of its dimensions (lg < 3: packed).
define i64 @rg_fuse_rank(i64 %t, i64 %lg) {
entry:
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  %k = call i64 @rg_u8_rank(i64 %t)
  ret i64 %k
wd:
  %r = call i64 @rg_t_rank(i64 %t)
  ret i64 %r
}

define i64 @rg_fuse_dims(i64 %t, i64 %lg) {
entry:
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  %d = call i64 @rg_t_data(i64 %t)
  %a = add i64 %d, 8
  ret i64 %a
wd:
  %s = call i64 @rg_t_dims(i64 %t)
  ret i64 %s
}

; A new tensor of the shape of model (of element size lgm) with elements of
; size lg; they are not set.
define i64 @rg_fuse_make(i64 %model, i64 %lgm, i64 %lg) {
entry:
  %same = icmp eq i64 %lgm, %lg
  %pm = icmp ult i64 %lgm, 3
  %pr = icmp ult i64 %lg, 3
  %both = and i1 %pm, %pr
  %bothw = or i1 %pm, %pr
  %neither = xor i1 %bothw, true
  %like0 = and i1 %same, %both
  %like = or i1 %like0, %neither
  br i1 %like, label %copy, label %other
copy:
  %r = call i64 @rg_fuse_like(i64 %model, i64 %lg)
  ret i64 %r
other:
  %rank = call i64 @rg_fuse_rank(i64 %model, i64 %lgm)
  %dims = call i64 @rg_fuse_dims(i64 %model, i64 %lgm)
  br i1 %pr, label %pack, label %words
pack:
  %t = call i64 @rg_pk_new(i64 %rank, i64 %dims, i64 0, i64 %lg)
  ret i64 %t
words:
  %n = call i64 @rg_fuse_len(i64 %model, i64 %lgm)
  %w = call i64 @rg_t_new(i64 %rank, i64 %n)
  %wd = call i64 @rg_t_dims(i64 %w)
  %rb = shl i64 %rank, 3
  call void @rg_copy(i64 %wd, i64 %dims, i64 %rb)
  ret i64 %w
}

; A tensor for a result of kind kr, of the shape of model: a leaf that nothing
; else holds, that has that shape and that kind and is read element by
; element (its entry in lkinds is kr; other leaves have 0) is taken from its
; slot and written in place; without one, a new tensor. *from is the first
; leaf to look at: a leaf that was taken moves it on, so the results of one
; program look at each leaf once.
define i64 @rg_fuse_take(i64 %slots, i64 %nl, i64 %lkinds, i64 %kr, i64 %model, i64 %lgm, ptr %from) {
entry:
  %lg = call i64 @rg_fuse_klg(i64 %kr)
  %samelg = icmp eq i64 %lg, %lgm
  %start = load i64, ptr %from, align 8
  br i1 %samelg, label %loop, label %fresh
loop:
  %i = phi i64 [ %start, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, %nl
  br i1 %more, label %body, label %fresh
body:
  %off = shl i64 %i, 3
  %ka = add i64 %lkinds, %off
  %lk = call i64 @rg_ld(i64 %ka)
  %elig = icmp eq i64 %lk, %kr
  br i1 %elig, label %tag, label %next
tag:
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
  %after = add i64 %i, 1
  store i64 %after, ptr %from, align 8
  ret i64 %v
next:
  %i1 = add i64 %i, 1
  br label %loop
fresh:
  %r = call i64 @rg_fuse_make(i64 %model, i64 %lgm, i64 %lg)
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
  %real = icmp eq i64 %k, 2
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
                                 i64 20, label %rotl
                                 i64 21, label %mulhi
                                 i64 22, label %clmul
                                 i64 23, label %clmulhi ]
clmul:
  ; both are below 2^bits: the whole product fits a word
  %cp = call i64 @rg_clmul_soft(i64 %a, i64 %b, i64 0)
  %cpw = call i64 @rg_fuse_wrap(i64 %cp, i64 %lg)
  ret i64 %cpw
clmulhi:
  %cq = call i64 @rg_clmul_soft(i64 %a, i64 %b, i64 0)
  %cqh = lshr i64 %cq, %bits
  ret i64 %cqh
mulhi:
  ; both are below 2^bits: the product fits a word, its high half is the result
  %mp = mul i64 %a, %b
  %mh = lshr i64 %mp, %bits
  ret i64 %mh
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

; The value v of kind k joined with acc, the values before it (first: there
; are none): id 0 the sum, 30 the smaller, 31 the larger. Integers of the
; packed kinds are below 2^32, so every integer is compared as signed.
define i64 @rg_fuse_join(i64 %id, i64 %acc, i64 %v, i64 %k, i1 %first) {
entry:
  %real = icmp eq i64 %k, 2
  %lg = call i64 @rg_fuse_klg(i64 %k)
  %w = call i64 @rg_fuse_wrap(i64 %v, i64 %lg)
  br i1 %first, label %one, label %more
one:
  ret i64 %w
more:
  br i1 %real, label %fl, label %int
fl:
  %fa = bitcast i64 %acc to double
  %fv = bitcast i64 %w to double
  switch i64 %id, label %fsum [ i64 30, label %fmin
                                i64 31, label %fmax ]
fsum:
  %fs = fadd double %fa, %fv
  %fsw = bitcast double %fs to i64
  ret i64 %fsw
fmin:
  %fl1 = fcmp olt double %fv, %fa
  %fmn = select i1 %fl1, i64 %w, i64 %acc
  ret i64 %fmn
fmax:
  %fg1 = fcmp ogt double %fv, %fa
  %fmx = select i1 %fg1, i64 %w, i64 %acc
  ret i64 %fmx
int:
  switch i64 %id, label %isum [ i64 30, label %imin
                                i64 31, label %imax ]
isum:
  %is = add i64 %acc, %w
  ret i64 %is
imin:
  %il = icmp slt i64 %w, %acc
  %imn = select i1 %il, i64 %w, i64 %acc
  ret i64 %imn
imax:
  %ig = icmp sgt i64 %w, %acc
  %imx = select i1 %ig, i64 %w, i64 %acc
  ret i64 %imx
}

; The number a reduction gives: an Int, or a Real for kind 2.
define i64 @rg_fuse_number(i64 %w, i64 %k) {
entry:
  %real = icmp eq i64 %k, 2
  br i1 %real, label %fl, label %int
fl:
  %d = bitcast i64 %w to double
  %r = call i64 @rg_real(double %d)
  ret i64 %r
int:
  %i = call i64 @rg_box_int(i64 %w)
  ret i64 %i
}

; The kind of tensor leaf number n: digit n of kinds (the 20th for later ones).
define i64 @rg_fuse_kind_of(i64 %kinds, i64 %n) alwaysinline {
  %far = icmp ugt i64 %n, 19
  %d = select i1 %far, i64 19, i64 %n
  %sh = mul i64 %d, 3
  %x = lshr i64 %kinds, %sh
  %k = and i64 %x, 7
  %z = icmp eq i64 %k, 0
  %r = select i1 %z, i64 1, i64 %k
  ret i64 %r
}

; fuse (slots, program, length, kinds): run the program on its leaves.
; Token tables (at most 2048 tokens and values, 96 results): type 0 e, 1 p,
; 2 u, 8 g (arg: the address of the elements, len: their number), 3 a number
; (arg: its word), 4 an operator (arg: its id), 5 w, 6 l (arg: the value),
; 7 o (arg: the result). vk: the kind of the value the token makes (0: a
; number that has not met a tensor yet), found once by running the kinds
; through the program.
define i64 @rg_fuse(i64 %slots, i64 %prog, i64 %plen, i64 %kinds) {
entry:
  %types = alloca [2048 x i64], align 8
  %args = alloca [2048 x i64], align 8
  %lens = alloca [2048 x i64], align 8
  %vks = alloca [2048 x i64], align 8
  %locals = alloca [2048 x i64], align 8
  %lockinds = alloca [2048 x i64], align 8
  %leafkinds = alloca [2048 x i64], align 8
  %stack = alloca [96 x i64], align 8
  %kstack = alloca [96 x i64], align 8
  %outs = alloca [96 x i64], align 8
  %outd = alloca [96 x i64], align 8
  %outk = alloca [96 x i64], align 8
  %endp = alloca i64, align 8
  %fromp = alloca i64, align 8
  store i64 0, ptr %fromp, align 8
  %leaftoks = alloca [2048 x i64], align 8
  %feeds = alloca [96 x i64], align 8
  %repsp = alloca i64, align 8
  store i64 1, ptr %repsp, align 8
  %ltk = ptrtoint ptr %leaftoks to i64
  %fd = ptrtoint ptr %feeds to i64
  %redp = alloca i64, align 8
  %redkp = alloca i64, align 8
  %accp = alloca i64, align 8
  store i64 0, ptr %redp, align 8
  store i64 1, ptr %redkp, align 8
  store i64 0, ptr %accp, align 8
  %ty = ptrtoint ptr %types to i64
  %ar = ptrtoint ptr %args to i64
  %ln = ptrtoint ptr %lens to i64
  %vk = ptrtoint ptr %vks to i64
  %lc = ptrtoint ptr %locals to i64
  %lck = ptrtoint ptr %lockinds to i64
  %lfk = ptrtoint ptr %leafkinds to i64
  %sk = ptrtoint ptr %stack to i64
  %ks = ptrtoint ptr %kstack to i64
  %ot = ptrtoint ptr %outs to i64
  %od = ptrtoint ptr %outd to i64
  %ok = ptrtoint ptr %outk to i64
  %end = add i64 %prog, %plen
  br label %scan
scan:
  ; p: the address in the program, nt: tokens, nl: leaves, ntn: tensor
  ; leaves, no: results, ksp: values on the kind stack, model: the first `e`
  ; tensor (0: none yet), mlg: its element size
  %p = phi i64 [ %prog, %entry ], [ %pn, %next ]
  %nt = phi i64 [ 0, %entry ], [ %nt1, %next ]
  %nl = phi i64 [ 0, %entry ], [ %nln, %next ]
  %ntn = phi i64 [ 0, %entry ], [ %ntnn, %next ]
  %no = phi i64 [ 0, %entry ], [ %non, %next ]
  %ksp = phi i64 [ 0, %entry ], [ %kspn, %next ]
  %model = phi i64 [ 0, %entry ], [ %modeln, %next ]
  %mlg = phi i64 [ 3, %entry ], [ %mlgn, %next ]
  %more = icmp ult i64 %p, %end
  br i1 %more, label %tok, label %scanned
tok:
  %room = icmp ult i64 %nt, 2048
  %kroom = icmp ult i64 %ksp, 94
  %rooms = and i1 %room, %kroom
  br i1 %rooms, label %tok1, label %bad
tok1:
  %ch = call i64 @rg_ldb(i64 %p)
  %p1 = add i64 %p, 1
  %ka = shl i64 %nt, 3
  %tp = add i64 %ty, %ka
  %ap = add i64 %ar, %ka
  %lp = add i64 %ln, %ka
  %vp = add i64 %vk, %ka
  %lo = shl i64 %nl, 3
  %ls = add i64 %slots, %lo
  %lka = add i64 %lfk, %lo
  %kto = shl i64 %ksp, 3
  %ktop = add i64 %ks, %kto
  %kt1 = sub i64 %ktop, 8
  %kt2 = sub i64 %ktop, 16
  call void @rg_st(i64 %lka, i64 0)
  switch i64 %ch, label %bad [ i64 101, label %te
                               i64 112, label %tp_
                               i64 117, label %tu
                               i64 103, label %tg
                               i64 115, label %ts
                               i64 99, label %tc
                               i64 120, label %tx
                               i64 119, label %tw
                               i64 108, label %tl
                               i64 111, label %to
                               i64 114, label %tr
                               i64 110, label %tn
                               i64 102, label %tf
                               i64 118, label %tvs
                               i64 107, label %tk_
                               i64 121, label %ty_ ]
ty_:
  %yhas = icmp uge i64 %ksp, 2
  br i1 %yhas, label %ty1, label %bad
ty1:
  %ykd = call i64 @rg_fuse_kind_of(i64 %kinds, i64 %ntn)
  %yklg = call i64 @rg_fuse_klg(i64 %ykd)
  %yv0 = call i64 @rg_ld(i64 %ls)
  %yv = call i64 @rg_fuse_leaf(i64 %yv0)
  %yd = call i64 @rg_fuse_data(i64 %yv, i64 %yklg)
  %yl = call i64 @rg_fuse_len(i64 %yv, i64 %yklg)
  call void @rg_st(i64 %tp, i64 13)
  call void @rg_st(i64 %ap, i64 %yd)
  call void @rg_st(i64 %lp, i64 %yl)
  call void @rg_st(i64 %vp, i64 %ykd)
  ; no result tensor: the program ends like one that gives a number
  store i64 1002, ptr %redp, align 8
  %kspy = sub i64 %ksp, 2
  %nl5 = add i64 %nl, 1
  %ntn5 = add i64 %ntn, 1
  br label %next
tk_:
  %kdv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pk = load i64, ptr %endp, align 8
  %khas = icmp uge i64 %ksp, 1
  br i1 %khas, label %tk1, label %bad
tk1:
  call void @rg_st(i64 %kt1, i64 %kdv)
  call void @rg_st(i64 %tp, i64 12)
  call void @rg_st(i64 %vp, i64 %kdv)
  br label %next
tvs:
  %vstep = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pvv = load i64, ptr %endp, align 8
  %vv0 = call i64 @rg_ld(i64 %ls)
  %vvw = call i64 @rg_raw_word(i64 %vv0)
  call void @rg_st(i64 %tp, i64 3)
  call void @rg_st(i64 %ap, i64 %vvw)
  call void @rg_st(i64 %lp, i64 %vstep)
  call void @rg_st(i64 %vp, i64 0)
  call void @rg_st(i64 %ktop, i64 0)
  %kspv = add i64 %ksp, 1
  %nl4 = add i64 %nl, 1
  br label %next
tn:
  ; the number of times: at least once
  %nv0 = call i64 @rg_ld(i64 %ls)
  %nv = call i64 @rg_raw_word(i64 %nv0)
  %npos = icmp sgt i64 %nv, 1
  %nreps = select i1 %npos, i64 %nv, i64 1
  store i64 %nreps, ptr %repsp, align 8
  call void @rg_st(i64 %tp, i64 10)
  %nl3 = add i64 %nl, 1
  br label %next
tf:
  %fv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pf = load i64, ptr %endp, align 8
  %fhas = icmp uge i64 %no, 1
  %fok = icmp ult i64 %fv, 2048
  %fboth = and i1 %fhas, %fok
  br i1 %fboth, label %tf1, label %bad
tf1:
  %fj = sub i64 %no, 1
  %fjo = shl i64 %fj, 3
  %fja = add i64 %fd, %fjo
  call void @rg_st(i64 %fja, i64 %fv)
  call void @rg_st(i64 %tp, i64 10)
  br label %next
tr:
  %rv9 = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pr = load i64, ptr %endp, align 8
  %rhas = icmp uge i64 %ksp, 1
  br i1 %rhas, label %tr1, label %bad
tr1:
  %rdk0 = call i64 @rg_ld(i64 %kt1)
  %rkz = icmp eq i64 %rdk0, 0
  %rkk = select i1 %rkz, i64 1, i64 %rdk0
  %rid1 = add i64 %rv9, 1
  store i64 %rid1, ptr %redp, align 8
  store i64 %rkk, ptr %redkp, align 8
  call void @rg_st(i64 %tp, i64 9)
  call void @rg_st(i64 %ap, i64 %rv9)
  call void @rg_st(i64 %vp, i64 %rkk)
  %kspr = sub i64 %ksp, 1
  br label %next
te:
  br label %tens
tp_:
  br label %tens
tu:
  br label %tens
tg:
  %ghas = icmp uge i64 %ksp, 1
  br i1 %ghas, label %tens, label %bad
tens:
  %tk = phi i64 [ 0, %te ], [ 1, %tp_ ], [ 2, %tu ], [ 8, %tg ]
  %kd = call i64 @rg_fuse_kind_of(i64 %kinds, i64 %ntn)
  %klg = call i64 @rg_fuse_klg(i64 %kd)
  %tv0 = call i64 @rg_ld(i64 %ls)
  %tv = call i64 @rg_fuse_leaf(i64 %tv0)
  %td = call i64 @rg_fuse_data(i64 %tv, i64 %klg)
  %tlen = call i64 @rg_fuse_len(i64 %tv, i64 %klg)
  call void @rg_st(i64 %tp, i64 %tk)
  %lto = add i64 %ltk, %lo
  call void @rg_st(i64 %lto, i64 %nt)
  call void @rg_st(i64 %ap, i64 %td)
  call void @rg_st(i64 %lp, i64 %tlen)
  call void @rg_st(i64 %vp, i64 %kd)
  %ise = icmp eq i64 %tk, 0
  %isg = icmp eq i64 %tk, 8
  ; only an `e` leaf can take a result
  %lkv = select i1 %ise, i64 %kd, i64 0
  call void @rg_st(i64 %lka, i64 %lkv)
  %nomodel = icmp eq i64 %model, 0
  %take = and i1 %ise, %nomodel
  %model1 = select i1 %take, i64 %tv, i64 %model
  %mlg1 = select i1 %take, i64 %klg, i64 %mlg
  ; a gather replaces the index on the kind stack; another tensor is pushed
  %gat = select i1 %isg, i64 %kt1, i64 %ktop
  call void @rg_st(i64 %gat, i64 %kd)
  %ksp1 = add i64 %ksp, 1
  %kspt = select i1 %isg, i64 %ksp, i64 %ksp1
  %nl1 = add i64 %nl, 1
  %ntn1 = add i64 %ntn, 1
  br label %next
ts:
  %sv = call i64 @rg_ld(i64 %ls)
  %sw = call i64 @rg_raw_word(i64 %sv)
  call void @rg_st(i64 %tp, i64 3)
  call void @rg_st(i64 %ap, i64 %sw)
  call void @rg_st(i64 %lp, i64 0)
  call void @rg_st(i64 %vp, i64 0)
  call void @rg_st(i64 %ktop, i64 0)
  %ksps = add i64 %ksp, 1
  %nl2 = add i64 %nl, 1
  br label %next
tc:
  %cv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pc = load i64, ptr %endp, align 8
  call void @rg_st(i64 %tp, i64 3)
  call void @rg_st(i64 %ap, i64 %cv)
  call void @rg_st(i64 %lp, i64 0)
  call void @rg_st(i64 %vp, i64 0)
  call void @rg_st(i64 %ktop, i64 0)
  %kspc = add i64 %ksp, 1
  br label %next
tx:
  %xv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %px = load i64, ptr %endp, align 8
  %xhas = icmp uge i64 %ksp, 2
  br i1 %xhas, label %tx1, label %bad
tx1:
  %xa = call i64 @rg_ld(i64 %kt2)
  %xb = call i64 @rg_ld(i64 %kt1)
  %xaz = icmp eq i64 %xa, 0
  %xbz = icmp eq i64 %xb, 0
  %xk0 = select i1 %xbz, i64 1, i64 %xb
  %xk = select i1 %xaz, i64 %xk0, i64 %xa
  call void @rg_st(i64 %tp, i64 4)
  call void @rg_st(i64 %ap, i64 %xv)
  call void @rg_st(i64 %vp, i64 %xk)
  call void @rg_st(i64 %kt2, i64 %xk)
  %kspx = sub i64 %ksp, 1
  br label %next
tw:
  %wv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pw = load i64, ptr %endp, align 8
  %wok = icmp ult i64 %wv, 2048
  %whas0 = icmp uge i64 %ksp, 1
  %wboth = and i1 %wok, %whas0
  br i1 %wboth, label %tw1, label %bad
tw1:
  %wk = call i64 @rg_ld(i64 %kt1)
  %wko = shl i64 %wv, 3
  %wka = add i64 %lck, %wko
  call void @rg_st(i64 %wka, i64 %wk)
  call void @rg_st(i64 %tp, i64 5)
  call void @rg_st(i64 %ap, i64 %wv)
  %kspw = sub i64 %ksp, 1
  br label %next
tl:
  %lv = call i64 @rg_fuse_num(i64 %p1, i64 %end, ptr %endp)
  %pl = load i64, ptr %endp, align 8
  %lok = icmp ult i64 %lv, 2048
  br i1 %lok, label %tl1, label %bad
tl1:
  %llo = shl i64 %lv, 3
  %lla = add i64 %lck, %llo
  %llk = call i64 @rg_ld(i64 %lla)
  call void @rg_st(i64 %tp, i64 6)
  call void @rg_st(i64 %ap, i64 %lv)
  call void @rg_st(i64 %ktop, i64 %llk)
  %kspl = add i64 %ksp, 1
  br label %next
to:
  %ook = icmp ult i64 %no, 96
  %ohas0 = icmp uge i64 %ksp, 1
  %oboth = and i1 %ook, %ohas0
  br i1 %oboth, label %to1, label %bad
to1:
  %ok0 = call i64 @rg_ld(i64 %kt1)
  %okz = icmp eq i64 %ok0, 0
  %okk = select i1 %okz, i64 1, i64 %ok0
  %oko = shl i64 %no, 3
  %oka = add i64 %ok, %oko
  call void @rg_st(i64 %oka, i64 %okk)
  %fia = add i64 %fd, %oko
  call void @rg_st(i64 %fia, i64 -1)
  call void @rg_st(i64 %tp, i64 7)
  call void @rg_st(i64 %ap, i64 %no)
  %no1 = add i64 %no, 1
  %kspo = sub i64 %ksp, 1
  br label %next
next:
  %pa = phi i64 [ %p1, %tens ], [ %p1, %ts ], [ %pc, %tc ], [ %px, %tx1 ], [ %pw, %tw1 ], [ %pl, %tl1 ], [ %p1, %to1 ], [ %pr, %tr1 ], [ %p1, %tn ], [ %pf, %tf1 ], [ %pvv, %tvs ], [ %pk, %tk1 ], [ %p1, %ty1 ]
  %nln = phi i64 [ %nl1, %tens ], [ %nl2, %ts ], [ %nl, %tc ], [ %nl, %tx1 ], [ %nl, %tw1 ], [ %nl, %tl1 ], [ %nl, %to1 ], [ %nl, %tr1 ], [ %nl3, %tn ], [ %nl, %tf1 ], [ %nl4, %tvs ], [ %nl, %tk1 ], [ %nl5, %ty1 ]
  %ntnn = phi i64 [ %ntn1, %tens ], [ %ntn, %ts ], [ %ntn, %tc ], [ %ntn, %tx1 ], [ %ntn, %tw1 ], [ %ntn, %tl1 ], [ %ntn, %to1 ], [ %ntn, %tr1 ], [ %ntn, %tn ], [ %ntn, %tf1 ], [ %ntn, %tvs ], [ %ntn, %tk1 ], [ %ntn5, %ty1 ]
  %non = phi i64 [ %no, %tens ], [ %no, %ts ], [ %no, %tc ], [ %no, %tx1 ], [ %no, %tw1 ], [ %no, %tl1 ], [ %no1, %to1 ], [ %no, %tr1 ], [ %no, %tn ], [ %no, %tf1 ], [ %no, %tvs ], [ %no, %tk1 ], [ %no, %ty1 ]
  %kspn = phi i64 [ %kspt, %tens ], [ %ksps, %ts ], [ %kspc, %tc ], [ %kspx, %tx1 ], [ %kspw, %tw1 ], [ %kspl, %tl1 ], [ %kspo, %to1 ], [ %kspr, %tr1 ], [ %ksp, %tn ], [ %ksp, %tf1 ], [ %kspv, %tvs ], [ %ksp, %tk1 ], [ %kspy, %ty1 ]
  %modeln = phi i64 [ %model1, %tens ], [ %model, %ts ], [ %model, %tc ], [ %model, %tx1 ], [ %model, %tw1 ], [ %model, %tl1 ], [ %model, %to1 ], [ %model, %tr1 ], [ %model, %tn ], [ %model, %tf1 ], [ %model, %tvs ], [ %model, %tk1 ], [ %model, %ty1 ]
  %mlgn = phi i64 [ %mlg1, %tens ], [ %mlg, %ts ], [ %mlg, %tc ], [ %mlg, %tx1 ], [ %mlg, %tw1 ], [ %mlg, %tl1 ], [ %mlg, %to1 ], [ %mlg, %tr1 ], [ %mlg, %tn ], [ %mlg, %tf1 ], [ %mlg, %tvs ], [ %mlg, %tk1 ], [ %mlg, %ty1 ]
  %nt1 = add i64 %nt, 1
  ; skip the space after the token
  %pn = add i64 %pa, 1
  br label %scan
scanned:
  %hasm = icmp ne i64 %model, 0
  br i1 %hasm, label %shapes, label %bad
shapes:
  %total = call i64 @rg_fuse_len(i64 %model, i64 %mlg)
  ; a program without `o` has one result: the value left on the kind stack
  ; (none when it ends in `r`: the result is a number)
  %single = icmp eq i64 %no, 0
  %red = load i64, ptr %redp, align 8
  %redk = load i64, ptr %redkp, align 8
  %reduces = icmp ne i64 %red, 0
  %redid = sub i64 %red, 1
  br i1 %reduces, label %chk0, label %sres
sres:
  br i1 %single, label %one_res, label %chk0
one_res:
  %left = icmp eq i64 %ksp, 1
  br i1 %left, label %one_res1, label %bad
one_res1:
  %lk0 = call i64 @rg_ld(i64 %ks)
  %lkz = icmp eq i64 %lk0, 0
  %lk1 = select i1 %lkz, i64 1, i64 %lk0
  call void @rg_st(i64 %ok, i64 %lk1)
  br label %chk0
chk0:
  %nres0 = select i1 %single, i64 1, i64 %no
  %nres = select i1 %reduces, i64 0, i64 %nres0
  br label %chk
chk:
  %ci = phi i64 [ 0, %chk0 ], [ %ci1, %chknext ]
  %cm = icmp ult i64 %ci, %nt
  br i1 %cm, label %chkone, label %elig
chkone:
  %co = shl i64 %ci, 3
  %ctp = add i64 %ty, %co
  %clp = add i64 %ln, %co
  %ck = call i64 @rg_ld(i64 %ctp)
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
elig:
  ; a program that runs several times: only a leaf that a result feeds can
  ; take a result (another leaf is read again after the first time)
  %ereps = load i64, ptr %repsp, align 8
  %emany = icmp ugt i64 %ereps, 1
  br i1 %emany, label %el, label %mk
el:
  %eli = phi i64 [ 0, %elig ], [ %eli1, %elnext ]
  %elm = icmp ult i64 %eli, %nl
  br i1 %elm, label %elf, label %mk
elf:
  %elj = phi i64 [ 0, %el ], [ %elj1, %elfn ]
  %eljm = icmp ult i64 %elj, %no
  br i1 %eljm, label %elfc, label %elclear
elfc:
  %eljo = shl i64 %elj, 3
  %elfa = add i64 %fd, %eljo
  %elfv = call i64 @rg_ld(i64 %elfa)
  %elhit = icmp eq i64 %elfv, %eli
  br i1 %elhit, label %elnext, label %elfn
elfn:
  %elj1 = add i64 %elj, 1
  br label %elf
elclear:
  %elo = shl i64 %eli, 3
  %elka = add i64 %lfk, %elo
  call void @rg_st(i64 %elka, i64 0)
  br label %elnext
elnext:
  %eli1 = add i64 %eli, 1
  br label %el
mk:
  %mi = phi i64 [ 0, %elig ], [ 0, %el ], [ %mi1, %mkone ]
  %mm = icmp ult i64 %mi, %nres
  br i1 %mm, label %mkone, label %elem
mkone:
  %mo = shl i64 %mi, 3
  %mka = add i64 %ok, %mo
  %mkk = call i64 @rg_ld(i64 %mka)
  %mklg = call i64 @rg_fuse_klg(i64 %mkk)
  %mr = call i64 @rg_fuse_take(i64 %slots, i64 %nl, i64 %lfk, i64 %mkk, i64 %model, i64 %mlg, ptr %fromp)
  %md = call i64 @rg_fuse_data(i64 %mr, i64 %mklg)
  %mta = add i64 %ot, %mo
  %mda = add i64 %od, %mo
  call void @rg_st(i64 %mta, i64 %mr)
  call void @rg_st(i64 %mda, i64 %md)
  %mi1 = add i64 %mi, 1
  br label %mk
elem:
  %e = phi i64 [ 0, %mk ], [ %e1, %stored ], [ 0, %moved ]
  %rep = phi i64 [ 1, %mk ], [ %rep, %stored ], [ %rep1, %moved ]
  %em = icmp ult i64 %e, %total
  br i1 %em, label %run, label %round
round:
  ; one time is done: when another follows, each leaf a result feeds reads
  ; that result from now on
  %reps = load i64, ptr %repsp, align 8
  %rmore = icmp ult i64 %rep, %reps
  br i1 %rmore, label %feed, label %finish
feed:
  %fi = phi i64 [ 0, %round ], [ %fi1, %feednext ]
  %fim = icmp ult i64 %fi, %no
  br i1 %fim, label %feedone, label %again
feedone:
  %fio = shl i64 %fi, 3
  %ffa = add i64 %fd, %fio
  %fleaf = call i64 @rg_ld(i64 %ffa)
  %fneg = icmp slt i64 %fleaf, 0
  br i1 %fneg, label %feednext, label %feedset
feedset:
  %flo = shl i64 %fleaf, 3
  %flta = add i64 %ltk, %flo
  %ftok = call i64 @rg_ld(i64 %flta)
  %fto = shl i64 %ftok, 3
  %fap = add i64 %ar, %fto
  %foda = add i64 %od, %fio
  %fod = call i64 @rg_ld(i64 %foda)
  call void @rg_st(i64 %fap, i64 %fod)
  br label %feednext
feednext:
  %fi1 = add i64 %fi, 1
  br label %feed
again:
  %rep1 = add i64 %rep, 1
  br label %move
move:
  ; the numbers that move each time
  %mvi = phi i64 [ 0, %again ], [ %mvi1, %movenext ]
  %mvm = icmp ult i64 %mvi, %nt
  br i1 %mvm, label %moveone, label %moved
moveone:
  %mvo = shl i64 %mvi, 3
  %mvtp = add i64 %ty, %mvo
  %mvt = call i64 @rg_ld(i64 %mvtp)
  %mvnum = icmp eq i64 %mvt, 3
  br i1 %mvnum, label %moveadd, label %movenext
moveadd:
  %mvlp = add i64 %ln, %mvo
  %mvap = add i64 %ar, %mvo
  %mvs = call i64 @rg_ld(i64 %mvlp)
  %mva = call i64 @rg_ld(i64 %mvap)
  %mvn = add i64 %mva, %mvs
  call void @rg_st(i64 %mvap, i64 %mvn)
  br label %movenext
movenext:
  %mvi1 = add i64 %mvi, 1
  br label %move
moved:
  br label %elem
run:
  br label %step
step:
  %ti = phi i64 [ 0, %run ], [ %ti1, %pushed ]
  %sp = phi i64 [ 0, %run ], [ %spn, %pushed ]
  %tm = icmp ult i64 %ti, %nt
  br i1 %tm, label %one, label %store
one:
  %tof = shl i64 %ti, 3
  %otp = add i64 %ty, %tof
  %oap = add i64 %ar, %tof
  %olp = add i64 %ln, %tof
  %ovp = add i64 %vk, %tof
  %oty = call i64 @rg_ld(i64 %otp)
  %oa = call i64 @rg_ld(i64 %oap)
  %ol = call i64 @rg_ld(i64 %olp)
  %ovk = call i64 @rg_ld(i64 %ovp)
  %olg = call i64 @rg_fuse_klg(i64 %ovk)
  %topi = sub i64 %sp, 1
  %topo = shl i64 %topi, 3
  %topa = add i64 %sk, %topo
  %vo = shl i64 %oa, 3
  switch i64 %oty, label %oop [ i64 0, label %oe
                                i64 1, label %op_
                                i64 2, label %ou
                                i64 3, label %on
                                i64 5, label %ow
                                i64 6, label %olget
                                i64 7, label %oo
                                i64 8, label %og
                                i64 9, label %ored
                                i64 10, label %onop
                                i64 12, label %okind
                                i64 13, label %oscat ]
oscat:
  ; the value under the index goes to the tensor at that index
  %six = call i64 @rg_ld(i64 %topa)
  %sin = icmp ult i64 %six, %ol
  br i1 %sin, label %oscat1, label %oob
oscat1:
  %svi = sub i64 %sp, 2
  %svo = shl i64 %svi, 3
  %sva = add i64 %sk, %svo
  %sval = call i64 @rg_ld(i64 %sva)
  call void @rg_fuse_put(i64 %oa, i64 %six, i64 %olg, i64 %sval)
  br label %pushed
okind:
  ; the value on top at the width of its new kind
  %kv0 = call i64 @rg_ld(i64 %topa)
  %kv1 = call i64 @rg_fuse_wrap(i64 %kv0, i64 %olg)
  call void @rg_st(i64 %topa, i64 %kv1)
  br label %pushed
onop:
  br label %pushed
ored:
  ; join the value on top with the ones before
  %dv = call i64 @rg_ld(i64 %topa)
  %dacc = load i64, ptr %accp, align 8
  %dfirst = icmp eq i64 %e, 0
  %dnew = call i64 @rg_fuse_join(i64 %redid, i64 %dacc, i64 %dv, i64 %ovk, i1 %dfirst)
  store i64 %dnew, ptr %accp, align 8
  br label %pushed
oe:
  %ve = call i64 @rg_fuse_get(i64 %oa, i64 %e, i64 %olg)
  br label %push
op_:
  %per = udiv i64 %total, %ol
  %pi = udiv i64 %e, %per
  %vpv = call i64 @rg_fuse_get(i64 %oa, i64 %pi, i64 %olg)
  br label %push
ou:
  %ui = urem i64 %e, %ol
  %vu = call i64 @rg_fuse_get(i64 %oa, i64 %ui, i64 %olg)
  br label %push
on:
  br label %push
olget:
  %lga = add i64 %lc, %vo
  %vl = call i64 @rg_ld(i64 %lga)
  br label %push
push:
  %pv = phi i64 [ %ve, %oe ], [ %vpv, %op_ ], [ %vu, %ou ], [ %oa, %on ], [ %vl, %olget ]
  %full = icmp uge i64 %sp, 96
  br i1 %full, label %bad, label %push1
push1:
  %so = shl i64 %sp, 3
  %sa = add i64 %sk, %so
  call void @rg_st(i64 %sa, i64 %pv)
  %sp1 = add i64 %sp, 1
  br label %pushed
og:
  ; the index on top gives way to the element there
  %gix = call i64 @rg_ld(i64 %topa)
  %gin = icmp ult i64 %gix, %ol
  br i1 %gin, label %og1, label %oob
og1:
  %gv = call i64 @rg_fuse_get(i64 %oa, i64 %gix, i64 %olg)
  call void @rg_st(i64 %topa, i64 %gv)
  br label %pushed
oob:
  call void @rg_oob()
  unreachable
ow:
  %wtop = call i64 @rg_ld(i64 %topa)
  %wla = add i64 %lc, %vo
  call void @rg_st(i64 %wla, i64 %wtop)
  br label %pushed
oo:
  %otop = call i64 @rg_ld(i64 %topa)
  %oda = add i64 %od, %vo
  %odp = call i64 @rg_ld(i64 %oda)
  %oka2 = add i64 %ok, %vo
  %okk2 = call i64 @rg_ld(i64 %oka2)
  %oklg = call i64 @rg_fuse_klg(i64 %okk2)
  call void @rg_fuse_put(i64 %odp, i64 %e, i64 %oklg, i64 %otop)
  br label %pushed
oop:
  %ai = sub i64 %sp, 2
  %ao = shl i64 %ai, 3
  %aa = add i64 %sk, %ao
  %bv0 = call i64 @rg_ld(i64 %topa)
  %av0 = call i64 @rg_ld(i64 %aa)
  %bv = call i64 @rg_fuse_wrap(i64 %bv0, i64 %olg)
  %av = call i64 @rg_fuse_wrap(i64 %av0, i64 %olg)
  %rv = call i64 @rg_fuse_op(i64 %oa, i64 %av, i64 %bv, i64 %ovk, i64 %olg)
  call void @rg_st(i64 %aa, i64 %rv)
  br label %pushed
pushed:
  %spn = phi i64 [ %sp1, %push1 ], [ %sp, %og1 ], [ %topi, %ow ], [ %topi, %oo ], [ %topi, %oop ], [ %topi, %ored ], [ %sp, %onop ], [ %sp, %okind ], [ %svi, %oscat1 ]
  %ti1 = add i64 %ti, 1
  br label %step
store:
  %keeps = xor i1 %reduces, true
  %stores = and i1 %single, %keeps
  br i1 %stores, label %store1, label %stored
store1:
  %top = call i64 @rg_ld(i64 %sk)
  %rd0 = call i64 @rg_ld(i64 %od)
  %rk0 = call i64 @rg_ld(i64 %ok)
  %rlg0 = call i64 @rg_fuse_klg(i64 %rk0)
  call void @rg_fuse_put(i64 %rd0, i64 %e, i64 %rlg0, i64 %top)
  br label %stored
stored:
  %e1 = add i64 %e, 1
  br label %elem
finish:
  call void @rg_drop_slots(i64 %slots, i64 %nl)
  br i1 %reduces, label %retr, label %rets
retr:
  %wrote = icmp eq i64 %red, 1002
  br i1 %wrote, label %retz, label %retnum
retz:
  ret i64 0
retnum:
  %facc = load i64, ptr %accp, align 8
  %fnum = call i64 @rg_fuse_number(i64 %facc, i64 %redk)
  ret i64 %fnum
rets:
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
; machine has. cpu_level says which: 2 plain, 3 AVX2 with PCLMULQDQ (the
; product without carries), 4 also AVX-512 (F, BW, DQ and VL). It is read once from the flags the system lists in /proc/cpuinfo (the
; system lists a flag only when it also saves those registers); where the
; file cannot be read the answer is 2.
declare i64 @__rg_pal_open(i64, i64, i64, i64)
declare i64 @__rg_pal_read(i64, i64, i64)
declare i64 @__rg_pal_close(i64)

@rg_cpu = internal global i64 0
@rg_cpuinfo = private constant [13 x i8] c"/proc/cpuinfo"
@rg_flag_avx2 = private constant [6 x i8] c" avx2 "
@rg_flag_pcl = private constant [11 x i8] c" pclmulqdq "
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
  %pcl = call i64 @rg_has_bytes(i64 %buf, i64 %n, ptr @rg_flag_pcl, i64 11)
  %a2p = and i64 %a2, %pcl
  %hasa2 = icmp ne i64 %a2p, 0
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
