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
  %c2 = call i64 @rg_chan_new()
  call void @rg_st(i64 %a, i64 %c2)
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

; spawn (function, argument), both taken: runs the spawn dispatcher now.
define internal i64 @rg_job_spawn(i64 %f, i64 %x) {
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

; 98: (3, value) for this thread's reply, or 0.
define internal i64 @rg_recv_mine(i64 %c, i1 %fallback) {
entry:
  %i0 = call i64 @rg_find_mine(i64 %c)
  %none = icmp slt i64 %i0, 0
  %n = call i64 @rg_chan_count(i64 %c)
  %any = icmp sgt i64 %n, 0
  %usefb = and i1 %none, %fallback
  %fb = and i1 %usefb, %any
  %i = select i1 %fb, i64 0, i64 %i0
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
define i64 @rg_builtin_agents(i64 %id, i64 %slots, i64 %n) {
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
  %v50 = call i64 @rg_arg(i64 %slots, i64 0)
  %ch50 = call i64 @rg_arg(i64 %slots, i64 1)
  %c50 = call i64 @rg_chan_of(i64 %ch50)
  %ok50 = icmp ne i64 %c50, 0
  br i1 %ok50, label %send_put, label %send_drop
send_put:
  call void @rg_chan_put(i64 %c50, i64 %v50)
  %d50 = call i64 @__rg_rt_drop_val(i64 %ch50)
  ret i64 0
send_drop:
  %e50 = call i64 @__rg_rt_drop_val(i64 %v50)
  %f50 = call i64 @__rg_rt_drop_val(i64 %ch50)
  ret i64 0
recv:
  %ch32 = call i64 @rg_arg(i64 %slots, i64 0)
  %c32 = call i64 @rg_chan_of(i64 %ch32)
  %ok32 = icmp ne i64 %c32, 0
  br i1 %ok32, label %recv_count, label %recv_none
recv_count:
  %k32 = call i64 @rg_chan_count(i64 %c32)
  %has32 = icmp sgt i64 %k32, 0
  br i1 %has32, label %recv_take, label %recv_empty
recv_take:
  %v32 = call i64 @rg_chan_take(i64 %c32, i64 0)
  %d32 = call i64 @__rg_rt_drop_val(i64 %ch32)
  ret i64 %v32
recv_empty:
  %wait = icmp ne i64 %n, 0
  br i1 %wait, label %deadlock, label %recv_none
recv_none:
  %e32 = call i64 @__rg_rt_drop_val(i64 %ch32)
  ret i64 0
deadlock:
  call void @rg_fatal(ptr @rg_msg_deadlock, i64 69)
  unreachable
try:
  %ch33 = call i64 @rg_arg(i64 %slots, i64 0)
  %c33 = call i64 @rg_chan_of(i64 %ch33)
  %ok33 = icmp ne i64 %c33, 0
  br i1 %ok33, label %try_count, label %try_none
try_count:
  %k33 = call i64 @rg_chan_count(i64 %c33)
  %has33 = icmp sgt i64 %k33, 0
  br i1 %has33, label %try_take, label %try_none
try_take:
  %v33 = call i64 @rg_chan_take(i64 %c33, i64 0)
  %d33 = call i64 @__rg_rt_drop_val(i64 %ch33)
  %r33 = call i64 @rg_ok(i64 %v33)
  ret i64 %r33
try_none:
  %e33 = call i64 @__rg_rt_drop_val(i64 %ch33)
  ret i64 0
spawn:
  %f57 = call i64 @rg_arg(i64 %slots, i64 0)
  %x57 = call i64 @rg_arg(i64 %slots, i64 1)
  %r57 = call i64 @rg_job_spawn(i64 %f57, i64 %x57)
  ret i64 %r57
poll:
  %j58 = call i64 @rg_arg(i64 %slots, i64 0)
  %d58 = call i64 @__rg_rt_drop_val(i64 %j58)
  ret i64 6
await:
  %j59 = call i64 @rg_arg(i64 %slots, i64 0)
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
  %v97 = call i64 @rg_arg(i64 %slots, i64 0)
  %ch97 = call i64 @rg_arg(i64 %slots, i64 1)
  %p97 = call i64 @rg_pair(i64 3, i64 %v97)
  %c97 = call i64 @rg_chan_of(i64 %ch97)
  %ok97 = icmp ne i64 %c97, 0
  br i1 %ok97, label %sendtag_put, label %sendtag_drop
sendtag_put:
  call void @rg_chan_put(i64 %c97, i64 %p97)
  %d97 = call i64 @__rg_rt_drop_val(i64 %ch97)
  ret i64 0
sendtag_drop:
  %e97 = call i64 @__rg_rt_drop_val(i64 %p97)
  %f97 = call i64 @__rg_rt_drop_val(i64 %ch97)
  ret i64 0
recvtag:
  %ch98 = call i64 @rg_arg(i64 %slots, i64 0)
  %c98 = call i64 @rg_chan_of(i64 %ch98)
  %ok98 = icmp ne i64 %c98, 0
  br i1 %ok98, label %recvtag_do, label %recvtag_none
recvtag_do:
  %fb = icmp ne i64 %n, 0
  %r98 = call i64 @rg_recv_mine(i64 %c98, i1 %fb)
  %d98 = call i64 @__rg_rt_drop_val(i64 %ch98)
  ret i64 %r98
recvtag_none:
  %e98 = call i64 @__rg_rt_drop_val(i64 %ch98)
  ret i64 0
takejob:
  %xs99 = call i64 @rg_arg(i64 %slots, i64 0)
  %r99 = call i64 @rg_take_mine(i64 %xs99)
  ret i64 %r99
}
