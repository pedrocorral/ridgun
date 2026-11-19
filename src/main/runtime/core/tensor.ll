; ============================================================
; src/main/runtime/core/tensor.ll
; Numeric tensors, GenTensors and the list helpers of the lowering
; (FR-COMP-020, FR-COMP-021, docs/etc/gentensor.md, ADR-0013).
;
; A numeric tensor is the heap object [5, shape, data]: shape is a raw
; vector of the dimensions (its length is the rank), data a raw vector of
; the elements as 64-bit words, row-major. An Int element is its integer, a
; Real element its bits (the compiler converts with NRealToBits and
; NRealFromBits). A GenTensor is a List (one dimension) or a List of row
; Lists (two dimensions).
;
; Runtime entries (rt slot k -> __rg_rt_<name>):
;   17 make_tensor (slots, n)        a tensor literal; nested rows flattened
;   19 pack_seq (frame, arity)       the arguments bound by `f (args)`
;   38 index (base slot, index slots, k)          t_(i ...) read
;   39 index_set (base slot, index slots, k, v)   t_(i ...) = v, in place
;   40 seq_select, 41 einsum, 42 hadamard
;   47 enter_region, 48 exit_region (`with region`)
;   56 is_list  57 is_gen  58 list_set  59 list_get  60 sort_by
;   61 gt_conv  62 real_from_bits  63 real_to_bits
; A negative k in index means k indices and a borrowed base.
; Builtins: 88 fill, 90 element-wise, 92..95 rows and columns; other ids go
; on to rg_builtin_bytes (bytes.ll).
; ============================================================

declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i1 @rg_is_heap(i64)
declare i64 @rg_tag(i64)
declare i1 @rg_has_tag(i64, i64)
declare i64 @rg_w1(i64)
declare i64 @rg_w2(i64)
declare i64 @rg_obj(i64, i64, i64)
declare i64 @rg_vec(i64, i64, i64)
declare i64 @rg_vdata(i64)
declare i64 @rg_vlen(i64)
declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare void @rg_copy(i64, i64, i64)
declare void @rg_fill(i64, i8, i64)
declare i64 @rg_ldb(i64)
declare i64 @rg_list_alloc(i64, i64)
declare i64 @rg_list_at(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_box_int(i64)
declare i64 @rg_bool(i1)
declare i64 @rg_compare(i64, i64)
declare i64 @__rg_rt_clone_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare i64 @__rg_rt_make_tuple(i64, i64)
declare void @rg_fatal(ptr, i64) noreturn
declare i64 @rg_builtin_bytes(i64, i64, i64)
declare i64 @rg_fuse(i64, i64, i64, i64)
declare i64 @rg_mulhi(i64, i64)
declare i64 @rg_clmul_soft(i64, i64, i64)

@rg_msg_oob = private constant [25 x i8] c"tensor index out of range"
@rg_msg_sortlen = private constant [41 x i8] c"sort by: the lists have different lengths"
@rg_msg_mask = private constant [36 x i8] c"sequence mask: wrong number of items"

define void @rg_oob() noreturn {
  call void @rg_fatal(ptr @rg_msg_oob, i64 25)
  unreachable
}

; ── Words ────────────────────────────────────────────────────

; The raw word of a number: the integer of an Int, the bits of a Real.
; Any other value is its own word.
define i64 @rg_raw_word(i64 %v) {
entry:
  %low = and i64 %v, 1
  %t = icmp eq i64 %low, 1
  br i1 %t, label %tagged, label %h
tagged:
  %n = ashr i64 %v, 1
  ret i64 %n
h:
  %num = call i1 @rg_has_tag(i64 %v, i64 0)
  br i1 %num, label %boxed, label %other
boxed:
  %p = call i64 @rg_w1(i64 %v)
  ret i64 %p
other:
  ret i64 %v
}

; An index value as an integer; -1 when it is not an Int.
define i64 @rg_index_of(i64 %v) {
entry:
  %low = and i64 %v, 1
  %t = icmp eq i64 %low, 1
  br i1 %t, label %tagged, label %h
tagged:
  %n = ashr i64 %v, 1
  ret i64 %n
h:
  %num = call i1 @rg_has_tag(i64 %v, i64 0)
  br i1 %num, label %w, label %bad
w:
  %word = call i64 @rg_ld(i64 %v)
  %isint = icmp eq i64 %word, -9223372036854775808
  br i1 %isint, label %boxed, label %bad
boxed:
  %p = call i64 @rg_w1(i64 %v)
  ret i64 %p
bad:
  ret i64 -1
}

; ── Tensor objects ───────────────────────────────────────────

; A new tensor of the given rank (dimensions not set) and n data words
; (not set).
define i64 @rg_t_new(i64 %rank, i64 %n) {
  %sh = call i64 @rg_vec(i64 %rank, i64 %rank, i64 8)
  %dh = call i64 @rg_vec(i64 %n, i64 %n, i64 8)
  %t = call i64 @rg_obj(i64 5, i64 %sh, i64 %dh)
  ret i64 %t
}

define i64 @rg_t_rank(i64 %t) alwaysinline {
  %sh = call i64 @rg_w1(i64 %t)
  %r = call i64 @rg_vlen(i64 %sh)
  ret i64 %r
}

; The address of the dimensions.
define i64 @rg_t_dims(i64 %t) alwaysinline {
  %sh = call i64 @rg_w1(i64 %t)
  %d = call i64 @rg_vdata(i64 %sh)
  ret i64 %d
}

; The address of the data words.
define i64 @rg_t_data(i64 %t) alwaysinline {
  %dh = call i64 @rg_w2(i64 %t)
  %d = call i64 @rg_vdata(i64 %dh)
  ret i64 %d
}

define i64 @rg_t_len(i64 %t) alwaysinline {
  %dh = call i64 @rg_w2(i64 %t)
  %n = call i64 @rg_vlen(i64 %dh)
  ret i64 %n
}

define i64 @rg_word_at(i64 %d, i64 %i) alwaysinline {
  %off = shl i64 %i, 3
  %a = add i64 %d, %off
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

define void @rg_word_set(i64 %d, i64 %i, i64 %v) alwaysinline {
  %off = shl i64 %i, 3
  %a = add i64 %d, %off
  call void @rg_st(i64 %a, i64 %v)
  ret void
}

; The product of the n words at d.
define i64 @rg_product(i64 %d, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %p = phi i64 [ 1, %entry ], [ %p1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %x = call i64 @rg_word_at(i64 %d, i64 %i)
  %pos = icmp sgt i64 %x, 0
  %x1 = select i1 %pos, i64 %x, i64 0
  %p1 = mul i64 %p, %x1
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %p
}

; A new tensor with the given dimensions (n of them at dims), every word
; equal to fill.
define i64 @rg_t_filled(i64 %dims, i64 %n, i64 %fill) {
entry:
  %tot = call i64 @rg_product(i64 %dims, i64 %n)
  %t = call i64 @rg_t_new(i64 %n, i64 %tot)
  %td = call i64 @rg_t_dims(i64 %t)
  %db = shl i64 %n, 3
  call void @rg_copy(i64 %td, i64 %dims, i64 %db)
  br label %clamp
clamp:
  %j = phi i64 [ 0, %entry ], [ %j1, %cbody ]
  %cm = icmp slt i64 %j, %n
  br i1 %cm, label %cbody, label %fill0
cbody:
  %x = call i64 @rg_word_at(i64 %td, i64 %j)
  %pos = icmp sgt i64 %x, 0
  %x1 = select i1 %pos, i64 %x, i64 0
  call void @rg_word_set(i64 %td, i64 %j, i64 %x1)
  %j1 = add i64 %j, 1
  br label %clamp
fill0:
  %d = call i64 @rg_t_data(i64 %t)
  br label %loop
loop:
  %i = phi i64 [ 0, %fill0 ], [ %i1, %body ]
  %more = icmp slt i64 %i, %tot
  br i1 %more, label %body, label %done
body:
  call void @rg_word_set(i64 %d, i64 %i, i64 %fill)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %t
}

; Clear n slots, dropping their values.
define void @rg_drop_slots(i64 %slots, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %off = shl i64 %i, 3
  %a = add i64 %slots, %off
  %v = call i64 @rg_ld(i64 %a)
  call void @rg_st(i64 %a, i64 0)
  %x = call i64 @__rg_rt_drop_val(i64 %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

; ── make_tensor ──────────────────────────────────────────────

; Write the leaves of v (a number, a List of them, or a tensor) as words at
; d from index `at`, at most up to cap; gives the next index.
define i64 @rg_flatten(i64 %v, i64 %d, i64 %at, i64 %cap) {
entry:
  %isl = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %isl, label %list, label %t5
list:
  %n = call i64 @rg_list_len(i64 %v)
  br label %lloop
lloop:
  %i = phi i64 [ 0, %list ], [ %i1, %lbody ]
  %a = phi i64 [ %at, %list ], [ %a1, %lbody ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %lbody, label %ldone
lbody:
  %ea = call i64 @rg_list_at(i64 %v, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  %a1 = call i64 @rg_flatten(i64 %e, i64 %d, i64 %a, i64 %cap)
  %i1 = add i64 %i, 1
  br label %lloop
ldone:
  ret i64 %a
t5:
  %ist = call i1 @rg_has_tag(i64 %v, i64 5)
  br i1 %ist, label %tensor, label %leaf
tensor:
  %tn = call i64 @rg_t_len(i64 %v)
  %room = sub i64 %cap, %at
  %fits = icmp slt i64 %tn, %room
  %k0 = select i1 %fits, i64 %tn, i64 %room
  %pos = icmp sgt i64 %k0, 0
  %k = select i1 %pos, i64 %k0, i64 0
  %src = call i64 @rg_t_data(i64 %v)
  %off = shl i64 %at, 3
  %dst = add i64 %d, %off
  %bytes = shl i64 %k, 3
  call void @rg_copy(i64 %dst, i64 %src, i64 %bytes)
  %r = add i64 %at, %tn
  ret i64 %r
leaf:
  %ok = icmp slt i64 %at, %cap
  br i1 %ok, label %put, label %skip
put:
  %w = call i64 @rg_raw_word(i64 %v)
  call void @rg_word_set(i64 %d, i64 %at, i64 %w)
  br label %skip
skip:
  %r2 = add i64 %at, 1
  ret i64 %r2
}

; make_tensor (slots, n): a tensor literal of the n slot values (taken).
; The shape is n, then the lengths of the first element's nested Lists,
; then the shape of a tensor found there.
define i64 @__rg_rt_make_tensor(i64 %slots, i64 %n) {
entry:
  %dims = alloca [16 x i64], align 8
  %dp = ptrtoint ptr %dims to i64
  call void @rg_word_set(i64 %dp, i64 0, i64 %n)
  %has = icmp sgt i64 %n, 0
  br i1 %has, label %first, label %shaped
first:
  %v0 = call i64 @rg_ld(i64 %slots)
  br label %walk
walk:
  %v = phi i64 [ %v0, %first ], [ %vn, %next ]
  %r = phi i64 [ 1, %first ], [ %r1, %next ]
  %isl = call i1 @rg_has_tag(i64 %v, i64 2)
  %room = icmp slt i64 %r, 16
  %go = and i1 %isl, %room
  br i1 %go, label %wbody, label %tens
wbody:
  %ln = call i64 @rg_list_len(i64 %v)
  call void @rg_word_set(i64 %dp, i64 %r, i64 %ln)
  %r1 = add i64 %r, 1
  %ne = icmp sgt i64 %ln, 0
  br i1 %ne, label %next, label %stop
next:
  %ea = call i64 @rg_list_at(i64 %v, i64 0)
  %vn = call i64 @rg_ld(i64 %ea)
  br label %walk
stop:
  br label %shaped
tens:
  %ist = call i1 @rg_has_tag(i64 %v, i64 5)
  br i1 %ist, label %tdims, label %shaped
tdims:
  %tr = call i64 @rg_t_rank(i64 %v)
  %td = call i64 @rg_t_dims(i64 %v)
  br label %tloop
tloop:
  %j = phi i64 [ 0, %tdims ], [ %j1, %tbody ]
  %rr = phi i64 [ %r, %tdims ], [ %rr1, %tbody ]
  %jm = icmp slt i64 %j, %tr
  %rm = icmp slt i64 %rr, 16
  %tg = and i1 %jm, %rm
  br i1 %tg, label %tbody, label %shaped
tbody:
  %x = call i64 @rg_word_at(i64 %td, i64 %j)
  call void @rg_word_set(i64 %dp, i64 %rr, i64 %x)
  %rr1 = add i64 %rr, 1
  %j1 = add i64 %j, 1
  br label %tloop
shaped:
  %rank = phi i64 [ 1, %entry ], [ %r1, %stop ], [ %r, %tens ], [ %rr, %tloop ]
  %t = call i64 @rg_t_filled(i64 %dp, i64 %rank, i64 0)
  %d = call i64 @rg_t_data(i64 %t)
  %cap = call i64 @rg_t_len(i64 %t)
  br label %fl
fl:
  %i = phi i64 [ 0, %shaped ], [ %i1, %fbody ]
  %at = phi i64 [ 0, %shaped ], [ %at1, %fbody ]
  %fm = icmp slt i64 %i, %n
  br i1 %fm, label %fbody, label %done
fbody:
  %off = shl i64 %i, 3
  %sa = add i64 %slots, %off
  %e = call i64 @rg_ld(i64 %sa)
  %at1 = call i64 @rg_flatten(i64 %e, i64 %d, i64 %at, i64 %cap)
  %i1 = add i64 %i, 1
  br label %fl
done:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %t
}

; pack_seq (frame, arity): `f (args) = ...` binds the arguments as one
; tuple; they are taken from slots 0 .. arity-1.
define i64 @__rg_rt_pack_seq(i64 %frame, i64 %arity) {
  %t = call i64 @__rg_rt_make_tuple(i64 %frame, i64 %arity)
  ret i64 %t
}

; ── Reading and writing elements ─────────────────────────────

; The flat offset of the k indices at idx in tensor t (k <= rank), checked
; against the dimensions; the index slots are cleared.
define i64 @rg_t_offset(i64 %t, i64 %idx, i64 %k) {
entry:
  %rank = call i64 @rg_t_rank(i64 %t)
  %over = icmp sgt i64 %k, %rank
  br i1 %over, label %bad, label %go
go:
  %dims = call i64 @rg_t_dims(i64 %t)
  br label %loop
loop:
  %j = phi i64 [ 0, %go ], [ %j1, %ok ]
  %off = phi i64 [ 0, %go ], [ %off1, %ok ]
  %more = icmp slt i64 %j, %k
  br i1 %more, label %body, label %done
body:
  %ia = shl i64 %j, 3
  %sa = add i64 %idx, %ia
  %iv = call i64 @rg_ld(i64 %sa)
  call void @rg_st(i64 %sa, i64 0)
  %x = call i64 @__rg_rt_drop_val(i64 %iv)
  %i = call i64 @rg_index_of(i64 %iv)
  %dim = call i64 @rg_word_at(i64 %dims, i64 %j)
  %neg = icmp slt i64 %i, 0
  %big = icmp sge i64 %i, %dim
  %out = or i1 %neg, %big
  br i1 %out, label %bad, label %ok
ok:
  %m = mul i64 %off, %dim
  %off1 = add i64 %m, %i
  %j1 = add i64 %j, 1
  br label %loop
done:
  ret i64 %off
bad:
  call void @rg_oob()
  unreachable
}

; The size of the block below the first k dimensions of t.
define i64 @rg_t_block(i64 %t, i64 %k) {
  %rank = call i64 @rg_t_rank(i64 %t)
  %dims = call i64 @rg_t_dims(i64 %t)
  %ko = shl i64 %k, 3
  %rest = add i64 %dims, %ko
  %n = sub i64 %rank, %k
  %p = call i64 @rg_product(i64 %rest, i64 %n)
  ret i64 %p
}

; The element (or the block below) at k indices of a tensor or a List of
; Lists. base is borrowed; the index slots are cleared.
define i64 @rg_index_get(i64 %base, i64 %idx, i64 %k) {
entry:
  %ist = call i1 @rg_has_tag(i64 %base, i64 5)
  br i1 %ist, label %tensor, label %lists
tensor:
  %off = call i64 @rg_t_offset(i64 %base, i64 %idx, i64 %k)
  %rank = call i64 @rg_t_rank(i64 %base)
  %blk = call i64 @rg_t_block(i64 %base, i64 %k)
  %start = mul i64 %off, %blk
  %end = add i64 %start, %blk
  %len = call i64 @rg_t_len(i64 %base)
  %short = icmp sgt i64 %end, %len
  br i1 %short, label %bad, label %read
read:
  %d = call i64 @rg_t_data(i64 %base)
  %full = icmp eq i64 %k, %rank
  br i1 %full, label %one, label %block
one:
  %w = call i64 @rg_word_at(i64 %d, i64 %start)
  %r = call i64 @rg_box_int(i64 %w)
  ret i64 %r
block:
  %sr = sub i64 %rank, %k
  %t = call i64 @rg_t_new(i64 %sr, i64 %blk)
  %dims = call i64 @rg_t_dims(i64 %base)
  %ko = shl i64 %k, 3
  %from = add i64 %dims, %ko
  %td = call i64 @rg_t_dims(i64 %t)
  %db = shl i64 %sr, 3
  call void @rg_copy(i64 %td, i64 %from, i64 %db)
  %tdata = call i64 @rg_t_data(i64 %t)
  %so = shl i64 %start, 3
  %src = add i64 %d, %so
  %bb = shl i64 %blk, 3
  call void @rg_copy(i64 %tdata, i64 %src, i64 %bb)
  ret i64 %t
lists:
  br label %walk
walk:
  %v = phi i64 [ %base, %lists ], [ %e, %step ]
  %j = phi i64 [ 0, %lists ], [ %j1, %step ]
  %more = icmp slt i64 %j, %k
  br i1 %more, label %level, label %found
level:
  %isl = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %isl, label %chk, label %bad
chk:
  %ia = shl i64 %j, 3
  %sa = add i64 %idx, %ia
  %iv = call i64 @rg_ld(i64 %sa)
  call void @rg_st(i64 %sa, i64 0)
  %x = call i64 @__rg_rt_drop_val(i64 %iv)
  %i = call i64 @rg_index_of(i64 %iv)
  %n = call i64 @rg_list_len(i64 %v)
  %ok = icmp ult i64 %i, %n
  br i1 %ok, label %step, label %bad
step:
  %ea = call i64 @rg_list_at(i64 %v, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  %j1 = add i64 %j, 1
  br label %walk
found:
  %c = call i64 @__rg_rt_clone_slot(i64 %v)
  ret i64 %c
bad:
  call void @rg_oob()
  unreachable
}

; index (base slot, index slots, k): t_(i ...). The base is taken from its
; slot (borrowed when k < 0, for -k indices); the indices are taken.
define i64 @__rg_rt_index(i64 %bslot, i64 %idx, i64 %n) {
entry:
  %neg = icmp slt i64 %n, 0
  %mn = sub i64 0, %n
  %k = select i1 %neg, i64 %mn, i64 %n
  %base = call i64 @rg_ld(i64 %bslot)
  br i1 %neg, label %get, label %take
take:
  call void @rg_st(i64 %bslot, i64 0)
  br label %get
get:
  %r = call i64 @rg_index_get(i64 %base, i64 %idx, i64 %k)
  br i1 %neg, label %done, label %drop
drop:
  %x = call i64 @__rg_rt_drop_val(i64 %base)
  br label %done
done:
  ret i64 %r
}

; Write v (taken) at k indices of base (borrowed), in place.
define void @rg_index_put(i64 %base, i64 %idx, i64 %k, i64 %v) {
entry:
  %ist = call i1 @rg_has_tag(i64 %base, i64 5)
  br i1 %ist, label %tensor, label %lists
tensor:
  %off = call i64 @rg_t_offset(i64 %base, i64 %idx, i64 %k)
  %rank = call i64 @rg_t_rank(i64 %base)
  %blk = call i64 @rg_t_block(i64 %base, i64 %k)
  %start = mul i64 %off, %blk
  %end = add i64 %start, %blk
  %len = call i64 @rg_t_len(i64 %base)
  %short = icmp sgt i64 %end, %len
  br i1 %short, label %bad, label %write
write:
  %d = call i64 @rg_t_data(i64 %base)
  %full = icmp eq i64 %k, %rank
  br i1 %full, label %one, label %block
one:
  %w = call i64 @rg_raw_word(i64 %v)
  call void @rg_word_set(i64 %d, i64 %start, i64 %w)
  br label %dropv
block:
  %vt = call i1 @rg_has_tag(i64 %v, i64 5)
  br i1 %vt, label %copy, label %dropv
copy:
  %vn = call i64 @rg_t_len(i64 %v)
  %fits = icmp slt i64 %vn, %blk
  %m = select i1 %fits, i64 %vn, i64 %blk
  %vd = call i64 @rg_t_data(i64 %v)
  %so = shl i64 %start, 3
  %dst = add i64 %d, %so
  %mb = shl i64 %m, 3
  call void @rg_copy(i64 %dst, i64 %vd, i64 %mb)
  br label %dropv
dropv:
  %x = call i64 @__rg_rt_drop_val(i64 %v)
  ret void
lists:
  br label %walk
walk:
  %row = phi i64 [ %base, %lists ], [ %e, %step ]
  %j = phi i64 [ 0, %lists ], [ %j1, %step ]
  %isl = call i1 @rg_has_tag(i64 %row, i64 2)
  br i1 %isl, label %chk, label %bad
chk:
  %ia = shl i64 %j, 3
  %sa = add i64 %idx, %ia
  %iv = call i64 @rg_ld(i64 %sa)
  call void @rg_st(i64 %sa, i64 0)
  %y = call i64 @__rg_rt_drop_val(i64 %iv)
  %i = call i64 @rg_index_of(i64 %iv)
  %n = call i64 @rg_list_len(i64 %row)
  %ok = icmp ult i64 %i, %n
  br i1 %ok, label %at, label %bad
at:
  %ea = call i64 @rg_list_at(i64 %row, i64 %i)
  %j1 = add i64 %j, 1
  %last = icmp sge i64 %j1, %k
  br i1 %last, label %store, label %step
step:
  %e = call i64 @rg_ld(i64 %ea)
  br label %walk
store:
  %old = call i64 @rg_ld(i64 %ea)
  call void @rg_st(i64 %ea, i64 %v)
  %z = call i64 @__rg_rt_drop_val(i64 %old)
  ret void
bad:
  call void @rg_oob()
  unreachable
}

; index_set (base slot, index slots, k, v): t_(i ...) = v in place; gives
; the base (taken from its slot).
define i64 @__rg_rt_index_set(i64 %bslot, i64 %idx, i64 %n, i64 %v) {
entry:
  %neg = icmp slt i64 %n, 0
  %mn = sub i64 0, %n
  %k = select i1 %neg, i64 %mn, i64 %n
  %base = call i64 @rg_ld(i64 %bslot)
  call void @rg_st(i64 %bslot, i64 0)
  call void @rg_index_put(i64 %base, i64 %idx, i64 %k, i64 %v)
  br i1 %neg, label %borrowed, label %done
borrowed:
  call void @rg_st(i64 %bslot, i64 %base)
  %c = call i64 @__rg_rt_clone_slot(i64 %base)
  ret i64 %c
done:
  ret i64 %base
}

; ── GenTensor tests and list access ──────────────────────────

define i64 @__rg_rt_is_list(i64 %v) {
  %l = call i1 @rg_has_tag(i64 %v, i64 2)
  %r = call i64 @rg_bool(i1 %l)
  ret i64 %r
}

; True when v is not a number (Int, boxed Int or Real).
define i64 @__rg_rt_is_gen(i64 %v) {
entry:
  %low = and i64 %v, 1
  %t = icmp eq i64 %low, 1
  br i1 %t, label %num, label %h
h:
  %n = call i1 @rg_has_tag(i64 %v, i64 0)
  br i1 %n, label %num, label %gen
num:
  ret i64 2
gen:
  ret i64 6
}

; list_set (list, index, v): stores v (taken) at the index of the list
; (borrowed) and drops the old element.
define i64 @__rg_rt_list_set(i64 %xs, i64 %iv, i64 %v) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  br i1 %isl, label %chk, label %bad
chk:
  %i = call i64 @rg_index_of(i64 %iv)
  %n = call i64 @rg_list_len(i64 %xs)
  %ok = icmp ult i64 %i, %n
  br i1 %ok, label %set, label %bad
set:
  %ea = call i64 @rg_list_at(i64 %xs, i64 %i)
  %old = call i64 @rg_ld(i64 %ea)
  call void @rg_st(i64 %ea, i64 %v)
  %x = call i64 @__rg_rt_drop_val(i64 %old)
  ret i64 0
bad:
  call void @rg_oob()
  unreachable
}

; list_get (list, index): a clone of the element; out of range stops.
define i64 @__rg_rt_list_get(i64 %xs, i64 %iv) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  br i1 %isl, label %chk, label %bad
chk:
  %i = call i64 @rg_index_of(i64 %iv)
  %n = call i64 @rg_list_len(i64 %xs)
  %ok = icmp ult i64 %i, %n
  br i1 %ok, label %get, label %bad
get:
  %ea = call i64 @rg_list_at(i64 %xs, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  %c = call i64 @__rg_rt_clone_slot(i64 %e)
  ret i64 %c
bad:
  call void @rg_oob()
  unreachable
}

; ── sort_by ──────────────────────────────────────────────────

; 1 when key a sorts before key b: by value (mode 0, Ints), by bytes
; (mode 1, Strings).
define i1 @rg_key_less(i64 %a, i64 %b, i64 %mode) {
entry:
  %texts = icmp ne i64 %mode, 0
  br i1 %texts, label %t, label %n
n:
  %ra = call i64 @rg_raw_word(i64 %a)
  %rb = call i64 @rg_raw_word(i64 %b)
  %lt = icmp slt i64 %ra, %rb
  ret i1 %lt
t:
  %c = call i64 @rg_compare(i64 %a, i64 %b)
  %lt2 = icmp slt i64 %c, 0
  ret i1 %lt2
}

; sort_by (list, keys, mode): a new List of clones of the items, in the
; order of their keys; stable (bottom-up merge sort of the indices). Both
; lists are borrowed.
define i64 @__rg_rt_sort_by(i64 %xs, i64 %keys, i64 %mode) {
entry:
  %xl = call i1 @rg_has_tag(i64 %xs, i64 2)
  %kl = call i1 @rg_has_tag(i64 %keys, i64 2)
  %nx = call i64 @rg_list_len(i64 %xs)
  %nk = call i64 @rg_list_len(i64 %keys)
  %n = select i1 %xl, i64 %nx, i64 0
  %m = select i1 %kl, i64 %nk, i64 0
  %same = icmp eq i64 %n, %m
  br i1 %same, label %chk, label %bad
bad:
  call void @rg_fatal(ptr @rg_msg_sortlen, i64 41)
  unreachable
chk:
  %has = icmp sgt i64 %n, 0
  br i1 %has, label %alloc, label %empty
empty:
  %e = call i64 @rg_list_alloc(i64 0, i64 0)
  ret i64 %e
alloc:
  %bytes = shl i64 %n, 3
  %a = call i64 @rg_alloc(i64 %bytes)
  %b = call i64 @rg_alloc(i64 %bytes)
  br label %init
init:
  %i0 = phi i64 [ 0, %alloc ], [ %i0n, %init ]
  call void @rg_word_set(i64 %a, i64 %i0, i64 %i0)
  %i0n = add i64 %i0, 1
  %im = icmp slt i64 %i0n, %n
  br i1 %im, label %init, label %passes
passes:
  %w = phi i64 [ 1, %init ], [ %w2, %pend ]
  %src = phi i64 [ %a, %init ], [ %dst, %pend ]
  %dst = phi i64 [ %b, %init ], [ %src, %pend ]
  %wm = icmp slt i64 %w, %n
  br i1 %wm, label %runs, label %fill
runs:
  %lo = phi i64 [ 0, %passes ], [ %lo2, %rdone ]
  %lm = icmp slt i64 %lo, %n
  br i1 %lm, label %run, label %pend
run:
  %mid0 = add i64 %lo, %w
  %midlt = icmp slt i64 %mid0, %n
  %mid = select i1 %midlt, i64 %mid0, i64 %n
  %w2x = shl i64 %w, 1
  %hi0 = add i64 %lo, %w2x
  %hilt = icmp slt i64 %hi0, %n
  %hi = select i1 %hilt, i64 %hi0, i64 %n
  br label %merge
merge:
  %ii = phi i64 [ %lo, %run ], [ %ii1, %put ]
  %jj = phi i64 [ %mid, %run ], [ %jj1, %put ]
  %kk = phi i64 [ %lo, %run ], [ %kk1, %put ]
  %km = icmp slt i64 %kk, %hi
  br i1 %km, label %pick, label %rdone
pick:
  %iok = icmp slt i64 %ii, %mid
  %jok = icmp slt i64 %jj, %hi
  br i1 %jok, label %jcand, label %takei
jcand:
  br i1 %iok, label %cmp, label %takej
cmp:
  %xi = call i64 @rg_word_at(i64 %src, i64 %ii)
  %xj = call i64 @rg_word_at(i64 %src, i64 %jj)
  %kia = call i64 @rg_list_at(i64 %keys, i64 %xi)
  %ki = call i64 @rg_ld(i64 %kia)
  %kja = call i64 @rg_list_at(i64 %keys, i64 %xj)
  %kj = call i64 @rg_ld(i64 %kja)
  %jless = call i1 @rg_key_less(i64 %kj, i64 %ki, i64 %mode)
  br i1 %jless, label %takej, label %takei
takei:
  %vi = call i64 @rg_word_at(i64 %src, i64 %ii)
  br label %put
takej:
  %vj = call i64 @rg_word_at(i64 %src, i64 %jj)
  br label %put
put:
  %pv = phi i64 [ %vi, %takei ], [ %vj, %takej ]
  %di = phi i64 [ 1, %takei ], [ 0, %takej ]
  call void @rg_word_set(i64 %dst, i64 %kk, i64 %pv)
  %ii1 = add i64 %ii, %di
  %dj = sub i64 1, %di
  %jj1 = add i64 %jj, %dj
  %kk1 = add i64 %kk, 1
  br label %merge
rdone:
  %lo2 = add i64 %lo, %w2x
  br label %runs
pend:
  %w2 = shl i64 %w, 1
  br label %passes
fill:
  %out = call i64 @rg_list_alloc(i64 %n, i64 %n)
  br label %floop
floop:
  %fi = phi i64 [ 0, %fill ], [ %fin, %fbody ]
  %fm = icmp slt i64 %fi, %n
  br i1 %fm, label %fbody, label %fdone
fbody:
  %x = call i64 @rg_word_at(i64 %src, i64 %fi)
  %xa = call i64 @rg_list_at(i64 %xs, i64 %x)
  %xv = call i64 @rg_ld(i64 %xa)
  %c = call i64 @__rg_rt_clone_slot(i64 %xv)
  %oa = call i64 @rg_list_at(i64 %out, i64 %fi)
  call void @rg_st(i64 %oa, i64 %c)
  %fin = add i64 %fi, 1
  br label %floop
fdone:
  call void @rg_free(i64 %a)
  call void @rg_free(i64 %b)
  ret i64 %out
}

; ── gt_conv ──────────────────────────────────────────────────

; A new List of clones of the items of a List (borrowed).
define i64 @rg_list_copy(i64 %xs) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  %n0 = call i64 @rg_list_len(i64 %xs)
  %n = select i1 %isl, i64 %n0, i64 0
  %out = call i64 @rg_list_alloc(i64 %n, i64 %n)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ea = call i64 @rg_list_at(i64 %xs, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  %c = call i64 @__rg_rt_clone_slot(i64 %e)
  %oa = call i64 @rg_list_at(i64 %out, i64 %i)
  call void @rg_st(i64 %oa, i64 %c)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %out
}

; [v, n] -> a List of n clones of v.
define i64 @rg_list_repeat(i64 %xs) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  %n0 = call i64 @rg_list_len(i64 %xs)
  %l = select i1 %isl, i64 %n0, i64 0
  %two = icmp sge i64 %l, 2
  br i1 %two, label %rd, label %empty
empty:
  %e = call i64 @rg_list_alloc(i64 0, i64 0)
  ret i64 %e
rd:
  %va = call i64 @rg_list_at(i64 %xs, i64 0)
  %v = call i64 @rg_ld(i64 %va)
  %na = call i64 @rg_list_at(i64 %xs, i64 1)
  %nv = call i64 @rg_ld(i64 %na)
  %ni = call i64 @rg_index_of(i64 %nv)
  %pos = icmp sgt i64 %ni, 0
  %n = select i1 %pos, i64 %ni, i64 0
  %out = call i64 @rg_list_alloc(i64 %n, i64 %n)
  br label %loop
loop:
  %i = phi i64 [ 0, %rd ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %c = call i64 @__rg_rt_clone_slot(i64 %v)
  %oa = call i64 @rg_list_at(i64 %out, i64 %i)
  call void @rg_st(i64 %oa, i64 %c)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %out
}

; A one-dimensional tensor of the numbers of a List.
define i64 @rg_list_tensor(i64 %xs) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  %n0 = call i64 @rg_list_len(i64 %xs)
  %n = select i1 %isl, i64 %n0, i64 0
  %dims = alloca i64, align 8
  store i64 %n, ptr %dims, align 8
  %dp = ptrtoint ptr %dims to i64
  %t = call i64 @rg_t_filled(i64 %dp, i64 1, i64 0)
  %d = call i64 @rg_t_data(i64 %t)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ea = call i64 @rg_list_at(i64 %xs, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  %w = call i64 @rg_raw_word(i64 %e)
  call void @rg_word_set(i64 %d, i64 %i, i64 %w)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %t
}

; A List of the data words of a tensor, as Ints (real = 0) or Reals.
define i64 @rg_tensor_list(i64 %t, i64 %real) {
entry:
  %ist = call i1 @rg_has_tag(i64 %t, i64 5)
  br i1 %ist, label %go, label %empty
empty:
  %e = call i64 @rg_list_alloc(i64 0, i64 0)
  ret i64 %e
go:
  %n = call i64 @rg_t_len(i64 %t)
  %d = call i64 @rg_t_data(i64 %t)
  %out = call i64 @rg_list_alloc(i64 %n, i64 %n)
  %isr = icmp ne i64 %real, 0
  br label %loop
loop:
  %i = phi i64 [ 0, %go ], [ %i1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %w = call i64 @rg_word_at(i64 %d, i64 %i)
  br i1 %isr, label %mkreal, label %mkint
mkreal:
  %rv = call i64 @rg_obj(i64 0, i64 %w, i64 0)
  br label %next
mkint:
  %iv = call i64 @rg_box_int(i64 %w)
  br label %next
next:
  %c = phi i64 [ %rv, %mkreal ], [ %iv, %mkint ]
  %oa = call i64 @rg_list_at(i64 %out, i64 %i)
  call void @rg_st(i64 %oa, i64 %c)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %out
}

; [v, d1, ..., dn] -> a tensor of those dimensions, every word that of v.
define i64 @rg_shape_tensor(i64 %xs) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  %n0 = call i64 @rg_list_len(i64 %xs)
  %l = select i1 %isl, i64 %n0, i64 0
  %ok = icmp sge i64 %l, 1
  br i1 %ok, label %go, label %empty
empty:
  %e = call i64 @rg_list_alloc(i64 0, i64 0)
  ret i64 %e
go:
  %va = call i64 @rg_list_at(i64 %xs, i64 0)
  %v = call i64 @rg_ld(i64 %va)
  %fill = call i64 @rg_raw_word(i64 %v)
  %rank = sub i64 %l, 1
  %dims = alloca [16 x i64], align 8
  %dp = ptrtoint ptr %dims to i64
  %big = icmp sgt i64 %rank, 16
  %r = select i1 %big, i64 16, i64 %rank
  br label %loop
loop:
  %i = phi i64 [ 0, %go ], [ %i1, %body ]
  %more = icmp slt i64 %i, %r
  br i1 %more, label %body, label %done
body:
  %j = add i64 %i, 1
  %da = call i64 @rg_list_at(i64 %xs, i64 %j)
  %dv = call i64 @rg_ld(i64 %da)
  %dn = call i64 @rg_index_of(i64 %dv)
  call void @rg_word_set(i64 %dp, i64 %i, i64 %dn)
  %i1 = add i64 %i, 1
  br label %loop
done:
  %t = call i64 @rg_t_filled(i64 %dp, i64 %r, i64 %fill)
  ret i64 %t
}

; gt_conv (value, mode, acc): the GenTensor conversions of the lowering
; (gentensor.md): 0 copy a List, 1 List -> tensor, 2 tensor -> Ints,
; 3 tensor -> Reals, 4 [v, dims] -> tensor, 5 [v, n] -> List of n v.
; The value is borrowed.
define i64 @__rg_rt_gt_conv(i64 %v, i64 %mode, i64 %acc) {
entry:
  switch i64 %mode, label %copy [ i64 1, label %tensor
                                  i64 2, label %ints
                                  i64 3, label %reals
                                  i64 4, label %shape
                                  i64 5, label %repeat ]
copy:
  %r0 = call i64 @rg_list_copy(i64 %v)
  ret i64 %r0
tensor:
  %r1 = call i64 @rg_list_tensor(i64 %v)
  ret i64 %r1
ints:
  %r2 = call i64 @rg_tensor_list(i64 %v, i64 0)
  ret i64 %r2
reals:
  %r3 = call i64 @rg_tensor_list(i64 %v, i64 1)
  ret i64 %r3
shape:
  %r4 = call i64 @rg_shape_tensor(i64 %v)
  ret i64 %r4
repeat:
  %r5 = call i64 @rg_list_repeat(i64 %v)
  ret i64 %r5
}

; real_from_bits (v): the Real with the bits of an Int (taken); any other
; value passes.
define i64 @__rg_rt_real_from_bits(i64 %v) {
entry:
  %low = and i64 %v, 1
  %t = icmp eq i64 %low, 1
  br i1 %t, label %tagged, label %z
tagged:
  %n = ashr i64 %v, 1
  br label %box
z:
  %zero = icmp eq i64 %v, 0
  br i1 %zero, label %box, label %h
h:
  %num = call i1 @rg_has_tag(i64 %v, i64 0)
  br i1 %num, label %w, label %pass
w:
  %word = call i64 @rg_ld(i64 %v)
  %isint = icmp eq i64 %word, -9223372036854775808
  br i1 %isint, label %boxed, label %pass
boxed:
  %p = call i64 @rg_w1(i64 %v)
  %x = call i64 @__rg_rt_drop_val(i64 %v)
  br label %box
box:
  %bits = phi i64 [ %n, %tagged ], [ 0, %z ], [ %p, %boxed ]
  %r = call i64 @rg_obj(i64 0, i64 %bits, i64 0)
  ret i64 %r
pass:
  ret i64 %v
}

; real_to_bits (v): the Int with the bits of a Real (taken); any other
; value passes.
define i64 @__rg_rt_real_to_bits(i64 %v) {
entry:
  %num = call i1 @rg_has_tag(i64 %v, i64 0)
  br i1 %num, label %w, label %pass
w:
  %word = call i64 @rg_ld(i64 %v)
  %isreal = icmp eq i64 %word, 0
  br i1 %isreal, label %conv, label %pass
conv:
  %p = call i64 @rg_w1(i64 %v)
  %x = call i64 @__rg_rt_drop_val(i64 %v)
  %r = call i64 @rg_box_int(i64 %p)
  ret i64 %r
pass:
  ret i64 %v
}

; ── Regions ──────────────────────────────────────────────────

; `with region q do` body (FR-COMP-002): enter notes how many bytes this
; thread has allocated; exit gives `Ok value` when the body allocated no more
; than q bytes (q = 0: no limit) and `QuotaExceeded` (the value dropped) when it
; did. The runtime has one heap, so nothing is released at exit; regions nest
; up to 16 deep per thread.
@rg_region_base = internal global [144 x i64] zeroinitializer
@rg_region_depth = internal global [72 x i64] zeroinitializer, align 64
@rg_nm_ok = private constant [2 x i8] c"Ok"
@rg_nm_quota = private constant [13 x i8] c"QuotaExceeded"
declare i64 @rg_slot()
declare i64 @__rg_rt_make_adt(i64, i64, i64, i64)
declare i64 @__rg_rt_load_adt0(i64, i64)
@rg_alloc_bytes = external global [72 x i64]

define i64 @__rg_rt_enter_region() {
entry:
  %s = call i64 @rg_slot()
  %sl = shl i64 %s, 3
  %dp = getelementptr inbounds [72 x i64], ptr @rg_region_depth, i64 0, i64 %sl
  %d = load i64, ptr %dp, align 8
  %room = icmp slt i64 %d, 16
  br i1 %room, label %push, label %done
push:
  %sl2 = shl i64 %s, 3
  %ab = getelementptr inbounds [72 x i64], ptr @rg_alloc_bytes, i64 0, i64 %sl2
  %av = load i64, ptr %ab, align 8
  %so = mul i64 %s, 16
  %i = add i64 %so, %d
  %bp = getelementptr inbounds [144 x i64], ptr @rg_region_base, i64 0, i64 %i
  store i64 %av, ptr %bp, align 8
  br label %done
done:
  %d1 = add i64 %d, 1
  store i64 %d1, ptr %dp, align 8
  ret i64 0
}

define i64 @__rg_rt_exit_region(i64 %quota, i64 %v) {
entry:
  %s = call i64 @rg_slot()
  %sl = shl i64 %s, 3
  %dp = getelementptr inbounds [72 x i64], ptr @rg_region_depth, i64 0, i64 %sl
  %d0 = load i64, ptr %dp, align 8
  %d = sub i64 %d0, 1
  store i64 %d, ptr %dp, align 8
  %sl2 = shl i64 %s, 3
  %ab = getelementptr inbounds [72 x i64], ptr @rg_alloc_bytes, i64 0, i64 %sl2
  %av = load i64, ptr %ab, align 8
  %so = mul i64 %s, 16
  %i = add i64 %so, %d
  %bp = getelementptr inbounds [144 x i64], ptr @rg_region_base, i64 0, i64 %i
  %base = load i64, ptr %bp, align 8
  %used = sub i64 %av, %base
  %limited = icmp sgt i64 %quota, 0
  %over = icmp sgt i64 %used, %quota
  %fail = and i1 %limited, %over
  br i1 %fail, label %exceeded, label %ok
exceeded:
  %dr = call i64 @__rg_rt_drop_val(i64 %v)
  %q = call i64 @__rg_rt_load_adt0(i64 ptrtoint (ptr @rg_nm_quota to i64), i64 13)
  ret i64 %q
ok:
  %vals = alloca [1 x i64], align 8
  store i64 %v, ptr %vals, align 8
  %va = ptrtoint ptr %vals to i64
  %r = call i64 @__rg_rt_make_adt(i64 ptrtoint (ptr @rg_nm_ok to i64), i64 2, i64 %va, i64 1)
  ret i64 %r
}

; ── Builtins ─────────────────────────────────────────────────

; 88 fill (value, d1 [, d2]): a tensor of those dimensions, every element
; the value.
define i64 @rg_fill_builtin(i64 %slots, i64 %n) {
entry:
  %v = call i64 @rg_ld(i64 %slots)
  %fill = call i64 @rg_raw_word(i64 %v)
  %k0 = sub i64 %n, 1
  %big = icmp sgt i64 %k0, 16
  %k = select i1 %big, i64 16, i64 %k0
  %dims = alloca [16 x i64], align 8
  %dp = ptrtoint ptr %dims to i64
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %k
  br i1 %more, label %body, label %done
body:
  %j = add i64 %i, 1
  %sa0 = shl i64 %j, 3
  %sa = add i64 %slots, %sa0
  %dv = call i64 @rg_ld(i64 %sa)
  %dn = call i64 @rg_index_of(i64 %dv)
  call void @rg_word_set(i64 %dp, i64 %i, i64 %dn)
  %i1 = add i64 %i, 1
  br label %loop
done:
  %t = call i64 @rg_t_filled(i64 %dp, i64 %k, i64 %fill)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %t
}

declare i64 @llvm.fshr.i64(i64, i64, i64)
declare i64 @llvm.fshl.i64(i64, i64, i64)

define i64 @rg_word_op(i64 %op, i64 %a, i64 %b) {
entry:
  switch i64 %op, label %xor [ i64 0, label %add
                               i64 1, label %sub
                               i64 2, label %mul
                               i64 11, label %and
                               i64 12, label %or
                               i64 3, label %div
                               i64 4, label %rem
                               i64 17, label %shl
                               i64 18, label %shr
                               i64 19, label %rotr
                               i64 20, label %rotl
                               i64 21, label %mulhi
                               i64 22, label %clmul
                               i64 23, label %clmulhi
                               i64 100, label %fadd
                               i64 101, label %fsub
                               i64 102, label %fmul
                               i64 103, label %fdiv ]
div:
  ; a divisor of 0 gives 0 (as `rg_hadamard_op`); -1 is done as a negation, which cannot trap
  %dz = icmp eq i64 %b, 0
  %dm = icmp eq i64 %b, -1
  %dsafe0 = select i1 %dz, i64 1, i64 %b
  %dsafe = select i1 %dm, i64 1, i64 %dsafe0
  %dq = sdiv i64 %a, %dsafe
  %dneg = sub i64 0, %a
  %dq1 = select i1 %dm, i64 %dneg, i64 %dq
  %dr = select i1 %dz, i64 0, i64 %dq1
  ret i64 %dr
rem:
  %rz = icmp eq i64 %b, 0
  %rm1 = icmp eq i64 %b, -1
  %rsafe0 = select i1 %rz, i64 1, i64 %b
  %rsafe = select i1 %rm1, i64 1, i64 %rsafe0
  %rq = srem i64 %a, %rsafe
  %rbad = or i1 %rz, %rm1
  %rres = select i1 %rbad, i64 0, i64 %rq
  ret i64 %rres
mulhi:
  %hr = call i64 @rg_mulhi(i64 %a, i64 %b)
  ret i64 %hr
clmul:
  %cl = call i64 @rg_clmul_soft(i64 %a, i64 %b, i64 0)
  ret i64 %cl
clmulhi:
  %ch = call i64 @rg_clmul_soft(i64 %a, i64 %b, i64 1)
  ret i64 %ch
rotr:
  %tr = call i64 @llvm.fshr.i64(i64 %a, i64 %a, i64 %b)
  ret i64 %tr
rotl:
  %tl = call i64 @llvm.fshl.i64(i64 %a, i64 %a, i64 %b)
  ret i64 %tl
fadd:
  %fa0 = bitcast i64 %a to double
  %fb0 = bitcast i64 %b to double
  %fr0 = fadd double %fa0, %fb0
  %fw0 = bitcast double %fr0 to i64
  ret i64 %fw0
fsub:
  %fa1 = bitcast i64 %a to double
  %fb1 = bitcast i64 %b to double
  %fr1 = fsub double %fa1, %fb1
  %fw1 = bitcast double %fr1 to i64
  ret i64 %fw1
fmul:
  %fa2 = bitcast i64 %a to double
  %fb2 = bitcast i64 %b to double
  %fr2 = fmul double %fa2, %fb2
  %fw2 = bitcast double %fr2 to i64
  ret i64 %fw2
fdiv:
  %fa3 = bitcast i64 %a to double
  %fb3 = bitcast i64 %b to double
  %fr3 = fdiv double %fa3, %fb3
  %fw3 = bitcast double %fr3 to i64
  ret i64 %fw3
shl:
  %c1 = and i64 %b, 63
  %rl = shl i64 %a, %c1
  ret i64 %rl
shr:
  %c2 = and i64 %b, 63
  %rr = lshr i64 %a, %c2
  ret i64 %rr
add:
  %r0 = add i64 %a, %b
  ret i64 %r0
sub:
  %r1 = sub i64 %a, %b
  ret i64 %r1
mul:
  %r2 = mul i64 %a, %b
  ret i64 %r2
and:
  %r3 = and i64 %a, %b
  ret i64 %r3
or:
  %r4 = or i64 %a, %b
  ret i64 %r4
xor:
  %r5 = xor i64 %a, %b
  ret i64 %r5
}

; 90 element-wise (a, b, op): a new tensor of a's shape with op on each
; pair of words (b a tensor, or a number used for every element); ops
; 0 +, 1 -, 2 *, 3 / and 4 % (a divisor of 0 gives 0), 11 and, 12 or, 17 shl, 18 shr (logical, the
; count modulo 64), 19 rotr, 20 rotl, 100 to 103 the words as Reals (+ - * /), else xor. `a or a` is a copy of a.
define i64 @rg_elementwise(i64 %slots, i64 %n) {
entry:
  %a = call i64 @rg_ld(i64 %slots)
  %s1 = add i64 %slots, 8
  %b = call i64 @rg_ld(i64 %s1)
  %s2 = add i64 %slots, 16
  %ov = call i64 @rg_ld(i64 %s2)
  %op = call i64 @rg_index_of(i64 %ov)
  %ist = call i1 @rg_has_tag(i64 %a, i64 5)
  br i1 %ist, label %go, label %pass
pass:
  %c = call i64 @__rg_rt_clone_slot(i64 %a)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %c
go:
  %rank = call i64 @rg_t_rank(i64 %a)
  %dims = call i64 @rg_t_dims(i64 %a)
  %len = call i64 @rg_t_len(i64 %a)
  %t = call i64 @rg_t_new(i64 %rank, i64 %len)
  %td = call i64 @rg_t_dims(i64 %t)
  %db = shl i64 %rank, 3
  call void @rg_copy(i64 %td, i64 %dims, i64 %db)
  %ad = call i64 @rg_t_data(i64 %a)
  %out = call i64 @rg_t_data(i64 %t)
  %bt = call i1 @rg_has_tag(i64 %b, i64 5)
  %bw = call i64 @rg_raw_word(i64 %b)
  br i1 %bt, label %bten, label %loop
bten:
  %bd0 = call i64 @rg_t_data(i64 %b)
  %bn0 = call i64 @rg_t_len(i64 %b)
  br label %loop
loop:
  %bd = phi i64 [ 0, %go ], [ %bd0, %bten ]
  %bn = phi i64 [ 0, %go ], [ %bn0, %bten ]
  br label %el
el:
  %i = phi i64 [ 0, %loop ], [ %i1, %put ]
  %more = icmp slt i64 %i, %len
  br i1 %more, label %body, label %done
body:
  %x = call i64 @rg_word_at(i64 %ad, i64 %i)
  %inb = icmp slt i64 %i, %bn
  br i1 %inb, label %fromb, label %scal
fromb:
  %y0 = call i64 @rg_word_at(i64 %bd, i64 %i)
  br label %put
scal:
  %y1 = select i1 %bt, i64 0, i64 %bw
  br label %put
put:
  %y = phi i64 [ %y0, %fromb ], [ %y1, %scal ]
  %r = call i64 @rg_word_op(i64 %op, i64 %x, i64 %y)
  call void @rg_word_set(i64 %out, i64 %i, i64 %r)
  %i1 = add i64 %i, 1
  br label %el
done:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %t
}

; 92 row (m, r): m_(r,). 93 (m, r, v): m_(r,) = v, gives m.
define i64 @rg_row_get(i64 %slots, i64 %n) {
  %s1 = add i64 %slots, 8
  %r = call i64 @__rg_rt_index(i64 %slots, i64 %s1, i64 1)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r
}

define i64 @rg_row_set(i64 %slots, i64 %n) {
  %s1 = add i64 %slots, 8
  %s2 = add i64 %slots, 16
  %v = call i64 @rg_ld(i64 %s2)
  call void @rg_st(i64 %s2, i64 0)
  %r = call i64 @__rg_rt_index_set(i64 %slots, i64 %s1, i64 1, i64 %v)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r
}

; The number of rows and columns of a matrix (tensor or List of rows) and
; a column index checked against them; stops when out of range.
define i64 @rg_col_index(i64 %m, i64 %cv, ptr %rows, ptr %cols) {
entry:
  %c = call i64 @rg_index_of(i64 %cv)
  %ist = call i1 @rg_has_tag(i64 %m, i64 5)
  br i1 %ist, label %tensor, label %lists
tensor:
  %rank = call i64 @rg_t_rank(i64 %m)
  %two = icmp eq i64 %rank, 2
  br i1 %two, label %tdims, label %bad
tdims:
  %dims = call i64 @rg_t_dims(i64 %m)
  %r0 = call i64 @rg_word_at(i64 %dims, i64 0)
  %c0 = call i64 @rg_word_at(i64 %dims, i64 1)
  br label %chk
lists:
  %isl = call i1 @rg_has_tag(i64 %m, i64 2)
  br i1 %isl, label %ldims, label %bad
ldims:
  %r1 = call i64 @rg_list_len(i64 %m)
  %has = icmp sgt i64 %r1, 0
  br i1 %has, label %first, label %chk
first:
  %ra = call i64 @rg_list_at(i64 %m, i64 0)
  %row = call i64 @rg_ld(i64 %ra)
  %rl = call i1 @rg_has_tag(i64 %row, i64 2)
  br i1 %rl, label %rlen, label %bad
rlen:
  %c1 = call i64 @rg_list_len(i64 %row)
  br label %chk
chk:
  %nr = phi i64 [ %r0, %tdims ], [ %r1, %ldims ], [ %r1, %rlen ]
  %nc = phi i64 [ %c0, %tdims ], [ 0, %ldims ], [ %c1, %rlen ]
  store i64 %nr, ptr %rows, align 8
  store i64 %nc, ptr %cols, align 8
  %ok = icmp ult i64 %c, %nc
  br i1 %ok, label %good, label %bad
good:
  ret i64 %c
bad:
  call void @rg_oob()
  unreachable
}

; 94 column (m, c): m_(,c), a one-dimensional tensor (or a List of the
; column's items for a List of rows).
define i64 @rg_col_get(i64 %slots, i64 %n) {
entry:
  %rp = alloca i64, align 8
  %cp = alloca i64, align 8
  %m = call i64 @rg_ld(i64 %slots)
  %s1 = add i64 %slots, 8
  %cv = call i64 @rg_ld(i64 %s1)
  %c = call i64 @rg_col_index(i64 %m, i64 %cv, ptr %rp, ptr %cp)
  %rows = load i64, ptr %rp, align 8
  %cols = load i64, ptr %cp, align 8
  %ist = call i1 @rg_has_tag(i64 %m, i64 5)
  br i1 %ist, label %tensor, label %lists
tensor:
  %dims = alloca i64, align 8
  store i64 %rows, ptr %dims, align 8
  %dp = ptrtoint ptr %dims to i64
  %t = call i64 @rg_t_filled(i64 %dp, i64 1, i64 0)
  %td = call i64 @rg_t_data(i64 %t)
  %md = call i64 @rg_t_data(i64 %m)
  br label %tloop
tloop:
  %i = phi i64 [ 0, %tensor ], [ %i1, %tbody ]
  %tm = icmp slt i64 %i, %rows
  br i1 %tm, label %tbody, label %done
tbody:
  %ro = mul i64 %i, %cols
  %fo = add i64 %ro, %c
  %w = call i64 @rg_word_at(i64 %md, i64 %fo)
  call void @rg_word_set(i64 %td, i64 %i, i64 %w)
  %i1 = add i64 %i, 1
  br label %tloop
lists:
  %out = call i64 @rg_list_alloc(i64 %rows, i64 %rows)
  br label %lloop
lloop:
  %j = phi i64 [ 0, %lists ], [ %j1, %lbody ]
  %lm = icmp slt i64 %j, %rows
  br i1 %lm, label %lbody, label %done
lbody:
  %ra = call i64 @rg_list_at(i64 %m, i64 %j)
  %row = call i64 @rg_ld(i64 %ra)
  %ea = call i64 @rg_list_at(i64 %row, i64 %c)
  %e = call i64 @rg_ld(i64 %ea)
  %ce = call i64 @__rg_rt_clone_slot(i64 %e)
  %oa = call i64 @rg_list_at(i64 %out, i64 %j)
  call void @rg_st(i64 %oa, i64 %ce)
  %j1 = add i64 %j, 1
  br label %lloop
done:
  %res = phi i64 [ %t, %tloop ], [ %out, %lloop ]
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %res
}

; 95 (m, c, v): m_(,c) = v in place, gives m.
define i64 @rg_col_set(i64 %slots, i64 %n) {
entry:
  %rp = alloca i64, align 8
  %cp = alloca i64, align 8
  %m = call i64 @rg_ld(i64 %slots)
  %s1 = add i64 %slots, 8
  %cv = call i64 @rg_ld(i64 %s1)
  %s2 = add i64 %slots, 16
  %v = call i64 @rg_ld(i64 %s2)
  %c = call i64 @rg_col_index(i64 %m, i64 %cv, ptr %rp, ptr %cp)
  %rows = load i64, ptr %rp, align 8
  %cols = load i64, ptr %cp, align 8
  %ist = call i1 @rg_has_tag(i64 %m, i64 5)
  br i1 %ist, label %tensor, label %lists
tensor:
  %vt = call i1 @rg_has_tag(i64 %v, i64 5)
  br i1 %vt, label %tgo, label %done
tgo:
  %vn = call i64 @rg_t_len(i64 %v)
  %vd = call i64 @rg_t_data(i64 %v)
  %md = call i64 @rg_t_data(i64 %m)
  %fits = icmp slt i64 %vn, %rows
  %k = select i1 %fits, i64 %vn, i64 %rows
  br label %tloop
tloop:
  %i = phi i64 [ 0, %tgo ], [ %i1, %tbody ]
  %tm = icmp slt i64 %i, %k
  br i1 %tm, label %tbody, label %done
tbody:
  %w = call i64 @rg_word_at(i64 %vd, i64 %i)
  %ro = mul i64 %i, %cols
  %fo = add i64 %ro, %c
  call void @rg_word_set(i64 %md, i64 %fo, i64 %w)
  %i1 = add i64 %i, 1
  br label %tloop
lists:
  %vl = call i1 @rg_has_tag(i64 %v, i64 2)
  %vn2 = call i64 @rg_list_len(i64 %v)
  %vn3 = select i1 %vl, i64 %vn2, i64 0
  %fits2 = icmp slt i64 %vn3, %rows
  %k2 = select i1 %fits2, i64 %vn3, i64 %rows
  br label %lloop
lloop:
  %j = phi i64 [ 0, %lists ], [ %j1, %lbody ]
  %lm = icmp slt i64 %j, %k2
  br i1 %lm, label %lbody, label %done
lbody:
  %va = call i64 @rg_list_at(i64 %v, i64 %j)
  %e = call i64 @rg_ld(i64 %va)
  %ce = call i64 @__rg_rt_clone_slot(i64 %e)
  %ra = call i64 @rg_list_at(i64 %m, i64 %j)
  %row = call i64 @rg_ld(i64 %ra)
  %ea = call i64 @rg_list_at(i64 %row, i64 %c)
  %old = call i64 @rg_ld(i64 %ea)
  call void @rg_st(i64 %ea, i64 %ce)
  %x = call i64 @__rg_rt_drop_val(i64 %old)
  %j1 = add i64 %j, 1
  br label %lloop
done:
  call void @rg_st(i64 %slots, i64 0)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %m
}

define i64 @rg_builtin_more(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %other [ i64 88, label %fill
                                 i64 90, label %elem
                                 i64 92, label %rowg
                                 i64 93, label %rows
                                 i64 94, label %colg
                                 i64 95, label %cols ]
fill:
  %r0 = call i64 @rg_fill_builtin(i64 %slots, i64 %n)
  ret i64 %r0
elem:
  %r1 = call i64 @rg_elementwise(i64 %slots, i64 %n)
  ret i64 %r1
rowg:
  %r2 = call i64 @rg_row_get(i64 %slots, i64 %n)
  ret i64 %r2
rows:
  %r3 = call i64 @rg_row_set(i64 %slots, i64 %n)
  ret i64 %r3
colg:
  %r4 = call i64 @rg_col_get(i64 %slots, i64 %n)
  ret i64 %r4
cols:
  %r5 = call i64 @rg_col_set(i64 %slots, i64 %n)
  ret i64 %r5
other:
  %r = call i64 @rg_builtin_bytes(i64 %id, i64 %slots, i64 %n)
  ret i64 %r
}

; ── Sequence masks ───────────────────────────────────────────

; Item i of a tuple or List (borrowed), or 0 when there is none.
define i64 @rg_seq_item(i64 %v, i64 %i) {
entry:
  %ist = call i1 @rg_has_tag(i64 %v, i64 3)
  br i1 %ist, label %tuple, label %list
tuple:
  %h = call i64 @rg_w1(i64 %v)
  %n = call i64 @rg_vlen(i64 %h)
  %ok = icmp ult i64 %i, %n
  br i1 %ok, label %tget, label %none
tget:
  %d = call i64 @rg_vdata(i64 %h)
  %e = call i64 @rg_word_at(i64 %d, i64 %i)
  ret i64 %e
list:
  %isl = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %isl, label %lchk, label %none
lchk:
  %ln = call i64 @rg_list_len(i64 %v)
  %lok = icmp ult i64 %i, %ln
  br i1 %lok, label %lget, label %none
lget:
  %ea = call i64 @rg_list_at(i64 %v, i64 %i)
  %le = call i64 @rg_ld(i64 %ea)
  ret i64 %le
none:
  ret i64 0
}

define i64 @rg_seq_count(i64 %v) {
entry:
  %ist = call i1 @rg_has_tag(i64 %v, i64 3)
  br i1 %ist, label %tuple, label %list
tuple:
  %h = call i64 @rg_w1(i64 %v)
  %n = call i64 @rg_vlen(i64 %h)
  ret i64 %n
list:
  %isl = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %isl, label %l, label %none
l:
  %ln = call i64 @rg_list_len(i64 %v)
  ret i64 %ln
none:
  ret i64 0
}

; seq_select (seq, mask, length): `s(+ _ +)` keeps the items at the `+`
; positions and skips those at `_`; ` +` (an ellipsis) keeps every item
; left; `s(0 3)` keeps the items at those positions. One item is given as
; itself, several as a tuple. The seq is taken.
define i64 @__rg_rt_seq_select(i64 %v, i64 %m, i64 %len) {
entry:
  %picked = alloca [64 x i64], align 8
  %pp = ptrtoint ptr %picked to i64
  %cnt = call i64 @rg_seq_count(i64 %v)
  %has = icmp sgt i64 %len, 0
  br i1 %has, label %kind, label %pack
kind:
  %c0 = call i64 @rg_ldb(i64 %m)
  %d0 = sub i64 %c0, 48
  %isdig = icmp ult i64 %d0, 10
  br i1 %isdig, label %nums, label %marks
marks:
  br label %mloop
mloop:
  %i = phi i64 [ 0, %marks ], [ %i1, %mnext ]
  %pos = phi i64 [ 0, %marks ], [ %pos1, %mnext ]
  %k = phi i64 [ 0, %marks ], [ %k1, %mnext ]
  %more = icmp slt i64 %i, %len
  br i1 %more, label %mchar, label %pack
mchar:
  %ca = add i64 %m, %i
  %c = call i64 @rg_ldb(i64 %ca)
  %isplus = icmp eq i64 %c, 43
  %isskip = icmp eq i64 %c, 95
  %issp = icmp eq i64 %c, 32
  br i1 %issp, label %rest, label %mone
mone:
  %room = icmp slt i64 %k, 64
  %keep = and i1 %isplus, %room
  br i1 %keep, label %mkeep, label %mstep
mkeep:
  call void @rg_word_set(i64 %pp, i64 %k, i64 %pos)
  br label %mstep
mstep:
  %add = select i1 %keep, i64 1, i64 0
  %k1a = add i64 %k, %add
  %adv = or i1 %isplus, %isskip
  %step = select i1 %adv, i64 1, i64 0
  %pos1a = add i64 %pos, %step
  br label %mnext
rest:
  br label %rloop
rloop:
  %rp = phi i64 [ %pos, %rest ], [ %rp1, %rbody ]
  %rk = phi i64 [ %k, %rest ], [ %rk1, %rbody ]
  %rmore = icmp slt i64 %rp, %cnt
  %rroom = icmp slt i64 %rk, 64
  %rgo = and i1 %rmore, %rroom
  br i1 %rgo, label %rbody, label %rdone
rbody:
  call void @rg_word_set(i64 %pp, i64 %rk, i64 %rp)
  %rp1 = add i64 %rp, 1
  %rk1 = add i64 %rk, 1
  br label %rloop
rdone:
  %skip2 = add i64 %i, 1
  br label %mnext
mnext:
  %i1n = phi i64 [ %i, %mstep ], [ %skip2, %rdone ]
  %pos1 = phi i64 [ %pos1a, %mstep ], [ %rp, %rdone ]
  %k1 = phi i64 [ %k1a, %mstep ], [ %rk, %rdone ]
  %i1 = add i64 %i1n, 1
  br label %mloop
nums:
  br label %nloop
nloop:
  %j = phi i64 [ 0, %nums ], [ %j1, %nnext ]
  %acc = phi i64 [ -1, %nums ], [ %acc1, %nnext ]
  %nk = phi i64 [ 0, %nums ], [ %nk1, %nnext ]
  %nmore = icmp slt i64 %j, %len
  br i1 %nmore, label %nchar, label %nend
nchar:
  %na = add i64 %m, %j
  %nc = call i64 @rg_ldb(i64 %na)
  %nd = sub i64 %nc, 48
  %dig = icmp ult i64 %nd, 10
  br i1 %dig, label %ndig, label %nsep
ndig:
  %neg = icmp slt i64 %acc, 0
  %base = select i1 %neg, i64 0, i64 %acc
  %t10 = mul i64 %base, 10
  %accd = add i64 %t10, %nd
  br label %nnext
nsep:
  %got = icmp sge i64 %acc, 0
  %nroom = icmp slt i64 %nk, 64
  %put = and i1 %got, %nroom
  br i1 %put, label %nput, label %nnext
nput:
  call void @rg_word_set(i64 %pp, i64 %nk, i64 %acc)
  %nkp = add i64 %nk, 1
  br label %nnext
nnext:
  %acc1 = phi i64 [ %accd, %ndig ], [ -1, %nsep ], [ -1, %nput ]
  %nk1 = phi i64 [ %nk, %ndig ], [ %nk, %nsep ], [ %nkp, %nput ]
  %j1 = add i64 %j, 1
  br label %nloop
nend:
  %last = icmp sge i64 %acc, 0
  %lroom = icmp slt i64 %nk, 64
  %lput = and i1 %last, %lroom
  br i1 %lput, label %nlast, label %pack
nlast:
  call void @rg_word_set(i64 %pp, i64 %nk, i64 %acc)
  %nkl = add i64 %nk, 1
  br label %pack
pack:
  %np = phi i64 [ 0, %entry ], [ %k, %mloop ], [ %nk, %nend ], [ %nkl, %nlast ]
  %one = icmp eq i64 %np, 1
  br i1 %one, label %single, label %tuple
single:
  %p0 = call i64 @rg_word_at(i64 %pp, i64 0)
  %e0 = call i64 @rg_seq_item(i64 %v, i64 %p0)
  %c1 = call i64 @__rg_rt_clone_slot(i64 %e0)
  %x1 = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 %c1
tuple:
  %vals = alloca [64 x i64], align 8
  %vp = ptrtoint ptr %vals to i64
  br label %tloop
tloop:
  %ti = phi i64 [ 0, %tuple ], [ %ti1, %tbody ]
  %tm = icmp slt i64 %ti, %np
  br i1 %tm, label %tbody, label %tdone
tbody:
  %pi = call i64 @rg_word_at(i64 %pp, i64 %ti)
  %ei = call i64 @rg_seq_item(i64 %v, i64 %pi)
  %ci = call i64 @__rg_rt_clone_slot(i64 %ei)
  call void @rg_word_set(i64 %vp, i64 %ti, i64 %ci)
  %ti1 = add i64 %ti, 1
  br label %tloop
tdone:
  %r = call i64 @__rg_rt_make_tuple(i64 %vp, i64 %np)
  %x2 = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 %r
}

; ── Einstein summation and Hadamard operations ───────────────

; The flat offset into a tensor of subscripts sub[0 .. n-1] (letters), each
; letter's value in val[letter] and its dimension in dim[letter].
define i64 @rg_sub_offset(i64 %sub, i64 %n, i64 %dim, i64 %val) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %off = phi i64 [ 0, %entry ], [ %off1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ca = add i64 %sub, %i
  %c = call i64 @rg_ldb(i64 %ca)
  %d = call i64 @rg_word_at(i64 %dim, i64 %c)
  %x = call i64 @rg_word_at(i64 %val, i64 %c)
  %m = mul i64 %off, %d
  %off1 = add i64 %m, %x
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %off
}

; Record the dimensions of tensor t under the letters sub[0 .. n-1].
define void @rg_sub_dims(i64 %t, i64 %sub, i64 %n, i64 %dim) {
entry:
  %rank = call i64 @rg_t_rank(i64 %t)
  %dims = call i64 @rg_t_dims(i64 %t)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  %inr = icmp slt i64 %i, %rank
  %go = and i1 %more, %inr
  br i1 %go, label %body, label %done
body:
  %ca = add i64 %sub, %i
  %c = call i64 @rg_ldb(i64 %ca)
  %d = call i64 @rg_word_at(i64 %dims, i64 %i)
  call void @rg_word_set(i64 %dim, i64 %c, i64 %d)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

; Step the letters ord[0 .. n-1] (the last fastest) through their
; dimensions; 0 when every combination was seen.
define i1 @rg_odometer(i64 %ord, i64 %n, i64 %dim, i64 %val) {
entry:
  %last = sub i64 %n, 1
  br label %loop
loop:
  %i = phi i64 [ %last, %entry ], [ %i1, %wrap ]
  %ok = icmp sge i64 %i, 0
  br i1 %ok, label %body, label %end
body:
  %c = call i64 @rg_word_at(i64 %ord, i64 %i)
  %x = call i64 @rg_word_at(i64 %val, i64 %c)
  %x1 = add i64 %x, 1
  %d = call i64 @rg_word_at(i64 %dim, i64 %c)
  %lt = icmp slt i64 %x1, %d
  br i1 %lt, label %set, label %wrap
set:
  call void @rg_word_set(i64 %val, i64 %c, i64 %x1)
  ret i1 true
wrap:
  call void @rg_word_set(i64 %val, i64 %c, i64 0)
  %i1 = sub i64 %i, 1
  br label %loop
end:
  ret i1 false
}

; einsum (slots, n, spec, length): `A_ab @ B_bc ...` on Int tensors (taken);
; spec is "ab,bc,...". A letter in more than one operand is summed; the
; others make the result, in order of first appearance; with none left the
; result has shape [1].
define i64 @__rg_rt_einsum(i64 %slots, i64 %n, i64 %spec, i64 %len) {
entry:
  %dimt = alloca [256 x i64], align 8
  %valt = alloca [256 x i64], align 8
  %seen = alloca [256 x i64], align 8
  %ords = alloca [64 x i64], align 8
  %outs = alloca [64 x i64], align 8
  %starts = alloca [17 x i64], align 8
  %odims = alloca [64 x i64], align 8
  %dim = ptrtoint ptr %dimt to i64
  %val = ptrtoint ptr %valt to i64
  %sn = ptrtoint ptr %seen to i64
  %ord = ptrtoint ptr %ords to i64
  %out = ptrtoint ptr %outs to i64
  %st = ptrtoint ptr %starts to i64
  %od = ptrtoint ptr %odims to i64
  call void @rg_fill(i64 %dim, i8 0, i64 2048)
  call void @rg_fill(i64 %val, i8 0, i64 2048)
  call void @rg_fill(i64 %sn, i8 0, i64 2048)
  call void @rg_word_set(i64 %st, i64 0, i64 0)
  br label %scan
scan:
  ; operand o starts at starts[o]; seen[c] = number of operands with c,
  ; counted once per operand through valt[c] = o + 1 while scanning
  %i = phi i64 [ 0, %entry ], [ %i1, %snext ]
  %o = phi i64 [ 0, %entry ], [ %o1, %snext ]
  %nl = phi i64 [ 0, %entry ], [ %nl1, %snext ]
  %more = icmp slt i64 %i, %len
  br i1 %more, label %schar, label %scanned
schar:
  %ca = add i64 %spec, %i
  %c = call i64 @rg_ldb(i64 %ca)
  %comma = icmp eq i64 %c, 44
  br i1 %comma, label %sop, label %slet
sop:
  %o1a = add i64 %o, 1
  %ip1 = add i64 %i, 1
  %oin = icmp slt i64 %o1a, 17
  br i1 %oin, label %sopset, label %snext
sopset:
  call void @rg_word_set(i64 %st, i64 %o1a, i64 %ip1)
  br label %snext
slet:
  %mark = call i64 @rg_word_at(i64 %val, i64 %c)
  %op1 = add i64 %o, 1
  %newop = icmp ne i64 %mark, %op1
  br i1 %newop, label %scount, label %snext
scount:
  call void @rg_word_set(i64 %val, i64 %c, i64 %op1)
  %cnt = call i64 @rg_word_at(i64 %sn, i64 %c)
  %cnt1 = add i64 %cnt, 1
  call void @rg_word_set(i64 %sn, i64 %c, i64 %cnt1)
  %first = icmp eq i64 %cnt, 0
  %room = icmp slt i64 %nl, 64
  %addl = and i1 %first, %room
  br i1 %addl, label %sadd, label %snext
sadd:
  call void @rg_word_set(i64 %ord, i64 %nl, i64 %c)
  %nladd = add i64 %nl, 1
  br label %snext
snext:
  %o1 = phi i64 [ %o1a, %sop ], [ %o1a, %sopset ], [ %o, %slet ], [ %o, %scount ], [ %o, %sadd ]
  %nl1 = phi i64 [ %nl, %sop ], [ %nl, %sopset ], [ %nl, %slet ], [ %nl, %scount ], [ %nladd, %sadd ]
  %i1 = add i64 %i, 1
  br label %scan
scanned:
  %nops0 = add i64 %o, 1
  %fewer = icmp slt i64 %nops0, %n
  %nops1 = select i1 %fewer, i64 %nops0, i64 %n
  %over = icmp sgt i64 %nops1, 16
  %nops = select i1 %over, i64 16, i64 %nops1
  %endi = add i64 %len, 1
  %nopsx = add i64 %o, 1
  %endok = icmp slt i64 %nopsx, 17
  br i1 %endok, label %setend, label %dims
setend:
  call void @rg_word_set(i64 %st, i64 %nopsx, i64 %endi)
  br label %dims
dims:
  br label %dloop
dloop:
  %k = phi i64 [ 0, %dims ], [ %k1, %dbody ], [ %k1, %drec ]
  %km = icmp slt i64 %k, %nops
  br i1 %km, label %dbody, label %outsel
dbody:
  %ko = shl i64 %k, 3
  %ta = add i64 %slots, %ko
  %t = call i64 @rg_ld(i64 %ta)
  %s0 = call i64 @rg_word_at(i64 %st, i64 %k)
  %k1 = add i64 %k, 1
  %s1 = call i64 @rg_word_at(i64 %st, i64 %k1)
  %sl = sub i64 %s1, %s0
  %sl1 = sub i64 %sl, 1
  %sa = add i64 %spec, %s0
  %ist = call i1 @rg_has_tag(i64 %t, i64 5)
  br i1 %ist, label %drec, label %dloop
drec:
  call void @rg_sub_dims(i64 %t, i64 %sa, i64 %sl1, i64 %dim)
  br label %dloop
outsel:
  br label %oloop
oloop:
  %q = phi i64 [ 0, %outsel ], [ %q1, %onext ]
  %nout = phi i64 [ 0, %outsel ], [ %nout1, %onext ]
  %qm = icmp slt i64 %q, %nl
  br i1 %qm, label %obody, label %build
obody:
  %lc = call i64 @rg_word_at(i64 %ord, i64 %q)
  %lcnt = call i64 @rg_word_at(i64 %sn, i64 %lc)
  %solo = icmp eq i64 %lcnt, 1
  br i1 %solo, label %oadd, label %onext
oadd:
  call void @rg_word_set(i64 %out, i64 %nout, i64 %lc)
  %ld = call i64 @rg_word_at(i64 %dim, i64 %lc)
  call void @rg_word_set(i64 %od, i64 %nout, i64 %ld)
  %noutp = add i64 %nout, 1
  br label %onext
onext:
  %nout1 = phi i64 [ %nout, %obody ], [ %noutp, %oadd ]
  %q1 = add i64 %q, 1
  br label %oloop
build:
  call void @rg_fill(i64 %val, i8 0, i64 2048)
  %none = icmp eq i64 %nout, 0
  br i1 %none, label %scalar, label %shaped
scalar:
  call void @rg_word_set(i64 %od, i64 0, i64 1)
  br label %shaped
shaped:
  %rank = phi i64 [ %nout, %build ], [ 1, %scalar ]
  %res = call i64 @rg_t_filled(i64 %od, i64 %rank, i64 0)
  %rd = call i64 @rg_t_data(i64 %res)
  %tot = call i64 @rg_product(i64 %dim, i64 0)
  ; every letter needs a dimension above 0 for any term to exist
  br label %zchk
zchk:
  %z = phi i64 [ 0, %shaped ], [ %z1, %zok ]
  %zm = icmp slt i64 %z, %nl
  br i1 %zm, label %zbody, label %terms
zbody:
  %zc = call i64 @rg_word_at(i64 %ord, i64 %z)
  %zd = call i64 @rg_word_at(i64 %dim, i64 %zc)
  %zpos = icmp sgt i64 %zd, 0
  %z1 = add i64 %z, 1
  br i1 %zpos, label %zok, label %done
zok:
  br label %zchk
terms:
  br label %term
term:
  br label %ploop
ploop:
  %pk = phi i64 [ 0, %term ], [ %pk1, %pbody ]
  %prod = phi i64 [ 1, %term ], [ %prod1, %pbody ]
  %pm = icmp slt i64 %pk, %nops
  br i1 %pm, label %pbody, label %padd
pbody:
  %pko = shl i64 %pk, 3
  %pta = add i64 %slots, %pko
  %pt = call i64 @rg_ld(i64 %pta)
  %ps0 = call i64 @rg_word_at(i64 %st, i64 %pk)
  %pk1 = add i64 %pk, 1
  %ps1 = call i64 @rg_word_at(i64 %st, i64 %pk1)
  %psl = sub i64 %ps1, %ps0
  %psl1 = sub i64 %psl, 1
  %psa = add i64 %spec, %ps0
  %poff = call i64 @rg_sub_offset(i64 %psa, i64 %psl1, i64 %dim, i64 %val)
  %pd = call i64 @rg_t_data(i64 %pt)
  %pw = call i64 @rg_word_at(i64 %pd, i64 %poff)
  %prod1 = mul i64 %prod, %pw
  br label %ploop
padd:
  %ooff = call i64 @rg_out_offset(i64 %out, i64 %nout, i64 %dim, i64 %val)
  %cur = call i64 @rg_word_at(i64 %rd, i64 %ooff)
  %sum = add i64 %cur, %prod
  call void @rg_word_set(i64 %rd, i64 %ooff, i64 %sum)
  %again = call i1 @rg_odometer(i64 %ord, i64 %nl, i64 %dim, i64 %val)
  br i1 %again, label %term, label %done
done:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %res
}

; The flat offset of the letters out[0 .. n-1] (words, not bytes).
define i64 @rg_out_offset(i64 %out, i64 %n, i64 %dim, i64 %val) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %off = phi i64 [ 0, %entry ], [ %off1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %c = call i64 @rg_word_at(i64 %out, i64 %i)
  %d = call i64 @rg_word_at(i64 %dim, i64 %c)
  %x = call i64 @rg_word_at(i64 %val, i64 %c)
  %m = mul i64 %off, %d
  %off1 = add i64 %m, %x
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %off
}

define i64 @rg_hadamard_op(i64 %op, i64 %a, i64 %b) {
entry:
  switch i64 %op, label %other [ i64 3, label %div
                                 i64 4, label %rem ]
div:
  %z = icmp eq i64 %b, 0
  br i1 %z, label %zero, label %dq
dq:
  %q = sdiv i64 %a, %b
  ret i64 %q
rem:
  %z2 = icmp eq i64 %b, 0
  br i1 %z2, label %zero, label %dr
dr:
  %r = srem i64 %a, %b
  ret i64 %r
zero:
  ret i64 0
other:
  %w = call i64 @rg_word_op(i64 %op, i64 %a, i64 %b)
  ret i64 %w
}

; hadamard (op, left slot, right, subscripts, length): `A_ij * B_j` on Int
; tensors (both taken); subscripts "ij,j". The result has the left letters,
; then the right letters the left one lacks; matching letters align, the
; others broadcast.
define i64 @__rg_rt_hadamard(i64 %op, i64 %lslot, i64 %b, i64 %subs, i64 %len) {
pre:
  ; op 1000 and up: a fused element-wise program (fuse.ll); its leaves start
  ; at the slot, and op - 1000 holds the element kinds of its tensors
  %isfuse = icmp sge i64 %op, 1000
  br i1 %isfuse, label %fuse, label %entry
fuse:
  %fkinds = sub i64 %op, 1000
  %fused = call i64 @rg_fuse(i64 %lslot, i64 %subs, i64 %len, i64 %fkinds)
  ret i64 %fused
entry:
  %dimt = alloca [256 x i64], align 8
  %valt = alloca [256 x i64], align 8
  %ords = alloca [64 x i64], align 8
  %odims = alloca [64 x i64], align 8
  %dim = ptrtoint ptr %dimt to i64
  %val = ptrtoint ptr %valt to i64
  %ord = ptrtoint ptr %ords to i64
  %od = ptrtoint ptr %odims to i64
  call void @rg_fill(i64 %dim, i8 0, i64 2048)
  call void @rg_fill(i64 %val, i8 0, i64 2048)
  %a = call i64 @rg_ld(i64 %lslot)
  call void @rg_st(i64 %lslot, i64 0)
  %at = call i1 @rg_has_tag(i64 %a, i64 5)
  %bt = call i1 @rg_has_tag(i64 %b, i64 5)
  %both = and i1 %at, %bt
  br i1 %both, label %split, label %fail
fail:
  %x1 = call i64 @__rg_rt_drop_val(i64 %a)
  %x2 = call i64 @__rg_rt_drop_val(i64 %b)
  ret i64 0
split:
  br label %find
find:
  %ci = phi i64 [ 0, %split ], [ %ci1, %fnext ]
  %fm = icmp slt i64 %ci, %len
  br i1 %fm, label %fbody, label %found
fbody:
  %fa = add i64 %subs, %ci
  %fc = call i64 @rg_ldb(i64 %fa)
  %isc = icmp eq i64 %fc, 44
  br i1 %isc, label %found, label %fnext
fnext:
  %ci1 = add i64 %ci, 1
  br label %find
found:
  %la = phi i64 [ %ci, %find ], [ %ci, %fbody ]
  %bs0 = add i64 %la, 1
  %bsa = add i64 %subs, %bs0
  %lb0 = sub i64 %len, %bs0
  %neg = icmp slt i64 %lb0, 0
  %lb = select i1 %neg, i64 0, i64 %lb0
  call void @rg_sub_dims(i64 %b, i64 %bsa, i64 %lb, i64 %dim)
  call void @rg_sub_dims(i64 %a, i64 %subs, i64 %la, i64 %dim)
  ; the result letters: a's, then b's letters a lacks (marked in val)
  br label %aloop
aloop:
  %ai = phi i64 [ 0, %found ], [ %ai1, %abody ]
  %am = icmp slt i64 %ai, %la
  br i1 %am, label %abody, label %bstart
abody:
  %aa = add i64 %subs, %ai
  %ac = call i64 @rg_ldb(i64 %aa)
  call void @rg_word_set(i64 %ord, i64 %ai, i64 %ac)
  call void @rg_word_set(i64 %val, i64 %ac, i64 1)
  %ai1 = add i64 %ai, 1
  br label %aloop
bstart:
  br label %bloop
bloop:
  %bi = phi i64 [ 0, %bstart ], [ %bi1, %bnext ]
  %nr = phi i64 [ %la, %bstart ], [ %nr1, %bnext ]
  %bm = icmp slt i64 %bi, %lb
  br i1 %bm, label %bbody, label %shape
bbody:
  %ba = add i64 %bsa, %bi
  %bc = call i64 @rg_ldb(i64 %ba)
  %mk = call i64 @rg_word_at(i64 %val, i64 %bc)
  %new = icmp eq i64 %mk, 0
  %room = icmp slt i64 %nr, 64
  %add = and i1 %new, %room
  br i1 %add, label %badd, label %bnext
badd:
  call void @rg_word_set(i64 %ord, i64 %nr, i64 %bc)
  call void @rg_word_set(i64 %val, i64 %bc, i64 1)
  %nrp = add i64 %nr, 1
  br label %bnext
bnext:
  %nr1 = phi i64 [ %nr, %bbody ], [ %nrp, %badd ]
  %bi1 = add i64 %bi, 1
  br label %bloop
shape:
  br label %sloop
sloop:
  %si = phi i64 [ 0, %shape ], [ %si1, %sbody ]
  %sm = icmp slt i64 %si, %nr
  br i1 %sm, label %sbody, label %make
sbody:
  %sc = call i64 @rg_word_at(i64 %ord, i64 %si)
  %sd = call i64 @rg_word_at(i64 %dim, i64 %sc)
  call void @rg_word_set(i64 %od, i64 %si, i64 %sd)
  %si1 = add i64 %si, 1
  br label %sloop
make:
  call void @rg_fill(i64 %val, i8 0, i64 2048)
  %res = call i64 @rg_t_filled(i64 %od, i64 %nr, i64 0)
  %rd = call i64 @rg_t_data(i64 %res)
  %tot = call i64 @rg_t_len(i64 %res)
  %ad = call i64 @rg_t_data(i64 %a)
  %bd = call i64 @rg_t_data(i64 %b)
  %any = icmp sgt i64 %tot, 0
  br i1 %any, label %el, label %done
el:
  %e = phi i64 [ 0, %make ], [ %e1, %eok ]
  %offa = call i64 @rg_sub_offset(i64 %subs, i64 %la, i64 %dim, i64 %val)
  %offb = call i64 @rg_sub_offset(i64 %bsa, i64 %lb, i64 %dim, i64 %val)
  %wa = call i64 @rg_word_at(i64 %ad, i64 %offa)
  %wb = call i64 @rg_word_at(i64 %bd, i64 %offb)
  %w = call i64 @rg_hadamard_op(i64 %op, i64 %wa, i64 %wb)
  call void @rg_word_set(i64 %rd, i64 %e, i64 %w)
  %e1 = add i64 %e, 1
  %again = call i1 @rg_odometer(i64 %ord, i64 %nr, i64 %dim, i64 %val)
  br i1 %again, label %eok, label %done
eok:
  br label %el
done:
  %y1 = call i64 @__rg_rt_drop_val(i64 %a)
  %y2 = call i64 @__rg_rt_drop_val(i64 %b)
  ret i64 %res
}
