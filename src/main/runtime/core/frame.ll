; ============================================================
; src/main/runtime/core/frame.ll
; Frames and slots (ADR-0013). Target-neutral: every value is an i64 word;
; a slot is the i64 at frame + 8 * index; addresses are converted with
; inttoptr, so the same IR works with 32-bit and 64-bit pointers.
; The result of every runtime entry becomes the program's accumulator.
; ============================================================

declare void @rg_copy(i64, i64, i64)
declare i64 @__rg_rt_drop_val(i64)

define internal ptr @rg_slot(i64 %frame, i64 %i) alwaysinline {
  %off = shl i64 %i, 3
  %a = add i64 %frame, %off
  %p = inttoptr i64 %a to ptr
  ret ptr %p
}

; Store 0 in slot i and drop what it held.
define internal void @rg_clear_slot(i64 %frame, i64 %i) {
  %p = call ptr @rg_slot(i64 %frame, i64 %i)
  %v = load i64, ptr %p, align 8
  store i64 0, ptr %p, align 8
  %r = call i64 @__rg_rt_drop_val(i64 %v)
  ret void
}

; init_frame (frame, args, arity, slots): move the arguments into slots
; 0..arity-1, clearing them at the source, and zero the other slots. No
; arguments address (0) means no arguments.
define i64 @__rg_rt_init_frame(i64 %frame, i64 %args, i64 %arity, i64 %slots) {
entry:
  %no_args = icmp eq i64 %args, 0
  %n = select i1 %no_args, i64 0, i64 %arity
  br label %move
move:
  %i = phi i64 [ 0, %entry ], [ %i1, %move_body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %move_body, label %zero
move_body:
  %src = call ptr @rg_slot(i64 %args, i64 %i)
  %dst = call ptr @rg_slot(i64 %frame, i64 %i)
  %v = load i64, ptr %src, align 8
  store i64 0, ptr %src, align 8
  store i64 %v, ptr %dst, align 8
  %i1 = add i64 %i, 1
  br label %move
zero:
  %j = phi i64 [ %i, %move ], [ %j1, %zero_body ]
  %zmore = icmp slt i64 %j, %slots
  br i1 %zmore, label %zero_body, label %done
zero_body:
  %zp = call ptr @rg_slot(i64 %frame, i64 %j)
  store i64 0, ptr %zp, align 8
  %j1 = add i64 %j, 1
  br label %zero
done:
  ret i64 0
}

; clear_locals (frame, start, end): clear slots start..end-1.
define i64 @__rg_rt_clear_locals(i64 %frame, i64 %start, i64 %end) {
entry:
  br label %loop
loop:
  %i = phi i64 [ %start, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %end
  br i1 %more, label %body, label %done
body:
  call void @rg_clear_slot(i64 %frame, i64 %i)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 0
}

; epilogue (frame, slots, result): drop every slot; the result stays.
define i64 @__rg_rt_epilogue(i64 %frame, i64 %slots, i64 %result) {
  %r = call i64 @__rg_rt_clear_locals(i64 %frame, i64 0, i64 %slots)
  ret i64 %result
}

; tco_copy (frame, start, arity, slots): drop the slots that are not the new
; arguments (start..start+arity-1), then move those down to 0..arity-1.
define i64 @__rg_rt_tco_copy(i64 %frame, i64 %start, i64 %arity, i64 %slots) {
entry:
  %end = add i64 %start, %arity
  br label %drop
drop:
  %i = phi i64 [ 0, %entry ], [ %i1, %drop_next ]
  %more = icmp slt i64 %i, %slots
  br i1 %more, label %drop_test, label %moves
drop_test:
  %below = icmp slt i64 %i, %start
  %above = icmp sge i64 %i, %end
  %other = or i1 %below, %above
  br i1 %other, label %drop_it, label %drop_next
drop_it:
  call void @rg_clear_slot(i64 %frame, i64 %i)
  br label %drop_next
drop_next:
  %i1 = add i64 %i, 1
  br label %drop
moves:
  %same = icmp eq i64 %start, 0
  br i1 %same, label %done, label %move
move:
  %k = phi i64 [ 0, %moves ], [ %k1, %move_body ]
  %kmore = icmp slt i64 %k, %arity
  br i1 %kmore, label %move_body, label %done
move_body:
  %si = add i64 %start, %k
  %src = call ptr @rg_slot(i64 %frame, i64 %si)
  %dst = call ptr @rg_slot(i64 %frame, i64 %k)
  %v = load i64, ptr %src, align 8
  store i64 0, ptr %src, align 8
  store i64 %v, ptr %dst, align 8
  %k1 = add i64 %k, 1
  br label %move
done:
  ret i64 0
}

; cmm_move (slot address): the value, and the slot cleared.
define i64 @__rg_rt_cmm_move(i64 %slot) {
  %p = inttoptr i64 %slot to ptr
  %v = load i64, ptr %p, align 8
  store i64 0, ptr %p, align 8
  ret i64 %v
}

; store_slot (slot address, value): store the value, then drop the old one.
define i64 @__rg_rt_store_slot(i64 %slot, i64 %v) {
  %p = inttoptr i64 %slot to ptr
  %old = load i64, ptr %p, align 8
  store i64 %v, ptr %p, align 8
  %r = call i64 @__rg_rt_drop_val(i64 %old)
  ret i64 %r
}

; cmm_drop_slot (slot address): clear the slot and drop its value.
; The counters of builtins 6 and 7 (`cmm cond spared`, `cmm cond freed`): a
; static last-use drop of a value that another name still holds spares the
; block; one that was the last holder frees it.
@rg_cond_spared = external global i64
@rg_cond_freed = external global i64
declare i1 @rg_is_heap(i64)
declare i64 @rg_rc(i64)
declare void @rg_count_add(i64, i64)

define i64 @__rg_rt_cmm_drop_slot(i64 %slot) {
entry:
  %p = inttoptr i64 %slot to ptr
  %v = load i64, ptr %p, align 8
  store i64 0, ptr %p, align 8
  %h = call i1 @rg_is_heap(i64 %v)
  br i1 %h, label %count, label %drop
count:
  %rc = call i64 @rg_rc(i64 %v)
  %shared = icmp sgt i64 %rc, 1
  %ctr = select i1 %shared, ptr @rg_cond_spared, ptr @rg_cond_freed
  %ca = ptrtoint ptr %ctr to i64
  call void @rg_count_add(i64 %ca, i64 1)
  br label %drop
drop:
  %r = call i64 @__rg_rt_drop_val(i64 %v)
  ret i64 %r
}

; rebind_slot (slot address, value): drop the old value, then store.
define i64 @__rg_rt_rebind_slot(i64 %slot, i64 %v) {
  %r = call i64 @__rg_rt_cmm_drop_slot(i64 %slot)
  %p = inttoptr i64 %slot to ptr
  store i64 %v, ptr %p, align 8
  ret i64 0
}

; tail_frame (frame, slots, count, callee slots): for a tail call to another
; function (OPT-019), after tco_copy put the arguments in slots 0..count-1:
; moves them to the base of a frame of the callee's size whose top is the
; top of this frame, and gives that base. The callee's prologue takes the
; same frame, so the arguments are already in place.
define i64 @__rg_rt_tail_frame(i64 %frame, i64 %slots, i64 %count, i64 %cs) {
  %top0 = shl i64 %slots, 3
  %top = add i64 %frame, %top0
  %sz = shl i64 %cs, 3
  %base = sub i64 %top, %sz
  %bytes = shl i64 %count, 3
  call void @rg_copy(i64 %base, i64 %frame, i64 %bytes)
  ret i64 %base
}
