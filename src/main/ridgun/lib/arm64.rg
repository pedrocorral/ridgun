-- ============================================================
-- src/main/ridgun/lib/arm64.rg
-- Pure-Ridgun Native ARM64 (AArch64) Machine-Code Assembler & ELF64 Emitter
-- Targets Linux AArch64 / Raspberry Pi (EM_AARCH64 = 183)
-- @implements FR-COMP-004
-- @implements FR-COMP-007
-- ============================================================

import elf64

-- ── Low-Level ARM64 (AArch64) 32-Bit Instruction Encoders ────

fn :: arm64 movz Int Int   Int       => Int
      arm64 movz rd  imm16 shift_idx =
        3489660928 + (shift_idx * 2097152) + ((imm16 % 65536) * 32) + rd

fn :: arm64 movk Int Int   Int       => Int
      arm64 movk rd  imm16 shift_idx =
        4068474880 + (shift_idx * 2097152) + ((imm16 % 65536) * 32) + rd

fn :: arm64 mov imm64 Int Int => [Int]
      arm64 mov imm64 rd  val =
        u_lo = normalize u32 (val % 4294967296)
        u_hi = normalize u32 (val / 4294967296)
        w0 = u_lo % 65536
        w1 = (u_lo / 65536) % 65536
        w2 = u_hi % 65536
        w3 = (u_hi / 65536) % 65536
        (u32 le (arm64 movz rd w0 0)) :: (u32 le (arm64 movk rd w1 1)) :: (u32 le (arm64 movk rd w2 2)) :: (u32 le (arm64 movk rd w3 3))

fn :: arm64 mov reg Int Int => [Int]
      arm64 mov reg rd  rm  =  u32 le (2852127712 + (rm * 65536) + rd)

fn :: arm64 mov sp to reg Int => [Int]
      arm64 mov sp to reg rd = u32 le (2432697312 + rd)

fn :: arm64 ldr slot Int Int  => [Int]
      arm64 ldr slot rd  slot =  u32 le (4181722080 + ((slot % 4096) * 1024) + rd)

fn :: arm64 lea slot Int Int  => [Int]
      arm64 lea slot rd  slot =  u32 le (2432697312 + (((slot * 8) % 4096) * 1024) + rd)

fn :: arm64 norm imm26 Int => Int
      arm64 norm imm26 w
        | w < 0 = (w + 67108864) % 67108864
        | otherwise = w % 67108864

fn :: arm64 norm imm19 Int => Int
      arm64 norm imm19 w
        | w < 0 = (w + 524288) % 524288
        | otherwise = w % 524288

fn :: arm64 b Int          Int       => [Int]
      arm64 b target_vaddr cur_vaddr =
        imm26 = arm64 norm imm26 ((target_vaddr - cur_vaddr) / 4)
        u32 le (335544320 + imm26)

fn :: arm64 bl Int          Int       => [Int]
      arm64 bl target_vaddr cur_vaddr =
        imm26 = arm64 norm imm26 ((target_vaddr - cur_vaddr) / 4)
        u32 le (2483027968 + imm26)

fn :: arm64 bl rt Int   Int       => [Int]
      arm64 bl rt rt_id cur_vaddr =  arm64 bl (4198400 + (rt_id * 8)) cur_vaddr

fn :: arm64 cbz x0 Int          Int       => [Int]
      arm64 cbz x0 target_vaddr cur_vaddr =
        imm19 = arm64 norm imm19 ((target_vaddr - cur_vaddr) / 4)
        u32 le (3019898880 + (imm19 * 32))

fn :: arm64 cbnz x0 Int          Int       => [Int]
      arm64 cbnz x0 target_vaddr cur_vaddr =
        imm19 = arm64 norm imm19 ((target_vaddr - cur_vaddr) / 4)
        u32 le (3036676096 + (imm19 * 32))

-- ── Fixed-Width ARM64 Instruction Size Table (Pass 1) ────────

fn :: arm64 instr size RNativeInstr       => Int
      arm64 instr size (NLabel _)         =  0
      arm64 instr size (NJump _)          =  4
      arm64 instr size (NJumpIfZero _)    =  4
      arm64 instr size (NJumpIfNonZero _) =  4
      arm64 instr size (NLoadImmInt _)    =  16
      arm64 instr size (NLoadImmRaw _)    =  16
      arm64 instr size (NLoadRealLit _ _) =  36
      arm64 instr size (NLoadStrLit _ _)  =  36
      arm64 instr size (NLoadAdt0 _ _)    =  36
      arm64 instr size (NCloneSlot _)     =  8
      arm64 instr size (NMoveSlot _)      =  8
      arm64 instr size (NStoreSlot _)     =  12
      arm64 instr size (NRebindSlot _)    =  12
      arm64 instr size (NCmmDropSlot _)   =  8
      arm64 instr size NDropVal           =  4
      arm64 instr size (NClearLocals _ _) =  40
      arm64 instr size (NMatchInt _ _)    =  24
      arm64 instr size (NMatchReal _ _ _) =  40
      arm64 instr size (NMatchStr _ _ _)  =  40
      arm64 instr size (NMatchBool _ _)   =  24
      arm64 instr size (NMatchEmpty _)    =  8
      arm64 instr size (NMatchNonEmpty _) =  8
      arm64 instr size (NMatchTuple _ _)  =  24
      arm64 instr size (NMatchAdt _ _ _ -1) = 8
      arm64 instr size (NMatchAdt _ _ _ -2) = 16
      arm64 instr size (NMatchAdt _ _ _ -3) = 32
      arm64 instr size (NMatchAdt _ _ _ -4) = 32
      arm64 instr size (NMatchAdt _ _ _ _) = 56
      arm64 instr size (NListHead _)      =  8
      arm64 instr size (NListTail _)      =  8
      arm64 instr size (NTupleGet _ _)    =  24
      arm64 instr size (NAdtField _ _)    =  24
      arm64 instr size (NPackSeq _)       =  24
      arm64 instr size NAsBool            =  4
      arm64 instr size NNot               =  4
      arm64 instr size NOut               =  4
      arm64 instr size (NBinOp _ _)       =  28
      arm64 instr size (NAdtSet _ _)      =  28
      arm64 instr size (NMakeList _ _)    =  24
      arm64 instr size (NMakeTuple _ _)   =  24
      arm64 instr size (NMakeTensor _ _)  =  24
      arm64 instr size (NMakeAdt _ _ _ _) =  56
      arm64 instr size (NEcho _ _)        =  24
      arm64 instr size (NStrInterp _ _)   =  24
      arm64 instr size (NIndex _ _ _)     =  28
      arm64 instr size (NIndexSet _ _ _)  =  32
      arm64 instr size (NSeqSelect _ _)   =  36
      arm64 instr size (NEinsum _ _ _ _)  =  56
      arm64 instr size (NHadamard _ _ _ _) = 60
      arm64 instr size NEnterRegion       =  4
      arm64 instr size (NExitRegion _)    =  24
      arm64 instr size (NCallFn _ _ _)    =  8
      arm64 instr size (NCallBuiltin _ _ _) = 40
      arm64 instr size (NCallIndirect1 _ _) = 12
      arm64 instr size (NCallIndirect2 _ _) = 12
      arm64 instr size (NTailCall _ _)    =  60
      arm64 instr size NReturn            =  52

fn :: arm64 scan instrs [RNativeInstr] Int [RLabelEntry] => RScanResult
      arm64 scan instrs [] cur_off labels = ScanResult cur_off labels
      arm64 scan instrs ((NLabel lid):rest) cur_off labels =
        arm64 scan instrs rest cur_off (labels :: [LabelEntry lid cur_off])
      arm64 scan instrs (ins:rest) cur_off labels =
        sz = arm64 instr size ins
        arm64 scan instrs rest (cur_off + sz) labels

fn :: arm64 scan fns [RNativeFn] Int [RLabelEntry] => RScanResult
      arm64 scan fns [] cur_vaddr fn_table = ScanResult cur_vaddr fn_table
      arm64 scan fns ((NativeFn fid _ _ _ instrs):rest) cur_vaddr fn_table =
        sr = arm64 scan instrs instrs (cur_vaddr + 72) []
        end_vaddr = scan offset sr
        arm64 scan fns rest end_vaddr (fn_table :: [LabelEntry fid cur_vaddr])

-- ── ARM64 Function Prologue & Instruction Encoder (Pass 2) ───

fn :: arm64 frame size Int       => Int
      arm64 frame size num_slots =  (((num_slots + 1) / 2) * 16)

fn :: arm64 prologue Int      Int   Int       => [Int]
      arm64 prologue fn_vaddr arity num_slots =
        fsz = arm64 frame size num_slots
        (u32 le 2843738109) :: (u32 le 2432697341) :: (arm64 mov imm64 9 fsz) :: (u32 le 3407938559) :: (arm64 mov reg 1 0) :: (arm64 mov sp to reg 0) :: (arm64 mov imm64 2 arity) :: (arm64 mov imm64 3 num_slots) :: (arm64 bl rt 1 (fn_vaddr + 68))

fn :: arm64 encode instr RNativeInstr Int Int Int Int [RLabelEntry] [RLabelEntry] => [Int]
      arm64 encode instr (NLabel _) _ _ _ _ _ _ = []
      arm64 encode instr (NJump lid) cur_vaddr _ _ _ lbl_table _ =
        target = lookup label offset lbl_table lid
        arm64 b target cur_vaddr
      arm64 encode instr (NJumpIfZero lid) cur_vaddr _ _ _ lbl_table _ =
        target = lookup label offset lbl_table lid
        arm64 cbz x0 target cur_vaddr
      arm64 encode instr (NJumpIfNonZero lid) cur_vaddr _ _ _ lbl_table _ =
        target = lookup label offset lbl_table lid
        arm64 cbnz x0 target cur_vaddr
      arm64 encode instr (NLoadImmInt n) _ _ _ _ _ _ =
        arm64 mov imm64 0 ((n * 2) + 1)
      arm64 encode instr (NLoadImmRaw raw) _ _ _ _ _ _ =
        arm64 mov imm64 0 raw
      arm64 encode instr (NLoadRealLit off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 mov imm64 0 (rodata_vaddr + off)) :: (arm64 mov imm64 1 len) :: (arm64 bl rt 11 (cur_vaddr + 32))
      arm64 encode instr (NLoadStrLit off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 mov imm64 0 (rodata_vaddr + off)) :: (arm64 mov imm64 1 len) :: (arm64 bl rt 12 (cur_vaddr + 32))
      arm64 encode instr (NLoadAdt0 -1 0) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 mov imm64 0 (rodata_vaddr + 28)) :: (arm64 mov imm64 1 5) :: (arm64 bl rt 13 (cur_vaddr + 32))
      arm64 encode instr (NLoadAdt0 off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 mov imm64 0 (rodata_vaddr + off)) :: (arm64 mov imm64 1 len) :: (arm64 bl rt 13 (cur_vaddr + 32))
      arm64 encode instr (NCloneSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 bl rt 5 (cur_vaddr + 4))
      arm64 encode instr (NMoveSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 slot) :: (arm64 bl rt 7 (cur_vaddr + 4))
      arm64 encode instr (NStoreSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64 mov reg 1 0) :: (arm64 lea slot 0 slot) :: (arm64 bl rt 8 (cur_vaddr + 8))
      arm64 encode instr (NRebindSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64 mov reg 1 0) :: (arm64 lea slot 0 slot) :: (arm64 bl rt 9 (cur_vaddr + 8))
      arm64 encode instr (NCmmDropSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 slot) :: (arm64 bl rt 10 (cur_vaddr + 4))
      arm64 encode instr NDropVal cur_vaddr _ _ _ _ _ =
        arm64 bl rt 6 cur_vaddr
      arm64 encode instr (NClearLocals start_slot end_slot) cur_vaddr _ _ _ _ _ =
        (arm64 mov sp to reg 0) :: (arm64 mov imm64 1 start_slot) :: (arm64 mov imm64 2 end_slot) :: (arm64 bl rt 4 (cur_vaddr + 36))
      arm64 encode instr (NMatchInt slot n) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 n) :: (arm64 bl rt 21 (cur_vaddr + 20))
      arm64 encode instr (NMatchReal slot off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 (rodata_vaddr + off)) :: (arm64 mov imm64 2 len) :: (arm64 bl rt 22 (cur_vaddr + 36))
      arm64 encode instr (NMatchStr slot off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 (rodata_vaddr + off)) :: (arm64 mov imm64 2 len) :: (arm64 bl rt 23 (cur_vaddr + 36))
      arm64 encode instr (NMatchBool slot b_int) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 b_int) :: (arm64 bl rt 24 (cur_vaddr + 20))
      arm64 encode instr (NMatchEmpty slot) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 bl rt 25 (cur_vaddr + 4))
      arm64 encode instr (NMatchNonEmpty slot) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 bl rt 26 (cur_vaddr + 4))
      arm64 encode instr (NMatchTuple slot arity) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 arity) :: (arm64 bl rt 29 (cur_vaddr + 20))
      arm64 encode instr (NMatchAdt slot _ _ -1) _ _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (u32 le 2453667840)
      arm64 encode instr (NMatchAdt slot _ _ -2) _ _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (u32 le 2457729024) :: (u32 le 4043311135) :: (u32 le 2594117600)
      arm64 encode instr (NMatchAdt slot _ _ -3) _ _ _ _ _ _ =
        (arm64 ldr slot 1 slot) :: (u32 le (arm64 movz 0 0 0)) :: (u32 le 3019899009) :: (u32 le 4064283711) :: (u32 le 1409286241) :: (u32 le 4181721121) :: (u32 le 4043310111) :: (u32 le 2594117600)
      arm64 encode instr (NMatchAdt slot _ _ -4) _ _ _ _ _ _ =
        (arm64 ldr slot 1 slot) :: (u32 le (arm64 movz 0 0 0)) :: (u32 le 3019899009) :: (u32 le 4064283711) :: (u32 le 1409286241) :: (u32 le 4181721121) :: (u32 le 4043309087) :: (u32 le 2594117600)
      arm64 encode instr (NMatchAdt slot off len arity) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 (rodata_vaddr + off)) :: (arm64 mov imm64 2 len) :: (arm64 mov imm64 3 arity) :: (arm64 bl rt 31 (cur_vaddr + 52))
      arm64 encode instr (NListHead slot) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 bl rt 27 (cur_vaddr + 4))
      arm64 encode instr (NListTail slot) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 bl rt 28 (cur_vaddr + 4))
      arm64 encode instr (NTupleGet slot idx) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 idx) :: (arm64 bl rt 30 (cur_vaddr + 20))
      arm64 encode instr (NAdtField slot idx) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 slot) :: (arm64 mov imm64 1 idx) :: (arm64 bl rt 32 (cur_vaddr + 20))
      arm64 encode instr (NPackSeq arity) cur_vaddr _ _ _ _ _ =
        (arm64 mov sp to reg 0) :: (arm64 mov imm64 1 arity) :: (arm64 bl rt 19 (cur_vaddr + 20))
      arm64 encode instr NAsBool cur_vaddr _ _ _ _ _ =
        arm64 bl rt 20 cur_vaddr
      arm64 encode instr NNot cur_vaddr _ _ _ _ _ =
        arm64 bl rt 34 cur_vaddr
      arm64 encode instr NOut cur_vaddr _ _ _ _ _ =
        arm64 bl rt 35 cur_vaddr
      arm64 encode instr (NBinOp op_id lhs_slot) cur_vaddr _ _ _ _ _ =
        (arm64 mov reg 2 0) :: (arm64 mov imm64 0 op_id) :: (arm64 lea slot 1 lhs_slot) :: (arm64 bl rt 37 (cur_vaddr + 24))
      arm64 encode instr (NAdtSet rec_slot idx) cur_vaddr _ _ _ _ _ =
        (arm64 mov reg 2 0) :: (arm64 lea slot 0 rec_slot) :: (arm64 mov imm64 1 idx) :: (arm64 bl rt 33 (cur_vaddr + 24))
      arm64 encode instr (NMakeList start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 start_slot) :: (arm64 mov imm64 1 count) :: (arm64 bl rt 15 (cur_vaddr + 20))
      arm64 encode instr (NMakeTuple start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 start_slot) :: (arm64 mov imm64 1 count) :: (arm64 bl rt 16 (cur_vaddr + 20))
      arm64 encode instr (NMakeTensor start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 start_slot) :: (arm64 mov imm64 1 count) :: (arm64 bl rt 17 (cur_vaddr + 20))
      arm64 encode instr (NMakeAdt off len start_slot count) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 mov imm64 0 (rodata_vaddr + off)) :: (arm64 mov imm64 1 len) :: (arm64 lea slot 2 start_slot) :: (arm64 mov imm64 3 count) :: (arm64 bl rt 14 (cur_vaddr + 52))
      arm64 encode instr (NEcho start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 start_slot) :: (arm64 mov imm64 1 count) :: (arm64 bl rt 36 (cur_vaddr + 20))
      arm64 encode instr (NStrInterp start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 start_slot) :: (arm64 mov imm64 1 count) :: (arm64 bl rt 18 (cur_vaddr + 20))
      arm64 encode instr (NIndex base_slot idx_start count) cur_vaddr _ _ _ _ _ =
        (arm64 lea slot 0 base_slot) :: (arm64 lea slot 1 idx_start) :: (arm64 mov imm64 2 count) :: (arm64 bl rt 38 (cur_vaddr + 24))
      arm64 encode instr (NIndexSet base_slot idx_start count) cur_vaddr _ _ _ _ _ =
        (arm64 mov reg 3 0) :: (arm64 lea slot 0 base_slot) :: (arm64 lea slot 1 idx_start) :: (arm64 mov imm64 2 count) :: (arm64 bl rt 39 (cur_vaddr + 28))
      arm64 encode instr (NSeqSelect mask_off mask_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 mov imm64 1 (rodata_vaddr + mask_off)) :: (arm64 mov imm64 2 mask_len) :: (arm64 bl rt 40 (cur_vaddr + 32))
      arm64 encode instr (NEinsum start_slot count spec_off spec_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 lea slot 0 start_slot) :: (arm64 mov imm64 1 count) :: (arm64 mov imm64 2 (rodata_vaddr + spec_off)) :: (arm64 mov imm64 3 spec_len) :: (arm64 bl rt 41 (cur_vaddr + 52))
      arm64 encode instr (NHadamard op_id lhs_slot subs_off subs_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64 mov reg 2 0) :: (arm64 mov imm64 0 op_id) :: (arm64 lea slot 1 lhs_slot) :: (arm64 mov imm64 3 (rodata_vaddr + subs_off)) :: (arm64 mov imm64 4 subs_len) :: (arm64 bl rt 42 (cur_vaddr + 56))
      arm64 encode instr NEnterRegion cur_vaddr _ _ _ _ _ =
        arm64 bl rt 47 cur_vaddr
      arm64 encode instr (NExitRegion quota) cur_vaddr _ _ _ _ _ =
        (arm64 mov reg 1 0) :: (arm64 mov imm64 0 quota) :: (arm64 bl rt 48 (cur_vaddr + 20))
      arm64 encode instr (NCallFn fid start_slot _) cur_vaddr _ _ _ _ fn_table =
        target_fn = lookup label offset fn_table fid
        (arm64 lea slot 0 start_slot) :: (arm64 bl target_fn (cur_vaddr + 4))
      arm64 encode instr (NCallBuiltin b_id start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64 mov imm64 0 b_id) :: (arm64 lea slot 1 start_slot) :: (arm64 mov imm64 2 count) :: (arm64 bl rt 55 (cur_vaddr + 36))
      arm64 encode instr (NCallIndirect1 fn_slot arg_slot) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 fn_slot) :: (arm64 lea slot 1 arg_slot) :: (arm64 bl rt 53 (cur_vaddr + 8))
      arm64 encode instr (NCallIndirect2 fn_slot start_slot) cur_vaddr _ _ _ _ _ =
        (arm64 ldr slot 0 fn_slot) :: (arm64 lea slot 1 start_slot) :: (arm64 bl rt 54 (cur_vaddr + 8))
      arm64 encode instr (NTailCall start_slot arity) cur_vaddr fn_vaddr num_slots _ _ _ =
        (arm64 mov sp to reg 0) :: (arm64 mov imm64 1 start_slot) :: (arm64 mov imm64 2 arity) :: (arm64 mov imm64 3 num_slots) :: (arm64 bl rt 3 (cur_vaddr + 52)) :: (arm64 b (fn_vaddr + 72) (cur_vaddr + 56))
      arm64 encode instr NReturn cur_vaddr _ num_slots _ _ _ =
        fsz = arm64 frame size num_slots
        (arm64 mov reg 2 0) :: (arm64 mov sp to reg 0) :: (arm64 mov imm64 1 num_slots) :: (arm64 bl rt 2 (cur_vaddr + 24)) :: (arm64 mov imm64 9 fsz) :: (u32 le 2334196735) :: (u32 le 2831155197) :: (u32 le 3596551104)

fn :: arm64 encode instrs [RNativeInstr] Int Int Int Int [RLabelEntry] [RLabelEntry] [Int] => [Int]
      arm64 encode instrs [] _ _ _ _ _ _ acc = acc
      arm64 encode instrs (ins:rest) cur_vaddr fn_vaddr num_slots rodata_vaddr lbl_table fn_table acc =
        sz = arm64 instr size ins
        bytes = arm64 encode instr ins cur_vaddr fn_vaddr num_slots rodata_vaddr lbl_table fn_table
        arm64 encode instrs rest (cur_vaddr + sz) fn_vaddr num_slots rodata_vaddr lbl_table fn_table (acc :: bytes)

fn :: arm64 encode fns [RNativeFn] Int [RLabelEntry] [Int] => [Int]
      arm64 encode fns [] _ _ acc = acc
      arm64 encode fns ((NativeFn fid _ arity num_slots instrs):rest) rodata_vaddr fn_table acc =
        fn_vaddr = lookup label offset fn_table fid
        sr = arm64 scan instrs instrs (fn_vaddr + 72) []
        lbl_table = scan labels sr
        pro = arm64 prologue fn_vaddr arity num_slots
        fn_bytes = arm64 encode instrs instrs (fn_vaddr + 72) fn_vaddr num_slots rodata_vaddr lbl_table fn_table pro
        arm64 encode fns rest rodata_vaddr fn_table (acc :: fn_bytes)

-- ── Freestanding Linux ARM64 (AArch64) Syscall Runtime Kernel (Region 1) ──
-- Each jump table slot `i` (`0..55`) at `0x401000 + i*8` is 8 bytes (two 32-bit
-- AArch64 instructions). Short 2-instruction primitives execute inline inside their
-- 8-byte jump table slot; multi-instruction routines branch (`B`) to `0x4011C0+`.

fn :: arm64 nop => [Int]
      arm64 nop =  u32 le 3573751839

fn :: arm64 ret => [Int]
      arm64 ret =  u32 le 3596551104

fn :: arm64 svc0 => [Int]
      arm64 svc0 =  u32 le 3556769793

fn :: arm64 blr Int => [Int]
      arm64 blr rn  =  u32 le (3594452992 + (rn * 32))

fn :: arm64 ldr base Int Int => [Int]
      arm64 ldr base rt  rn  =  u32 le (4181721088 + (rn * 32) + rt)

fn :: arm64 str base Int Int => [Int]
      arm64 str base rt  rn  =  u32 le (4177526784 + (rn * 32) + rt)

fn :: arm64 asr1 Int Int => [Int]
      arm64 asr1 rd  rn  =  u32 le (2470575104 + (rn * 32) + rd)

fn :: arm64 lsl1 Int Int => [Int]
      arm64 lsl1 rd  rn  =  u32 le (3544186880 + (rn * 32) + rd)

fn :: arm64 orr1 Int Int => [Int]
      arm64 orr1 rd  rn  =  u32 le (2990538752 + (rn * 32) + rd)

fn :: arm64 cmp reg Int Int => [Int]
      arm64 cmp reg rn  rm  =  u32 le (3942645791 + (rm * 65536) + (rn * 32))

fn :: arm64 cset eq Int => [Int]
      arm64 cset eq rd  =  u32 le (2594117600 + rd)

fn :: arm64 cset ne Int => [Int]
      arm64 cset ne rd  =  u32 le (2594119648 + rd)

fn :: arm64 rt slot Int => [Int]
      -- rt_0 (_start): branch to 0x4011C0 (+112 words)
      arm64 rt slot 0   =  (arm64 b 4198848 4198400) :: arm64 nop
      -- rt_1 (rg_init_frame): branch to 0x4011E8 (+121 words from slot 1)
      arm64 rt slot 1   =  (arm64 b 4198888 4198408) :: arm64 nop
      -- rt_2 (rg_epilogue): MOV X0, X2 ; RET
      arm64 rt slot 2   =  (arm64 mov reg 0 2) :: arm64 ret
      -- rt_3 (rg_tco_copy): branch to 0x401204 (+126 words from slot 3)
      arm64 rt slot 3   =  (arm64 b 4198916 4198424) :: arm64 nop
      -- rt_4 (rg_clear_locals): NOP ; RET
      arm64 rt slot 4   =  arm64 nop :: arm64 ret
      -- rt_5 (rg_clone): NOP ; RET (X0 already holds value)
      arm64 rt slot 5   =  arm64 nop :: arm64 ret
      -- rt_6 (rg_drop): NOP ; RET
      arm64 rt slot 6   =  arm64 nop :: arm64 ret
      -- rt_7 (rg_cmm_move): LDR X0, [X0] ; RET
      arm64 rt slot 7   =  (arm64 ldr base 0 0) :: arm64 ret
      -- rt_8 (rg_store_local): STR X1, [X0] ; RET
      arm64 rt slot 8   =  (arm64 str base 1 0) :: arm64 ret
      -- rt_9 (rg_rebind_local): STR X1, [X0] ; RET
      arm64 rt slot 9   =  (arm64 str base 1 0) :: arm64 ret
      -- rt_10 (rg_cmm_drop): STR XZR, [X0] ; RET
      arm64 rt slot 10  =  (arm64 str base 31 0) :: arm64 ret
      -- rt_11 (rg_load_real_lit): NOP ; RET (X0 holds rodata ptr)
      arm64 rt slot 11  =  arm64 nop :: arm64 ret
      -- rt_12 (rg_load_str_lit): NOP ; RET (X0 holds rodata ptr)
      arm64 rt slot 12  =  arm64 nop :: arm64 ret
      -- rt_13 (rg_load_adt0): NOP ; RET (X0 holds tag ptr)
      arm64 rt slot 13  =  arm64 nop :: arm64 ret
      -- rt_14 (rg_make_adt): MOV X0, X2 ; RET
      arm64 rt slot 14  =  (arm64 mov reg 0 2) :: arm64 ret
      -- rt_15 (rg_make_list): NOP ; RET (X0 holds list slots ptr)
      arm64 rt slot 15  =  arm64 nop :: arm64 ret
      -- rt_16 (rg_make_tuple): NOP ; RET (X0 holds tuple slots ptr)
      arm64 rt slot 16  =  arm64 nop :: arm64 ret
      -- rt_17 (rg_make_tensor): NOP ; RET (X0 holds tensor slots ptr)
      arm64 rt slot 17  =  arm64 nop :: arm64 ret
      -- rt_18 (rg_str_interp): LDR X0, [X0] ; RET
      arm64 rt slot 18  =  (arm64 ldr base 0 0) :: arm64 ret
      -- rt_19 (rg_pack_seq): NOP ; RET (X0 holds frame ptr)
      arm64 rt slot 19  =  arm64 nop :: arm64 ret
      -- rt_20 (rg_as_bool): UBFX X0, X0, #1, #1 ; RET
      arm64 rt slot 20  =  (u32 le 3544253440) :: arm64 ret
      -- rt_21 (rg_match_int): branch to 0x401220 (+94 words from slot 21)
      arm64 rt slot 21  =  (arm64 b 4198944 4198568) :: arm64 nop
      -- rt_22 (rg_match_real): CMP X0, X1 ; CSET X0, EQ (branch to 0x4012CC)
      arm64 rt slot 22  =  (arm64 b 4199116 4198576) :: arm64 nop
      -- rt_23 (rg_match_str): CMP X0, X1 ; CSET X0, EQ (branch to 0x4012CC)
      arm64 rt slot 23  =  (arm64 b 4199116 4198584) :: arm64 nop
      -- rt_24 (rg_match_bool): branch to 0x401230 (+92 words from slot 24)
      arm64 rt slot 24  =  (arm64 b 4198960 4198592) :: arm64 nop
      -- rt_25 (rg_match_empty): CMP X0, XZR ; CSET X0, EQ (branch to 0x4012D8)
      arm64 rt slot 25  =  (arm64 b 4199128 4198600) :: arm64 nop
      -- rt_26 (rg_match_nonempty): CMP X0, XZR ; CSET X0, NE (branch to 0x4012E4)
      arm64 rt slot 26  =  (arm64 b 4199140 4198608) :: arm64 nop
      -- rt_27 (rg_list_head): LDR X0, [X0] ; RET
      arm64 rt slot 27  =  (arm64 ldr base 0 0) :: arm64 ret
      -- rt_28 (rg_list_tail): ADD X0, X0, #8 ; RET
      arm64 rt slot 28  =  (u32 le 2432698368) :: arm64 ret
      -- rt_29 (rg_match_tuple): MOVZ X0, #1 ; RET
      arm64 rt slot 29  =  (u32 le (arm64 movz 0 1 0)) :: arm64 ret
      -- rt_30 (rg_tuple_get): LDR X0, [X0, X1, LSL #3] ; RET
      arm64 rt slot 30  =  (u32 le 4167113216) :: arm64 ret
      -- rt_31 (rg_match_adt): CMP X0, X1 ; CSET X0, EQ (branch to 0x4012CC)
      arm64 rt slot 31  =  (arm64 b 4199116 4198648) :: arm64 nop
      -- rt_32 (rg_adt_field): LDR X0, [X0, X1, LSL #3] ; RET
      arm64 rt slot 32  =  (u32 le 4167113216) :: arm64 ret
      -- rt_33 (rg_adt_set): STR X2, [X0, X1, LSL #3] ; RET
      arm64 rt slot 33  =  (u32 le 4162918914) :: arm64 ret
      -- rt_34 (rg_not): EOR X0, X0, #2 ; RET
      arm64 rt slot 34  =  (u32 le 3531538432) :: arm64 ret
      -- rt_35 (rg_out): MOVZ X0, #0 ; RET
      arm64 rt slot 35  =  (u32 le (arm64 movz 0 0 0)) :: arm64 ret
      -- rt_36 (rg_echo): MOVZ X0, #0 ; RET
      arm64 rt slot 36  =  (u32 le (arm64 movz 0 0 0)) :: arm64 ret
      -- rt_37 (rg_bin_op): branch to 0x401240 (+70 words from slot 37)
      arm64 rt slot 37  =  (arm64 b 4198976 4198696) :: arm64 nop
      -- rt_38 (rg_index_get): branch to 0x4012F0
      arm64 rt slot 38  =  (arm64 b 4199152 4198704) :: arm64 nop
      -- rt_39 (rg_index_set): branch to 0x401304
      arm64 rt slot 39  =  (arm64 b 4199172 4198712) :: arm64 nop
      -- rt_40 (rg_seq_select): NOP ; RET (X0 holds seq ptr)
      arm64 rt slot 40  =  arm64 nop :: arm64 ret
      -- rt_41 (rg_einsum): LDR X0, [X0] ; RET
      arm64 rt slot 41  =  (arm64 ldr base 0 0) :: arm64 ret
      -- rt_42 (rg_hadamard): LDR X0, [X1] ; RET
      arm64 rt slot 42  =  (arm64 ldr base 0 1) :: arm64 ret
      -- rt_43 (rg_push_ctx): MOV X0, X2 ; RET
      arm64 rt slot 43  =  (arm64 mov reg 0 2) :: arm64 ret
      -- rt_44 (rg_pop_ctx): MOV X0, X2 ; RET
      arm64 rt slot 44  =  (arm64 mov reg 0 2) :: arm64 ret
      -- rt_45 (rg_has_ctx): MOVZ X0, #1 ; RET
      arm64 rt slot 45  =  (u32 le (arm64 movz 0 1 0)) :: arm64 ret
      -- rt_46 (rg_get_ctx): MOVZ X0, #0 ; RET
      arm64 rt slot 46  =  (u32 le (arm64 movz 0 0 0)) :: arm64 ret
      -- rt_47 (rg_enter_region): MOVZ X0, #0 ; RET
      arm64 rt slot 47  =  (u32 le (arm64 movz 0 0 0)) :: arm64 ret
      -- rt_48 (rg_exit_region): MOV X0, X1 ; RET (returns block result in X1)
      arm64 rt slot 48  =  (arm64 mov reg 0 1) :: arm64 ret
      -- rt_49 (rg_has_shared): MOVZ X0, #1 ; RET
      arm64 rt slot 49  =  (u32 le (arm64 movz 0 1 0)) :: arm64 ret
      -- rt_50 (rg_get_shared): MOVZ X0, #0 ; RET
      arm64 rt slot 50  =  (u32 le (arm64 movz 0 0 0)) :: arm64 ret
      -- rt_51 (rg_init_shared): MOV X0, X2 ; RET
      arm64 rt slot 51  =  (arm64 mov reg 0 2) :: arm64 ret
      -- rt_52 (rg_store_shared): MOV X0, X2 ; RET
      arm64 rt slot 52  =  (arm64 mov reg 0 2) :: arm64 ret
      -- rt_53 (rg_call_indirect1): branch to 0x401318
      arm64 rt slot 53  =  (arm64 b 4199192 4198824) :: arm64 nop
      -- rt_54 (rg_call_indirect2): branch to 0x40132C
      arm64 rt slot 54  =  (arm64 b 4199212 4198832) :: arm64 nop
      -- rt_55 (rg_call_builtin / PAL dispatch): branch to 0x401270 (+46 words from slot 55)
      arm64 rt slot 55  =  (arm64 b 4199024 4198840) :: arm64 nop
      -- Default slot: RET ; NOP
      arm64 rt slot _   =  arm64 ret :: arm64 nop

fn :: arm64 rt stub table Int [Int] => [Int]
      arm64 rt stub table idx acc
        | idx >= 56 = acc
        | otherwise =
          entry = arm64 rt slot idx
          arm64 rt stub table (idx + 1) (acc :: entry)

-- Phase 1 & Core Symbolic ARM64 Runtime Routines (`0x4011C0+`)

-- 0x4011C0 (_start, 10 words = 40 bytes):
-- Load main_vaddr from 0x400080, pass SP in X0, BLR X10, then SYS_exit_group(0) (X8=94, SVC #0)
fn :: arm64 rt start code => [Int]
      arm64 rt start code =
        (arm64 mov imm64 9 4194432) :: (arm64 ldr base 10 9) :: (arm64 mov sp to reg 0) :: (arm64 blr 10) :: (u32 le (arm64 movz 0 0 0)) :: (u32 le (arm64 movz 8 94 0)) :: arm64 svc0

-- 0x4011E8 (Slot 1: rg_init_frame, 7 words = 28 bytes):
-- Copy X2 args from [X1] into [X0]
fn :: arm64 rt slot1 init frame => [Int]
      arm64 rt slot1 init frame =
        (u32 le 3019898978) :: (u32 le 4165009449) :: (u32 le 4160815113) :: (u32 le 3407873090) :: (u32 le 1409286141) :: arm64 ret :: arm64 nop

-- 0x401204 (Slot 3: rg_tco_copy, 7 words = 28 bytes):
-- Copy X2 args from [X0 + X1*8] into [X0]
fn :: arm64 rt slot3 tco copy => [Int]
      arm64 rt slot3 tco copy =
        (u32 le 2335705099) :: (u32 le 3019898978) :: (u32 le 4165009545) :: (u32 le 4160815113) :: (u32 le 3407873090) :: (u32 le 1409286141) :: arm64 ret

-- 0x401220 (Slot 21: rg_match_int, 4 words = 16 bytes): ASR X0, X0, #1 ; CMP X0, X1 ; CSET X0, EQ ; RET
fn :: arm64 rt slot21 match int => [Int]
      arm64 rt slot21 match int =
        (arm64 asr1 0 0) :: (arm64 cmp reg 0 1) :: (arm64 cset eq 0) :: arm64 ret

-- 0x401230 (Slot 24: rg_match_bool, 4 words = 16 bytes): UBFX X0, X0, #1, #1 ; CMP X0, X1 ; CSET X0, EQ ; RET
fn :: arm64 rt slot24 match bool => [Int]
      arm64 rt slot24 match bool =
        (u32 le 3544253440) :: (arm64 cmp reg 0 1) :: (arm64 cset eq 0) :: arm64 ret

-- 0x401240 (Slot 37: rg_bin_op, 12 words = 48 bytes):
-- LDR X9, [X1] ; ASR X9, X9, #1 ; ASR X10, X2, #1 ; ADD/SUB/MUL dispatch ; LSL X0, X0, #1 ; ORR X0, X0, #1 ; RET
fn :: arm64 rt slot37 binop => [Int]
      arm64 rt slot37 binop =
        (arm64 ldr base 9 1) :: (u32 le 2470575399) :: (arm64 asr1 10 2) :: (u32 le 3942649856) :: (u32 le 1409286148) :: (u32 le 2332688681) :: (u32 le 335544323) :: (u32 le 3406430505) :: (u32 le 2583691561) :: (arm64 lsl1 0 0) :: (arm64 orr1 0 0) :: arm64 ret

-- 0x401270 (Slot 55: rg_call_builtin PAL dispatch, 23 words = 92 bytes):
fn :: arm64 rt slot55 pal dispatch => [Int]
      arm64 rt slot55 pal dispatch =
        (u32 le 4043380767) :: (u32 le 1409286337) :: (u32 le (arm64 movz 8 172 0)) :: arm64 svc0 :: (arm64 lsl1 0 0) :: (arm64 orr1 0 0) :: arm64 ret :: (u32 le 4043387935) :: (u32 le 1409286401) :: (arm64 ldr base 0 1) :: (arm64 asr1 0 0) :: (u32 le (arm64 movz 8 57 0)) :: arm64 svc0 :: (arm64 lsl1 0 0) :: (arm64 orr1 0 0) :: arm64 ret :: (u32 le 4043396127) :: (u32 le 1409286273) :: (arm64 ldr base 0 1) :: (arm64 str base 31 1) :: arm64 ret :: (u32 le (arm64 movz 0 0 0)) :: arm64 ret

-- 0x4012CC (Slots 22/23/31: rg_match_ptr_eq, 3 words = 12 bytes): CMP X0, X1 ; CSET X0, EQ ; RET
fn :: arm64 rt slot22 match ptr eq => [Int]
      arm64 rt slot22 match ptr eq =
        (arm64 cmp reg 0 1) :: (arm64 cset eq 0) :: arm64 ret

-- 0x4012D8 (Slot 25: rg_match_empty, 3 words = 12 bytes): CMP X0, XZR ; CSET X0, EQ ; RET
fn :: arm64 rt slot25 match empty => [Int]
      arm64 rt slot25 match empty =
        (arm64 cmp reg 0 31) :: (arm64 cset eq 0) :: arm64 ret

-- 0x4012E4 (Slot 26: rg_match_nonempty, 3 words = 12 bytes): CMP X0, XZR ; CSET X0, NE ; RET
fn :: arm64 rt slot26 match nonempty => [Int]
      arm64 rt slot26 match nonempty =
        (arm64 cmp reg 0 31) :: (arm64 cset ne 0) :: arm64 ret

-- 0x4012F0 (Slot 38: rg_index_get, 5 words = 20 bytes): LDR X9, [X0] ; LDR X10, [X1] ; ASR X10, X10, #1 ; LDR X0, [X9, X10, LSL #3] ; RET
fn :: arm64 rt slot38 index get => [Int]
      arm64 rt slot38 index get =
        (arm64 ldr base 9 0) :: (arm64 ldr base 10 1) :: (arm64 asr1 10 10) :: (u32 le 4167768896) :: arm64 ret

-- 0x401304 (Slot 39: rg_index_set, 5 words = 20 bytes): LDR X9, [X0] ; LDR X10, [X1] ; ASR X10, X10, #1 ; STR X3, [X9, X10, LSL #3] ; RET
fn :: arm64 rt slot39 index set => [Int]
      arm64 rt slot39 index set =
        (arm64 ldr base 9 0) :: (arm64 ldr base 10 1) :: (arm64 asr1 10 10) :: (u32 le 4163574595) :: arm64 ret

-- 0x401318 (Slot 53: rg_call_indirect1, 5 words = 20 bytes): MOV X9, #0x400088 ; LDR X10, [X9] ; BR X10
fn :: arm64 rt slot53 call indirect1 => [Int]
      arm64 rt slot53 call indirect1 =
        (arm64 mov imm64 9 4194440) :: (arm64 ldr base 10 9) :: (u32 le (3592355840 + (10 * 32)))

-- 0x40132C (Slot 54: rg_call_indirect2, 5 words = 20 bytes): MOV X9, #0x400090 ; LDR X10, [X9] ; BR X10
fn :: arm64 rt slot54 call indirect2 => [Int]
      arm64 rt slot54 call indirect2 =
        (arm64 mov imm64 9 4194448) :: (arm64 ldr base 10 9) :: (u32 le (3592355840 + (10 * 32)))

fn :: build arm64 rt kernel => [Int]
      build arm64 rt kernel =
        jt = arm64 rt stub table 0 []
        jt :: arm64 rt start code :: arm64 rt slot1 init frame :: arm64 rt slot3 tco copy :: arm64 rt slot21 match int :: arm64 rt slot24 match bool :: arm64 rt slot37 binop :: arm64 rt slot55 pal dispatch :: arm64 rt slot22 match ptr eq :: arm64 rt slot25 match empty :: arm64 rt slot26 match nonempty :: arm64 rt slot38 index get :: arm64 rt slot39 index set :: arm64 rt slot53 call indirect1 :: arm64 rt slot54 call indirect2

-- ── Public ARM64 ELF64 Image Builder ─────────────────────────

fn :: emit arm64 elf kind Int RNativeProg => [Int]
      emit arm64 elf kind e_type (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
        rt_bytes = build arm64 rt kernel
        rt_len = byte list len rt_bytes
        region2_vaddr = 4198400 + rt_len
        sr = arm64 scan fns fns region2_vaddr []
        rodata_vaddr = scan offset sr
        fn_table = scan labels sr
        code_len = rodata_vaddr - region2_vaddr
        code_bytes = arm64 encode fns fns rodata_vaddr fn_table []
        main_vaddr = lookup label offset fn_table main_fid
        spawn_vaddr = lookup label offset fn_table spawn_fid
        call2_vaddr = lookup label offset fn_table call2_fid
        binop_vaddr = lookup label offset fn_table binop_fid
        build elf64 image kind e_type 183 main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: emit arm64 elf RNativeProg => [Int]
      emit arm64 elf nprog       =  emit arm64 elf kind 2 nprog

fn :: emit arm64 so elf RNativeProg => [Int]
      emit arm64 so elf nprog       =  emit arm64 elf kind 3 nprog
