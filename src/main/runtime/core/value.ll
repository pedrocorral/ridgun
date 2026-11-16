; ============================================================
; src/main/runtime/core/value.ll
; Values and heap objects (ADR-0013, docs/etc/runtime_contract.md).
;
; A value is one i64 word: a tagged Int (2n + 1), False (2), True (6),
; Unit (0), or the address of a heap object (nonzero, low 3 bits 0).
;
; A heap object is three words [tag, w1, w2] with its reference count in the
; word before it (object - 8). The tag is the i32 at +0:
;   0  Real (word 0, w1 = IEEE-754 bits) or boxed Int (word 2^63, w1 = value)
;   1  String: w1 = byte vector header
;   2  List:   w1 = value vector header, w2 = index of the first element
;   3  Tuple:  w1 = value vector header
;   4  ADT:    w1 = name header (bytes), w2 = field vector header
;   5  Tensor: w1 = shape header, w2 = data header (raw words)
; A vector header is four words {cap, data, len, rc}. cap = 0 with data /= 0
; means the data is not owned (a name in the rodata).
;
; Ownership: constructors take the values they are given; accessors give a
; new reference (+1) and leave their argument alone; drop at zero frees the
; object and drops its children.
; ============================================================

declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare void @rg_copy(i64, i64, i64)
declare i64 @__rg_pal_write(i64, i64, i64)
declare void @__rg_pal_exit(i64)

declare void @rg_live_add(i64)
declare void @rg_rc_inc(i64)
declare i64 @rg_rc_dec(i64)
declare void @rg_count_add(i64, i64)

; ── Words ────────────────────────────────────────────────────

define i64 @rg_ld(i64 %a) alwaysinline {
  %p = inttoptr i64 %a to ptr
  %v = load i64, ptr %p, align 8
  ret i64 %v
}

define void @rg_st(i64 %a, i64 %v) alwaysinline {
  %p = inttoptr i64 %a to ptr
  store i64 %v, ptr %p, align 8
  ret void
}

define i64 @rg_ldb(i64 %a) alwaysinline {
  %p = inttoptr i64 %a to ptr
  %b = load i8, ptr %p, align 1
  %v = zext i8 %b to i64
  ret i64 %v
}

define void @rg_stb(i64 %a, i64 %v) alwaysinline {
  %p = inttoptr i64 %a to ptr
  %b = trunc i64 %v to i8
  store i8 %b, ptr %p, align 1
  ret void
}

define i1 @rg_is_heap(i64 %v) alwaysinline {
  %nz = icmp ne i64 %v, 0
  %low = and i64 %v, 7
  %al = icmp eq i64 %low, 0
  %r = and i1 %nz, %al
  ret i1 %r
}

; The i32 tag of a heap object.
define i64 @rg_tag(i64 %o) alwaysinline {
  %p = inttoptr i64 %o to ptr
  %t = load i32, ptr %p, align 8
  %r = zext i32 %t to i64
  ret i64 %r
}

; 1 when v is a heap object with tag t.
define i1 @rg_has_tag(i64 %v, i64 %t) alwaysinline {
entry:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %test, label %no
test:
  %tag = call i64 @rg_tag(i64 %v)
  %eq = icmp eq i64 %tag, %t
  ret i1 %eq
no:
  ret i1 false
}

define i64 @rg_w1(i64 %o) alwaysinline {
  %a = add i64 %o, 8
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

define i64 @rg_w2(i64 %o) alwaysinline {
  %a = add i64 %o, 16
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

define i64 @rg_int(i64 %n) alwaysinline {
  %s = shl i64 %n, 1
  %t = or i64 %s, 1
  ret i64 %t
}

define i64 @rg_untag(i64 %v) alwaysinline {
  %n = ashr i64 %v, 1
  ret i64 %n
}

define i64 @rg_bool(i1 %c) alwaysinline {
  %r = select i1 %c, i64 6, i64 2
  ret i64 %r
}

; ── Errors ───────────────────────────────────────────────────

@rg_msg_rterr = private constant [15 x i8] c"runtime error: "
@rg_msg_nl = private constant [1 x i8] c"\0A"

; fatal (message, length): writes "runtime error: <message>" to standard
; error, then a newline, and ends the program with status 1.
define void @rg_fatal(ptr %msg, i64 %len) noreturn {
  %pre = ptrtoint ptr @rg_msg_rterr to i64
  %w1 = call i64 @__rg_pal_write(i64 2, i64 %pre, i64 15)
  %m = ptrtoint ptr %msg to i64
  %w2 = call i64 @__rg_pal_write(i64 2, i64 %m, i64 %len)
  %nl = ptrtoint ptr @rg_msg_nl to i64
  %w3 = call i64 @__rg_pal_write(i64 2, i64 %nl, i64 1)
  call void @__rg_pal_exit(i64 1)
  unreachable
}

; ── Objects and vectors ──────────────────────────────────────

; A new object [tag word, w1, w2] with one reference.
define i64 @rg_obj(i64 %tagword, i64 %w1, i64 %w2) {
  %b = call i64 @rg_alloc(i64 32)
  call void @rg_st(i64 %b, i64 1)
  %o = add i64 %b, 8
  call void @rg_st(i64 %o, i64 %tagword)
  %a1 = add i64 %o, 8
  call void @rg_st(i64 %a1, i64 %w1)
  %a2 = add i64 %o, 16
  call void @rg_st(i64 %a2, i64 %w2)
  call void @rg_live_add(i64 1)
  ret i64 %o
}

define i64 @rg_rc(i64 %o) alwaysinline {
  %a = sub i64 %o, 8
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

; A vector header {cap, data, len, rc = 1} with room for cap items of
; `size` bytes (no data block when cap is 0).
define i64 @rg_vec(i64 %cap, i64 %len, i64 %size) {
entry:
  %h = call i64 @rg_alloc(i64 32)
  %has = icmp sgt i64 %cap, 0
  br i1 %has, label %data, label %set
data:
  %bytes = mul i64 %cap, %size
  %d0 = call i64 @rg_alloc(i64 %bytes)
  br label %set
set:
  %d = phi i64 [ 0, %entry ], [ %d0, %data ]
  call void @rg_st(i64 %h, i64 %cap)
  %a1 = add i64 %h, 8
  call void @rg_st(i64 %a1, i64 %d)
  %a2 = add i64 %h, 16
  call void @rg_st(i64 %a2, i64 %len)
  %a3 = add i64 %h, 24
  call void @rg_st(i64 %a3, i64 1)
  ret i64 %h
}

define i64 @rg_vcap(i64 %h) alwaysinline {
  %v = call i64 @rg_ld(i64 %h)
  ret i64 %v
}

define i64 @rg_vdata(i64 %h) alwaysinline {
  %a = add i64 %h, 8
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

define i64 @rg_vlen(i64 %h) alwaysinline {
  %a = add i64 %h, 16
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

define void @rg_vset_len(i64 %h, i64 %n) alwaysinline {
  %a = add i64 %h, 16
  call void @rg_st(i64 %a, i64 %n)
  ret void
}

define i64 @rg_vrc(i64 %h) alwaysinline {
  %a = add i64 %h, 24
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

define void @rg_vretain(i64 %h) {
  %a = add i64 %h, 24
  call void @rg_rc_inc(i64 %a)
  ret void
}

; One reference less to a vector; at zero, drop its values (when it holds
; values) and free it.
define void @rg_vrelease(i64 %h, i1 %values) {
entry:
  %z = icmp eq i64 %h, 0
  br i1 %z, label %done, label %dec
dec:
  %a = add i64 %h, 24
  %rc1 = call i64 @rg_rc_dec(i64 %a)
  %last = icmp sle i64 %rc1, 0
  br i1 %last, label %free, label %done
free:
  %d = call i64 @rg_vdata(i64 %h)
  %n = call i64 @rg_vlen(i64 %h)
  br i1 %values, label %loop, label %fdata
loop:
  %i = phi i64 [ 0, %free ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %fdata
body:
  %off = shl i64 %i, 3
  %ea = add i64 %d, %off
  %e = call i64 @rg_ld(i64 %ea)
  %r = call i64 @__rg_rt_drop_val(i64 %e)
  %i1 = add i64 %i, 1
  br label %loop
fdata:
  %cap = call i64 @rg_vcap(i64 %h)
  %owned = icmp sgt i64 %cap, 0
  br i1 %owned, label %fd, label %fh
fd:
  call void @rg_free(i64 %d)
  br label %fh
fh:
  call void @rg_free(i64 %h)
  br label %done
done:
  ret void
}

; ── clone and drop ───────────────────────────────────────────

; clone_slot (value): one more reference; the same word.
define i64 @__rg_rt_clone_slot(i64 %v) {
entry:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %inc, label %done
inc:
  %a = sub i64 %v, 8
  call void @rg_rc_inc(i64 %a)
  br label %done
done:
  ret i64 %v
}

; drop_val (value): one reference less; at zero the children are dropped and
; the object is freed. Gives 0.
define i64 @__rg_rt_drop_val(i64 %v) {
entry:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %dec, label %done
dec:
  %a = sub i64 %v, 8
  %rc1 = call i64 @rg_rc_dec(i64 %a)
  %last = icmp sle i64 %rc1, 0
  br i1 %last, label %kids, label %done
kids:
  %t = call i64 @rg_tag(i64 %v)
  %w1 = call i64 @rg_w1(i64 %v)
  %w2 = call i64 @rg_w2(i64 %v)
  switch i64 %t, label %free [ i64 1, label %bytes
                               i64 2, label %vals
                               i64 3, label %vals
                               i64 4, label %adt
                               i64 5, label %tensor
                               i64 6, label %vals ]
bytes:
  call void @rg_vrelease(i64 %w1, i1 false)
  br label %free
vals:
  call void @rg_vrelease(i64 %w1, i1 true)
  br label %free
adt:
  call void @rg_vrelease(i64 %w1, i1 false)
  call void @rg_vrelease(i64 %w2, i1 true)
  br label %free
tensor:
  call void @rg_vrelease(i64 %w1, i1 false)
  call void @rg_vrelease(i64 %w2, i1 false)
  br label %free
free:
  call void @rg_free(i64 %a)
  call void @rg_live_add(i64 -1)
  br label %done
done:
  ret i64 0
}

; ── Strings ──────────────────────────────────────────────────

; A new String of n bytes (contents not set) with room for cap bytes.
define i64 @rg_str_alloc(i64 %n, i64 %cap) {
  %big = icmp sgt i64 %n, %cap
  %c0 = select i1 %big, i64 %n, i64 %cap
  %small = icmp slt i64 %c0, 8
  %c = select i1 %small, i64 8, i64 %c0
  %h = call i64 @rg_vec(i64 %c, i64 %n, i64 1)
  %o = call i64 @rg_obj(i64 1, i64 %h, i64 0)
  ret i64 %o
}

; A new String with a copy of n bytes at src.
define i64 @rg_str_from(i64 %src, i64 %n) {
  %o = call i64 @rg_str_alloc(i64 %n, i64 %n)
  %d = call i64 @rg_str_data(i64 %o)
  call void @rg_copy(i64 %d, i64 %src, i64 %n)
  ret i64 %o
}

define i64 @rg_str_data(i64 %o) alwaysinline {
  %h = call i64 @rg_w1(i64 %o)
  %d = call i64 @rg_vdata(i64 %h)
  ret i64 %d
}

define i64 @rg_str_len(i64 %o) alwaysinline {
  %h = call i64 @rg_w1(i64 %o)
  %n = call i64 @rg_vlen(i64 %h)
  ret i64 %n
}

; 1 when the n bytes at a and at b are equal.
define i1 @rg_bytes_eq(i64 %a, i64 %b, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %yes
body:
  %pa = add i64 %a, %i
  %pb = add i64 %b, %i
  %ca = call i64 @rg_ldb(i64 %pa)
  %cb = call i64 @rg_ldb(i64 %pb)
  %eq = icmp eq i64 %ca, %cb
  br i1 %eq, label %next, label %no
next:
  %i1 = add i64 %i, 1
  br label %loop
yes:
  ret i1 true
no:
  ret i1 false
}

; ── Lists and tuples ─────────────────────────────────────────

; A new List of n values (not set) with room for cap.
define i64 @rg_list_alloc(i64 %n, i64 %cap) {
  %big = icmp sgt i64 %n, %cap
  %c0 = select i1 %big, i64 %n, i64 %cap
  %h = call i64 @rg_vec(i64 %c0, i64 %n, i64 8)
  %o = call i64 @rg_obj(i64 2, i64 %h, i64 0)
  ret i64 %o
}

; The address of element i of a List (from its first element).
define i64 @rg_list_at(i64 %o, i64 %i) alwaysinline {
  %h = call i64 @rg_w1(i64 %o)
  %d = call i64 @rg_vdata(i64 %h)
  %s = call i64 @rg_w2(i64 %o)
  %k = add i64 %s, %i
  %off = shl i64 %k, 3
  %a = add i64 %d, %off
  ret i64 %a
}

define i64 @rg_list_len(i64 %o) alwaysinline {
  %h = call i64 @rg_w1(i64 %o)
  %n = call i64 @rg_vlen(i64 %h)
  %s = call i64 @rg_w2(i64 %o)
  %l = sub i64 %n, %s
  ret i64 %l
}

; Element i of a tuple or of the fields of an ADT (the vector in w1 or w2).
define i64 @rg_vec_item(i64 %h, i64 %i) alwaysinline {
  %d = call i64 @rg_vdata(i64 %h)
  %off = shl i64 %i, 3
  %a = add i64 %d, %off
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

; Move n values from the slots at `slots` into a new vector (slots cleared).
define i64 @rg_vec_take(i64 %slots, i64 %n) {
entry:
  %h = call i64 @rg_vec(i64 %n, i64 %n, i64 8)
  %d = call i64 @rg_vdata(i64 %h)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %off = shl i64 %i, 3
  %sa = add i64 %slots, %off
  %v = call i64 @rg_ld(i64 %sa)
  call void @rg_st(i64 %sa, i64 0)
  %da = add i64 %d, %off
  call void @rg_st(i64 %da, i64 %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %h
}

; make_list (slots, n): a List of the n slot values (taken).
define i64 @__rg_rt_make_list(i64 %slots, i64 %n) {
  %h = call i64 @rg_vec_take(i64 %slots, i64 %n)
  %o = call i64 @rg_obj(i64 2, i64 %h, i64 0)
  ret i64 %o
}

; make_tuple (slots, n): a Tuple of the n slot values (taken).
define i64 @__rg_rt_make_tuple(i64 %slots, i64 %n) {
  %h = call i64 @rg_vec_take(i64 %slots, i64 %n)
  %o = call i64 @rg_obj(i64 3, i64 %h, i64 0)
  ret i64 %o
}

; A name header for n bytes at a in the rodata (not owned).
define i64 @rg_name(i64 %a, i64 %n) {
  %h = call i64 @rg_vec(i64 0, i64 %n, i64 1)
  %da = add i64 %h, 8
  call void @rg_st(i64 %da, i64 %a)
  ret i64 %h
}

; make_adt (name, name length, slots, arity): the constructor applied to the
; slot values (taken).
define i64 @__rg_rt_make_adt(i64 %name, i64 %nlen, i64 %slots, i64 %n) {
  %nh = call i64 @rg_name(i64 %name, i64 %nlen)
  %fh = call i64 @rg_vec_take(i64 %slots, i64 %n)
  %o = call i64 @rg_obj(i64 4, i64 %nh, i64 %fh)
  ret i64 %o
}

; load_adt0 (name, length): a constructor without fields.
define i64 @__rg_rt_load_adt0(i64 %name, i64 %nlen) {
  %r = call i64 @__rg_rt_make_adt(i64 %name, i64 %nlen, i64 0, i64 0)
  ret i64 %r
}

; load_str_lit (bytes, length): a new String with these bytes.
define i64 @__rg_rt_load_str_lit(i64 %a, i64 %n) {
  %o = call i64 @rg_str_from(i64 %a, i64 %n)
  ret i64 %o
}

; ── Reals ────────────────────────────────────────────────────

define i64 @rg_real(double %x) {
  %b = bitcast double %x to i64
  %o = call i64 @rg_obj(i64 0, i64 %b, i64 0)
  ret i64 %o
}

; 1 when v is a Real (tag word 0).
define i1 @rg_is_real(i64 %v) {
entry:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %test, label %no
test:
  %w = call i64 @rg_ld(i64 %v)
  %r = icmp eq i64 %w, 0
  ret i1 %r
no:
  ret i1 false
}

define double @rg_real_of(i64 %o) alwaysinline {
  %b = call i64 @rg_w1(i64 %o)
  %x = bitcast i64 %b to double
  ret double %x
}

; Parse the decimal text of a Real literal: digits, an optional point and
; digits, an optional e[+-]digits. Exact for up to 19 significant digits and
; powers of ten up to 10^22, as Clinger's fast path.
define double @rg_parse_real(i64 %a, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %m = phi i64 [ 0, %entry ], [ %m1, %next ]
  %e = phi i64 [ 0, %entry ], [ %e1, %next ]
  %dot = phi i1 [ false, %entry ], [ %dot1, %next ]
  %neg = phi i1 [ false, %entry ], [ %neg1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %finish
body:
  %ca = add i64 %a, %i
  %c = call i64 @rg_ldb(i64 %ca)
  %isminus = icmp eq i64 %c, 45
  %ispoint = icmp eq i64 %c, 46
  %ise = icmp eq i64 %c, 101
  %isE = icmp eq i64 %c, 69
  %isexp = or i1 %ise, %isE
  br i1 %isexp, label %exp, label %digit
digit:
  %dv = sub i64 %c, 48
  %isdig = icmp ult i64 %dv, 10
  %room = icmp ult i64 %m, 922337203685477580
  %take = and i1 %isdig, %room
  %m10 = mul i64 %m, 10
  %md = add i64 %m10, %dv
  %mx = select i1 %take, i64 %md, i64 %m
  %frac = and i1 %take, %dot
  %skipped = and i1 %isdig, %dot
  %lost = xor i1 %take, %isdig
  %lostint = and i1 %lost, true
  %edec = sub i64 %e, 1
  %e_a = select i1 %frac, i64 %edec, i64 %e
  %notdot = xor i1 %dot, true
  %intlost = and i1 %lost, %notdot
  %einc = add i64 %e_a, 1
  %e_b = select i1 %intlost, i64 %einc, i64 %e_a
  %dot_n = or i1 %dot, %ispoint
  %neg_n = or i1 %neg, %isminus
  br label %next
next:
  %m1 = phi i64 [ %mx, %digit ]
  %e1 = phi i64 [ %e_b, %digit ]
  %dot1 = phi i1 [ %dot_n, %digit ]
  %neg1 = phi i1 [ %neg_n, %digit ]
  %i1 = add i64 %i, 1
  br label %loop
exp:
  %j0 = add i64 %i, 1
  br label %eloop
eloop:
  %j = phi i64 [ %j0, %exp ], [ %j1, %ebody ]
  %ev = phi i64 [ 0, %exp ], [ %ev1, %ebody ]
  %eneg = phi i1 [ false, %exp ], [ %eneg1, %ebody ]
  %emore = icmp slt i64 %j, %n
  br i1 %emore, label %ebody, label %edone
ebody:
  %eca = add i64 %a, %j
  %ec = call i64 @rg_ldb(i64 %eca)
  %em = icmp eq i64 %ec, 45
  %eneg1 = or i1 %eneg, %em
  %ed = sub i64 %ec, 48
  %eisd = icmp ult i64 %ed, 10
  %ev10 = mul i64 %ev, 10
  %evd = add i64 %ev10, %ed
  %ev1 = select i1 %eisd, i64 %evd, i64 %ev
  %j1 = add i64 %j, 1
  br label %eloop
edone:
  %evn = sub i64 0, %ev
  %evs = select i1 %eneg, i64 %evn, i64 %ev
  %etot = add i64 %e, %evs
  br label %finish
finish:
  %mf = phi i64 [ %m, %loop ], [ %m, %edone ]
  %ef = phi i64 [ %e, %loop ], [ %etot, %edone ]
  %nf = phi i1 [ %neg, %loop ], [ %neg, %edone ]
  %x = uitofp i64 %mf to double
  %y = call double @rg_scale10(double %x, i64 %ef)
  %yn = fneg double %y
  %r = select i1 %nf, double %yn, double %y
  ret double %r
}

; x * 10^e
define double @rg_scale10(double %x, i64 %e) {
entry:
  %neg = icmp slt i64 %e, 0
  %ne = sub i64 0, %e
  %k = select i1 %neg, i64 %ne, i64 %e
  br label %loop
loop:
  %i = phi i64 [ %k, %entry ], [ %i1, %body ]
  %p = phi double [ 1.0, %entry ], [ %p1, %body ]
  %more = icmp sgt i64 %i, 0
  br i1 %more, label %body, label %done
body:
  %p1 = fmul double %p, 10.0
  %i1 = sub i64 %i, 1
  br label %loop
done:
  %d = fdiv double %x, %p
  %m = fmul double %x, %p
  %r = select i1 %neg, double %d, double %m
  ret double %r
}

; load_real_lit (text, length): the Real of the decimal text.
define i64 @__rg_rt_load_real_lit(i64 %a, i64 %n) {
  %x = call double @rg_parse_real(i64 %a, i64 %n)
  %o = call i64 @rg_real(double %x)
  ret i64 %o
}

; ── Tests and access ─────────────────────────────────────────

; as_bool (value): 1 for True, else 0; the value is dropped.
define i64 @__rg_rt_as_bool(i64 %v) {
  %t = icmp eq i64 %v, 6
  %r = zext i1 %t to i64
  %d = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 %r
}

; match_int (value, n): 1 when the value is the Int n.
define i64 @__rg_rt_match_int(i64 %v, i64 %n) {
entry:
  %t = call i64 @rg_int(i64 %n)
  %eq = icmp eq i64 %v, %t
  br i1 %eq, label %yes, label %boxed
boxed:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %tw, label %no
tw:
  %w = call i64 @rg_ld(i64 %v)
  %isb = icmp eq i64 %w, -9223372036854775808
  br i1 %isb, label %cmp, label %no
cmp:
  %x = call i64 @rg_w1(i64 %v)
  %e2 = icmp eq i64 %x, %n
  %r2 = zext i1 %e2 to i64
  ret i64 %r2
yes:
  ret i64 1
no:
  ret i64 0
}

; match_bool (value, b): 1 when the value is True for b /= 0, False for b = 0.
define i64 @__rg_rt_match_bool(i64 %v, i64 %b) {
  %nz = icmp ne i64 %b, 0
  %want = select i1 %nz, i64 6, i64 2
  %eq = icmp eq i64 %v, %want
  %r = zext i1 %eq to i64
  ret i64 %r
}

; bool_inv (value): the other Bool.
define i64 @__rg_rt_bool_inv(i64 %v) {
  %t = icmp eq i64 %v, 6
  %r = select i1 %t, i64 2, i64 6
  ret i64 %r
}

; match_empty / match_nonempty (value): 1 for an empty / a non-empty List
; (a String counts by its bytes).
define i64 @rg_seq_len(i64 %v) {
entry:
  %l = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %l, label %list, label %s
list:
  %n = call i64 @rg_list_len(i64 %v)
  ret i64 %n
s:
  %st = call i1 @rg_has_tag(i64 %v, i64 1)
  br i1 %st, label %str, label %none
str:
  %sn = call i64 @rg_str_len(i64 %v)
  ret i64 %sn
none:
  ret i64 -1
}

define i64 @__rg_rt_match_empty(i64 %v) {
  %n = call i64 @rg_seq_len(i64 %v)
  %e = icmp eq i64 %n, 0
  %r = zext i1 %e to i64
  ret i64 %r
}

define i64 @__rg_rt_match_nonempty(i64 %v) {
  %n = call i64 @rg_seq_len(i64 %v)
  %e = icmp sgt i64 %n, 0
  %r = zext i1 %e to i64
  ret i64 %r
}

@rg_msg_head = private constant [25 x i8] c"head of an empty sequence"

; list_head (value): the first element (a new reference).
define i64 @__rg_rt_list_head(i64 %v) {
entry:
  %n = call i64 @rg_seq_len(i64 %v)
  %ok = icmp sgt i64 %n, 0
  br i1 %ok, label %kind, label %bad
kind:
  %l = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %l, label %list, label %str
list:
  %a = call i64 @rg_list_at(i64 %v, i64 0)
  %e = call i64 @rg_ld(i64 %a)
  %c = call i64 @__rg_rt_clone_slot(i64 %e)
  ret i64 %c
str:
  %d = call i64 @rg_str_data(i64 %v)
  %s = call i64 @rg_str_from(i64 %d, i64 1)
  ret i64 %s
bad:
  call void @rg_fatal(ptr @rg_msg_head, i64 25)
  unreachable
}

; list_tail (value): the List without its first element. It shares the
; vector: a new List object one element further.
define i64 @__rg_rt_list_tail(i64 %v) {
entry:
  %n = call i64 @rg_seq_len(i64 %v)
  %ok = icmp sgt i64 %n, 0
  br i1 %ok, label %kind, label %bad
kind:
  %l = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %l, label %list, label %str
list:
  %h = call i64 @rg_w1(i64 %v)
  call void @rg_vretain(i64 %h)
  %s = call i64 @rg_w2(i64 %v)
  %s1 = add i64 %s, 1
  %o = call i64 @rg_obj(i64 2, i64 %h, i64 %s1)
  ret i64 %o
str:
  %d = call i64 @rg_str_data(i64 %v)
  %d1 = add i64 %d, 1
  %m = sub i64 %n, 1
  %t = call i64 @rg_str_from(i64 %d1, i64 %m)
  ret i64 %t
bad:
  call void @rg_fatal(ptr @rg_msg_head, i64 25)
  unreachable
}

; match_tuple (value, arity): 1 for a Tuple of this arity.
define i64 @__rg_rt_match_tuple(i64 %v, i64 %n) {
entry:
  %t = call i1 @rg_has_tag(i64 %v, i64 3)
  br i1 %t, label %len, label %no
len:
  %h = call i64 @rg_w1(i64 %v)
  %l = call i64 @rg_vlen(i64 %h)
  %eq = icmp eq i64 %l, %n
  %r = zext i1 %eq to i64
  ret i64 %r
no:
  ret i64 0
}

@rg_msg_tget = private constant [24 x i8] c"tuple index out of range"

; tuple_get (value, index): the element (a new reference). A List is read
; as a tuple too.
define i64 @__rg_rt_tuple_get(i64 %v, i64 %i) {
entry:
  %t = call i1 @rg_has_tag(i64 %v, i64 3)
  br i1 %t, label %tuple, label %list
tuple:
  %h = call i64 @rg_w1(i64 %v)
  %l = call i64 @rg_vlen(i64 %h)
  %ok = icmp ult i64 %i, %l
  br i1 %ok, label %get, label %bad
get:
  %e = call i64 @rg_vec_item(i64 %h, i64 %i)
  %c = call i64 @__rg_rt_clone_slot(i64 %e)
  ret i64 %c
list:
  %n = call i64 @rg_seq_len(i64 %v)
  %lok = icmp ult i64 %i, %n
  %isl = call i1 @rg_has_tag(i64 %v, i64 2)
  %both = and i1 %lok, %isl
  br i1 %both, label %lget, label %bad
lget:
  %a = call i64 @rg_list_at(i64 %v, i64 %i)
  %le = call i64 @rg_ld(i64 %a)
  %lc = call i64 @__rg_rt_clone_slot(i64 %le)
  ret i64 %lc
bad:
  call void @rg_fatal(ptr @rg_msg_tget, i64 24)
  unreachable
}

; match_adt (value, name, length, arity): 1 for this constructor with this
; number of fields.
; A negative arity tests a primitive type (prim type tag id): -1 Int (a
; tagged word), -2 Bool, -3 String (heap tag word 1), -4 Real (heap tag
; word 0), -5 numeric tensor (heap tag word 5). Raw 1 or 0.
define i64 @__rg_rt_match_adt(i64 %v, i64 %name, i64 %nlen, i64 %n) {
entry:
  %neg = icmp slt i64 %n, 0
  br i1 %neg, label %prim, label %adt
prim:
  %isint = icmp eq i64 %n, -1
  br i1 %isint, label %pint, label %pb
pint:
  %ri = and i64 %v, 1
  ret i64 %ri
pb:
  %isbool = icmp eq i64 %n, -2
  br i1 %isbool, label %pbool, label %pheap
pbool:
  %bm = and i64 %v, -5
  %bc = icmp eq i64 %bm, 2
  %rb = zext i1 %bc to i64
  ret i64 %rb
pheap:
  %nz = icmp ne i64 %v, 0
  %lo = and i64 %v, 7
  %al = icmp eq i64 %lo, 0
  %hp = and i1 %nz, %al
  br i1 %hp, label %ptag, label %no
ptag:
  %is3 = icmp eq i64 %n, -3
  %is4 = icmp eq i64 %n, -4
  %w45 = select i1 %is4, i64 0, i64 5
  %want = select i1 %is3, i64 1, i64 %w45
  %tp = inttoptr i64 %v to ptr
  %tw = load i64, ptr %tp, align 8
  %tc = icmp eq i64 %tw, %want
  %rt = zext i1 %tc to i64
  ret i64 %rt
adt:
  %t = call i1 @rg_has_tag(i64 %v, i64 4)
  br i1 %t, label %ar, label %no
ar:
  %fh = call i64 @rg_w2(i64 %v)
  %fl = call i64 @rg_vlen(i64 %fh)
  %aok = icmp eq i64 %fl, %n
  br i1 %aok, label %nm, label %no
nm:
  %nh = call i64 @rg_w1(i64 %v)
  %l = call i64 @rg_vlen(i64 %nh)
  %lok = icmp eq i64 %l, %nlen
  br i1 %lok, label %bytes, label %no
bytes:
  %d = call i64 @rg_vdata(i64 %nh)
  %eq = call i1 @rg_bytes_eq(i64 %d, i64 %name, i64 %nlen)
  %r = zext i1 %eq to i64
  ret i64 %r
no:
  ret i64 0
}

@rg_msg_field = private constant [24 x i8] c"field index out of range"

; adt_field (value, index): the field (a new reference).
; A negative index reads a length (the native encoders do it inline):
; -1 the length of the vector in w1 (a String's length), -2 the length of
; the vector in w2, -10 - k dimension k of a tensor's shape. As tagged Ints.
define i64 @__rg_rt_adt_field(i64 %v, i64 %i) {
entry:
  %neg = icmp slt i64 %i, 0
  br i1 %neg, label %lens, label %adt
lens:
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %which, label %bad
which:
  %m1 = icmp eq i64 %i, -1
  br i1 %m1, label %len1, label %w2q
len1:
  %h1 = call i64 @rg_w1(i64 %v)
  %l1 = call i64 @rg_vlen(i64 %h1)
  %r1 = call i64 @rg_int(i64 %l1)
  ret i64 %r1
w2q:
  %m2 = icmp eq i64 %i, -2
  br i1 %m2, label %len2, label %dim
len2:
  %h2 = call i64 @rg_w2(i64 %v)
  %l2 = call i64 @rg_vlen(i64 %h2)
  %r2 = call i64 @rg_int(i64 %l2)
  ret i64 %r2
dim:
  %k = sub i64 -10, %i
  %sh = call i64 @rg_w1(i64 %v)
  %rank = call i64 @rg_vlen(i64 %sh)
  %okd = icmp ult i64 %k, %rank
  br i1 %okd, label %getd, label %bad
getd:
  %dv = call i64 @rg_vec_item(i64 %sh, i64 %k)
  %r3 = call i64 @rg_int(i64 %dv)
  ret i64 %r3
adt:
  %t = call i1 @rg_has_tag(i64 %v, i64 4)
  br i1 %t, label %chk, label %bad
chk:
  %fh = call i64 @rg_w2(i64 %v)
  %fl = call i64 @rg_vlen(i64 %fh)
  %ok = icmp ult i64 %i, %fl
  br i1 %ok, label %get, label %bad
get:
  %e = call i64 @rg_vec_item(i64 %fh, i64 %i)
  %c = call i64 @__rg_rt_clone_slot(i64 %e)
  ret i64 %c
bad:
  call void @rg_fatal(ptr @rg_msg_field, i64 24)
  unreachable
}

; adt_set (record slot address, index, value): the record with field i set
; to the value (taken). The record in the slot is taken too: it is changed in
; place when nothing else holds it, else copied. The slot is cleared.
define i64 @__rg_rt_adt_set(i64 %slot, i64 %i, i64 %nv) {
entry:
  %r = call i64 @rg_ld(i64 %slot)
  call void @rg_st(i64 %slot, i64 0)
  %t = call i1 @rg_has_tag(i64 %r, i64 4)
  br i1 %t, label %own, label %bad
own:
  %rc = call i64 @rg_rc(i64 %r)
  %fh = call i64 @rg_w2(i64 %r)
  %vrc = call i64 @rg_vrc(i64 %fh)
  %sole = icmp sle i64 %rc, 1
  %vsole = icmp sle i64 %vrc, 1
  %both = and i1 %sole, %vsole
  br i1 %both, label %inplace, label %copy
inplace:
  %fl = call i64 @rg_vlen(i64 %fh)
  %ok = icmp ult i64 %i, %fl
  br i1 %ok, label %put, label %bad
put:
  %d = call i64 @rg_vdata(i64 %fh)
  %off = shl i64 %i, 3
  %ea = add i64 %d, %off
  %old = call i64 @rg_ld(i64 %ea)
  call void @rg_st(i64 %ea, i64 %nv)
  %x = call i64 @__rg_rt_drop_val(i64 %old)
  ret i64 %r
copy:
  %n = call i64 @rg_vlen(i64 %fh)
  %nh = call i64 @rg_vec(i64 %n, i64 %n, i64 8)
  %nd = call i64 @rg_vdata(i64 %nh)
  %od = call i64 @rg_vdata(i64 %fh)
  br label %cloop
cloop:
  %k = phi i64 [ 0, %copy ], [ %k1, %cbody ]
  %more = icmp slt i64 %k, %n
  br i1 %more, label %cbody, label %built
cbody:
  %ko = shl i64 %k, 3
  %oa = add i64 %od, %ko
  %ov = call i64 @rg_ld(i64 %oa)
  %cv = call i64 @__rg_rt_clone_slot(i64 %ov)
  %na = add i64 %nd, %ko
  call void @rg_st(i64 %na, i64 %cv)
  %k1 = add i64 %k, 1
  br label %cloop
built:
  %name = call i64 @rg_w1(i64 %r)
  call void @rg_vretain(i64 %name)
  %nr = call i64 @rg_obj(i64 4, i64 %name, i64 %nh)
  %y = call i64 @__rg_rt_drop_val(i64 %r)
  call void @rg_st(i64 %slot, i64 %nr)
  br label %inplace2
inplace2:
  %res = call i64 @__rg_rt_adt_set(i64 %slot, i64 %i, i64 %nv)
  ret i64 %res
bad:
  call void @rg_fatal(ptr @rg_msg_field, i64 24)
  unreachable
}

; match_str (value, bytes, length): 1 when the value is a String with
; exactly these bytes. The value is left alone.
define i64 @__rg_rt_match_str(i64 %v, i64 %p, i64 %n) {
entry:
  %s = call i1 @rg_has_tag(i64 %v, i64 1)
  br i1 %s, label %len, label %no
len:
  %l = call i64 @rg_str_len(i64 %v)
  %le = icmp eq i64 %l, %n
  br i1 %le, label %bytes, label %no
bytes:
  %d = call i64 @rg_str_data(i64 %v)
  %e = call i1 @rg_bytes_eq(i64 %d, i64 %p, i64 %n)
  %r = zext i1 %e to i64
  ret i64 %r
no:
  ret i64 0
}

; match_real (value, text, length): 1 when the value is a Real equal to the
; Real literal written in the text. The value is left alone.
define i64 @__rg_rt_match_real(i64 %v, i64 %p, i64 %n) {
entry:
  %r = call i1 @rg_is_real(i64 %v)
  br i1 %r, label %cmp, label %no
cmp:
  %x = call double @rg_real_of(i64 %v)
  %y = call double @rg_parse_real(i64 %p, i64 %n)
  %e = fcmp oeq double %x, %y
  %z = zext i1 %e to i64
  ret i64 %z
no:
  ret i64 0
}
