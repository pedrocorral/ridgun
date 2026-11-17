; ============================================================
; src/main/runtime/core/agents.ll
; Channels, jobs and the agent builtins (FR-COMP-009, FR-COMP-026 §6) for a
; runtime on one thread. The compiler lowers agents to channels and jobs
; (`lower agent call` in compiler.ridgun): an agent is (step, state
; channel, reply channel); a send runs the step as a job. On one thread a
; job runs when it is spawned, so an agent's step runs when its message
; arrives, and every value a receive waits for is already in its channel.
;
; A channel is a heap object [6, queue, head]: the queue is a value vector,
; the items waiting are those from index head to its length. A channel can
; also be named by an Int k: the global channel k (agents declared at top
; level), made on first use.
;
; Builtins (ids from `builtin call id`, behaviour from the LLVM lowering):
;   1  new channel                35 new bounded channel (no bound needed)
;   50 send (value, channel)      32 receive (count 0: the value or 0 when
;                                    empty; count 1: waits for a value)
;   33 try receive: `Ok v`, or 0 when empty
;   57 spawn job (function, argument): runs it, gives (-999999, result)
;   58 poll job: True     59 await job: the result
;   96 thread id: 1       97 send (thread id, value) through a channel
;   98 receive this thread's reply (count = take the first item when none
;      is tagged with this thread): (3, value), or 0
;   99 take this thread's job from a list: (job, rest)
; ============================================================

declare i64 @rg_ld(i64)
declare void @rg_st(i64, i64)
declare i1 @rg_is_heap(i64)
declare i1 @rg_has_tag(i64, i64)
declare i64 @rg_w1(i64)
declare i64 @rg_w2(i64)
declare i64 @rg_obj(i64, i64, i64)
declare i64 @rg_vec(i64, i64, i64)
declare i64 @rg_vcap(i64)
declare i64 @rg_vdata(i64)
declare i64 @rg_vlen(i64)
declare void @rg_vset_len(i64, i64)
declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare void @rg_copy(i64, i64, i64)
declare i64 @rg_int(i64)
declare i64 @rg_list_alloc(i64, i64)
declare i64 @rg_list_at(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_name(i64, i64)
declare i64 @rg_arg(i64, i64)
declare i64 @rg_call_fn(i64, i64)
declare i64 @rg_fn_spawn_addr()
declare i64 @__rg_rt_make_tuple(i64, i64)
declare i64 @__rg_rt_tuple_get(i64, i64)
declare i64 @__rg_rt_match_tuple(i64, i64)
declare i64 @__rg_rt_clone_slot(i64)
declare i64 @__rg_rt_drop_val(i64)
declare void @rg_fatal(ptr, i64)
declare i64 @rg_builtin_more(i64, i64, i64)

; ── Channels ─────────────────────────────────────────────────

define internal i64 @rg_chan_new() {
  %h = call i64 @rg_vec(i64 8, i64 0, i64 8)
  %c = call i64 @rg_obj(i64 6, i64 %h, i64 0)
  ret i64 %c
}

; The global channels: a block of words, one per Int name, 0 until used.
@rg_globals = internal global i64 0
@rg_nglobals = internal global i64 0

; The channel named by v (left alone): v itself, or global channel k for
; the Int k. 0 when v is neither.
define internal i64 @rg_chan_of(i64 %v) {
entry:
  %ischan = call i1 @rg_has_tag(i64 %v, i64 6)
  br i1 %ischan, label %self, label %int
self:
  ret i64 %v
int:
  %bit = and i64 %v, 1
  %isint = icmp ne i64 %bit, 0
  br i1 %isint, label %global, label %none
none:
  ret i64 0
global:
  %k = ashr i64 %v, 1
  %neg = icmp slt i64 %k, 0
  br i1 %neg, label %none, label %room
room:
  %n = load i64, ptr @rg_nglobals, align 8
  %fits = icmp slt i64 %k, %n
  br i1 %fits, label %get, label %grow
grow:
  %k1 = add i64 %k, 1
  %n2 = shl i64 %n, 1
  %big = icmp sgt i64 %k1, %n2
  %nn0 = select i1 %big, i64 %k1, i64 %n2
  %small = icmp slt i64 %nn0, 16
  %nn = select i1 %small, i64 16, i64 %nn0
  %bytes = shl i64 %nn, 3
  %nb = call i64 @rg_alloc(i64 %bytes)
  call void @rg_zero(i64 %nb, i64 %bytes)
  %old = load i64, ptr @rg_globals, align 8
  %obytes = shl i64 %n, 3
  %hasold = icmp ne i64 %old, 0
  br i1 %hasold, label %move, label %set
move:
  call void @rg_copy(i64 %nb, i64 %old, i64 %obytes)
  call void @rg_free(i64 %old)
  br label %set
set:
  store i64 %nb, ptr @rg_globals, align 8
  store i64 %nn, ptr @rg_nglobals, align 8
  br label %get
get:
  %g = load i64, ptr @rg_globals, align 8
  %off = shl i64 %k, 3
  %a = add i64 %g, %off
  %c = call i64 @rg_ld(i64 %a)
  %made = icmp ne i64 %c, 0
  br i1 %made, label %have, label %make
make:
  ; a channel named by an Int is a global agent's: the compiler's start-up
  ; code (`build gagent chan instrs`) sends Int 0 to the channel it creates
  ; for it, meaning "no sink yet", and flush and `with agent` read that first
  %c2 = call i64 @rg_chan_new()
  call void @rg_st(i64 %a, i64 %c2)
  call void @rg_chan_put(i64 %c2, i64 1)
  ret i64 %c2
have:
  ret i64 %c
}

define internal void @rg_zero(i64 %p, i64 %n) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %a = add i64 %p, %i
  call void @rg_st(i64 %a, i64 0)
  %i1 = add i64 %i, 8
  br label %loop
done:
  ret void
}

; Put v (taken) at the end of channel c's queue.
define internal void @rg_chan_put(i64 %c, i64 %v) {
entry:
  %h = call i64 @rg_w1(i64 %c)
  %len = call i64 @rg_vlen(i64 %h)
  %cap = call i64 @rg_vcap(i64 %h)
  %full = icmp sge i64 %len, %cap
  br i1 %full, label %compact, label %put
compact:
  ; move the waiting items to the front, then grow when still full
  %head = call i64 @rg_w2(i64 %c)
  %d = call i64 @rg_vdata(i64 %h)
  %n = sub i64 %len, %head
  %hoff = shl i64 %head, 3
  %src = add i64 %d, %hoff
  %nbytes = shl i64 %n, 3
  call void @rg_copy(i64 %d, i64 %src, i64 %nbytes)
  call void @rg_vset_len(i64 %h, i64 %n)
  %ha = add i64 %c, 16
  call void @rg_st(i64 %ha, i64 0)
  %still = icmp sge i64 %n, %cap
  br i1 %still, label %grow, label %put
grow:
  %cap2 = shl i64 %cap, 1
  %bytes = shl i64 %cap2, 3
  %nd = call i64 @rg_alloc(i64 %bytes)
  call void @rg_copy(i64 %nd, i64 %d, i64 %nbytes)
  call void @rg_free(i64 %d)
  call void @rg_st(i64 %h, i64 %cap2)
  %da = add i64 %h, 8
  call void @rg_st(i64 %da, i64 %nd)
  br label %put
put:
  %l2 = call i64 @rg_vlen(i64 %h)
  %dd = call i64 @rg_vdata(i64 %h)
  %off = shl i64 %l2, 3
  %at = add i64 %dd, %off
  call void @rg_st(i64 %at, i64 %v)
  %l3 = add i64 %l2, 1
  call void @rg_vset_len(i64 %h, i64 %l3)
  ret void
}

; The number of items waiting in c.
define internal i64 @rg_chan_count(i64 %c) {
  %h = call i64 @rg_w1(i64 %c)
  %len = call i64 @rg_vlen(i64 %h)
  %head = call i64 @rg_w2(i64 %c)
  %n = sub i64 %len, %head
  ret i64 %n
}

; Take the item at position i of the waiting items of c (0 = the first).
define internal i64 @rg_chan_take(i64 %c, i64 %i) {
entry:
  %h = call i64 @rg_w1(i64 %c)
  %d = call i64 @rg_vdata(i64 %h)
  %len = call i64 @rg_vlen(i64 %h)
  %head = call i64 @rg_w2(i64 %c)
  %k = add i64 %head, %i
  %off = shl i64 %k, 3
  %a = add i64 %d, %off
  %v = call i64 @rg_ld(i64 %a)
  %first = icmp eq i64 %i, 0
  br i1 %first, label %front, label %middle
front:
  call void @rg_st(i64 %a, i64 0)
  %head1 = add i64 %head, 1
  %ha = add i64 %c, 16
  %empty = icmp sge i64 %head1, %len
  br i1 %empty, label %reset, label %advance
reset:
  call void @rg_vset_len(i64 %h, i64 0)
  call void @rg_st(i64 %ha, i64 0)
  ret i64 %v
advance:
  call void @rg_st(i64 %ha, i64 %head1)
  ret i64 %v
middle:
  ; close the gap
  %k1 = add i64 %k, 1
  %soff = shl i64 %k1, 3
  %src = add i64 %d, %soff
  %rest = sub i64 %len, %k1
  %bytes = shl i64 %rest, 3
  call void @rg_copy(i64 %a, i64 %src, i64 %bytes)
  %len1 = sub i64 %len, 1
  %lasto = shl i64 %len1, 3
  %lasta = add i64 %d, %lasto
  call void @rg_st(i64 %lasta, i64 0)
  call void @rg_vset_len(i64 %h, i64 %len1)
  ret i64 %v
}

@rg_ok_name = private constant [2 x i8] c"Ok"
@rg_msg_deadlock = private constant [69 x i8] c"receive on an empty channel: nothing else can send on this one thread"

; `Ok v` (v taken).
define internal i64 @rg_ok(i64 %v) {
  %name = call i64 @rg_name(i64 ptrtoint (ptr @rg_ok_name to i64), i64 2)
  %h = call i64 @rg_vec(i64 1, i64 1, i64 8)
  %d = call i64 @rg_vdata(i64 %h)
  call void @rg_st(i64 %d, i64 %v)
  %o = call i64 @rg_obj(i64 4, i64 %name, i64 %h)
  ret i64 %o
}

; A tuple of a and b (taken).
define internal i64 @rg_pair(i64 %a, i64 %b) {
  %vals = alloca [2 x i64], align 8
  store i64 %a, ptr %vals, align 8
  %p1 = getelementptr inbounds [2 x i64], ptr %vals, i64 0, i64 1
  store i64 %b, ptr %p1, align 8
  %va = ptrtoint ptr %vals to i64
  %t = call i64 @__rg_rt_make_tuple(i64 %va, i64 2)
  ret i64 %t
}

; ── Jobs ─────────────────────────────────────────────────────

; A job that has run to its end gives (-999999, result): the form of a job
; handle whose work was done at spawn time.
define internal i64 @rg_job_inline(i64 %f, i64 %x) {
  %args = alloca [2 x i64], align 8
  store i64 %f, ptr %args, align 8
  %p1 = getelementptr inbounds [2 x i64], ptr %args, i64 0, i64 1
  store i64 %x, ptr %p1, align 8
  %d = call i64 @rg_fn_spawn_addr()
  %a = ptrtoint ptr %args to i64
  %r = call i64 @rg_call_fn(i64 %d, i64 %a)
  %tag = call i64 @rg_int(i64 -999999)
  %t = call i64 @rg_pair(i64 %tag, i64 %r)
  ret i64 %t
}

; ── Jobs on worker threads (ADR-0014, step c) ────────────────
; A job cell is four words: [state, function, argument, result]. State 0 is
; running or waiting to run, 1 is done, 2 is running with nobody holding its
; handle any more (the worker then frees the result and the cell). The
; handle of a job on a worker is a heap value with tag 7 that holds the
; address of the cell; a job that ran at once keeps the tuple form above.
;
; Workers are the threads of threads.ll (slots 1 .. 8). Each has a state
; (0 no thread, 1 idle, 2 busy), a flag word to sleep on and a mailbox for
; the cell it must run. A job goes to an idle worker, or to a new thread
; while there is a free slot, or else runs on the calling thread. A job
; started from a worker thread runs on that thread, so no job waits for a
; worker that is itself waiting.

declare i64 @rg_slot()
declare i64 @rg_thread_start(i64, i64)
declare void @rg_thread_release(i64)
declare i64 @__rg_pal_futex_wait(i64, i64, i64)
declare i64 @__rg_pal_futex_wake(i64, i64)

; Jobs on worker threads that have not ended. A receive on an empty channel
; waits while some other thread may still send, and only stops with the
; deadlock message when nothing else can run.
@rg_jobs_active = internal global i64 0

@rg_w_state = internal global [9 x i32] zeroinitializer
@rg_w_flag = internal global [9 x i32] zeroinitializer
@rg_w_box = internal global [9 x i64] zeroinitializer

; Runs the job of a cell: its result. A cell whose function is -1 is a task
; of the runtime itself (a chunk of a parallel map): its argument is the
; address of [function, argument], an IR function of one word.
define internal i64 @rg_job_run(i64 %cell) {
entry:
  %fa = add i64 %cell, 8
  %f = call i64 @rg_ld(i64 %fa)
  %xa = add i64 %cell, 16
  %x = call i64 @rg_ld(i64 %xa)
  %istask = icmp eq i64 %f, -1
  br i1 %istask, label %task, label %job
task:
  %fn = call i64 @rg_ld(i64 %x)
  %ta = add i64 %x, 8
  %arg = call i64 @rg_ld(i64 %ta)
  %fp = inttoptr i64 %fn to ptr
  call void %fp(i64 %arg)
  ret i64 0
job:
  %args = alloca [2 x i64], align 8
  store i64 %f, ptr %args, align 8
  %p1 = getelementptr inbounds [2 x i64], ptr %args, i64 0, i64 1
  store i64 %x, ptr %p1, align 8
  %d = call i64 @rg_fn_spawn_addr()
  %a = ptrtoint ptr %args to i64
  %r = call i64 @rg_call_fn(i64 %d, i64 %a)
  ret i64 %r
}

; The job is over: publish the result, or free everything when its handle is gone.
define internal void @rg_job_done(i64 %cell, i64 %result) {
entry:
  %ra = add i64 %cell, 24
  call void @rg_st(i64 %ra, i64 %result)
  %sp = inttoptr i64 %cell to ptr
  %c = cmpxchg ptr %sp, i64 0, i64 1 release monotonic
  %ok = extractvalue { i64, i1 } %c, 1
  br i1 %ok, label %wake, label %detached
wake:
  %w = call i64 @__rg_pal_futex_wake(i64 %cell, i64 2147483647)
  %o1 = atomicrmw sub ptr @rg_jobs_active, i64 1 release
  ret void
detached:
  %d = call i64 @__rg_rt_drop_val(i64 %result)
  call void @rg_free(i64 %cell)
  %o2 = atomicrmw sub ptr @rg_jobs_active, i64 1 release
  ret void
}

define void @rg_worker_main(i64 %first) {
entry:
  %slot = call i64 @rg_slot()
  %stp = getelementptr inbounds [9 x i32], ptr @rg_w_state, i64 0, i64 %slot
  %flp = getelementptr inbounds [9 x i32], ptr @rg_w_flag, i64 0, i64 %slot
  %bxp = getelementptr inbounds [9 x i64], ptr @rg_w_box, i64 0, i64 %slot
  %fla = ptrtoint ptr %flp to i64
  store atomic i32 2, ptr %stp release, align 4
  br label %run
run:
  %cell = phi i64 [ %first, %entry ], [ %next, %got ]
  %r = call i64 @rg_job_run(i64 %cell)
  call void @rg_job_done(i64 %cell, i64 %r)
  store atomic i32 1, ptr %stp release, align 4
  br label %wait
wait:
  %fl = load atomic i32, ptr %flp acquire, align 4
  %has = icmp ne i32 %fl, 0
  br i1 %has, label %got, label %sleep
sleep:
  %w = call i64 @__rg_pal_futex_wait(i64 %fla, i64 0, i64 -1)
  br label %wait
got:
  store atomic i32 0, ptr %flp release, align 4
  %next = load atomic i64, ptr %bxp acquire, align 8
  br label %run
}

; The handle of a job on a worker.
define internal i64 @rg_job_handle(i64 %cell) {
  %h = call i64 @rg_obj(i64 7, i64 %cell, i64 0)
  ret i64 %h
}

; Hands the cell to an idle worker: 1, or 0 when none is idle.
define internal i1 @rg_job_post(i64 %cell) {
entry:
  br label %scan
scan:
  %k = phi i64 [ 1, %entry ], [ %k1, %next ]
  %m = icmp ule i64 %k, 8
  br i1 %m, label %try, label %none
try:
  %stp = getelementptr inbounds [9 x i32], ptr @rg_w_state, i64 0, i64 %k
  %c = cmpxchg ptr %stp, i32 1, i32 2 acquire monotonic
  %ok = extractvalue { i32, i1 } %c, 1
  br i1 %ok, label %post, label %next
next:
  %k1 = add i64 %k, 1
  br label %scan
post:
  %bxp = getelementptr inbounds [9 x i64], ptr @rg_w_box, i64 0, i64 %k
  store atomic i64 %cell, ptr %bxp release, align 8
  %flp = getelementptr inbounds [9 x i32], ptr @rg_w_flag, i64 0, i64 %k
  store atomic i32 1, ptr %flp release, align 4
  %fla = ptrtoint ptr %flp to i64
  %w = call i64 @__rg_pal_futex_wake(i64 %fla, i64 1)
  ret i1 true
none:
  ret i1 false
}

; Gives a filled cell to a worker: an idle one, or a new thread. 1 when it
; went to a worker, 0 when the caller has to run it.
define internal i1 @rg_job_dispatch(i64 %c) {
entry:
  %a0 = atomicrmw add ptr @rg_jobs_active, i64 1 acquire
  %posted = call i1 @rg_job_post(i64 %c)
  br i1 %posted, label %yes, label %start
start:
  %t = call i64 @rg_thread_start(i64 ptrtoint (ptr @rg_worker_main to i64), i64 %c)
  %ok = icmp sgt i64 %t, 0
  br i1 %ok, label %yes, label %no
no:
  %a1 = atomicrmw sub ptr @rg_jobs_active, i64 1 release
  ret i1 false
yes:
  ret i1 true
}

; spawn (function, argument), both taken: a job handle.
define internal i64 @rg_job_spawn(i64 %f, i64 %x) {
entry:
  %slot = call i64 @rg_slot()
  %onworker = icmp ne i64 %slot, 0
  br i1 %onworker, label %inline, label %cell
cell:
  %c = call i64 @rg_alloc(i64 32)
  call void @rg_st(i64 %c, i64 0)
  %fa = add i64 %c, 8
  call void @rg_st(i64 %fa, i64 %f)
  %xa = add i64 %c, 16
  call void @rg_st(i64 %xa, i64 %x)
  %ra = add i64 %c, 24
  call void @rg_st(i64 %ra, i64 0)
  %a0 = atomicrmw add ptr @rg_jobs_active, i64 1 acquire
  %posted = call i1 @rg_job_post(i64 %c)
  br i1 %posted, label %handle, label %start
start:
  %t = call i64 @rg_thread_start(i64 ptrtoint (ptr @rg_worker_main to i64), i64 %c)
  %ok = icmp sgt i64 %t, 0
  br i1 %ok, label %handle, label %free
free:
  %a1 = atomicrmw sub ptr @rg_jobs_active, i64 1 release
  call void @rg_free(i64 %c)
  br label %inline
handle:
  %h = call i64 @rg_job_handle(i64 %c)
  ret i64 %h
inline:
  %r = call i64 @rg_job_inline(i64 %f, i64 %x)
  ret i64 %r
}

; await on a worker's handle: waits for the end, keeps the result in the
; handle (its second word; the first word becomes 0) and gives a copy of it.
; Like the tuple form, the handle can be awaited again and each time gives
; the same result; the one reference this call was given is dropped.
define internal i64 @rg_job_await(i64 %h) {
entry:
  %cell = call i64 @rg_w1(i64 %h)
  %fin = icmp eq i64 %cell, 0
  br i1 %fin, label %give, label %wait
wait:
  %sp = inttoptr i64 %cell to ptr
  %s = load atomic i64, ptr %sp acquire, align 8
  %done = icmp eq i64 %s, 1
  br i1 %done, label %take, label %sleep
sleep:
  %w = call i64 @__rg_pal_futex_wait(i64 %cell, i64 0, i64 -1)
  br label %wait
take:
  %ra = add i64 %cell, 24
  %r = call i64 @rg_ld(i64 %ra)
  call void @rg_free(i64 %cell)
  %h1 = add i64 %h, 8
  call void @rg_st(i64 %h1, i64 0)
  %h2 = add i64 %h, 16
  call void @rg_st(i64 %h2, i64 %r)
  br label %give
give:
  %h2g = add i64 %h, 16
  %res = call i64 @rg_ld(i64 %h2g)
  %copy = call i64 @__rg_rt_clone_slot(i64 %res)
  %d = call i64 @__rg_rt_drop_val(i64 %h)
  ret i64 %copy
}

; 1 when the job of a handle on a worker has ended (the handle is left alone).
define internal i1 @rg_job_ended(i64 %h) {
entry:
  %cell = call i64 @rg_w1(i64 %h)
  %none = icmp eq i64 %cell, 0
  br i1 %none, label %yes, label %check
yes:
  ret i1 true
check:
  %sp = inttoptr i64 %cell to ptr
  %s = load atomic i64, ptr %sp acquire, align 8
  %r = icmp eq i64 %s, 1
  ret i1 %r
}

; The last reference to a handle on a worker is gone (called by drop): once
; awaited it holds the result (second word); else a job that has ended frees
; its result and cell, and one that is running will do it.
define void @rg_job_drop(i64 %cell, i64 %result) {
  %fin = icmp eq i64 %cell, 0
  br i1 %fin, label %held, label %detach
held:
  %d = call i64 @__rg_rt_drop_val(i64 %result)
  ret void
detach:
  call void @rg_job_detach(i64 %cell)
  ret void
}

define void @rg_job_detach(i64 %cell) {
entry:
  %isnull = icmp eq i64 %cell, 0
  br i1 %isnull, label %done, label %go
go:
  %sp = inttoptr i64 %cell to ptr
  %c = cmpxchg ptr %sp, i64 0, i64 2 acq_rel monotonic
  %ok = extractvalue { i64, i1 } %c, 1
  br i1 %ok, label %done, label %ended
ended:
  %ra = add i64 %cell, 24
  %r = call i64 @rg_ld(i64 %ra)
  %d = call i64 @__rg_rt_drop_val(i64 %r)
  call void @rg_free(i64 %cell)
  br label %done
done:
  ret void
}


; ── Parallel map and filter (||map, ||filter) ────────────────
declare i64 @rg_ldb(i64)
; The list is split into chunks (up to 8); the chunks after the first go to
; workers as tasks, the first runs on the calling thread, and the caller waits
; for all of them. Short lists, and calls made from a worker, run in order.
; Every chunk works on its own indices, so the results keep the order.
;
; A chunk descriptor: [function value, list, out, own (0 or 1), start, end,
; remaining (address of the counter the caller waits on), flags (filter)].

declare i64 @rg_apply1(i64, i64)
declare i64 @rg_map(i64, i64)
declare i64 @rg_filter(i64, i64)
declare i1 @rg_sole(i64)

; Chunk of a map: out[i] = f xs[i] for i in [start, end).
define void @rg_pmap_chunk(i64 %d) {
entry:
  %f = call i64 @rg_ld(i64 %d)
  %xa = add i64 %d, 8
  %xs = call i64 @rg_ld(i64 %xa)
  %oa0 = add i64 %d, 16
  %out = call i64 @rg_ld(i64 %oa0)
  %na = add i64 %d, 24
  %own = call i64 @rg_ld(i64 %na)
  %sa = add i64 %d, 32
  %start = call i64 @rg_ld(i64 %sa)
  %ea = add i64 %d, 40
  %end = call i64 @rg_ld(i64 %ea)
  br label %loop
loop:
  %i = phi i64 [ %start, %entry ], [ %i1, %call ]
  %more = icmp slt i64 %i, %end
  br i1 %more, label %body, label %done
body:
  %ia = call i64 @rg_list_at(i64 %xs, i64 %i)
  %v = call i64 @rg_ld(i64 %ia)
  %isown = icmp ne i64 %own, 0
  br i1 %isown, label %take, label %clone
take:
  call void @rg_st(i64 %ia, i64 0)
  br label %call
clone:
  %c = call i64 @__rg_rt_clone_slot(i64 %v)
  br label %call
call:
  %x = phi i64 [ %v, %take ], [ %c, %clone ]
  %y = call i64 @rg_apply1(i64 %f, i64 %x)
  %oa = call i64 @rg_list_at(i64 %out, i64 %i)
  call void @rg_st(i64 %oa, i64 %y)
  %i1 = add i64 %i, 1
  br label %loop
done:
  call void @rg_pchunk_done(i64 %d)
  ret void
}

; Chunk of a filter: flags[i] = 1 when f xs[i] is True.
define void @rg_pfilter_chunk(i64 %d) {
entry:
  %f = call i64 @rg_ld(i64 %d)
  %xa = add i64 %d, 8
  %xs = call i64 @rg_ld(i64 %xa)
  %sa = add i64 %d, 32
  %start = call i64 @rg_ld(i64 %sa)
  %ea = add i64 %d, 40
  %end = call i64 @rg_ld(i64 %ea)
  %fa = add i64 %d, 56
  %flags = call i64 @rg_ld(i64 %fa)
  br label %loop
loop:
  %i = phi i64 [ %start, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %end
  br i1 %more, label %body, label %done
body:
  %ia = call i64 @rg_list_at(i64 %xs, i64 %i)
  %v = call i64 @rg_ld(i64 %ia)
  %xc = call i64 @__rg_rt_clone_slot(i64 %v)
  %t = call i64 @rg_apply1(i64 %f, i64 %xc)
  %keep = icmp eq i64 %t, 6
  %dt = call i64 @__rg_rt_drop_val(i64 %t)
  %fl = add i64 %flags, %i
  %kv = zext i1 %keep to i64
  call void @rg_stb(i64 %fl, i64 %kv)
  %i1 = add i64 %i, 1
  br label %loop
done:
  call void @rg_pchunk_done(i64 %d)
  ret void
}

declare void @rg_stb(i64, i64)

; A chunk is finished: one less on the caller's counter, and wake it.
define internal void @rg_pchunk_done(i64 %d) {
  %ra = add i64 %d, 48
  %rem = call i64 @rg_ld(i64 %ra)
  %p = inttoptr i64 %rem to ptr
  %o = atomicrmw sub ptr %p, i64 1 release
  %w = call i64 @__rg_pal_futex_wake(i64 %rem, i64 2147483647)
  ret void
}

; Runs the chunks [lo, hi) of n in `chunks` pieces: descriptors in `descs`
; (chunks * 64 bytes), tasks in `tasks` (chunks * 16 bytes); `fn` runs a chunk.
; The first chunk runs here; the others go to workers or run here too when no
; worker takes them. Waits for all.
define internal void @rg_pfor(i64 %descs, i64 %tasks, i64 %chunks, i64 %fn, i64 %counter) {
entry:
  call void @rg_st(i64 %counter, i64 %chunks)
  br label %post
post:
  %k = phi i64 [ 1, %entry ], [ %k1, %posted ]
  %m = icmp slt i64 %k, %chunks
  br i1 %m, label %one, label %first
one:
  %do = mul i64 %k, 64
  %d = add i64 %descs, %do
  %to = shl i64 %k, 4
  %t = add i64 %tasks, %to
  call void @rg_st(i64 %t, i64 %fn)
  %ta = add i64 %t, 8
  call void @rg_st(i64 %ta, i64 %d)
  %c = call i64 @rg_alloc(i64 32)
  call void @rg_st(i64 %c, i64 2)
  %cf = add i64 %c, 8
  call void @rg_st(i64 %cf, i64 -1)
  %cx = add i64 %c, 16
  call void @rg_st(i64 %cx, i64 %t)
  %cr = add i64 %c, 24
  call void @rg_st(i64 %cr, i64 0)
  %sent = call i1 @rg_job_dispatch(i64 %c)
  br i1 %sent, label %posted, label %inline
inline:
  call void @rg_free(i64 %c)
  %fp = inttoptr i64 %fn to ptr
  call void %fp(i64 %d)
  br label %posted
posted:
  %k1 = add i64 %k, 1
  br label %post
first:
  %fp0 = inttoptr i64 %fn to ptr
  call void %fp0(i64 %descs)
  br label %wait
wait:
  %cp = inttoptr i64 %counter to ptr
  %v = load atomic i64, ptr %cp acquire, align 8
  %z = icmp eq i64 %v, 0
  br i1 %z, label %done, label %sleep
sleep:
  %w = call i64 @__rg_pal_futex_wait(i64 %counter, i64 %v, i64 -1)
  br label %wait
done:
  ret void
}

; How many chunks for n items: 1 (run in order) below 8 items or on a worker.
define internal i64 @rg_pchunks(i64 %n) {
entry:
  %slot = call i64 @rg_slot()
  %onw = icmp ne i64 %slot, 0
  %small = icmp slt i64 %n, 8
  %seq = or i1 %onw, %small
  br i1 %seq, label %one, label %many
one:
  ret i64 1
many:
  %half = sdiv i64 %n, 2
  %big = icmp sgt i64 %half, 8
  %c = select i1 %big, i64 8, i64 %half
  ret i64 %c
}

; Fills the descriptors of `chunks` chunks over [0, n).
define internal void @rg_pfill(i64 %descs, i64 %chunks, i64 %n, i64 %f, i64 %xs, i64 %out, i64 %own, i64 %counter, i64 %flags) {
entry:
  br label %loop
loop:
  %k = phi i64 [ 0, %entry ], [ %k1, %body ]
  %m = icmp slt i64 %k, %chunks
  br i1 %m, label %body, label %done
body:
  %do = mul i64 %k, 64
  %d = add i64 %descs, %do
  call void @rg_st(i64 %d, i64 %f)
  %a1 = add i64 %d, 8
  call void @rg_st(i64 %a1, i64 %xs)
  %a2 = add i64 %d, 16
  call void @rg_st(i64 %a2, i64 %out)
  %a3 = add i64 %d, 24
  call void @rg_st(i64 %a3, i64 %own)
  %lo = mul i64 %k, %n
  %start = sdiv i64 %lo, %chunks
  %k2 = add i64 %k, 1
  %hi = mul i64 %k2, %n
  %end = sdiv i64 %hi, %chunks
  %a4 = add i64 %d, 32
  call void @rg_st(i64 %a4, i64 %start)
  %a5 = add i64 %d, 40
  call void @rg_st(i64 %a5, i64 %end)
  %a6 = add i64 %d, 48
  call void @rg_st(i64 %a6, i64 %counter)
  %a7 = add i64 %d, 56
  call void @rg_st(i64 %a7, i64 %flags)
  %k1 = add i64 %k, 1
  br label %loop
done:
  ret void
}

; ||map (f, xs): like map, with the chunks on the pool; both taken.
define i64 @rg_par_map(i64 %f, i64 %xs) {
entry:
  %n = call i64 @rg_list_len(i64 %xs)
  %chunks = call i64 @rg_pchunks(i64 %n)
  %seq = icmp sle i64 %chunks, 1
  br i1 %seq, label %sequential, label %parallel
sequential:
  %r0 = call i64 @rg_map(i64 %f, i64 %xs)
  ret i64 %r0
parallel:
  %own = call i1 @rg_sole(i64 %xs)
  %ownw = zext i1 %own to i64
  %out = call i64 @rg_list_alloc(i64 %n, i64 %n)
  %db = mul i64 %chunks, 64
  %descs = call i64 @rg_alloc(i64 %db)
  %tb = shl i64 %chunks, 4
  %tasks = call i64 @rg_alloc(i64 %tb)
  %counter = call i64 @rg_alloc(i64 8)
  call void @rg_pfill(i64 %descs, i64 %chunks, i64 %n, i64 %f, i64 %xs, i64 %out, i64 %ownw, i64 %counter, i64 0)
  call void @rg_pfor(i64 %descs, i64 %tasks, i64 %chunks, i64 ptrtoint (ptr @rg_pmap_chunk to i64), i64 %counter)
  call void @rg_free(i64 %descs)
  call void @rg_free(i64 %tasks)
  call void @rg_free(i64 %counter)
  %d1 = call i64 @__rg_rt_drop_val(i64 %xs)
  %d2 = call i64 @__rg_rt_drop_val(i64 %f)
  ret i64 %out
}

; ||filter (f, xs): the flags are computed on the pool, the list is built in
; order here; both taken.
define i64 @rg_par_filter(i64 %f, i64 %xs) {
entry:
  %n = call i64 @rg_list_len(i64 %xs)
  %chunks = call i64 @rg_pchunks(i64 %n)
  %seq = icmp sle i64 %chunks, 1
  br i1 %seq, label %sequential, label %parallel
sequential:
  %r0 = call i64 @rg_filter(i64 %f, i64 %xs)
  ret i64 %r0
parallel:
  %db = mul i64 %chunks, 64
  %descs = call i64 @rg_alloc(i64 %db)
  %tb = shl i64 %chunks, 4
  %tasks = call i64 @rg_alloc(i64 %tb)
  %counter = call i64 @rg_alloc(i64 8)
  %flags = call i64 @rg_alloc(i64 %n)
  call void @rg_pfill(i64 %descs, i64 %chunks, i64 %n, i64 %f, i64 %xs, i64 0, i64 0, i64 %counter, i64 %flags)
  call void @rg_pfor(i64 %descs, i64 %tasks, i64 %chunks, i64 ptrtoint (ptr @rg_pfilter_chunk to i64), i64 %counter)
  %out = call i64 @rg_list_alloc(i64 0, i64 %n)
  %h = call i64 @rg_w1(i64 %out)
  %own = call i1 @rg_sole(i64 %xs)
  br label %build
build:
  %i = phi i64 [ 0, %parallel ], [ %i1, %next ]
  %k = phi i64 [ 0, %parallel ], [ %k2, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %fin
body:
  %fa = add i64 %flags, %i
  %fv = call i64 @rg_ldb(i64 %fa)
  %keep = icmp ne i64 %fv, 0
  br i1 %keep, label %put, label %next
put:
  %ia = call i64 @rg_list_at(i64 %xs, i64 %i)
  %v = call i64 @rg_ld(i64 %ia)
  br i1 %own, label %movev, label %clonev
movev:
  call void @rg_st(i64 %ia, i64 0)
  br label %store
clonev:
  %c = call i64 @__rg_rt_clone_slot(i64 %v)
  br label %store
store:
  %x = phi i64 [ %v, %movev ], [ %c, %clonev ]
  %oa = call i64 @rg_list_at(i64 %out, i64 %k)
  call void @rg_st(i64 %oa, i64 %x)
  %kp = add i64 %k, 1
  call void @rg_vset_len(i64 %h, i64 %kp)
  br label %next
next:
  %k2 = phi i64 [ %kp, %store ], [ %k, %body ]
  %i1 = add i64 %i, 1
  br label %build
fin:
  call void @rg_free(i64 %descs)
  call void @rg_free(i64 %tasks)
  call void @rg_free(i64 %counter)
  call void @rg_free(i64 %flags)
  %d1 = call i64 @__rg_rt_drop_val(i64 %xs)
  %d2 = call i64 @__rg_rt_drop_val(i64 %f)
  ret i64 %out
}

; ── Tagged replies ───────────────────────────────────────────

; The index of the first waiting item of c that is a pair tagged with this
; thread (Int 1), or -1.
define internal i64 @rg_find_mine(i64 %c) {
entry:
  %n = call i64 @rg_chan_count(i64 %c)
  %h = call i64 @rg_w1(i64 %c)
  %d = call i64 @rg_vdata(i64 %h)
  %head = call i64 @rg_w2(i64 %c)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %k = add i64 %head, %i
  %off = shl i64 %k, 3
  %a = add i64 %d, %off
  %v = call i64 @rg_ld(i64 %a)
  %ist = call i64 @__rg_rt_match_tuple(i64 %v, i64 2)
  %t = icmp ne i64 %ist, 0
  br i1 %t, label %tid, label %next
tid:
  %x = call i64 @__rg_rt_tuple_get(i64 %v, i64 0)
  %mine = icmp eq i64 %x, 3
  br i1 %mine, label %found, label %next
found:
  ret i64 %i
next:
  %i1 = add i64 %i, 1
  br label %loop
none:
  ret i64 -1
}

; The index of the first waiting item of c that is not addressed to a thread:
; a value that is not a pair, or a pair whose tag is Int 3 (the plain reply of
; `send`), or -1. A thread never takes a reply addressed to another thread
; (Vonkeep request 3: answers reached the wrong caller).
define internal i64 @rg_find_plain(i64 %c) {
entry:
  %n = call i64 @rg_chan_count(i64 %c)
  %h = call i64 @rg_w1(i64 %c)
  %d = call i64 @rg_vdata(i64 %h)
  %head = call i64 @rg_w2(i64 %c)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %none
body:
  %k = add i64 %head, %i
  %off = shl i64 %k, 3
  %a = add i64 %d, %off
  %v = call i64 @rg_ld(i64 %a)
  %ist = call i64 @__rg_rt_match_tuple(i64 %v, i64 2)
  %t = icmp ne i64 %ist, 0
  br i1 %t, label %tag, label %found
tag:
  %x = call i64 @__rg_rt_tuple_get(i64 %v, i64 0)
  %plain = icmp eq i64 %x, 7
  br i1 %plain, label %found, label %next
found:
  ret i64 %i
next:
  %i1 = add i64 %i, 1
  br label %loop
none:
  ret i64 -1
}

; 98: (3, value) for this thread's reply, or 0.
define internal i64 @rg_recv_mine(i64 %c, i1 %fallback) {
entry:
  %i0 = call i64 @rg_find_mine(i64 %c)
  %none = icmp slt i64 %i0, 0
  %ip = call i64 @rg_find_plain(i64 %c)
  %anyp = icmp sge i64 %ip, 0
  %usefb = and i1 %none, %fallback
  %fb = and i1 %usefb, %anyp
  %i = select i1 %fb, i64 %ip, i64 %i0
  %got = icmp sge i64 %i, 0
  br i1 %got, label %take, label %nothing
nothing:
  ret i64 0
take:
  %v = call i64 @rg_chan_take(i64 %c, i64 %i)
  %ist = call i64 @__rg_rt_match_tuple(i64 %v, i64 2)
  %t = icmp ne i64 %ist, 0
  br i1 %t, label %unwrap, label %wrap
unwrap:
  %p = call i64 @__rg_rt_tuple_get(i64 %v, i64 1)
  %dv = call i64 @__rg_rt_drop_val(i64 %v)
  br label %wrap
wrap:
  %pay = phi i64 [ %p, %unwrap ], [ %v, %take ]
  %r = call i64 @rg_pair(i64 3, i64 %pay)
  ret i64 %r
}

; 99: (job, rest) from a list of (thread id, job) pairs (taken): the first
; pair of this thread, else the first item.
define internal i64 @rg_take_mine(i64 %xs) {
entry:
  %n = call i64 @rg_list_len(i64 %xs)
  br label %find
find:
  %i = phi i64 [ 0, %entry ], [ %i1, %fnext ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %fbody, label %first
fbody:
  %a = call i64 @rg_list_at(i64 %xs, i64 %i)
  %v = call i64 @rg_ld(i64 %a)
  %ist = call i64 @__rg_rt_match_tuple(i64 %v, i64 2)
  %t = icmp ne i64 %ist, 0
  br i1 %t, label %ftid, label %fnext
ftid:
  %x = call i64 @__rg_rt_tuple_get(i64 %v, i64 0)
  %mine = icmp eq i64 %x, 3
  br i1 %mine, label %pick, label %fnext
fnext:
  %i1 = add i64 %i, 1
  br label %find
first:
  br label %pick
pick:
  %k = phi i64 [ %i, %ftid ], [ 0, %first ]
  %rest0 = sub i64 %n, 1
  %rneg = icmp slt i64 %rest0, 0
  %rn = select i1 %rneg, i64 0, i64 %rest0
  %rest = call i64 @rg_list_alloc(i64 %rn, i64 %rn)
  br label %copy
copy:
  %j = phi i64 [ 0, %pick ], [ %j1, %cnext ]
  %o = phi i64 [ 0, %pick ], [ %o1, %cnext ]
  %cm = icmp slt i64 %j, %n
  br i1 %cm, label %cbody, label %built
cbody:
  %ja = call i64 @rg_list_at(i64 %xs, i64 %j)
  %jv = call i64 @rg_ld(i64 %ja)
  %isk = icmp eq i64 %j, %k
  br i1 %isk, label %cskip, label %cput
cput:
  %c = call i64 @__rg_rt_clone_slot(i64 %jv)
  %oa = call i64 @rg_list_at(i64 %rest, i64 %o)
  call void @rg_st(i64 %oa, i64 %c)
  %o2 = add i64 %o, 1
  br label %cnext
cskip:
  br label %cnext
cnext:
  %o1 = phi i64 [ %o2, %cput ], [ %o, %cskip ]
  %j1 = add i64 %j, 1
  br label %copy
built:
  %ka = call i64 @rg_list_at(i64 %xs, i64 %k)
  %kv = call i64 @rg_ld(i64 %ka)
  %kt = call i64 @__rg_rt_match_tuple(i64 %kv, i64 2)
  %iskt = icmp ne i64 %kt, 0
  br i1 %iskt, label %jobt, label %jobv
jobt:
  %jb = call i64 @__rg_rt_tuple_get(i64 %kv, i64 1)
  br label %out
jobv:
  %jc = call i64 @__rg_rt_clone_slot(i64 %kv)
  br label %out
out:
  %job = phi i64 [ %jb, %jobt ], [ %jc, %jobv ]
  %dx = call i64 @__rg_rt_drop_val(i64 %xs)
  %r = call i64 @rg_pair(i64 %job, i64 %rest)
  ret i64 %r
}

; ── Dispatch ─────────────────────────────────────────────────
; 51 receive from timeout (channel, ticks): `Ok v` when an item arrives within
; `ticks` milliseconds, else `Err Timeout` (as the old runtime and the book
; give it). The channel stays with the caller like for 32 and 33; the time is
; taken.
declare i64 @__rg_pal_clock_ns(i64)
declare void @__rg_pal_sleep_ns(i64)
declare i64 @__rg_rt_make_adt(i64, i64, i64, i64)
declare i64 @rg_int_of(i64)
declare i64 @__rg_rt_load_adt0(i64, i64)
@rg_nm_err = private constant [3 x i8] c"Err"
@rg_nm_timeout = private constant [7 x i8] c"Timeout"

define internal i64 @rg_recv_timeout(i64 %slots) {
entry:
  %ch = call i64 @rg_ld(i64 %slots)
  %ta = add i64 %slots, 8
  %tv = call i64 @rg_ld(i64 %ta)
  %ms = call i64 @rg_int_of(i64 %tv)
  %t0 = call i64 @__rg_pal_clock_ns(i64 0)
  %span = mul i64 %ms, 1000000
  %deadline = add i64 %t0, %span
  %la = ptrtoint ptr @rg_chan_lock to i64
  br label %try
try:
  call void @rg_lock(i64 %la)
  %c = call i64 @rg_chan_of(i64 %ch)
  %ok = icmp ne i64 %c, 0
  br i1 %ok, label %count, label %nochan
nochan:
  call void @rg_unlock(i64 %la)
  br label %none
count:
  %k = call i64 @rg_chan_count(i64 %c)
  %has = icmp sgt i64 %k, 0
  br i1 %has, label %take, label %wait
take:
  %v = call i64 @rg_chan_take(i64 %c, i64 0)
  call void @rg_unlock(i64 %la)
  %vals = alloca [1 x i64], align 8
  store i64 %v, ptr %vals, align 8
  %va = ptrtoint ptr %vals to i64
  %some = call i64 @rg_ok(i64 %v)
  call void @rg_st(i64 %ta, i64 0)
  ret i64 %some
wait:
  call void @rg_unlock(i64 %la)
  %now = call i64 @__rg_pal_clock_ns(i64 0)
  %late = icmp sge i64 %now, %deadline
  br i1 %late, label %none, label %nap
nap:
  call void @__rg_pal_sleep_ns(i64 100000)
  br label %try
none:
  call void @rg_st(i64 %ta, i64 0)
  %tm = call i64 @__rg_rt_load_adt0(i64 ptrtoint (ptr @rg_nm_timeout to i64), i64 7)
  %ev = alloca [1 x i64], align 8
  store i64 %tm, ptr %ev, align 8
  %ea = ptrtoint ptr %ev to i64
  %n = call i64 @__rg_rt_make_adt(i64 ptrtoint (ptr @rg_nm_err to i64), i64 3, i64 %ea, i64 1)
  ret i64 %n
}

; The channel builtins take the channel lock (ADR-0014): channels, the table
; of global channels and the tagged replies are shared between threads.
@rg_chan_lock = internal global i32 0
declare void @rg_lock(i64)
declare void @rg_unlock(i64)
declare void @__rg_pal_yield()

define i64 @rg_builtin_agents(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %direct [ i64 51, label %timed
                                  i64 1, label %locked
                                  i64 35, label %locked
                                  i64 50, label %locked
                                  i64 32, label %locked
                                  i64 33, label %locked
                                  i64 97, label %locked
                                  i64 98, label %locked
                                  i64 99, label %locked ]
direct:
  %rd = call i64 @rg_builtin_agents_run(i64 %id, i64 %slots, i64 %n)
  ret i64 %rd
timed:
  %rt = call i64 @rg_recv_timeout(i64 %slots)
  ret i64 %rt
locked:
  %la = ptrtoint ptr @rg_chan_lock to i64
  br label %again
again:
  call void @rg_lock(i64 %la)
  %rl = call i64 @rg_builtin_agents_run(i64 %id, i64 %slots, i64 %n)
  call void @rg_unlock(i64 %la)
  %retry = icmp eq i64 %rl, -8
  br i1 %retry, label %wait, label %out
wait:
  call void @__rg_pal_yield()
  br label %again
out:
  ret i64 %rl
}

define internal i64 @rg_builtin_agents_run(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %next [ i64 1, label %new
                                i64 35, label %new
                                i64 50, label %send
                                i64 32, label %recv
                                i64 33, label %try
                                i64 57, label %spawn
                                i64 58, label %poll
                                i64 59, label %await
                                i64 96, label %tid
                                i64 97, label %sendtag
                                i64 98, label %recvtag
                                i64 99, label %takejob ]
next:
  %r = call i64 @rg_builtin_more(i64 %id, i64 %slots, i64 %n)
  ret i64 %r
new:
  %c1 = call i64 @rg_chan_new()
  ret i64 %c1
send:
  ; the value is taken; the channel stays with the caller (as for 32 and 33)
  %v50 = call i64 @rg_arg(i64 %slots, i64 0)
  %s50 = add i64 %slots, 8
  %ch50 = call i64 @rg_ld(i64 %s50)
  %c50 = call i64 @rg_chan_of(i64 %ch50)
  %ok50 = icmp ne i64 %c50, 0
  br i1 %ok50, label %send_put, label %send_drop
send_put:
  call void @rg_chan_put(i64 %c50, i64 %v50)
  ret i64 0
send_drop:
  %e50 = call i64 @__rg_rt_drop_val(i64 %v50)
  ret i64 0
recv:
  %ch32 = call i64 @rg_ld(i64 %slots)
  %c32 = call i64 @rg_chan_of(i64 %ch32)
  %ok32 = icmp ne i64 %c32, 0
  br i1 %ok32, label %recv_count, label %recv_none
recv_count:
  %k32 = call i64 @rg_chan_count(i64 %c32)
  %has32 = icmp sgt i64 %k32, 0
  br i1 %has32, label %recv_take, label %recv_empty
recv_take:
  %v32 = call i64 @rg_chan_take(i64 %c32, i64 0)
  ret i64 %v32
recv_empty:
  %wait = icmp ne i64 %n, 0
  br i1 %wait, label %recv_wait, label %recv_none
recv_wait:
  ; another thread may still send: ask the caller to try again (-8), or stop
  ; when no other job runs
  ; (a worker always waits: the main thread may still send; the main thread
  ; waits while some job runs)
  %act = load atomic i64, ptr @rg_jobs_active acquire, align 8
  %rs = call i64 @rg_slot()
  %onw = icmp ne i64 %rs, 0
  %busy = icmp sgt i64 %act, 0
  %more = or i1 %onw, %busy
  br i1 %more, label %recv_retry, label %deadlock
recv_retry:
  ret i64 -8
recv_none:
  ret i64 0
deadlock:
  call void @rg_fatal(ptr @rg_msg_deadlock, i64 69)
  unreachable
try:
  ; the channel stays in the slot, with the caller (builtins 32, 33 and 50 do
  ; not consume it): the backends' blocking receive passes the same reference
  ; to every try, and the caller empties the slot
  %ch33 = call i64 @rg_ld(i64 %slots)
  %c33 = call i64 @rg_chan_of(i64 %ch33)
  %ok33 = icmp ne i64 %c33, 0
  br i1 %ok33, label %try_count, label %try_none
try_count:
  %k33 = call i64 @rg_chan_count(i64 %c33)
  %has33 = icmp sgt i64 %k33, 0
  br i1 %has33, label %try_take, label %try_none
try_take:
  %v33 = call i64 @rg_chan_take(i64 %c33, i64 0)
  %r33 = call i64 @rg_ok(i64 %v33)
  ret i64 %r33
try_none:
  ret i64 0
spawn:
  %f57 = call i64 @rg_arg(i64 %slots, i64 0)
  %x57 = call i64 @rg_arg(i64 %slots, i64 1)
  %r57 = call i64 @rg_job_spawn(i64 %f57, i64 %x57)
  ret i64 %r57
poll:
  %j58 = call i64 @rg_arg(i64 %slots, i64 0)
  %w58 = call i1 @rg_has_tag(i64 %j58, i64 7)
  br i1 %w58, label %poll_worker, label %poll_done
poll_worker:
  %e58 = call i1 @rg_job_ended(i64 %j58)
  %d58w = call i64 @__rg_rt_drop_val(i64 %j58)
  %b58 = select i1 %e58, i64 6, i64 2
  ret i64 %b58
poll_done:
  %d58 = call i64 @__rg_rt_drop_val(i64 %j58)
  ret i64 6
await:
  %j59 = call i64 @rg_arg(i64 %slots, i64 0)
  %w59 = call i1 @rg_has_tag(i64 %j59, i64 7)
  br i1 %w59, label %await_worker, label %await_tuple
await_worker:
  %r59 = call i64 @rg_job_await(i64 %j59)
  ret i64 %r59
await_tuple:
  %t59 = call i64 @__rg_rt_match_tuple(i64 %j59, i64 2)
  %ist59 = icmp ne i64 %t59, 0
  br i1 %ist59, label %await_get, label %await_self
await_get:
  %v59 = call i64 @__rg_rt_tuple_get(i64 %j59, i64 1)
  %d59 = call i64 @__rg_rt_drop_val(i64 %j59)
  ret i64 %v59
await_self:
  ret i64 %j59
tid:
  ret i64 3
sendtag:
  ; like 50: the value is taken, the channel stays with the caller
  %v97 = call i64 @rg_arg(i64 %slots, i64 0)
  %s97 = add i64 %slots, 8
  %ch97 = call i64 @rg_ld(i64 %s97)
  %p97 = call i64 @rg_pair(i64 3, i64 %v97)
  %c97 = call i64 @rg_chan_of(i64 %ch97)
  %ok97 = icmp ne i64 %c97, 0
  br i1 %ok97, label %sendtag_put, label %sendtag_drop
sendtag_put:
  call void @rg_chan_put(i64 %c97, i64 %p97)
  ret i64 0
sendtag_drop:
  %e97 = call i64 @__rg_rt_drop_val(i64 %p97)
  ret i64 0
recvtag:
  ; like 33: the channel stays with the caller
  %ch98 = call i64 @rg_ld(i64 %slots)
  %c98 = call i64 @rg_chan_of(i64 %ch98)
  %ok98 = icmp ne i64 %c98, 0
  br i1 %ok98, label %recvtag_do, label %recvtag_none
recvtag_do:
  %fb = icmp ne i64 %n, 0
  %r98 = call i64 @rg_recv_mine(i64 %c98, i1 %fb)
  ret i64 %r98
recvtag_none:
  ret i64 0
takejob:
  %xs99 = call i64 @rg_arg(i64 %slots, i64 0)
  %r99 = call i64 @rg_take_mine(i64 %xs99)
  ret i64 %r99
}
