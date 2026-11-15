; ============================================================
; src/main/runtime/core/heap.ll
; The heap allocator (ADR-0013). Blocks come in power-of-two size classes
; (16 bytes to 2^40); each block starts with one word that holds its class,
; and the caller gets the address after it. A freed block goes to the free
; list of its class and is reused for the next request of that class. Fresh
; blocks are cut from the current chunk; a new chunk comes from the PAL.
; Memory is never given back to the system.
; ============================================================

declare i64 @__rg_pal_alloc_chunk(i64)
declare void @rg_fatal(ptr, i64)
declare i64 @llvm.ctlz.i64(i64, i1)

@rg_bump = internal global i64 0
@rg_bump_end = internal global i64 0
@rg_free_lists = internal global [48 x i64] zeroinitializer
@rg_msg_oom = private constant [13 x i8] c"out of memory"

; heap init (start, end): the first chunk is [start, end).
define void @rg_heap_init(i64 %start, i64 %end) {
  %s = add i64 %start, 15
  %a = and i64 %s, -16
  store i64 %a, ptr @rg_bump, align 8
  store i64 %end, ptr @rg_bump_end, align 8
  ret void
}

; The class of a request of n bytes: the smallest c >= 4 with 2^c >= n + 8.
define internal i64 @rg_class(i64 %n) alwaysinline {
  %need = add i64 %n, 7
  %lz = call i64 @llvm.ctlz.i64(i64 %need, i1 false)
  %c = sub i64 64, %lz
  %small = icmp ult i64 %c, 4
  %r = select i1 %small, i64 4, i64 %c
  ret i64 %r
}

; alloc (n): the address of n usable bytes, 8-aligned; not zeroed.
define i64 @rg_alloc(i64 %n) {
entry:
  %c = call i64 @rg_class(i64 %n)
  %lp = getelementptr inbounds [48 x i64], ptr @rg_free_lists, i64 0, i64 %c
  %head = load i64, ptr %lp, align 8
  %empty = icmp eq i64 %head, 0
  br i1 %empty, label %fresh, label %reuse
reuse:
  %hp = inttoptr i64 %head to ptr
  %np = getelementptr inbounds i8, ptr %hp, i64 8
  %next = load i64, ptr %np, align 8
  store i64 %next, ptr %lp, align 8
  %u = add i64 %head, 8
  ret i64 %u
fresh:
  %size = shl i64 1, %c
  %b = load i64, ptr @rg_bump, align 8
  %e = load i64, ptr @rg_bump_end, align 8
  %nb = add i64 %b, %size
  %fits = icmp ule i64 %nb, %e
  br i1 %fits, label %cut, label %grow
grow:
  %big = icmp ugt i64 %size, 1048576
  %want = select i1 %big, i64 %size, i64 1048576
  %chunk = call i64 @__rg_pal_alloc_chunk(i64 %want)
  %none = icmp eq i64 %chunk, 0
  br i1 %none, label %oom, label %got
oom:
  call void @rg_fatal(ptr @rg_msg_oom, i64 13)
  unreachable
got:
  %chunk_end = add i64 %chunk, %want
  %contig = icmp eq i64 %chunk, %e
  %nstart = select i1 %contig, i64 %b, i64 %chunk
  store i64 %nstart, ptr @rg_bump, align 8
  store i64 %chunk_end, ptr @rg_bump_end, align 8
  br label %fresh
cut:
  store i64 %nb, ptr @rg_bump, align 8
  %bp = inttoptr i64 %b to ptr
  store i64 %c, ptr %bp, align 8
  %r = add i64 %b, 8
  ret i64 %r
}

; free (address from alloc): the block goes back to the free list of its class.
define void @rg_free(i64 %p) {
  %blk = sub i64 %p, 8
  %bp = inttoptr i64 %blk to ptr
  %c = load i64, ptr %bp, align 8
  %lp = getelementptr inbounds [48 x i64], ptr @rg_free_lists, i64 0, i64 %c
  %head = load i64, ptr %lp, align 8
  %np = inttoptr i64 %p to ptr
  store i64 %head, ptr %np, align 8
  store i64 %blk, ptr %lp, align 8
  ret void
}

; The usable size of a block from alloc.
define i64 @rg_alloc_size(i64 %p) {
  %blk = sub i64 %p, 8
  %bp = inttoptr i64 %blk to ptr
  %c = load i64, ptr %bp, align 8
  %size = shl i64 1, %c
  %u = sub i64 %size, 8
  ret i64 %u
}

; Copy (overlapping regions too) and fill, for any target (no libc). They
; are "no-builtins" so LLVM does not turn their loops into memcpy calls.
define void @rg_copy(i64 %dst, i64 %src, i64 %n) #0 {
entry:
  %d = inttoptr i64 %dst to ptr
  %s = inttoptr i64 %src to ptr
  %back = icmp ugt i64 %dst, %src
  br i1 %back, label %bloop, label %loop
bloop:
  %j = phi i64 [ %n, %entry ], [ %j1, %bbody ]
  %bmore = icmp sgt i64 %j, 0
  br i1 %bmore, label %bbody, label %done
bbody:
  %j1 = sub i64 %j, 1
  %bsp = getelementptr inbounds i8, ptr %s, i64 %j1
  %bdp = getelementptr inbounds i8, ptr %d, i64 %j1
  %bv = load i8, ptr %bsp, align 1
  store i8 %bv, ptr %bdp, align 1
  br label %bloop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %sp = getelementptr inbounds i8, ptr %s, i64 %i
  %dp = getelementptr inbounds i8, ptr %d, i64 %i
  %v = load i8, ptr %sp, align 1
  store i8 %v, ptr %dp, align 1
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}

define void @rg_fill(i64 %dst, i8 %v, i64 %n) #0 {
entry:
  %d = inttoptr i64 %dst to ptr
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %dp = getelementptr inbounds i8, ptr %d, i64 %i
  store i8 %v, ptr %dp, align 1
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}


attributes #0 = { "no-builtins" }
