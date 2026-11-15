; ============================================================
; src/main/runtime/core/call.ll
; Calls from the runtime into the program (ADR-0013). A function value of
; the program is the address of a NIR function: `i64 (args address)`. The
; backend gives the runtime the program's dispatchers at start:
;   spawn: (function, argument)        -> calls a function value with 1
;   call2: (function, first, rest)     -> calls a function value with 2+
;   binop: (operator name, lhs, rhs)   -> user + - * / % on other types
; A Ridgun function value is the String of its name, or a closure: the
; Tuple (name, captured values); the dispatchers tell them apart.
; ============================================================

declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i64 @rg_str_from(i64, i64)
declare i64 @__rg_rt_clone_slot(i64)
declare void @rg_heap_init(i64, i64)
declare i64 @__rg_pal_memory_end()

@rg_fn_spawn = internal global i64 0
@rg_fn_call2 = internal global i64 0
@rg_fn_binop = internal global i64 0

; Call the program function at address f with the arguments at `args`.
define i64 @rg_call_fn(i64 %f, i64 %args) {
  %fp = inttoptr i64 %f to ptr
  %ap = inttoptr i64 %args to ptr
  %r = call i64 %fp(ptr %ap)
  ret i64 %r
}

; start (heap start, main, spawn, call2, binop): sets up the heap from the
; heap start to the end of the memory the program has now, keeps the
; dispatchers, and runs main with no arguments. Gives main's value.
define i64 @__rg_rt_start(i64 %heap, i64 %main, i64 %spawn, i64 %call2, i64 %binop) {
  %end = call i64 @__rg_pal_memory_end()
  call void @rg_heap_init(i64 %heap, i64 %end)
  store i64 %spawn, ptr @rg_fn_spawn, align 8
  store i64 %call2, ptr @rg_fn_call2, align 8
  store i64 %binop, ptr @rg_fn_binop, align 8
  %r = call i64 @rg_call_fn(i64 %main, i64 0)
  ret i64 %r
}

; Call function value f (left alone) with one argument (taken).
define i64 @rg_apply1(i64 %f, i64 %x) {
  %args = alloca [2 x i64], align 8
  %fc = call i64 @__rg_rt_clone_slot(i64 %f)
  %p0 = getelementptr inbounds [2 x i64], ptr %args, i64 0, i64 0
  store i64 %fc, ptr %p0, align 8
  %p1 = getelementptr inbounds [2 x i64], ptr %args, i64 0, i64 1
  store i64 %x, ptr %p1, align 8
  %d = load i64, ptr @rg_fn_spawn, align 8
  %a = ptrtoint ptr %args to i64
  %r = call i64 @rg_call_fn(i64 %d, i64 %a)
  ret i64 %r
}

; Call function value f (left alone) with two arguments (taken).
define i64 @rg_apply2(i64 %f, i64 %x, i64 %y) {
  %args = alloca [3 x i64], align 8
  %fc = call i64 @__rg_rt_clone_slot(i64 %f)
  %p0 = getelementptr inbounds [3 x i64], ptr %args, i64 0, i64 0
  store i64 %fc, ptr %p0, align 8
  %p1 = getelementptr inbounds [3 x i64], ptr %args, i64 0, i64 1
  store i64 %x, ptr %p1, align 8
  %p2 = getelementptr inbounds [3 x i64], ptr %args, i64 0, i64 2
  store i64 %y, ptr %p2, align 8
  %d = load i64, ptr @rg_fn_call2, align 8
  %a = ptrtoint ptr %args to i64
  %r = call i64 @rg_call_fn(i64 %d, i64 %a)
  ret i64 %r
}

; call_indirect1 (function value, argument slot address): the function value
; is left alone, the argument is taken from its slot.
define i64 @__rg_rt_call_indirect1(i64 %f, i64 %slot) {
  %x = call i64 @rg_ld(i64 %slot)
  call void @rg_st(i64 %slot, i64 0)
  %r = call i64 @rg_apply1(i64 %f, i64 %x)
  ret i64 %r
}

; call_indirect2 (function value, first of two argument slots).
define i64 @__rg_rt_call_indirect2(i64 %f, i64 %slot) {
  %x = call i64 @rg_ld(i64 %slot)
  call void @rg_st(i64 %slot, i64 0)
  %s2 = add i64 %slot, 8
  %y = call i64 @rg_ld(i64 %s2)
  call void @rg_st(i64 %s2, i64 0)
  %r = call i64 @rg_apply2(i64 %f, i64 %x, i64 %y)
  ret i64 %r
}

@rg_opnames = private constant [5 x i8] c"+-*/%"

; A user operator: the binop dispatcher with the operator's name (op 0..4)
; and both operands (taken).
define i64 @rg_call_binop_user(i64 %op, i64 %a, i64 %b) {
  %np = getelementptr inbounds [5 x i8], ptr @rg_opnames, i64 0, i64 %op
  %na = ptrtoint ptr %np to i64
  %name = call i64 @rg_str_from(i64 %na, i64 1)
  %args = alloca [3 x i64], align 8
  %p0 = getelementptr inbounds [3 x i64], ptr %args, i64 0, i64 0
  store i64 %name, ptr %p0, align 8
  %p1 = getelementptr inbounds [3 x i64], ptr %args, i64 0, i64 1
  store i64 %a, ptr %p1, align 8
  %p2 = getelementptr inbounds [3 x i64], ptr %args, i64 0, i64 2
  store i64 %b, ptr %p2, align 8
  %d = load i64, ptr @rg_fn_binop, align 8
  %aa = ptrtoint ptr %args to i64
  %r = call i64 @rg_call_fn(i64 %d, i64 %aa)
  ret i64 %r
}

; The spawn dispatcher's address (jobs, agents.ll).
define i64 @rg_fn_spawn_addr() {
  %d = load i64, ptr @rg_fn_spawn, align 8
  ret i64 %d
}
