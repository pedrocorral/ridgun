; ============================================================
; src/main/runtime/core/threads.ll
; What the runtime needs to run on more than one thread (ADR-0014, step b).
;
; - `rg_mt` is 0 until the first worker thread starts. Reference counts and
;   counters use plain updates while it is 0 and atomic ones after, so a
;   program that never starts a thread keeps the plain path.
; - A thread knows which one it is from its stack: worker stacks are slots
;   of one region (RG_STACK_SHIFT bits each), so the slot of the thread is
;   the index of the stack that holds the stack pointer; any other stack
;   (the main thread's) is slot 0. No thread-local storage is needed, so
;   the same IR works on every target. The slot picks the thread's allocator
;   shard (heap.ll).
; - A mutex on a futex word (spin, then sleep), for channels and the pool.
; ============================================================

declare i64 @__rg_pal_alloc_chunk(i64)
declare i64 @__rg_pal_thread_spawn(i64, i64, i64)
declare i64 @__rg_pal_futex_wait(i64, i64, i64)
declare i64 @__rg_pal_futex_wake(i64, i64)
declare void @__rg_pal_yield()
declare ptr @llvm.stacksave.p0()

; 8 worker slots (1 .. 8) of 64 MiB each; slot 0 is every other stack.
@rg_mt = global i32 0
@rg_pool_base = global i64 0
@rg_pool_busy = internal global [9 x i32] zeroinitializer

; The slot of the calling thread (0 .. 8).
define i64 @rg_slot() alwaysinline {
entry:
  %mt = load i32, ptr @rg_mt, align 4
  %multi = icmp ne i32 %mt, 0
  br i1 %multi, label %find, label %main
main:
  ret i64 0
find:
  %sp = call ptr @llvm.stacksave.p0()
  %spi = ptrtoint ptr %sp to i64
  %base = load i64, ptr @rg_pool_base, align 8
  %off = sub i64 %spi, %base
  %in = icmp ult i64 %off, 536870912
  br i1 %in, label %worker, label %main
worker:
  %k = lshr i64 %off, 26
  %s = add i64 %k, 1
  ret i64 %s
}

; 1 once a worker has started.
define i1 @rg_is_mt() alwaysinline {
  %mt = load i32, ptr @rg_mt, align 4
  %r = icmp ne i32 %mt, 0
  ret i1 %r
}

; ── Counts and counters ──────────────────────────────────────

; One reference more at address a: the update is atomic once there are threads.
define void @rg_rc_inc(i64 %a) alwaysinline {
entry:
  %p = inttoptr i64 %a to ptr
  %mt = load i32, ptr @rg_mt, align 4
  %multi = icmp ne i32 %mt, 0
  br i1 %multi, label %atomic, label %plain
atomic:
  %o = atomicrmw add ptr %p, i64 1 monotonic
  ret void
plain:
  %v = load i64, ptr %p, align 8
  %v1 = add i64 %v, 1
  store i64 %v1, ptr %p, align 8
  ret void
}

; One reference less at address a: the new count.
define i64 @rg_rc_dec(i64 %a) alwaysinline {
entry:
  %p = inttoptr i64 %a to ptr
  %mt = load i32, ptr @rg_mt, align 4
  %multi = icmp ne i32 %mt, 0
  br i1 %multi, label %atomic, label %plain
atomic:
  %o = atomicrmw sub ptr %p, i64 1 acq_rel
  %n = sub i64 %o, 1
  ret i64 %n
plain:
  %v = load i64, ptr %p, align 8
  %v1 = sub i64 %v, 1
  store i64 %v1, ptr %p, align 8
  ret i64 %v1
}

; A counter at address a changes by d.
define void @rg_count_add(i64 %a, i64 %d) alwaysinline {
entry:
  %p = inttoptr i64 %a to ptr
  %mt = load i32, ptr @rg_mt, align 4
  %multi = icmp ne i32 %mt, 0
  br i1 %multi, label %atomic, label %plain
atomic:
  %o = atomicrmw add ptr %p, i64 %d monotonic
  ret void
plain:
  %v = load i64, ptr %p, align 8
  %v1 = add i64 %v, %d
  store i64 %v1, ptr %p, align 8
  ret void
}

; The count of live blocks (builtin 5, the leak tests). One counter per slot,
; each on its own cache line and changed only by its owner thread, so the
; counting never makes threads share a cache line; a block freed by another
; thread than the one that made it leaves a negative count in that slot, and
; the total is the sum.
@rg_live = global [72 x i64] zeroinitializer

define void @rg_live_add(i64 %d) alwaysinline {
  %s = call i64 @rg_slot()
  %i = shl i64 %s, 3
  %p = getelementptr inbounds [72 x i64], ptr @rg_live, i64 0, i64 %i
  %v = load i64, ptr %p, align 8
  %v1 = add i64 %v, %d
  store i64 %v1, ptr %p, align 8
  ret void
}

define i64 @rg_live_total() {
entry:
  br label %loop
loop:
  %s = phi i64 [ 0, %entry ], [ %s1, %loop ]
  %t = phi i64 [ 0, %entry ], [ %t1, %loop ]
  %i = shl i64 %s, 3
  %p = getelementptr inbounds [72 x i64], ptr @rg_live, i64 0, i64 %i
  %v = load i64, ptr %p, align 8
  %t1 = add i64 %t, %v
  %s1 = add i64 %s, 1
  %more = icmp slt i64 %s1, 9
  br i1 %more, label %loop, label %done
done:
  ret i64 %t1
}

; ── Mutex (a futex word: 0 free, 1 held, 2 held with waiters) ──
define void @rg_lock(i64 %a) {
entry:
  %p = inttoptr i64 %a to ptr
  %c0 = cmpxchg ptr %p, i32 0, i32 1 acquire monotonic
  %ok0 = extractvalue { i32, i1 } %c0, 1
  br i1 %ok0, label %done, label %spin
spin:
  %i = phi i32 [ 0, %entry ], [ %i1, %spinagain ]
  %cs = cmpxchg ptr %p, i32 0, i32 1 acquire monotonic
  %oks = extractvalue { i32, i1 } %cs, 1
  br i1 %oks, label %done, label %spinagain
spinagain:
  %i1 = add i32 %i, 1
  %more = icmp ult i32 %i1, 100
  br i1 %more, label %spin, label %slow
slow:
  br label %wait
wait:
  %x = atomicrmw xchg ptr %p, i32 2 acquire
  %free = icmp eq i32 %x, 0
  br i1 %free, label %done, label %sleep
sleep:
  %r = call i64 @__rg_pal_futex_wait(i64 %a, i64 2, i64 -1)
  br label %wait
done:
  ret void
}

define void @rg_unlock(i64 %a) {
entry:
  %p = inttoptr i64 %a to ptr
  %o = atomicrmw xchg ptr %p, i32 0 release
  %waiters = icmp eq i32 %o, 2
  br i1 %waiters, label %wake, label %done
wake:
  %w = call i64 @__rg_pal_futex_wake(i64 %a, i64 1)
  br label %done
done:
  ret void
}

; ── Starting a thread ────────────────────────────────────────
; rg_thread_start (entry, arg): runs entry(arg) on a new thread with a stack
; of its own; gives its slot (1 .. 8), or a negative number when there is no
; free slot or the system refuses. The caller gives the slot back with
; rg_thread_release when the thread has ended.
define i64 @rg_thread_start(i64 %fnp, i64 %arg) {
entry:
  %base0 = load i64, ptr @rg_pool_base, align 8
  %has = icmp ne i64 %base0, 0
  br i1 %has, label %claim, label %region
region:
  %m = call i64 @__rg_pal_alloc_chunk(i64 536870912)
  %mfail = icmp eq i64 %m, 0
  br i1 %mfail, label %nomem, label %publish
nomem:
  ret i64 -12
publish:
  %cx = cmpxchg ptr @rg_pool_base, i64 0, i64 %m seq_cst seq_cst
  br label %claim
claim:
  br label %scan
scan:
  %k = phi i64 [ 1, %claim ], [ %k1, %scannext ]
  %kk = icmp ule i64 %k, 8
  br i1 %kk, label %try, label %full
try:
  %bp = getelementptr inbounds [9 x i32], ptr @rg_pool_busy, i64 0, i64 %k
  %cs = cmpxchg ptr %bp, i32 0, i32 1 acquire monotonic
  %got = extractvalue { i32, i1 } %cs, 1
  br i1 %got, label %start, label %scannext
scannext:
  %k1 = add i64 %k, 1
  br label %scan
full:
  ret i64 -11
start:
  store atomic i32 1, ptr @rg_mt seq_cst, align 4
  %base = load i64, ptr @rg_pool_base, align 8
  %top0 = shl i64 %k, 26
  %top = add i64 %base, %top0
  %r = call i64 @__rg_pal_thread_spawn(i64 %fnp, i64 %arg, i64 %top)
  %bad = icmp slt i64 %r, 0
  br i1 %bad, label %release, label %ok
release:
  store atomic i32 0, ptr %bp release, align 4
  ret i64 %r
ok:
  ret i64 %k
}

define void @rg_thread_release(i64 %k) {
  %bp = getelementptr inbounds [9 x i32], ptr @rg_pool_busy, i64 0, i64 %k
  store atomic i32 0, ptr %bp release, align 4
  ret void
}
