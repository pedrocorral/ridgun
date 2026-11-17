; ============================================================
; tests/runtime/threads.ll
; Concurrency tests of the IR runtime (ADR-0014, TASK-0096), written against
; the runtime itself: they link with the Linux runtime object, start real
; threads with rg_thread_start and check what must hold:
;   T1 shared reference counts end where they began after 8 threads clone
;      and drop one object 400 000 times each
;   T2 the mutex gives exact totals (8 threads, 200 000 increments each)
;   T3 every thread has its own slot, slot 0 stays the main thread's
;   T4 blocks allocated by one thread and freed by another keep their
;      contents and the live count returns to its start
;   T5 threads start, end and their slots are reused in 50 rounds
;   T6 channel builtins from 4 producers and 4 consumers: nothing lost, nothing
;      twice, FIFO per producer
;   T7 jobs on worker threads: 40 jobs give 2 * x, some ran on a worker, poll
;      sees the end, handles dropped before the end leak nothing, a job
;      started on a worker runs inline
; Run: sh tests/runtime/run-threads.sh  (exit 0 and "all passed")
; ============================================================

declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare i64 @rg_obj(i64, i64, i64)
declare i64 @__rg_rt_clone_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare i64 @rg_rc(i64)
declare i64 @rg_slot()
declare i64 @rg_thread_start(i64, i64)
declare void @rg_thread_release(i64)
declare void @rg_lock(i64)
declare void @rg_unlock(i64)
declare void @__rg_pal_yield()
declare i64 @__rg_pal_write(i64, i64, i64)
declare void @__rg_pal_exit(i64)
declare i64 @__rg_pal_thread_id()
declare i64 @__rg_rt_builtin(i64, i64, i64)
declare i64 @__rg_rt_match_adt(i64, ptr, i64, i64)
declare i64 @__rg_rt_adt_field(i64, i64)
@str_Ok = private constant [2 x i8] c"Ok"

declare i64 @rg_live_total()

@drv_page0 = global { ptr, ptr, ptr, ptr, [3936 x i8] } { ptr @drv_main, ptr @drv_spawn, ptr @drv_main, ptr @drv_main, [3936 x i8] zeroinitializer }, section ".rg_page0", align 8

; Shared state of one test: [0] object, [1] done counter, [2] lock word,
; [3] total, [4] the slot table (9 words), [14] mailbox (64 words).
@st = internal global [128 x i64] zeroinitializer

@msg_ok = private constant [4 x i8] c"ok T"
@msg_fail = private constant [8 x i8] c"FAILED T"
@msg_all = private constant [11 x i8] c"all passed\0A"

define internal void @say(ptr %m, i64 %len, i64 %n) {
  %b = alloca [2 x i8], align 1
  %d = add i64 %n, 48
  %d8 = trunc i64 %d to i8
  store i8 %d8, ptr %b, align 1
  %nl = getelementptr inbounds [2 x i8], ptr %b, i64 0, i64 1
  store i8 10, ptr %nl, align 1
  %ma = ptrtoint ptr %m to i64
  %w1 = call i64 @__rg_pal_write(i64 1, i64 %ma, i64 %len)
  %ba = ptrtoint ptr %b to i64
  %w2 = call i64 @__rg_pal_write(i64 1, i64 %ba, i64 2)
  ret void
}

define internal i64 @cell(i64 %i) {
  %p = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 %i
  %a = ptrtoint ptr %p to i64
  ret i64 %a
}

; Wait until the done counter (word 1) reaches n.
define internal void @wait_done(i64 %n) {
entry:
  %p = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 1
  br label %loop
loop:
  %v = load atomic i64, ptr %p acquire, align 8
  %ok = icmp sge i64 %v, %n
  br i1 %ok, label %done, label %y
y:
  call void @__rg_pal_yield()
  br label %loop
done:
  ret void
}

define internal void @finish() {
  %p = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 1
  %o = atomicrmw add ptr %p, i64 1 release
  ret void
}

define internal void @reset() {
  call void @llvm.memset.p0.i64(ptr @st, i8 0, i64 1024, i1 false)
  ret void
}
declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)

; Start n threads on entry, remembering their slots in the table; waits for them.
define internal i64 @run_threads(i64 %fnp, i64 %n) {
entry:
  %slots = alloca [8 x i64], align 8
  br label %start
start:
  %i = phi i64 [ 0, %entry ], [ %i1, %started ]
  %m = icmp slt i64 %i, %n
  br i1 %m, label %go, label %wait
go:
  %k = call i64 @rg_thread_start(i64 %fnp, i64 %i)
  %bad = icmp slt i64 %k, 0
  br i1 %bad, label %fail, label %started
started:
  %sp = getelementptr inbounds [8 x i64], ptr %slots, i64 0, i64 %i
  store i64 %k, ptr %sp, align 8
  %i1 = add i64 %i, 1
  br label %start
wait:
  call void @wait_done(i64 %n)
  br label %rel
rel:
  %j = phi i64 [ 0, %wait ], [ %j1, %relb ]
  %jm = icmp slt i64 %j, %n
  br i1 %jm, label %relb, label %ok
relb:
  %jp = getelementptr inbounds [8 x i64], ptr %slots, i64 0, i64 %j
  %jk = load i64, ptr %jp, align 8
  call void @rg_thread_release(i64 %jk)
  %j1 = add i64 %j, 1
  br label %rel
ok:
  ret i64 1
fail:
  ret i64 0
}

; ── T1 ───────────────────────────────────────────────────────
define void @t1_worker(i64 %id) {
entry:
  %op = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 0
  %o = load i64, ptr %op, align 8
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  %c = call i64 @__rg_rt_clone_slot(i64 %o)
  %d = call i64 @__rg_rt_drop_val(i64 %c)
  %i1 = add i64 %i, 1
  %more = icmp slt i64 %i1, 400000
  br i1 %more, label %loop, label %done
done:
  call void @finish()
  ret void
}

define internal i1 @t1() {
entry:
  call void @reset()
  %live0 = call i64 @rg_live_total()
  %o = call i64 @rg_obj(i64 6, i64 0, i64 0)
  %op = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 0
  store i64 %o, ptr %op, align 8
  %ran = call i64 @run_threads(i64 ptrtoint (ptr @t1_worker to i64), i64 8)
  %rc = call i64 @rg_rc(i64 %o)
  %d = call i64 @__rg_rt_drop_val(i64 %o)
  %live1 = call i64 @rg_live_total()
  %a = icmp eq i64 %ran, 1
  %b = icmp eq i64 %rc, 1
  %c = icmp eq i64 %live0, %live1
  %ab = and i1 %a, %b
  %abc = and i1 %ab, %c
  ret i1 %abc
}

; ── T2 ───────────────────────────────────────────────────────
define void @t2_worker(i64 %id) {
entry:
  %lock = call i64 @cell(i64 2)
  %tp = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %loop ]
  call void @rg_lock(i64 %lock)
  %v = load i64, ptr %tp, align 8
  %v1 = add i64 %v, 1
  store i64 %v1, ptr %tp, align 8
  call void @rg_unlock(i64 %lock)
  %i1 = add i64 %i, 1
  %more = icmp slt i64 %i1, 200000
  br i1 %more, label %loop, label %done
done:
  call void @finish()
  ret void
}

define internal i1 @t2() {
  call void @reset()
  %ran = call i64 @run_threads(i64 ptrtoint (ptr @t2_worker to i64), i64 8)
  %tp = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  %t = load i64, ptr %tp, align 8
  %a = icmp eq i64 %ran, 1
  %b = icmp eq i64 %t, 1600000
  %r = and i1 %a, %b
  ret i1 %r
}

; ── T3 ───────────────────────────────────────────────────────
define void @t3_worker(i64 %id) {
  %s = call i64 @rg_slot()
  %i = add i64 %id, 4
  %p = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 %i
  store i64 %s, ptr %p, align 8
  call void @finish()
  ret void
}

define internal i1 @t3() {
entry:
  call void @reset()
  %ran = call i64 @run_threads(i64 ptrtoint (ptr @t3_worker to i64), i64 8)
  %main = call i64 @rg_slot()
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %seen = phi i64 [ 0, %entry ], [ %seen2, %next ]
  %m = icmp slt i64 %i, 8
  br i1 %m, label %body, label %done
body:
  %ci = add i64 %i, 4
  %p = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 %ci
  %s = load i64, ptr %p, align 8
  %ge = icmp sge i64 %s, 1
  %le = icmp sle i64 %s, 8
  %inr = and i1 %ge, %le
  %bit = shl i64 1, %s
  %had = and i64 %seen, %bit
  %fresh = icmp eq i64 %had, 0
  %good = and i1 %inr, %fresh
  br i1 %good, label %next, label %bad
next:
  %seen2 = or i64 %seen, %bit
  %i1 = add i64 %i, 1
  br label %loop
bad:
  ret i1 false
done:
  %a = icmp eq i64 %ran, 1
  %b = icmp eq i64 %main, 0
  %r = and i1 %a, %b
  ret i1 %r
}

; ── T4 ──────────────────────────────────────────────────────
; Threads 0-3 allocate blocks of mixed sizes (24 bytes to 3 KB), fill every
; word with a pattern and hand them to threads 4-7 through a mailbox of 16
; cells per pair (words 14 + 16 * pair + cell); the consumer checks every
; word and frees the block, so each block is freed by another thread than
; the one that allocated it. Each producer makes 4 000 blocks. Errors are
; counted in word 3.
define internal void @fill(i64 %b, i64 %words, i64 %pat) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %m = icmp slt i64 %i, %words
  br i1 %m, label %body, label %done
body:
  %o = shl i64 %i, 3
  %a = add i64 %b, %o
  %p = inttoptr i64 %a to ptr
  %v = add i64 %pat, %i
  store i64 %v, ptr %p, align 8
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

define internal i1 @check(i64 %b, i64 %words, i64 %pat) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %m = icmp slt i64 %i, %words
  br i1 %m, label %body, label %ok
body:
  %o = shl i64 %i, 3
  %a = add i64 %b, %o
  %p = inttoptr i64 %a to ptr
  %v = load i64, ptr %p, align 8
  %want = add i64 %pat, %i
  %same = icmp eq i64 %v, %want
  %i1 = add i64 %i, 1
  br i1 %same, label %loop, label %bad
ok:
  ret i1 true
bad:
  ret i1 false
}

define internal i64 @cell_ptr(i64 %pair, i64 %j) {
  %a = mul i64 %pair, 16
  %b = add i64 %a, 14
  %c = add i64 %b, %j
  %p = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 %c
  %r = ptrtoint ptr %p to i64
  ret i64 %r
}

define void @t4_worker(i64 %id) {
entry:
  %prod = icmp slt i64 %id, 4
  br i1 %prod, label %p, label %c
p:
  br label %ploop
ploop:
  %i = phi i64 [ 0, %p ], [ %i1, %pput ]
  %m = icmp slt i64 %i, 4000
  br i1 %m, label %pb, label %pdone
pb:
  %j = and i64 %i, 15
  %cp = call i64 @cell_ptr(i64 %id, i64 %j)
  %cpp = inttoptr i64 %cp to ptr
  br label %pwait
pwait:
  %cv = load atomic i64, ptr %cpp acquire, align 8
  %empty = icmp eq i64 %cv, 0
  br i1 %empty, label %palloc, label %pyield
pyield:
  call void @__rg_pal_yield()
  br label %pwait
palloc:
  %s0 = and i64 %i, 7
  %s1 = shl i64 1, %s0
  %words = mul i64 %s1, 3
  %bytes = shl i64 %words, 3
  %b = call i64 @rg_alloc(i64 %bytes)
  %pat0 = mul i64 %i, 7
  %pat = add i64 %pat0, %id
  call void @fill(i64 %b, i64 %words, i64 %pat)
  store atomic i64 %b, ptr %cpp release, align 8
  br label %pput
pput:
  %i1 = add i64 %i, 1
  br label %ploop
pdone:
  call void @finish()
  ret void
c:
  %pair = sub i64 %id, 4
  br label %cloop
cloop:
  %ci = phi i64 [ 0, %c ], [ %ci1, %cnext ]
  %cm = icmp slt i64 %ci, 4000
  br i1 %cm, label %cb, label %cdone
cb:
  %cj = and i64 %ci, 15
  %ccp = call i64 @cell_ptr(i64 %pair, i64 %cj)
  %ccpp = inttoptr i64 %ccp to ptr
  br label %cwait
cwait:
  %blk = load atomic i64, ptr %ccpp acquire, align 8
  %has = icmp ne i64 %blk, 0
  br i1 %has, label %ctake, label %cyield
cyield:
  call void @__rg_pal_yield()
  br label %cwait
ctake:
  store atomic i64 0, ptr %ccpp release, align 8
  %cs0 = and i64 %ci, 7
  %cs1 = shl i64 1, %cs0
  %cwords = mul i64 %cs1, 3
  %cpat0 = mul i64 %ci, 7
  %cpat = add i64 %cpat0, %pair
  %ok = call i1 @check(i64 %blk, i64 %cwords, i64 %cpat)
  call void @rg_free(i64 %blk)
  br i1 %ok, label %cnext, label %cbad
cbad:
  %ep = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  %eo = atomicrmw add ptr %ep, i64 1 monotonic
  br label %cnext
cnext:
  %ci1 = add i64 %ci, 1
  br label %cloop
cdone:
  call void @finish()
  ret void
}

define internal i1 @t4() {
  call void @reset()
  %live0 = call i64 @rg_live_total()
  %ran = call i64 @run_threads(i64 ptrtoint (ptr @t4_worker to i64), i64 8)
  %ep = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  %errors = load i64, ptr %ep, align 8
  %a = icmp eq i64 %ran, 1
  %b = icmp eq i64 %errors, 0
  %r = and i1 %a, %b
  ret i1 %r
}

; ── T6 ──────────────────────────────────────────────────────
; Channel builtins from 4 producers and 4 consumers at once: each producer
; sends 20 000 Ints (producer * 1 000 000 + i) to one channel (builtin 50);
; the consumers take items with the non-blocking receive (builtin 33) until
; 80 000 have been taken. Checks: the sum of what was taken, that no value
; came twice (sum of squares as a second witness), and that each consumer
; saw every producer's values in increasing order. Errors go to word 3, the
; taken count to word 5, the sums to words 6 and 7.
define void @t6_worker(i64 %id) {
entry:
  %chp = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 0
  %ch = load i64, ptr %chp, align 8
  %slots = alloca [2 x i64], align 8
  %sa = ptrtoint ptr %slots to i64
  %s1 = getelementptr inbounds [2 x i64], ptr %slots, i64 0, i64 1
  %prod = icmp slt i64 %id, 4
  br i1 %prod, label %p, label %c
p:
  br label %ploop
ploop:
  %i = phi i64 [ 0, %p ], [ %i1, %pb ]
  %m = icmp slt i64 %i, 20000
  br i1 %m, label %pb, label %pdone
pb:
  %v0 = mul i64 %id, 1000000
  %v = add i64 %v0, %i
  %vt = shl i64 %v, 1
  %vi = or i64 %vt, 1
  %chc = call i64 @__rg_rt_clone_slot(i64 %ch)
  store i64 %vi, ptr %slots, align 8
  store i64 %chc, ptr %s1, align 8
  %r = call i64 @__rg_rt_builtin(i64 50, i64 %sa, i64 2)
  %i1 = add i64 %i, 1
  br label %ploop
pdone:
  call void @finish()
  ret void
c:
  %last = alloca [4 x i64], align 8
  call void @llvm.memset.p0.i64(ptr %last, i8 -1, i64 32, i1 false)
  %tp = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 5
  br label %cloop
cloop:
  %taken = load atomic i64, ptr %tp acquire, align 8
  %more = icmp slt i64 %taken, 80000
  br i1 %more, label %try, label %cdone
try:
  %chc2 = call i64 @__rg_rt_clone_slot(i64 %ch)
  store i64 %chc2, ptr %slots, align 8
  %rr = call i64 @__rg_rt_builtin(i64 33, i64 %sa, i64 1)
  %ok = call i64 @__rg_rt_match_adt(i64 %rr, ptr @str_Ok, i64 2, i64 1)
  %has = icmp ne i64 %ok, 0
  br i1 %has, label %got, label %empty
empty:
  %dr = call i64 @__rg_rt_drop_val(i64 %rr)
  call void @__rg_pal_yield()
  br label %cloop
got:
  %item = call i64 @__rg_rt_adt_field(i64 %rr, i64 0)
  %dr2 = call i64 @__rg_rt_drop_val(i64 %rr)
  %cv = ashr i64 %item, 1
  %pr = udiv i64 %cv, 1000000
  %seq = urem i64 %cv, 1000000
  %lp = getelementptr inbounds [4 x i64], ptr %last, i64 0, i64 %pr
  %lv = load i64, ptr %lp, align 8
  %inc = icmp sgt i64 %seq, %lv
  store i64 %seq, ptr %lp, align 8
  br i1 %inc, label %count, label %order
order:
  %ep = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  %eo = atomicrmw add ptr %ep, i64 1 monotonic
  br label %count
count:
  %s6 = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 6
  %o6 = atomicrmw add ptr %s6, i64 %cv monotonic
  %sq = mul i64 %seq, %seq
  %s7 = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 7
  %o7 = atomicrmw add ptr %s7, i64 %sq monotonic
  %tk = atomicrmw add ptr %tp, i64 1 release
  br label %cloop
cdone:
  call void @finish()
  ret void
}

define internal i1 @t6() {
entry:
  call void @reset()
  %slots = alloca [2 x i64], align 8
  %sa = ptrtoint ptr %slots to i64
  %r = call i64 @__rg_rt_builtin(i64 1, i64 %sa, i64 0)
  %chp = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 0
  store i64 %r, ptr %chp, align 8
  %ran = call i64 @run_threads(i64 ptrtoint (ptr @t6_worker to i64), i64 8)
  %ep = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  %errors = load i64, ptr %ep, align 8
  %tp = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 5
  %taken = load i64, ptr %tp, align 8
  %s6 = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 6
  %sum = load i64, ptr %s6, align 8
  %s7 = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 7
  %sq = load i64, ptr %s7, align 8
  ; producers 0..3, i in 0..19999: sum = 20000 * 1000000 * (0+1+2+3) + 4 * (19999 * 20000 / 2)
  %want_sum = add i64 120000000000, 799960000
  ; sum of i^2 for i in 0..19999, four times
  %want_sq = mul i64 4, 2666466670000
  %a = icmp eq i64 %ran, 1
  %b = icmp eq i64 %errors, 0
  %c = icmp eq i64 %taken, 80000
  %d = icmp eq i64 %sum, %want_sum
  %e = icmp eq i64 %sq, %want_sq
  %ab = and i1 %a, %b
  %cd = and i1 %c, %d
  %abcd = and i1 %ab, %cd
  %all = and i1 %abcd, %e
  ret i1 %all
}

; ── T7 ──────────────────────────────────────────────────────
; The spawn dispatcher of this program: args = [function, argument]. The
; argument is a tagged Int x: the job busies itself a little, counts itself
; (words 8 and 9: jobs done, jobs that ran on a worker) and gives 2 * x; for
; x >= 1000 it starts another job (x - 1000) itself and adds its answer.
define i64 @drv_spawn(ptr %args) {
entry:
  %xp = getelementptr inbounds i64, ptr %args, i64 1
  %xt = load i64, ptr %xp, align 8
  %x = ashr i64 %xt, 1
  br label %busy
busy:
  %i = phi i64 [ 0, %entry ], [ %i1, %busy ]
  %acc = phi i64 [ 0, %entry ], [ %acc1, %busy ]
  %acc1 = add i64 %acc, %i
  %i1 = add i64 %i, 1
  %more = icmp slt i64 %i1, 20000
  br i1 %more, label %busy, label %count
count:
  %slot = call i64 @rg_slot()
  %onw = icmp ne i64 %slot, 0
  %inc = zext i1 %onw to i64
  %w9 = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 9
  %o9 = atomicrmw add ptr %w9, i64 %inc monotonic
  %big = icmp sge i64 %x, 1000
  br i1 %big, label %nested, label %plain
nested:
  %inner = sub i64 %x, 1000
  %it = shl i64 %inner, 1
  %iv = or i64 %it, 1
  %ss = alloca [2 x i64], align 8
  %ssa = ptrtoint ptr %ss to i64
  store i64 1, ptr %ss, align 8
  %s1 = getelementptr inbounds [2 x i64], ptr %ss, i64 0, i64 1
  store i64 %iv, ptr %s1, align 8
  %h = call i64 @__rg_rt_builtin(i64 57, i64 %ssa, i64 2)
  store i64 %h, ptr %ss, align 8
  %r = call i64 @__rg_rt_builtin(i64 59, i64 %ssa, i64 1)
  %rv = ashr i64 %r, 1
  %sum = add i64 %rv, %inner
  %sumt = shl i64 %sum, 1
  %sumv = or i64 %sumt, 1
  call void @job_end()
  ret i64 %sumv
plain:
  %d = shl i64 %x, 1
  %dt = shl i64 %d, 1
  %dv = or i64 %dt, 1
  call void @job_end()
  ret i64 %dv
}

define internal void @job_end() {
  %w8 = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 8
  %o8 = atomicrmw add ptr %w8, i64 1 release
  ret void
}

define internal i1 @t7() {
entry:
  call void @reset()
  %live0 = call i64 @rg_live_total()
  %hs = alloca [40 x i64], align 8
  %ss = alloca [2 x i64], align 8
  %ssa = ptrtoint ptr %ss to i64
  %s1 = getelementptr inbounds [2 x i64], ptr %ss, i64 0, i64 1
  br label %spawn
spawn:
  %i = phi i64 [ 0, %entry ], [ %i1, %spawnb ]
  %m = icmp slt i64 %i, 40
  br i1 %m, label %spawnb, label %collect
spawnb:
  %it = shl i64 %i, 1
  %iv = or i64 %it, 1
  store i64 1, ptr %ss, align 8
  store i64 %iv, ptr %s1, align 8
  %h = call i64 @__rg_rt_builtin(i64 57, i64 %ssa, i64 2)
  %hp = getelementptr inbounds [40 x i64], ptr %hs, i64 0, i64 %i
  store i64 %h, ptr %hp, align 8
  %i1 = add i64 %i, 1
  br label %spawn
collect:
  br label %cl
cl:
  %j = phi i64 [ 0, %collect ], [ %j1, %clb ]
  %okc = phi i1 [ true, %collect ], [ %okc2, %clb ]
  %jm = icmp slt i64 %j, 40
  br i1 %jm, label %clb, label %polled
clb:
  %jp = getelementptr inbounds [40 x i64], ptr %hs, i64 0, i64 %j
  %jh = load i64, ptr %jp, align 8
  store i64 %jh, ptr %ss, align 8
  %r = call i64 @__rg_rt_builtin(i64 59, i64 %ssa, i64 1)
  %want0 = shl i64 %j, 2
  %want = or i64 %want0, 1
  %same = icmp eq i64 %r, %want
  %okc2 = and i1 %okc, %same
  %j1 = add i64 %j, 1
  br label %cl
polled:
  ; poll: a job is seen to end; the handle is cloned for the poll (it takes one)
  store i64 1, ptr %ss, align 8
  store i64 201, ptr %s1, align 8
  %ph = call i64 @__rg_rt_builtin(i64 57, i64 %ssa, i64 2)
  br label %ploop
ploop:
  %pc = call i64 @__rg_rt_clone_slot(i64 %ph)
  store i64 %pc, ptr %ss, align 8
  %pr = call i64 @__rg_rt_builtin(i64 58, i64 %ssa, i64 1)
  %ended = icmp eq i64 %pr, 6
  br i1 %ended, label %pdone, label %pyield
pyield:
  call void @__rg_pal_yield()
  br label %ploop
pdone:
  store i64 %ph, ptr %ss, align 8
  %pa = call i64 @__rg_rt_builtin(i64 59, i64 %ssa, i64 1)
  %pok = icmp eq i64 %pa, 401
  ; handles dropped before the end of 20 jobs
  br label %dl
dl:
  %k = phi i64 [ 0, %pdone ], [ %k1, %dlb ]
  %km = icmp slt i64 %k, 20
  br i1 %km, label %dlb, label %waitd
dlb:
  %kt = shl i64 %k, 1
  %kv = or i64 %kt, 1
  store i64 1, ptr %ss, align 8
  store i64 %kv, ptr %s1, align 8
  %dh = call i64 @__rg_rt_builtin(i64 57, i64 %ssa, i64 2)
  %dd = call i64 @__rg_rt_drop_val(i64 %dh)
  %k1 = add i64 %k, 1
  br label %dl
waitd:
  ; 40 + 1 + 20 jobs in all
  br label %wl
wl:
  %w8 = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 8
  %dn = load atomic i64, ptr %w8 acquire, align 8
  %all = icmp sge i64 %dn, 61
  br i1 %all, label %nest, label %wy
wy:
  call void @__rg_pal_yield()
  br label %wl
nest:
  ; a job started from the main thread that starts another inside it
  store i64 1, ptr %ss, align 8
  store i64 2011, ptr %s1, align 8
  %nh = call i64 @__rg_rt_builtin(i64 57, i64 %ssa, i64 2)
  store i64 %nh, ptr %ss, align 8
  %nr = call i64 @__rg_rt_builtin(i64 59, i64 %ssa, i64 1)
  ; x = 1005: the inner job (x - 1000 = 5) gives 2 * 5 = 10, the sum with 5 is 15, tagged 31
  %nok = icmp eq i64 %nr, 31
  %onw = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 9
  %ran = load i64, ptr %onw, align 8
  %ranok = icmp sgt i64 %ran, 0
  %live1 = call i64 @rg_live_total()
  %liveok = icmp eq i64 %live0, %live1
  %a = and i1 %okc, %pok
  %b = and i1 %a, %ranok
  %c0 = and i1 %b, %liveok
  %c = and i1 %c0, %nok
  ret i1 %c
}

; ── T8 ──────────────────────────────────────────────────────
; Builtin 51 (receive with timeout) on an empty channel waits about the time
; asked and gives Err; with an item it gives Ok at once.
declare i64 @__rg_pal_clock_ns(i64)
@str_Ok2 = private constant [2 x i8] c"Ok"

define internal i1 @t8() {
entry:
  %ss = alloca [2 x i64], align 8
  %ssa = ptrtoint ptr %ss to i64
  %s1 = getelementptr inbounds [2 x i64], ptr %ss, i64 0, i64 1
  %cs = alloca [2 x i64], align 8
  %csa = ptrtoint ptr %cs to i64
  %ch = call i64 @__rg_rt_builtin(i64 1, i64 %csa, i64 0)
  ; 60 ms on an empty channel
  store i64 %ch, ptr %ss, align 8
  store i64 121, ptr %s1, align 8
  %t0 = call i64 @__rg_pal_clock_ns(i64 0)
  %r0 = call i64 @__rg_rt_builtin(i64 51, i64 %ssa, i64 2)
  %t1 = call i64 @__rg_pal_clock_ns(i64 0)
  %el = sub i64 %t1, %t0
  %long = icmp sge i64 %el, 50000000
  %short = icmp slt i64 %el, 1000000000
  %isok0 = call i64 @__rg_rt_match_adt(i64 %r0, ptr @str_Ok2, i64 2, i64 1)
  %notok = icmp eq i64 %isok0, 0
  ; an item in the channel: Ok at once
  store i64 15, ptr %ss, align 8
  store i64 %ch, ptr %s1, align 8
  %sent = call i64 @__rg_rt_builtin(i64 50, i64 %ssa, i64 2)
  store i64 %ch, ptr %ss, align 8
  store i64 121, ptr %s1, align 8
  %r1 = call i64 @__rg_rt_builtin(i64 51, i64 %ssa, i64 2)
  %isok1 = call i64 @__rg_rt_match_adt(i64 %r1, ptr @str_Ok2, i64 2, i64 1)
  %ok1 = icmp ne i64 %isok1, 0
  %a = and i1 %long, %short
  %b = and i1 %a, %notok
  %c = and i1 %b, %ok1
  ret i1 %c
}

; ── T9 ──────────────────────────────────────────────────────
; Builtin 98 (receive this thread's reply, with the fallback): an item addressed
; to another thread (a pair whose tag is neither this thread's nor Int 3) is
; never taken; a plain reply (tag Int 3) and a value that is not a pair are
; (Vonkeep request 3: answers reached the wrong caller).
define internal i1 @t9() {
entry:
  %cs = alloca [2 x i64], align 8
  %csa = ptrtoint ptr %cs to i64
  %ss = alloca [2 x i64], align 8
  %ssa = ptrtoint ptr %ss to i64
  %s1 = getelementptr inbounds [2 x i64], ptr %ss, i64 0, i64 1
  %vals = alloca [2 x i64], align 8
  %va = ptrtoint ptr %vals to i64
  %v1 = getelementptr inbounds [2 x i64], ptr %vals, i64 0, i64 1
  %ch = call i64 @__rg_rt_builtin(i64 1, i64 %csa, i64 0)
  ; an item addressed to another thread: tag Int 123456 (tagged), payload 9
  store i64 246913, ptr %vals, align 8
  store i64 19, ptr %v1, align 8
  %other = call i64 @__rg_rt_make_tuple(i64 %va, i64 2)
  store i64 %other, ptr %ss, align 8
  store i64 %ch, ptr %s1, align 8
  %p1 = call i64 @__rg_rt_builtin(i64 50, i64 %ssa, i64 2)
  ; fallback receive (count 1): nothing may be taken
  store i64 %ch, ptr %ss, align 8
  %r1 = call i64 @__rg_rt_builtin(i64 98, i64 %ssa, i64 1)
  %none1 = icmp eq i64 %r1, 0
  ; now a plain reply (tag Int 3, payload 5): it is taken, not the other one
  store i64 7, ptr %vals, align 8
  store i64 11, ptr %v1, align 8
  %plain = call i64 @__rg_rt_make_tuple(i64 %va, i64 2)
  store i64 %plain, ptr %ss, align 8
  store i64 %ch, ptr %s1, align 8
  %p2 = call i64 @__rg_rt_builtin(i64 50, i64 %ssa, i64 2)
  store i64 %ch, ptr %ss, align 8
  %r2 = call i64 @__rg_rt_builtin(i64 98, i64 %ssa, i64 1)
  %got2 = icmp ne i64 %r2, 0
  %pay2 = call i64 @__rg_rt_tuple_get(i64 %r2, i64 1)
  %ok2 = icmp eq i64 %pay2, 11
  ; the addressed one is still there: a second fallback receive finds nothing
  store i64 %ch, ptr %ss, align 8
  %r3 = call i64 @__rg_rt_builtin(i64 98, i64 %ssa, i64 1)
  %none3 = icmp eq i64 %r3, 0
  %a = and i1 %none1, %got2
  %b = and i1 %a, %ok2
  %c = and i1 %b, %none3
  ret i1 %c
}

declare i64 @__rg_rt_make_tuple(i64, i64)
declare i64 @__rg_rt_tuple_get(i64, i64)

; ── T5 ───────────────────────────────────────────────────────
define void @t5_worker(i64 %id) {
  %p = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  %o = atomicrmw add ptr %p, i64 1 monotonic
  call void @finish()
  ret void
}

define internal i1 @t5() {
entry:
  br label %round
round:
  %r = phi i64 [ 0, %entry ], [ %r1, %next ]
  %all = phi i1 [ true, %entry ], [ %all2, %next ]
  %m = icmp slt i64 %r, 50
  br i1 %m, label %go, label %done
go:
  call void @reset()
  %ran = call i64 @run_threads(i64 ptrtoint (ptr @t5_worker to i64), i64 8)
  %tp = getelementptr inbounds [128 x i64], ptr @st, i64 0, i64 3
  %t = load i64, ptr %tp, align 8
  %a = icmp eq i64 %ran, 1
  %b = icmp eq i64 %t, 8
  %ab = and i1 %a, %b
  %all2 = and i1 %all, %ab
  br label %next
next:
  %r1 = add i64 %r, 1
  br label %round
done:
  ret i1 %all
}

define i64 @drv_main(ptr %args) {
entry:
  %r1 = call i1 @t1()
  br i1 %r1, label %o1, label %f1
o1:
  call void @say(ptr @msg_ok, i64 4, i64 1)
  br label %n2
f1:
  call void @say(ptr @msg_fail, i64 8, i64 1)
  call void @__rg_pal_exit(i64 1)
  unreachable
n2:
  %r2 = call i1 @t2()
  br i1 %r2, label %o2, label %f2
o2:
  call void @say(ptr @msg_ok, i64 4, i64 2)
  br label %n3
f2:
  call void @say(ptr @msg_fail, i64 8, i64 2)
  call void @__rg_pal_exit(i64 1)
  unreachable
n3:
  %r3 = call i1 @t3()
  br i1 %r3, label %o3, label %f3
o3:
  call void @say(ptr @msg_ok, i64 4, i64 3)
  br label %n4
f3:
  call void @say(ptr @msg_fail, i64 8, i64 3)
  call void @__rg_pal_exit(i64 1)
  unreachable
n4:
  %r4 = call i1 @t4()
  br i1 %r4, label %o4, label %f4
o4:
  call void @say(ptr @msg_ok, i64 4, i64 4)
  br label %n6
f4:
  call void @say(ptr @msg_fail, i64 8, i64 4)
  call void @__rg_pal_exit(i64 1)
  unreachable
n6:
  %r6 = call i1 @t6()
  br i1 %r6, label %o6, label %f6
o6:
  call void @say(ptr @msg_ok, i64 4, i64 6)
  br label %n8
f6:
  call void @say(ptr @msg_fail, i64 8, i64 6)
  call void @__rg_pal_exit(i64 1)
  unreachable
n7:
  %r7 = call i1 @t7()
  br i1 %r7, label %o7, label %f7
o7:
  call void @say(ptr @msg_ok, i64 4, i64 7)
  br label %end
f7:
  call void @say(ptr @msg_fail, i64 8, i64 7)
  call void @__rg_pal_exit(i64 1)
  unreachable
n8:
  %r8 = call i1 @t8()
  br i1 %r8, label %o8, label %f8
o8:
  call void @say(ptr @msg_ok, i64 4, i64 8)
  br label %n9
f8:
  call void @say(ptr @msg_fail, i64 8, i64 8)
  call void @__rg_pal_exit(i64 1)
  unreachable
n9:
  %r9 = call i1 @t9()
  br i1 %r9, label %o9, label %f9
o9:
  call void @say(ptr @msg_ok, i64 4, i64 9)
  br label %n5
f9:
  call void @say(ptr @msg_fail, i64 8, i64 9)
  call void @__rg_pal_exit(i64 1)
  unreachable
n5:
  %r5 = call i1 @t5()
  br i1 %r5, label %o5, label %f5
o5:
  call void @say(ptr @msg_ok, i64 4, i64 5)
  br label %n7
f5:
  call void @say(ptr @msg_fail, i64 8, i64 5)
  call void @__rg_pal_exit(i64 1)
  unreachable
end:
  %w = call i64 @__rg_pal_write(i64 1, i64 ptrtoint (ptr @msg_all to i64), i64 11)
  ret i64 0
}
