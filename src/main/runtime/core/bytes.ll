; ============================================================
; src/main/runtime/core/bytes.ll
; Byte tensors, CRC-32, SHA-256 and byte I/O (FR-COMP-022, FR-COMP-023,
; docs/etc/runtime_ext.md, ADR-0013).
;
; A Tensor[U8] is a numeric tensor (tag 5) whose shape is [W] and whose W
; data words hold: word 0 the rank k, words 1 .. k the dimensions, then the
; bytes, packed and zero padded to a whole word.
;
; Builtins (they take their slots; a borrowed slot is cleared, not dropped):
;   20 sha256 file (path): hex digest of the content ("" when unreadable)
;   21 sha256 str (s): hex digest      36 sha256 raw (s or bytes): 32 bytes
;   89 sha256 raw (a + b)
;   103 crc32 range (data, from, to, crc)
;   104 new (fill, d1 .. dk)    105 t_(i ..) (i1 .. ik, t borrowed)
;   106 t_(i ..) = v (i1 .. ik, v, t borrowed)   107 dim (k, t borrowed)
;   108 from str  109 to str  110 to list  111 to words (for echo)
;   112 read bytes (path)  113 write bytes (path, data)
;   114 sys read into, 115 sys write from (fd, t, from, count)
;   117 sha256 raw (bytes)  118 sha256 digest  119 from list
; System calls, execve and sockets (116, 120, 125 .. 135) are not part of
; the wasm32 target (FR-COMP-026): they stop with rg_no_builtin.
; ============================================================

declare i64 @rg_ld(i64)
declare i64 @rg_fuse_get(i64, i64, i64)
declare i64 @rg_fuse_leaf(i64)
declare i64 @rg_fuse_len(i64, i64)
declare i64 @rg_fuse_data(i64, i64)
declare void @rg_fuse_put(i64, i64, i64, i64)
declare void @rg_st(i64, i64)
declare i64 @rg_ldb(i64)
declare void @rg_stb(i64, i64)
declare i1 @rg_has_tag(i64, i64)
declare i64 @rg_w1(i64)
declare i64 @rg_alloc(i64)
declare void @rg_free(i64)
declare void @rg_copy(i64, i64, i64)
declare void @rg_fill(i64, i8, i64)
declare i64 @rg_str_alloc(i64, i64)
declare i64 @rg_str_from(i64, i64)
declare i64 @rg_str_data(i64)
declare i64 @rg_str_len(i64)
declare i64 @rg_list_alloc(i64, i64)
declare i64 @rg_list_at(i64, i64)
declare i64 @rg_list_len(i64)
declare i64 @rg_box_int(i64)
declare i64 @rg_int(i64)
declare i64 @__rg_rt_drop_val(i64)
declare void @rg_fatal(ptr, i64) noreturn
declare void @rg_oob() noreturn
declare void @rg_no_builtin(i64) noreturn
declare void @rg_drop_slots(i64, i64)
declare i64 @rg_t_new(i64, i64)
declare i64 @rg_t_data(i64)
declare i64 @rg_t_len(i64)
declare i64 @rg_t_dims(i64)
declare i64 @rg_word_at(i64, i64)
declare void @rg_word_set(i64, i64, i64)
declare i64 @rg_raw_word(i64)
declare i64 @rg_index_of(i64)
declare i64 @rg_read_file(i64)
declare i64 @rg_write_fd_all(i64, i64, i64)
declare i64 @__rg_pal_open(i64, i64, i64, i64)
declare i64 @__rg_pal_close(i64)
declare i64 @__rg_pal_read(i64, i64, i64)
declare i64 @__rg_pal_write(i64, i64, i64)
declare i32 @llvm.fshr.i32(i32, i32, i32)

@rg_msg_u8 = private constant [24 x i8] c"U8 element out of 0..255"
@rg_msg_words = private constant [80 x i8] c"tensor u32 from bytes: the number of bytes is not a multiple of the element size"
@rg_msg_ilv = private constant [65 x i8] c"tensor interleave: the tensors differ in their number of elements"
@rg_msg_ilv0 = private constant [32 x i8] c"tensor interleave: an empty list"
@rg_msg_u16 = private constant [27 x i8] c"U16 element out of 0..65535"
@rg_msg_u32 = private constant [32 x i8] c"U32 element out of 0..4294967295"
@rg_msg_crc = private constant [32 x i8] c"crc32 range: range out of bounds"
@rg_msg_wbytes = private constant [34 x i8] c"write bytes: element out of 0..255"
@rg_msg_io = private constant [24 x i8] c"byte range out of bounds"
@rg_hex = private constant [16 x i8] c"0123456789abcdef"
@rg_crc_tab = internal global [256 x i32] zeroinitializer
@rg_crc_ready = internal global i1 false
@rg_sha_k = private constant [64 x i32] [i32 1116352408, i32 1899447441, i32 -1245643825, i32 -373957723, i32 961987163, i32 1508970993, i32 -1841331548, i32 -1424204075, i32 -670586216, i32 310598401, i32 607225278, i32 1426881987, i32 1925078388, i32 -2132889090, i32 -1680079193, i32 -1046744716, i32 -459576895, i32 -272742522, i32 264347078, i32 604807628, i32 770255983, i32 1249150122, i32 1555081692, i32 1996064986, i32 -1740746414, i32 -1473132947, i32 -1341970488, i32 -1084653625, i32 -958395405, i32 -710438585, i32 113926993, i32 338241895, i32 666307205, i32 773529912, i32 1294757372, i32 1396182291, i32 1695183700, i32 1986661051, i32 -2117940946, i32 -1838011259, i32 -1564481375, i32 -1474664885, i32 -1035236496, i32 -949202525, i32 -778901479, i32 -694614492, i32 -200395387, i32 275423344, i32 430227734, i32 506948616, i32 659060556, i32 883997877, i32 958139571, i32 1322822218, i32 1537002063, i32 1747873779, i32 1955562222, i32 2024104815, i32 -2067236844, i32 -1933114872, i32 -1866530822, i32 -1538233109, i32 -1090935817, i32 -965641998]
@rg_sha_h0 = private constant [8 x i32] [i32 1779033703, i32 -1150833019, i32 1013904242, i32 -1521486534, i32 1359893119, i32 -1694144372, i32 528734635, i32 1541459225]

; ── Tensor[U8] ───────────────────────────────────────────────

; A packed tensor holds elements of 1, 2 or 4 bytes (U8, U16, U32): the first
; data word is rank + (lg << 32), lg the size as a power of two. A Tensor[U8]
; has lg 0, so its word is its rank.
define i64 @rg_u8_rank(i64 %t) {
  %d = call i64 @rg_t_data(i64 %t)
  %h = call i64 @rg_ld(i64 %d)
  %k = and i64 %h, 4294967295
  ret i64 %k
}

define i64 @rg_u8_lg(i64 %t) {
  %d = call i64 @rg_t_data(i64 %t)
  %h = call i64 @rg_ld(i64 %d)
  %lg = lshr i64 %h, 32
  ret i64 %lg
}

define i64 @rg_u8_count(i64 %t) {
entry:
  %d = call i64 @rg_t_data(i64 %t)
  %k = call i64 @rg_u8_rank(i64 %t)
  br label %loop
loop:
  %j = phi i64 [ 0, %entry ], [ %j1, %body ]
  %n = phi i64 [ 1, %entry ], [ %n1, %body ]
  %more = icmp slt i64 %j, %k
  br i1 %more, label %body, label %done
body:
  %j1 = add i64 %j, 1
  %x = call i64 @rg_word_at(i64 %d, i64 %j1)
  %n1 = mul i64 %n, %x
  br label %loop
done:
  ret i64 %n
}

; The address of the first byte.
define i64 @rg_u8_bytes(i64 %t) {
  %d = call i64 @rg_t_data(i64 %t)
  %k = call i64 @rg_u8_rank(i64 %t)
  %w = add i64 %k, 1
  %o = shl i64 %w, 3
  %a = add i64 %d, %o
  ret i64 %a
}

; A new Tensor[U8] of rank k with the dimensions at dims (negative as 0),
; every byte fill.
define i64 @rg_u8_new(i64 %k, i64 %dims, i64 %fill) {
  %t = call i64 @rg_pk_new(i64 %k, i64 %dims, i64 %fill, i64 0)
  ret i64 %t
}

; The same for elements of 2^lg bytes.
define i64 @rg_pk_new(i64 %k, i64 %dims, i64 %fill, i64 %lg) {
entry:
  br label %prod
prod:
  %j = phi i64 [ 0, %entry ], [ %j1, %pbody ]
  %n = phi i64 [ 1, %entry ], [ %n1, %pbody ]
  %more = icmp slt i64 %j, %k
  br i1 %more, label %pbody, label %make
pbody:
  %x = call i64 @rg_word_at(i64 %dims, i64 %j)
  %pos = icmp sgt i64 %x, 0
  %x1 = select i1 %pos, i64 %x, i64 0
  %n1 = mul i64 %n, %x1
  %j1 = add i64 %j, 1
  br label %prod
make:
  %nb = shl i64 %n, %lg
  %n7 = add i64 %nb, 7
  %nw = lshr i64 %n7, 3
  %h = add i64 %k, 1
  %w = add i64 %h, %nw
  %t = call i64 @rg_t_new(i64 1, i64 %w)
  %sd = call i64 @rg_t_dims(i64 %t)
  call void @rg_st(i64 %sd, i64 %w)
  %d = call i64 @rg_t_data(i64 %t)
  %wb = shl i64 %w, 3
  call void @rg_fill(i64 %d, i8 0, i64 %wb)
  %lgs = shl i64 %lg, 32
  %hdr = or i64 %k, %lgs
  call void @rg_st(i64 %d, i64 %hdr)
  br label %dl
dl:
  %i = phi i64 [ 0, %make ], [ %i1, %dbody ]
  %dm = icmp slt i64 %i, %k
  br i1 %dm, label %dbody, label %bytes
dbody:
  %y = call i64 @rg_word_at(i64 %dims, i64 %i)
  %ypos = icmp sgt i64 %y, 0
  %y1 = select i1 %ypos, i64 %y, i64 0
  %i1 = add i64 %i, 1
  call void @rg_word_set(i64 %d, i64 %i1, i64 %y1)
  br label %dl
bytes:
  %b = call i64 @rg_u8_bytes(i64 %t)
  %fz = icmp eq i64 %fill, 0
  br i1 %fz, label %made, label %fl
fl:
  %fi = phi i64 [ 0, %bytes ], [ %fi1, %flb ]
  %fm = icmp ult i64 %fi, %n
  br i1 %fm, label %flb, label %made
flb:
  call void @rg_fuse_put(i64 %b, i64 %fi, i64 %lg, i64 %fill)
  %fi1 = add i64 %fi, 1
  br label %fl
made:
  ret i64 %t
}

; A one-dimensional Tensor[U8] with a copy of n bytes at src.
define i64 @rg_u8_from(i64 %src, i64 %n) {
  %dims = alloca i64, align 8
  store i64 %n, ptr %dims, align 8
  %dp = ptrtoint ptr %dims to i64
  %t = call i64 @rg_u8_new(i64 1, i64 %dp, i64 0)
  %b = call i64 @rg_u8_bytes(i64 %t)
  call void @rg_copy(i64 %b, i64 %src, i64 %n)
  ret i64 %t
}

; The bytes of a String or a Tensor[U8]: 1, with their address and count.
define i1 @rg_bytes_of(i64 %v, ptr %data, ptr %len) {
entry:
  %iss = call i1 @rg_has_tag(i64 %v, i64 1)
  br i1 %iss, label %str, label %t
str:
  %sd = call i64 @rg_str_data(i64 %v)
  %sl = call i64 @rg_str_len(i64 %v)
  store i64 %sd, ptr %data, align 8
  store i64 %sl, ptr %len, align 8
  ret i1 true
t:
  %ist = call i1 @rg_has_tag(i64 %v, i64 5)
  br i1 %ist, label %u8, label %no
u8:
  %b = call i64 @rg_u8_bytes(i64 %v)
  %n = call i64 @rg_u8_count(i64 %v)
  store i64 %b, ptr %data, align 8
  store i64 %n, ptr %len, align 8
  ret i1 true
no:
  store i64 0, ptr %data, align 8
  store i64 0, ptr %len, align 8
  ret i1 false
}

; The byte offset of the k indices at idx (cleared) in t; stops when the
; rank differs or an index is out of range.
define i64 @rg_u8_offset(i64 %t, i64 %idx, i64 %k) {
entry:
  %d = call i64 @rg_t_data(i64 %t)
  %rank = call i64 @rg_u8_rank(i64 %t)
  %same = icmp eq i64 %rank, %k
  br i1 %same, label %loop, label %bad
loop:
  %j = phi i64 [ 0, %entry ], [ %j1, %ok ]
  %off = phi i64 [ 0, %entry ], [ %off1, %ok ]
  %more = icmp slt i64 %j, %k
  br i1 %more, label %body, label %done
body:
  %sa0 = shl i64 %j, 3
  %sa = add i64 %idx, %sa0
  %iv = call i64 @rg_ld(i64 %sa)
  call void @rg_st(i64 %sa, i64 0)
  %x = call i64 @__rg_rt_drop_val(i64 %iv)
  %i = call i64 @rg_index_of(i64 %iv)
  %j1 = add i64 %j, 1
  %dim = call i64 @rg_word_at(i64 %d, i64 %j1)
  %in = icmp ult i64 %i, %dim
  br i1 %in, label %ok, label %bad
ok:
  %m = mul i64 %off, %dim
  %off1 = add i64 %m, %i
  br label %loop
done:
  ret i64 %off
bad:
  call void @rg_oob()
  unreachable
}

; An integer argument (an Int, or the payload of a boxed number).
define i64 @rg_int_arg(i64 %v) {
  %w = call i64 @rg_raw_word(i64 %v)
  ret i64 %w
}

define i64 @rg_slot_at(i64 %slots, i64 %i) alwaysinline {
  %o = shl i64 %i, 3
  %a = add i64 %slots, %o
  %v = call i64 @rg_ld(i64 %a)
  ret i64 %v
}

; An element of 2^lg bytes: 0 .. 2^(8 * 2^lg) - 1.
define void @rg_pk_check(i64 %b, i64 %lg) {
entry:
  switch i64 %lg, label %w1 [ i64 1, label %w2
                              i64 2, label %w4 ]
w1:
  call void @rg_u8_check(i64 %b)
  ret void
w2:
  %ok2 = icmp ult i64 %b, 65536
  br i1 %ok2, label %good, label %bad2
w4:
  %ok4 = icmp ult i64 %b, 4294967296
  br i1 %ok4, label %good, label %bad4
good:
  ret void
bad2:
  call void @rg_fatal(ptr @rg_msg_u16, i64 27)
  unreachable
bad4:
  call void @rg_fatal(ptr @rg_msg_u32, i64 32)
  unreachable
}

define void @rg_u8_check(i64 %b) {
entry:
  %ok = icmp ult i64 %b, 256
  br i1 %ok, label %good, label %bad
good:
  ret void
bad:
  call void @rg_fatal(ptr @rg_msg_u8, i64 24)
  unreachable
}

; 104 (fill, d1 .. dk)
define i64 @rg_u8_new_b(i64 %slots, i64 %n) {
entry:
  %dims = alloca [16 x i64], align 8
  %dp = ptrtoint ptr %dims to i64
  %fv = call i64 @rg_slot_at(i64 %slots, i64 0)
  %fill = call i64 @rg_int_arg(i64 %fv)
  call void @rg_u8_check(i64 %fill)
  %k0 = sub i64 %n, 1
  %big = icmp sgt i64 %k0, 16
  %k = select i1 %big, i64 16, i64 %k0
  br label %loop
loop:
  %j = phi i64 [ 0, %entry ], [ %j1, %body ]
  %more = icmp slt i64 %j, %k
  br i1 %more, label %body, label %done
body:
  %j1 = add i64 %j, 1
  %dv = call i64 @rg_slot_at(i64 %slots, i64 %j1)
  %d = call i64 @rg_int_arg(i64 %dv)
  call void @rg_word_set(i64 %dp, i64 %j, i64 %d)
  br label %loop
done:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %t = call i64 @rg_u8_new(i64 %k, i64 %dp, i64 %fill)
  ret i64 %t
}

; 141 (lg, fill, d1 .. dk): a packed tensor of elements of 2^lg bytes.
define i64 @rg_pk_new_b(i64 %slots, i64 %n) {
entry:
  %dims = alloca [16 x i64], align 8
  %dp = ptrtoint ptr %dims to i64
  %lv = call i64 @rg_slot_at(i64 %slots, i64 0)
  %lg = call i64 @rg_int_arg(i64 %lv)
  %fv = call i64 @rg_slot_at(i64 %slots, i64 1)
  %fill = call i64 @rg_int_arg(i64 %fv)
  call void @rg_pk_check(i64 %fill, i64 %lg)
  %k0 = sub i64 %n, 2
  %big = icmp sgt i64 %k0, 16
  %k = select i1 %big, i64 16, i64 %k0
  br label %loop
loop:
  %j = phi i64 [ 0, %entry ], [ %j1, %body ]
  %more = icmp slt i64 %j, %k
  br i1 %more, label %body, label %done
body:
  %j1 = add i64 %j, 1
  %j2 = add i64 %j, 2
  %dv = call i64 @rg_slot_at(i64 %slots, i64 %j2)
  %d = call i64 @rg_int_arg(i64 %dv)
  call void @rg_word_set(i64 %dp, i64 %j, i64 %d)
  br label %loop
done:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %t = call i64 @rg_pk_new(i64 %k, i64 %dp, i64 %fill, i64 %lg)
  ret i64 %t
}

; ── Bytes and words, and tensors side by side (FR-COMP-031) ───
; The elements of a packed tensor are stored in the order of their bytes
; (the low byte first), so its bytes and its words are the same memory.

; 142: a Tensor[U8] of one dimension with the bytes of a packed tensor.
define i64 @rg_pk_bytes(i64 %t) {
  %lg = call i64 @rg_u8_lg(i64 %t)
  %n = call i64 @rg_u8_count(i64 %t)
  %nb = shl i64 %n, %lg
  %dims = alloca i64, align 8
  store i64 %nb, ptr %dims, align 8
  %dp = ptrtoint ptr %dims to i64
  %r = call i64 @rg_u8_new(i64 1, i64 %dp, i64 0)
  %dst = call i64 @rg_u8_bytes(i64 %r)
  %src = call i64 @rg_u8_bytes(i64 %t)
  call void @rg_copy(i64 %dst, i64 %src, i64 %nb)
  ret i64 %r
}

; 143, 145: a packed tensor of one dimension, of elements of 2^lg bytes, with
; the bytes of a Tensor[U8]; stops when the bytes are not a whole number of
; elements.
define i64 @rg_pk_words(i64 %b, i64 %lg) {
entry:
  %nb = call i64 @rg_u8_count(i64 %b)
  %size = shl i64 1, %lg
  %mask = sub i64 %size, 1
  %rest = and i64 %nb, %mask
  %whole = icmp eq i64 %rest, 0
  br i1 %whole, label %make, label %bad
make:
  %n = lshr i64 %nb, %lg
  %dims = alloca i64, align 8
  store i64 %n, ptr %dims, align 8
  %dp = ptrtoint ptr %dims to i64
  %r = call i64 @rg_pk_new(i64 1, i64 %dp, i64 0, i64 %lg)
  %dst = call i64 @rg_u8_bytes(i64 %r)
  %src = call i64 @rg_u8_bytes(i64 %b)
  call void @rg_copy(i64 %dst, i64 %src, i64 %nb)
  ret i64 %r
bad:
  call void @rg_fatal(ptr @rg_msg_words, i64 80)
  unreachable
}

; 144 (list, lg): the k tensors of the list (each of n elements of 2^lg
; bytes; lg 3: words) side by side: a tensor of one dimension of n * k
; elements, element i * k + j the element i of tensor j.
define i64 @rg_interleave(i64 %xs, i64 %lg) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  %k0 = call i64 @rg_list_len(i64 %xs)
  %k = select i1 %isl, i64 %k0, i64 0
  %none = icmp eq i64 %k, 0
  br i1 %none, label %empty, label %first
empty:
  call void @rg_fatal(ptr @rg_msg_ilv0, i64 32)
  unreachable
first:
  %fa = call i64 @rg_list_at(i64 %xs, i64 0)
  %f0 = call i64 @rg_ld(i64 %fa)
  %f = call i64 @rg_fuse_leaf(i64 %f0)
  %n = call i64 @rg_fuse_len(i64 %f, i64 %lg)
  %total = mul i64 %n, %k
  %dims = alloca i64, align 8
  store i64 %total, ptr %dims, align 8
  %dp = ptrtoint ptr %dims to i64
  %packed = icmp ult i64 %lg, 3
  br i1 %packed, label %pk, label %wd
pk:
  %rp = call i64 @rg_pk_new(i64 1, i64 %dp, i64 0, i64 %lg)
  br label %fill
wd:
  %rw = call i64 @rg_t_new(i64 1, i64 %total)
  %rwd = call i64 @rg_t_dims(i64 %rw)
  call void @rg_st(i64 %rwd, i64 %total)
  br label %fill
fill:
  %r = phi i64 [ %rp, %pk ], [ %rw, %wd ]
  %dst = call i64 @rg_fuse_data(i64 %r, i64 %lg)
  br label %each
each:
  %j = phi i64 [ 0, %fill ], [ %j1, %next ]
  %jm = icmp ult i64 %j, %k
  br i1 %jm, label %one, label %done
one:
  %ta = call i64 @rg_list_at(i64 %xs, i64 %j)
  %t0 = call i64 @rg_ld(i64 %ta)
  %t = call i64 @rg_fuse_leaf(i64 %t0)
  %tn = call i64 @rg_fuse_len(i64 %t, i64 %lg)
  %same = icmp eq i64 %tn, %n
  br i1 %same, label %copy, label %differ
copy:
  %src = call i64 @rg_fuse_data(i64 %t, i64 %lg)
  br label %elem
elem:
  %i = phi i64 [ 0, %copy ], [ %i1, %put ]
  %im = icmp ult i64 %i, %n
  br i1 %im, label %put, label %next
put:
  %v = call i64 @rg_fuse_get(i64 %src, i64 %i, i64 %lg)
  %at0 = mul i64 %i, %k
  %at = add i64 %at0, %j
  call void @rg_fuse_put(i64 %dst, i64 %at, i64 %lg, i64 %v)
  %i1 = add i64 %i, 1
  br label %elem
next:
  %j1 = add i64 %j, 1
  br label %each
differ:
  call void @rg_fatal(ptr @rg_msg_ilv, i64 65)
  unreachable
done:
  ret i64 %r
}

; 105 (i1 .. ik, t borrowed)
define i64 @rg_u8_get_b(i64 %slots, i64 %n) {
  %k = sub i64 %n, 1
  %ta0 = shl i64 %k, 3
  %ta = add i64 %slots, %ta0
  %t = call i64 @rg_ld(i64 %ta)
  call void @rg_st(i64 %ta, i64 0)
  %off = call i64 @rg_u8_offset(i64 %t, i64 %slots, i64 %k)
  %b = call i64 @rg_u8_bytes(i64 %t)
  %lg = call i64 @rg_u8_lg(i64 %t)
  %x = call i64 @rg_fuse_get(i64 %b, i64 %off, i64 %lg)
  %r = call i64 @rg_int(i64 %x)
  ret i64 %r
}

; 106 (i1 .. ik, v, t borrowed)
define i64 @rg_u8_set_b(i64 %slots, i64 %n) {
  %k1 = sub i64 %n, 1
  %ta0 = shl i64 %k1, 3
  %ta = add i64 %slots, %ta0
  %t = call i64 @rg_ld(i64 %ta)
  call void @rg_st(i64 %ta, i64 0)
  %k = sub i64 %n, 2
  %va0 = shl i64 %k, 3
  %va = add i64 %slots, %va0
  %vv = call i64 @rg_ld(i64 %va)
  %v = call i64 @rg_int_arg(i64 %vv)
  %lg = call i64 @rg_u8_lg(i64 %t)
  call void @rg_pk_check(i64 %v, i64 %lg)
  call void @rg_st(i64 %va, i64 0)
  %x = call i64 @__rg_rt_drop_val(i64 %vv)
  %off = call i64 @rg_u8_offset(i64 %t, i64 %slots, i64 %k)
  %b = call i64 @rg_u8_bytes(i64 %t)
  call void @rg_fuse_put(i64 %b, i64 %off, i64 %lg, i64 %v)
  ret i64 0
}

; 107 (k, t borrowed): the rank (k = 0) or dimension k.
define i64 @rg_u8_dim_b(i64 %slots) {
entry:
  %kv = call i64 @rg_ld(i64 %slots)
  %k = call i64 @rg_int_arg(i64 %kv)
  call void @rg_st(i64 %slots, i64 0)
  %s1 = add i64 %slots, 8
  %t = call i64 @rg_ld(i64 %s1)
  call void @rg_st(i64 %s1, i64 0)
  %d = call i64 @rg_t_data(i64 %t)
  %rank = call i64 @rg_u8_rank(i64 %t)
  %z = icmp eq i64 %k, 0
  br i1 %z, label %r, label %dim
r:
  %rr = call i64 @rg_int(i64 %rank)
  ret i64 %rr
dim:
  %in = icmp ule i64 %k, %rank
  br i1 %in, label %get, label %zero
get:
  %x = call i64 @rg_word_at(i64 %d, i64 %k)
  %rx = call i64 @rg_int(i64 %x)
  ret i64 %rx
zero:
  %r0 = call i64 @rg_int(i64 0)
  ret i64 %r0
}

; A List of Ints, one per byte of t.
define i64 @rg_u8_to_list(i64 %t) {
entry:
  %n = call i64 @rg_u8_count(i64 %t)
  %b = call i64 @rg_u8_bytes(i64 %t)
  %lg = call i64 @rg_u8_lg(i64 %t)
  %out = call i64 @rg_list_alloc(i64 %n, i64 %n)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %x = call i64 @rg_fuse_get(i64 %b, i64 %i, i64 %lg)
  %v = call i64 @rg_int(i64 %x)
  %oa = call i64 @rg_list_at(i64 %out, i64 %i)
  call void @rg_st(i64 %oa, i64 %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %out
}

; A numeric tensor of the same shape, one word per byte (echo).
define i64 @rg_u8_to_words(i64 %t) {
entry:
  %d = call i64 @rg_t_data(i64 %t)
  %k = call i64 @rg_u8_rank(i64 %t)
  %lg = call i64 @rg_u8_lg(i64 %t)
  %n = call i64 @rg_u8_count(i64 %t)
  %r = call i64 @rg_t_new(i64 %k, i64 %n)
  %rdims = call i64 @rg_t_dims(i64 %r)
  %src = add i64 %d, 8
  %kb = shl i64 %k, 3
  call void @rg_copy(i64 %rdims, i64 %src, i64 %kb)
  %rd = call i64 @rg_t_data(i64 %r)
  %b = call i64 @rg_u8_bytes(i64 %t)
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %x = call i64 @rg_fuse_get(i64 %b, i64 %i, i64 %lg)
  call void @rg_word_set(i64 %rd, i64 %i, i64 %x)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %r
}

; A Tensor[U8] from a List of Ints 0 .. 255.
define i64 @rg_u8_from_list(i64 %xs) {
entry:
  %isl = call i1 @rg_has_tag(i64 %xs, i64 2)
  %n0 = call i64 @rg_list_len(i64 %xs)
  %n = select i1 %isl, i64 %n0, i64 0
  br label %chk
chk:
  %i = phi i64 [ 0, %entry ], [ %i1, %cbody ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %cbody, label %make
cbody:
  %ea = call i64 @rg_list_at(i64 %xs, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  %x = call i64 @rg_int_arg(i64 %e)
  call void @rg_u8_check(i64 %x)
  %i1 = add i64 %i, 1
  br label %chk
make:
  %dims = alloca i64, align 8
  store i64 %n, ptr %dims, align 8
  %dp = ptrtoint ptr %dims to i64
  %t = call i64 @rg_u8_new(i64 1, i64 %dp, i64 0)
  %b = call i64 @rg_u8_bytes(i64 %t)
  br label %fill
fill:
  %j = phi i64 [ 0, %make ], [ %j1, %fbody ]
  %fm = icmp slt i64 %j, %n
  br i1 %fm, label %fbody, label %done
fbody:
  %fa = call i64 @rg_list_at(i64 %xs, i64 %j)
  %fe = call i64 @rg_ld(i64 %fa)
  %fx = call i64 @rg_int_arg(i64 %fe)
  %ba = add i64 %b, %j
  call void @rg_stb(i64 %ba, i64 %fx)
  %j1 = add i64 %j, 1
  br label %fill
done:
  ret i64 %t
}

; ── CRC-32 (IEEE 802.3, reflected 0xEDB88320) ────────────────

define void @rg_crc_init() {
entry:
  br label %outer
outer:
  %i = phi i32 [ 0, %entry ], [ %i1, %store ]
  %om = icmp ult i32 %i, 256
  br i1 %om, label %bits, label %done
bits:
  br label %inner
inner:
  %c = phi i32 [ %i, %bits ], [ %c1, %inner ]
  %k = phi i32 [ 0, %bits ], [ %k1, %inner ]
  %low = and i32 %c, 1
  %sh = lshr i32 %c, 1
  %x = xor i32 %sh, -306674912
  %odd = icmp ne i32 %low, 0
  %c1 = select i1 %odd, i32 %x, i32 %sh
  %k1 = add i32 %k, 1
  %km = icmp ult i32 %k1, 8
  br i1 %km, label %inner, label %store
store:
  %ie = zext i32 %i to i64
  %p = getelementptr inbounds [256 x i32], ptr @rg_crc_tab, i64 0, i64 %ie
  store i32 %c1, ptr %p, align 4
  %i1 = add i32 %i, 1
  br label %outer
done:
  store i1 true, ptr @rg_crc_ready, align 1
  ret void
}

define i64 @rg_crc32(i64 %crc, i64 %p, i64 %n) {
entry:
  %ready = load i1, ptr @rg_crc_ready, align 1
  br i1 %ready, label %go, label %init
init:
  call void @rg_crc_init()
  br label %go
go:
  %c0 = trunc i64 %crc to i32
  %c0n = xor i32 %c0, -1
  br label %loop
loop:
  %i = phi i64 [ 0, %go ], [ %i1, %body ]
  %c = phi i32 [ %c0n, %go ], [ %c1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %a = add i64 %p, %i
  %b = call i64 @rg_ldb(i64 %a)
  %b32 = trunc i64 %b to i32
  %x = xor i32 %c, %b32
  %ix = and i32 %x, 255
  %ie = zext i32 %ix to i64
  %tp = getelementptr inbounds [256 x i32], ptr @rg_crc_tab, i64 0, i64 %ie
  %tv = load i32, ptr %tp, align 4
  %sh = lshr i32 %c, 8
  %c1 = xor i32 %tv, %sh
  %i1 = add i64 %i, 1
  br label %loop
done:
  %r = xor i32 %c, -1
  %r64 = zext i32 %r to i64
  ret i64 %r64
}

; 103 (data, from, to, crc)
define i64 @rg_crc_b(i64 %slots, i64 %n) {
entry:
  %dp = alloca i64, align 8
  %lp = alloca i64, align 8
  %v = call i64 @rg_slot_at(i64 %slots, i64 0)
  %fv = call i64 @rg_slot_at(i64 %slots, i64 1)
  %tv = call i64 @rg_slot_at(i64 %slots, i64 2)
  %cv = call i64 @rg_slot_at(i64 %slots, i64 3)
  %from = call i64 @rg_int_arg(i64 %fv)
  %to = call i64 @rg_int_arg(i64 %tv)
  %crc = call i64 @rg_int_arg(i64 %cv)
  %ok = call i1 @rg_bytes_of(i64 %v, ptr %dp, ptr %lp)
  %d = load i64, ptr %dp, align 8
  %l = load i64, ptr %lp, align 8
  %neg = icmp slt i64 %from, 0
  %rev = icmp sgt i64 %from, %to
  %past = icmp sgt i64 %to, %l
  %b1 = or i1 %neg, %rev
  %b2 = or i1 %b1, %past
  %nok = xor i1 %ok, true
  %bad = or i1 %b2, %nok
  br i1 %bad, label %fail, label %go
fail:
  call void @rg_fatal(ptr @rg_msg_crc, i64 32)
  unreachable
go:
  %s = add i64 %d, %from
  %len = sub i64 %to, %from
  %r = call i64 @rg_crc32(i64 %crc, i64 %s, i64 %len)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ri = call i64 @rg_int(i64 %r)
  ret i64 %ri
}

; ── SHA-256 (FIPS 180-4) ─────────────────────────────────────

; Byte pos of the padded message of n bytes at src, `end` bytes in all.
define i64 @rg_sha_byte(i64 %src, i64 %n, i64 %end, i64 %pos) {
entry:
  %in = icmp ult i64 %pos, %n
  br i1 %in, label %data, label %pad
data:
  %a = add i64 %src, %pos
  %b = call i64 @rg_ldb(i64 %a)
  ret i64 %b
pad:
  %one = icmp eq i64 %pos, %n
  br i1 %one, label %mark, label %tail
mark:
  ret i64 128
tail:
  %lstart = sub i64 %end, 8
  %inlen = icmp uge i64 %pos, %lstart
  br i1 %inlen, label %len, label %zero
len:
  %j = sub i64 %pos, %lstart
  %bits = shl i64 %n, 3
  %j8 = shl i64 %j, 3
  %sh = sub i64 56, %j8
  %s = lshr i64 %bits, %sh
  %r = and i64 %s, 255
  ret i64 %r
zero:
  ret i64 0
}

define i32 @rg_rotr(i32 %x, i32 %r) alwaysinline {
  %v = call i32 @llvm.fshr.i32(i32 %x, i32 %x, i32 %r)
  ret i32 %v
}

; The 32-byte digest of n bytes at src, written at out.
define void @rg_sha256(i64 %src, i64 %n, i64 %out) {
entry:
  %h = alloca [8 x i32], align 4
  %w = alloca [64 x i32], align 4
  call void @llvm.memcpy.p0.p0.i64(ptr %h, ptr @rg_sha_h0, i64 32, i1 false)
  %n9 = add i64 %n, 72
  %nb = lshr i64 %n9, 6
  %end = shl i64 %nb, 6
  br label %block
block:
  %bi = phi i64 [ 0, %entry ], [ %bi1, %bdone ]
  %bm = icmp ult i64 %bi, %nb
  br i1 %bm, label %load, label %emit
load:
  %base = shl i64 %bi, 6
  br label %wl
wl:
  %t = phi i64 [ 0, %load ], [ %t1, %wput ]
  %tm = icmp ult i64 %t, 16
  br i1 %tm, label %wbytes, label %sched
wbytes:
  %p0 = shl i64 %t, 2
  %p = add i64 %base, %p0
  %y0 = call i64 @rg_sha_byte(i64 %src, i64 %n, i64 %end, i64 %p)
  %pa = add i64 %p, 1
  %y1 = call i64 @rg_sha_byte(i64 %src, i64 %n, i64 %end, i64 %pa)
  %pb = add i64 %p, 2
  %y2 = call i64 @rg_sha_byte(i64 %src, i64 %n, i64 %end, i64 %pb)
  %pc = add i64 %p, 3
  %y3 = call i64 @rg_sha_byte(i64 %src, i64 %n, i64 %end, i64 %pc)
  %z0 = shl i64 %y0, 24
  %z1 = shl i64 %y1, 16
  %z2 = shl i64 %y2, 8
  %o1 = or i64 %z0, %z1
  %o2 = or i64 %o1, %z2
  %o3 = or i64 %o2, %y3
  %wv = trunc i64 %o3 to i32
  br label %wput
wput:
  %wp = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %t
  store i32 %wv, ptr %wp, align 4
  %t1 = add i64 %t, 1
  br label %wl
sched:
  %s = phi i64 [ 16, %wl ], [ %s1, %sbody ]
  %sm = icmp ult i64 %s, 64
  br i1 %sm, label %sbody, label %comp
sbody:
  %i15 = sub i64 %s, 15
  %i2 = sub i64 %s, 2
  %i16 = sub i64 %s, 16
  %i7 = sub i64 %s, 7
  %a15 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i15
  %v15 = load i32, ptr %a15, align 4
  %a2 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i2
  %v2 = load i32, ptr %a2, align 4
  %a16 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i16
  %v16 = load i32, ptr %a16, align 4
  %a7 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %i7
  %v7 = load i32, ptr %a7, align 4
  %r7 = call i32 @rg_rotr(i32 %v15, i32 7)
  %r18 = call i32 @rg_rotr(i32 %v15, i32 18)
  %q3 = lshr i32 %v15, 3
  %x0a = xor i32 %r7, %r18
  %s0 = xor i32 %x0a, %q3
  %r17 = call i32 @rg_rotr(i32 %v2, i32 17)
  %r19 = call i32 @rg_rotr(i32 %v2, i32 19)
  %q10 = lshr i32 %v2, 10
  %x1a = xor i32 %r17, %r19
  %s1v = xor i32 %x1a, %q10
  %sum1 = add i32 %v16, %s0
  %sum2 = add i32 %sum1, %v7
  %sum3 = add i32 %sum2, %s1v
  %as = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %s
  store i32 %sum3, ptr %as, align 4
  %s1 = add i64 %s, 1
  br label %sched
comp:
  %hp0 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 0
  %ha = load i32, ptr %hp0, align 4
  %hp1 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 1
  %hb = load i32, ptr %hp1, align 4
  %hp2 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 2
  %hc = load i32, ptr %hp2, align 4
  %hp3 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 3
  %hd = load i32, ptr %hp3, align 4
  %hp4 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 4
  %he = load i32, ptr %hp4, align 4
  %hp5 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 5
  %hf = load i32, ptr %hp5, align 4
  %hp6 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 6
  %hg = load i32, ptr %hp6, align 4
  %hp7 = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 7
  %hh = load i32, ptr %hp7, align 4
  br label %round
round:
  %r = phi i64 [ 0, %comp ], [ %r1, %rbody ]
  %a = phi i32 [ %ha, %comp ], [ %na, %rbody ]
  %b = phi i32 [ %hb, %comp ], [ %a, %rbody ]
  %c = phi i32 [ %hc, %comp ], [ %b, %rbody ]
  %d = phi i32 [ %hd, %comp ], [ %c, %rbody ]
  %e = phi i32 [ %he, %comp ], [ %ne, %rbody ]
  %f = phi i32 [ %hf, %comp ], [ %e, %rbody ]
  %g = phi i32 [ %hg, %comp ], [ %f, %rbody ]
  %hv = phi i32 [ %hh, %comp ], [ %g, %rbody ]
  %rm = icmp ult i64 %r, 64
  br i1 %rm, label %rbody, label %add
rbody:
  %e6 = call i32 @rg_rotr(i32 %e, i32 6)
  %e11 = call i32 @rg_rotr(i32 %e, i32 11)
  %e25 = call i32 @rg_rotr(i32 %e, i32 25)
  %S1a = xor i32 %e6, %e11
  %S1 = xor i32 %S1a, %e25
  %ef = and i32 %e, %f
  %ne0 = xor i32 %e, -1
  %eg = and i32 %ne0, %g
  %ch = xor i32 %ef, %eg
  %kp = getelementptr inbounds [64 x i32], ptr @rg_sha_k, i64 0, i64 %r
  %kv = load i32, ptr %kp, align 4
  %wp2 = getelementptr inbounds [64 x i32], ptr %w, i64 0, i64 %r
  %wv2 = load i32, ptr %wp2, align 4
  %t1a = add i32 %hv, %S1
  %t1b = add i32 %t1a, %ch
  %t1c = add i32 %t1b, %kv
  %T1 = add i32 %t1c, %wv2
  %a2r = call i32 @rg_rotr(i32 %a, i32 2)
  %a13 = call i32 @rg_rotr(i32 %a, i32 13)
  %a22 = call i32 @rg_rotr(i32 %a, i32 22)
  %S0a = xor i32 %a2r, %a13
  %S0 = xor i32 %S0a, %a22
  %ab = and i32 %a, %b
  %ac = and i32 %a, %c
  %bc = and i32 %b, %c
  %mja = xor i32 %ab, %ac
  %maj = xor i32 %mja, %bc
  %T2 = add i32 %S0, %maj
  %ne = add i32 %d, %T1
  %na = add i32 %T1, %T2
  %r1 = add i64 %r, 1
  br label %round
add:
  %fa = add i32 %ha, %a
  store i32 %fa, ptr %hp0, align 4
  %fb = add i32 %hb, %b
  store i32 %fb, ptr %hp1, align 4
  %fc = add i32 %hc, %c
  store i32 %fc, ptr %hp2, align 4
  %fd = add i32 %hd, %d
  store i32 %fd, ptr %hp3, align 4
  %fe = add i32 %he, %e
  store i32 %fe, ptr %hp4, align 4
  %ff = add i32 %hf, %f
  store i32 %ff, ptr %hp5, align 4
  %fg = add i32 %hg, %g
  store i32 %fg, ptr %hp6, align 4
  %fh = add i32 %hh, %hv
  store i32 %fh, ptr %hp7, align 4
  br label %bdone
bdone:
  %bi1 = add i64 %bi, 1
  br label %block
emit:
  br label %ol
ol:
  %oi = phi i64 [ 0, %emit ], [ %oi1, %obody ]
  %om = icmp ult i64 %oi, 32
  br i1 %om, label %obody, label %fin
obody:
  %wi = lshr i64 %oi, 2
  %hpi = getelementptr inbounds [8 x i32], ptr %h, i64 0, i64 %wi
  %hw = load i32, ptr %hpi, align 4
  %bpos = and i64 %oi, 3
  %b8 = shl i64 %bpos, 3
  %shb = sub i64 24, %b8
  %sh32 = trunc i64 %shb to i32
  %byte32 = lshr i32 %hw, %sh32
  %byte = zext i32 %byte32 to i64
  %bb = and i64 %byte, 255
  %oa = add i64 %out, %oi
  call void @rg_stb(i64 %oa, i64 %bb)
  %oi1 = add i64 %oi, 1
  br label %ol
fin:
  ret void
}

declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)

; The digest of a String or a Tensor[U8] (borrowed) at out.
define void @rg_sha_of(i64 %v, i64 %out) {
  %dp = alloca i64, align 8
  %lp = alloca i64, align 8
  %ok = call i1 @rg_bytes_of(i64 %v, ptr %dp, ptr %lp)
  %d = load i64, ptr %dp, align 8
  %l = load i64, ptr %lp, align 8
  call void @rg_sha256(i64 %d, i64 %l, i64 %out)
  ret void
}

; 64 lowercase hex digits of the 32 bytes at dg.
define i64 @rg_hex_of(i64 %dg) {
entry:
  %s = call i64 @rg_str_alloc(i64 64, i64 64)
  %sd = call i64 @rg_str_data(i64 %s)
  %hex = ptrtoint ptr @rg_hex to i64
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp ult i64 %i, 32
  br i1 %more, label %body, label %done
body:
  %a = add i64 %dg, %i
  %b = call i64 @rg_ldb(i64 %a)
  %hi = lshr i64 %b, 4
  %lo = and i64 %b, 15
  %ha = add i64 %hex, %hi
  %hc = call i64 @rg_ldb(i64 %ha)
  %la = add i64 %hex, %lo
  %lc = call i64 @rg_ldb(i64 %la)
  %o = shl i64 %i, 1
  %oa = add i64 %sd, %o
  call void @rg_stb(i64 %oa, i64 %hc)
  %ob = add i64 %oa, 1
  call void @rg_stb(i64 %ob, i64 %lc)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %s
}

; 20 (path), 21 (s), 36 / 117 (s or bytes), 118 (s or bytes), 89 (a, b).
define i64 @rg_sha_b(i64 %id, i64 %slots, i64 %n) {
entry:
  %dg = alloca [32 x i8], align 8
  %dp = ptrtoint ptr %dg to i64
  %v = call i64 @rg_slot_at(i64 %slots, i64 0)
  switch i64 %id, label %plain [ i64 20, label %file
                                 i64 89, label %two ]
file:
  %text = call i64 @rg_read_file(i64 %v)
  call void @rg_sha_of(i64 %text, i64 %dp)
  %x = call i64 @__rg_rt_drop_val(i64 %text)
  br label %result
two:
  %ap = alloca i64, align 8
  %al = alloca i64, align 8
  %bp = alloca i64, align 8
  %bl = alloca i64, align 8
  %w = call i64 @rg_slot_at(i64 %slots, i64 1)
  %oka = call i1 @rg_bytes_of(i64 %v, ptr %ap, ptr %al)
  %okb = call i1 @rg_bytes_of(i64 %w, ptr %bp, ptr %bl)
  %ad = load i64, ptr %ap, align 8
  %an = load i64, ptr %al, align 8
  %bd = load i64, ptr %bp, align 8
  %bn = load i64, ptr %bl, align 8
  %tot = add i64 %an, %bn
  %cap = add i64 %tot, 8
  %buf = call i64 @rg_alloc(i64 %cap)
  call void @rg_copy(i64 %buf, i64 %ad, i64 %an)
  %bufb = add i64 %buf, %an
  call void @rg_copy(i64 %bufb, i64 %bd, i64 %bn)
  call void @rg_sha256(i64 %buf, i64 %tot, i64 %dp)
  call void @rg_free(i64 %buf)
  br label %raw
plain:
  call void @rg_sha_of(i64 %v, i64 %dp)
  %ishex = icmp eq i64 %id, 21
  br i1 %ishex, label %result, label %kind
kind:
  %isdig = icmp eq i64 %id, 118
  br i1 %isdig, label %digest, label %raw
result:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %h = call i64 @rg_hex_of(i64 %dp)
  ret i64 %h
raw:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %s = call i64 @rg_str_from(i64 %dp, i64 32)
  ret i64 %s
digest:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %t = call i64 @rg_u8_from(i64 %dp, i64 32)
  ret i64 %t
}

; ── Byte I/O ─────────────────────────────────────────────────

; 112 read bytes (path): the content, or an empty Tensor[U8].
define i64 @rg_read_bytes_b(i64 %slots, i64 %n) {
  %p = call i64 @rg_slot_at(i64 %slots, i64 0)
  %s = call i64 @rg_read_file(i64 %p)
  %sd = call i64 @rg_str_data(i64 %s)
  %sl = call i64 @rg_str_len(i64 %s)
  %t = call i64 @rg_u8_from(i64 %sd, i64 %sl)
  %x = call i64 @__rg_rt_drop_val(i64 %s)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %t
}

; 113 write bytes (path, Tensor[U8] or List of Ints 0 .. 255): gives ().
define i64 @rg_write_bytes_b(i64 %slots, i64 %n) {
entry:
  %dp = alloca i64, align 8
  %lp = alloca i64, align 8
  %p = call i64 @rg_slot_at(i64 %slots, i64 0)
  %v = call i64 @rg_slot_at(i64 %slots, i64 1)
  %isl = call i1 @rg_has_tag(i64 %v, i64 2)
  br i1 %isl, label %list, label %bytes
list:
  %xn = call i64 @rg_list_len(i64 %v)
  %cap = add i64 %xn, 8
  %buf = call i64 @rg_alloc(i64 %cap)
  br label %ll
ll:
  %i = phi i64 [ 0, %list ], [ %i1, %lok ]
  %more = icmp slt i64 %i, %xn
  br i1 %more, label %lbody, label %lwrite
lbody:
  %ea = call i64 @rg_list_at(i64 %v, i64 %i)
  %e = call i64 @rg_ld(i64 %ea)
  %x = call i64 @rg_int_arg(i64 %e)
  %ok = icmp ult i64 %x, 256
  br i1 %ok, label %lok, label %lbad
lbad:
  call void @rg_fatal(ptr @rg_msg_wbytes, i64 34)
  unreachable
lok:
  %ba = add i64 %buf, %i
  call void @rg_stb(i64 %ba, i64 %x)
  %i1 = add i64 %i, 1
  br label %ll
lwrite:
  call void @rg_write_out(i64 %p, i64 %buf, i64 %xn)
  call void @rg_free(i64 %buf)
  br label %done
bytes:
  %has = call i1 @rg_bytes_of(i64 %v, ptr %dp, ptr %lp)
  %d = load i64, ptr %dp, align 8
  %l = load i64, ptr %lp, align 8
  br i1 %has, label %bw, label %empty
bw:
  call void @rg_write_out(i64 %p, i64 %d, i64 %l)
  br label %done
empty:
  call void @rg_write_out(i64 %p, i64 0, i64 0)
  br label %done
done:
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 0
}

; Replace the file at path (a String) with n bytes at d.
define void @rg_write_out(i64 %path, i64 %d, i64 %n) {
entry:
  %ps = call i1 @rg_has_tag(i64 %path, i64 1)
  br i1 %ps, label %open, label %done
open:
  %pd = call i64 @rg_str_data(i64 %path)
  %pl = call i64 @rg_str_len(i64 %path)
  %fd = call i64 @__rg_pal_open(i64 %pd, i64 %pl, i64 577, i64 420)
  %bad = icmp slt i64 %fd, 0
  br i1 %bad, label %done, label %write
write:
  %w = call i64 @rg_write_fd_all(i64 %fd, i64 %d, i64 %n)
  %c = call i64 @__rg_pal_close(i64 %fd)
  br label %done
done:
  ret void
}

; 114 / 115 (fd, t, from, count): read into / write from a byte range.
define i64 @rg_fd_range_b(i64 %id, i64 %slots, i64 %n) {
entry:
  %dp = alloca i64, align 8
  %lp = alloca i64, align 8
  %fv = call i64 @rg_slot_at(i64 %slots, i64 0)
  %t = call i64 @rg_slot_at(i64 %slots, i64 1)
  %av = call i64 @rg_slot_at(i64 %slots, i64 2)
  %cv = call i64 @rg_slot_at(i64 %slots, i64 3)
  %fd = call i64 @rg_int_arg(i64 %fv)
  %from = call i64 @rg_int_arg(i64 %av)
  %count = call i64 @rg_int_arg(i64 %cv)
  %ok = call i1 @rg_bytes_of(i64 %t, ptr %dp, ptr %lp)
  %d = load i64, ptr %dp, align 8
  %l = load i64, ptr %lp, align 8
  %b1 = icmp slt i64 %from, 0
  %b2 = icmp slt i64 %count, 0
  %b3 = icmp sgt i64 %from, %l
  %left = sub i64 %l, %from
  %b4 = icmp sgt i64 %count, %left
  %nok = xor i1 %ok, true
  %o1 = or i1 %b1, %b2
  %o2 = or i1 %o1, %b3
  %o3 = or i1 %o2, %b4
  %bad = or i1 %o3, %nok
  br i1 %bad, label %fail, label %go
fail:
  call void @rg_fatal(ptr @rg_msg_io, i64 24)
  unreachable
go:
  %a = add i64 %d, %from
  %rd = icmp eq i64 %id, 114
  br i1 %rd, label %read, label %write
read:
  %r1 = call i64 @__rg_pal_read(i64 %fd, i64 %a, i64 %count)
  br label %done
write:
  %r2 = call i64 @__rg_pal_write(i64 %fd, i64 %a, i64 %count)
  br label %done
done:
  %r = phi i64 [ %r1, %read ], [ %r2, %write ]
  call void @rg_drop_slots(i64 %slots, i64 %n)
  %ri = call i64 @rg_box_int(i64 %r)
  ret i64 %ri
}

; ── Dispatch ─────────────────────────────────────────────────

define i64 @rg_builtin_bytes(i64 %id, i64 %slots, i64 %n) {
entry:
  switch i64 %id, label %none [ i64 20, label %sha
                                i64 21, label %sha
                                i64 36, label %sha
                                i64 89, label %sha
                                i64 117, label %sha
                                i64 118, label %sha
                                i64 103, label %crc
                                i64 104, label %new
                                i64 105, label %get
                                i64 106, label %set
                                i64 107, label %dim
                                i64 108, label %fromstr
                                i64 109, label %tostr
                                i64 110, label %tolist
                                i64 111, label %towords
                                i64 112, label %readb
                                i64 113, label %writeb
                                i64 114, label %range
                                i64 115, label %range
                                i64 119, label %fromlist
                                i64 141, label %pknew
                                i64 142, label %bytesof
                                i64 143, label %words16
                                i64 145, label %words32
                                i64 144, label %ilv ]
bytesof:
  %v142 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %r142 = call i64 @rg_pk_bytes(i64 %v142)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r142
words16:
  %v143 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %r143 = call i64 @rg_pk_words(i64 %v143, i64 1)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r143
words32:
  %v145 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %r145 = call i64 @rg_pk_words(i64 %v145, i64 2)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r145
ilv:
  %v144 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %l144v = call i64 @rg_slot_at(i64 %slots, i64 1)
  %l144 = call i64 @rg_int_arg(i64 %l144v)
  %r144 = call i64 @rg_interleave(i64 %v144, i64 %l144)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r144
pknew:
  %r141 = call i64 @rg_pk_new_b(i64 %slots, i64 %n)
  ret i64 %r141
sha:
  %r0 = call i64 @rg_sha_b(i64 %id, i64 %slots, i64 %n)
  ret i64 %r0
crc:
  %r1 = call i64 @rg_crc_b(i64 %slots, i64 %n)
  ret i64 %r1
new:
  %r2 = call i64 @rg_u8_new_b(i64 %slots, i64 %n)
  ret i64 %r2
get:
  %r3 = call i64 @rg_u8_get_b(i64 %slots, i64 %n)
  ret i64 %r3
set:
  %r4 = call i64 @rg_u8_set_b(i64 %slots, i64 %n)
  ret i64 %r4
dim:
  %r5 = call i64 @rg_u8_dim_b(i64 %slots)
  ret i64 %r5
fromstr:
  %v6 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %dp6 = alloca i64, align 8
  %lp6 = alloca i64, align 8
  %ok6 = call i1 @rg_bytes_of(i64 %v6, ptr %dp6, ptr %lp6)
  %d6 = load i64, ptr %dp6, align 8
  %l6 = load i64, ptr %lp6, align 8
  %r6 = call i64 @rg_u8_from(i64 %d6, i64 %l6)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r6
tostr:
  %v7 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %dp7 = alloca i64, align 8
  %lp7 = alloca i64, align 8
  %ok7 = call i1 @rg_bytes_of(i64 %v7, ptr %dp7, ptr %lp7)
  %d7 = load i64, ptr %dp7, align 8
  %l7 = load i64, ptr %lp7, align 8
  %r7 = call i64 @rg_str_from(i64 %d7, i64 %l7)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r7
tolist:
  %v8 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %r8 = call i64 @rg_u8_to_list(i64 %v8)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r8
towords:
  %v9 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %r9 = call i64 @rg_u8_to_words(i64 %v9)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r9
readb:
  %r10 = call i64 @rg_read_bytes_b(i64 %slots, i64 %n)
  ret i64 %r10
writeb:
  %r11 = call i64 @rg_write_bytes_b(i64 %slots, i64 %n)
  ret i64 %r11
range:
  %r12 = call i64 @rg_fd_range_b(i64 %id, i64 %slots, i64 %n)
  ret i64 %r12
fromlist:
  %v13 = call i64 @rg_slot_at(i64 %slots, i64 0)
  %r13 = call i64 @rg_u8_from_list(i64 %v13)
  call void @rg_drop_slots(i64 %slots, i64 %n)
  ret i64 %r13
none:
  %rp = call i64 @rg_builtin_posix(i64 %id, i64 %slots, i64 %n)
  ret i64 %rp
}

; The builtins that need a POSIX system (sys call, processes, execve): posix/
; posix.ll has them; a target without one keeps this weak stub.
define weak i64 @rg_builtin_posix(i64 %id, i64 %slots, i64 %n) {
  call void @rg_no_builtin(i64 %id)
  unreachable
}
