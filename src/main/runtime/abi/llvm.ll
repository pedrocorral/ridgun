; ============================================================
; src/main/runtime/abi/llvm.ll
; The runtime entry points the LLVM backend's own helpers call besides the
; promised `__rg_rt_*` set (TASK-0096): raw buffers, boxes made from a
; three-word template, an Int popped from a slot, and the builtin dispatcher
; under its two older names. Each is a thin form of a function the runtime
; already has.
; ============================================================

declare i64 @rg_alloc(i64)
declare i64 @rg_obj(i64, i64, i64)
declare i64 @rg_str_from(i64, i64)
declare i64 @rg_int_of(i64)
declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare void @rg_fill(i64, i8, i64)
declare i64 @__rg_rt_cmm_drop_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare i64 @__rg_rt_builtin(i64, i64, i64)

; alloc_buf (n): a buffer of n zeroed bytes.
define i64 @__rg_rt_alloc_buf(i64 %n) {
  %b = call i64 @rg_alloc(i64 %n)
  call void @rg_fill(i64 %b, i8 0, i64 %n)
  ret i64 %b
}

; box_rc_vec (template {cap, data, len}): a vector header {cap, data, len, 1}.
define i64 @__rg_rt_box_rc_vec(i64 %t) {
  %h = call i64 @rg_alloc(i64 32)
  %w0 = call i64 @rg_ld(i64 %t)
  call void @rg_st(i64 %h, i64 %w0)
  %t1 = add i64 %t, 8
  %w1 = call i64 @rg_ld(i64 %t1)
  %h1 = add i64 %h, 8
  call void @rg_st(i64 %h1, i64 %w1)
  %t2 = add i64 %t, 16
  %w2 = call i64 @rg_ld(i64 %t2)
  %h2 = add i64 %h, 16
  call void @rg_st(i64 %h2, i64 %w2)
  %h3 = add i64 %h, 24
  call void @rg_st(i64 %h3, i64 1)
  ret i64 %h
}

; box_rval (template {tag, w1, w2}): the heap value with those words.
define i64 @__rg_rt_box_rval(i64 %t) {
  %w0 = call i64 @rg_ld(i64 %t)
  %t1 = add i64 %t, 8
  %w1 = call i64 @rg_ld(i64 %t1)
  %t2 = add i64 %t, 16
  %w2 = call i64 @rg_ld(i64 %t2)
  %o = call i64 @rg_obj(i64 %w0, i64 %w1, i64 %w2)
  ret i64 %o
}

; alloc_str (bytes, n): a String of n bytes.
define i64 @__rg_rt_alloc_str(i64 %a, i64 %n) {
  %o = call i64 @rg_str_from(i64 %a, i64 %n)
  ret i64 %o
}

; pop_i64 (slot address): the 64-bit integer of the Int in the slot; the slot
; is emptied and its value dropped.
define i64 @__rg_rt_pop_i64(i64 %slot) {
  %v = call i64 @rg_ld(i64 %slot)
  %n = call i64 @rg_int_of(i64 %v)
  %d = call i64 @__rg_rt_cmm_drop_slot(i64 %slot)
  ret i64 %n
}

; drop_slot (slot address): drop the value in the slot and empty it.
define void @__rg_rt_drop_slot(i64 %slot) {
  %d = call i64 @__rg_rt_cmm_drop_slot(i64 %slot)
  ret void
}

; The builtin dispatcher under its older names (ids of every range).
define i64 @__rg_rt_ext(i64 %id, i64 %slots, i64 %n) {
  %r = call i64 @__rg_rt_builtin(i64 %id, i64 %slots, i64 %n)
  ret i64 %r
}

define i64 @__rg_rt_pal_dispatch(i64 %id, i64 %slots, i64 %n) {
  %r = call i64 @__rg_rt_builtin(i64 %id, i64 %slots, i64 %n)
  ret i64 %r
}
