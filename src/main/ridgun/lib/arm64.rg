-- ============================================================
-- src/main/ridgun/lib/arm64.rg
-- Pure-Ridgun Native ARM64 (AArch64) Machine-Code Assembler & ELF64 Emitter
-- Targets Linux AArch64 / Raspberry Pi (EM_AARCH64 = 183)
-- @implements FR-COMP-004
-- ============================================================

import elf64

-- ── Low-Level ARM64 (AArch64) 32-Bit Instruction Encoders ────

fn :: arm64_movz Int Int   Int       => Int
      arm64_movz rd  imm16 shift_idx =
        3489660928 + (shift_idx * 2097152) + ((imm16 % 65536) * 32) + rd

fn :: arm64_movk Int Int   Int       => Int
      arm64_movk rd  imm16 shift_idx =
        4068474880 + (shift_idx * 2097152) + ((imm16 % 65536) * 32) + rd

fn :: arm64_mov_imm64 Int Int => [Int]
      arm64_mov_imm64 rd  val =
        u_lo = normalize_u32 (val % 4294967296)
        u_hi = normalize_u32 (val / 4294967296)
        w0 = u_lo % 65536
        w1 = (u_lo / 65536) % 65536
        w2 = u_hi % 65536
        w3 = (u_hi / 65536) % 65536
        (u32_le (arm64_movz rd w0 0)) :: (u32_le (arm64_movk rd w1 1)) :: (u32_le (arm64_movk rd w2 2)) :: (u32_le (arm64_movk rd w3 3))

fn :: arm64_mov_reg Int Int => [Int]
      arm64_mov_reg rd  rm  =  u32_le (2852127712 + (rm * 65536) + rd)

fn :: arm64_mov_sp_to_reg Int => [Int]
      arm64_mov_sp_to_reg rd  =  u32_le (2432697312 + rd)

fn :: arm64_ldr_slot Int Int  => [Int]
      arm64_ldr_slot rd  slot =  u32_le (4181722080 + ((slot % 4096) * 1024) + rd)

fn :: arm64_lea_slot Int Int  => [Int]
      arm64_lea_slot rd  slot =  u32_le (2432697312 + (((slot * 8) % 4096) * 1024) + rd)

fn :: arm64_norm_imm26 Int => Int
      arm64_norm_imm26 w
        | w < 0 = (w + 67108864) % 67108864
        | otherwise = w % 67108864

fn :: arm64_norm_imm19 Int => Int
      arm64_norm_imm19 w
        | w < 0 = (w + 524288) % 524288
        | otherwise = w % 524288

fn :: arm64_b Int          Int       => [Int]
      arm64_b target_vaddr cur_vaddr =
        imm26 = arm64_norm_imm26 ((target_vaddr - cur_vaddr) / 4)
        u32_le (335544320 + imm26)

fn :: arm64_bl Int          Int       => [Int]
      arm64_bl target_vaddr cur_vaddr =
        imm26 = arm64_norm_imm26 ((target_vaddr - cur_vaddr) / 4)
        u32_le (2483027968 + imm26)

fn :: arm64_bl_rt Int   Int       => [Int]
      arm64_bl_rt rt_id cur_vaddr =  arm64_bl (4198400 + (rt_id * 8)) cur_vaddr

fn :: arm64_cbz_x0 Int          Int       => [Int]
      arm64_cbz_x0 target_vaddr cur_vaddr =
        imm19 = arm64_norm_imm19 ((target_vaddr - cur_vaddr) / 4)
        u32_le (3019898880 + (imm19 * 32))

fn :: arm64_cbnz_x0 Int          Int       => [Int]
      arm64_cbnz_x0 target_vaddr cur_vaddr =
        imm19 = arm64_norm_imm19 ((target_vaddr - cur_vaddr) / 4)
        u32_le (3036676096 + (imm19 * 32))

-- ── Fixed-Width ARM64 Instruction Size Table (Pass 1) ────────

fn :: arm64_instr_size RNativeInstr       => Int
      arm64_instr_size (NLabel _)         =  0
      arm64_instr_size (NJump _)          =  4
      arm64_instr_size (NJumpIfZero _)    =  4
      arm64_instr_size (NJumpIfNonZero _) =  4
      arm64_instr_size (NLoadImmInt _)    =  16
      arm64_instr_size (NLoadImmRaw _)    =  16
      arm64_instr_size (NLoadRealLit _ _) =  36
      arm64_instr_size (NLoadStrLit _ _)  =  36
      arm64_instr_size (NLoadAdt0 _ _)    =  36
      arm64_instr_size (NCloneSlot _)     =  8
      arm64_instr_size (NMoveSlot _)      =  8
      arm64_instr_size (NStoreSlot _)     =  12
      arm64_instr_size (NRebindSlot _)    =  12
      arm64_instr_size (NCmmDropSlot _)   =  8
      arm64_instr_size NDropVal           =  4
      arm64_instr_size (NClearLocals _ _) =  40
      arm64_instr_size (NMatchInt _ _)    =  24
      arm64_instr_size (NMatchReal _ _ _) =  40
      arm64_instr_size (NMatchStr _ _ _)  =  40
      arm64_instr_size (NMatchBool _ _)   =  24
      arm64_instr_size (NMatchEmpty _)    =  8
      arm64_instr_size (NMatchNonEmpty _) =  8
      arm64_instr_size (NMatchTuple _ _)  =  24
      arm64_instr_size (NMatchAdt _ _ _ _) = 56
      arm64_instr_size (NListHead _)      =  8
      arm64_instr_size (NListTail _)      =  8
      arm64_instr_size (NTupleGet _ _)    =  24
      arm64_instr_size (NAdtField _ _)    =  24
      arm64_instr_size (NPackSeq _)       =  24
      arm64_instr_size NAsBool            =  4
      arm64_instr_size NNot               =  4
      arm64_instr_size NOut               =  4
      arm64_instr_size (NBinOp _ _)       =  28
      arm64_instr_size (NAdtSet _ _)      =  28
      arm64_instr_size (NMakeList _ _)    =  24
      arm64_instr_size (NMakeTuple _ _)   =  24
      arm64_instr_size (NMakeTensor _ _)  =  24
      arm64_instr_size (NMakeAdt _ _ _ _) =  56
      arm64_instr_size (NEcho _ _)        =  24
      arm64_instr_size (NStrInterp _ _)   =  24
      arm64_instr_size (NIndex _ _ _)     =  28
      arm64_instr_size (NIndexSet _ _ _)  =  32
      arm64_instr_size (NSeqSelect _ _)   =  36
      arm64_instr_size (NEinsum _ _ _ _)  =  56
      arm64_instr_size (NHadamard _ _ _ _) = 60
      arm64_instr_size (NPushCtx _ _)     =  40
      arm64_instr_size (NPopCtx _ _)      =  40
      arm64_instr_size (NHasCtx _ _)      =  36
      arm64_instr_size (NGetCtx _ _)      =  36
      arm64_instr_size NEnterRegion       =  4
      arm64_instr_size (NExitRegion _)    =  24
      arm64_instr_size (NHasShared _ _)   =  36
      arm64_instr_size (NGetShared _ _)   =  36
      arm64_instr_size (NInitShared _ _)  =  40
      arm64_instr_size (NStoreShared _ _) =  40
      arm64_instr_size (NCallFn _ _ _)    =  8
      arm64_instr_size (NCallBuiltin _ _ _) = 40
      arm64_instr_size (NCallIndirect1 _ _) = 12
      arm64_instr_size (NCallIndirect2 _ _) = 12
      arm64_instr_size (NTailCall _ _)    =  60
      arm64_instr_size NReturn            =  52

fn :: arm64_scan_instrs [RNativeInstr] Int     [RLabelEntry] => RScanResult
      arm64_scan_instrs []             cur_off labels        =  ScanResult cur_off labels
      arm64_scan_instrs ((NLabel lid):rest) cur_off labels   =
        arm64_scan_instrs rest cur_off (labels :: [LabelEntry lid cur_off])
      arm64_scan_instrs (ins:rest)     cur_off labels        =
        sz = arm64_instr_size ins
        arm64_scan_instrs rest (cur_off + sz) labels

fn :: arm64_scan_fns [RNativeFn] Int       [RLabelEntry] => RScanResult
      arm64_scan_fns []          cur_vaddr fn_table      =  ScanResult cur_vaddr fn_table
      arm64_scan_fns ((NativeFn fid _ _ _ instrs):rest) cur_vaddr fn_table =
        sr = arm64_scan_instrs instrs (cur_vaddr + 72) []
        end_vaddr = scan_offset sr
        arm64_scan_fns rest end_vaddr (fn_table :: [LabelEntry fid cur_vaddr])

-- ── ARM64 Function Prologue & Instruction Encoder (Pass 2) ───

fn :: arm64_frame_size Int       => Int
      arm64_frame_size num_slots =  (((num_slots + 1) / 2) * 16)

fn :: arm64_prologue Int      Int   Int       => [Int]
      arm64_prologue fn_vaddr arity num_slots =
        fsz = arm64_frame_size num_slots
        (u32_le 2843738109) :: (u32_le 2432697341) :: (arm64_mov_imm64 9 fsz) :: (u32_le 3407938559) :: (arm64_mov_reg 1 0) :: (arm64_mov_sp_to_reg 0) :: (arm64_mov_imm64 2 arity) :: (arm64_mov_imm64 3 num_slots) :: (arm64_bl_rt 1 (fn_vaddr + 68))

fn :: arm64_encode_instr RNativeInstr Int Int Int Int [RLabelEntry] [RLabelEntry] => [Int]
      arm64_encode_instr (NLabel _) _ _ _ _ _ _ = []
      arm64_encode_instr (NJump lid) cur_vaddr _ _ _ lbl_table _ =
        target = lookup_label_offset lbl_table lid
        arm64_b target cur_vaddr
      arm64_encode_instr (NJumpIfZero lid) cur_vaddr _ _ _ lbl_table _ =
        target = lookup_label_offset lbl_table lid
        arm64_cbz_x0 target cur_vaddr
      arm64_encode_instr (NJumpIfNonZero lid) cur_vaddr _ _ _ lbl_table _ =
        target = lookup_label_offset lbl_table lid
        arm64_cbnz_x0 target cur_vaddr
      arm64_encode_instr (NLoadImmInt n) _ _ _ _ _ _ =
        arm64_mov_imm64 0 ((n * 2) + 1)
      arm64_encode_instr (NLoadImmRaw raw) _ _ _ _ _ _ =
        arm64_mov_imm64 0 raw
      arm64_encode_instr (NLoadRealLit off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + off)) :: (arm64_mov_imm64 1 len) :: (arm64_bl_rt 11 (cur_vaddr + 32))
      arm64_encode_instr (NLoadStrLit off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + off)) :: (arm64_mov_imm64 1 len) :: (arm64_bl_rt 12 (cur_vaddr + 32))
      arm64_encode_instr (NLoadAdt0 off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + off)) :: (arm64_mov_imm64 1 len) :: (arm64_bl_rt 13 (cur_vaddr + 32))
      arm64_encode_instr (NCloneSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_bl_rt 5 (cur_vaddr + 4))
      arm64_encode_instr (NMoveSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 slot) :: (arm64_bl_rt 7 (cur_vaddr + 4))
      arm64_encode_instr (NStoreSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64_mov_reg 1 0) :: (arm64_lea_slot 0 slot) :: (arm64_bl_rt 8 (cur_vaddr + 8))
      arm64_encode_instr (NRebindSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64_mov_reg 1 0) :: (arm64_lea_slot 0 slot) :: (arm64_bl_rt 9 (cur_vaddr + 8))
      arm64_encode_instr (NCmmDropSlot slot) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 slot) :: (arm64_bl_rt 10 (cur_vaddr + 4))
      arm64_encode_instr NDropVal cur_vaddr _ _ _ _ _ =
        arm64_bl_rt 6 cur_vaddr
      arm64_encode_instr (NClearLocals start_slot end_slot) cur_vaddr _ _ _ _ _ =
        (arm64_mov_sp_to_reg 0) :: (arm64_mov_imm64 1 start_slot) :: (arm64_mov_imm64 2 end_slot) :: (arm64_bl_rt 4 (cur_vaddr + 36))
      arm64_encode_instr (NMatchInt slot n) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 n) :: (arm64_bl_rt 21 (cur_vaddr + 20))
      arm64_encode_instr (NMatchReal slot off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 (rodata_vaddr + off)) :: (arm64_mov_imm64 2 len) :: (arm64_bl_rt 22 (cur_vaddr + 36))
      arm64_encode_instr (NMatchStr slot off len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 (rodata_vaddr + off)) :: (arm64_mov_imm64 2 len) :: (arm64_bl_rt 23 (cur_vaddr + 36))
      arm64_encode_instr (NMatchBool slot b_int) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 b_int) :: (arm64_bl_rt 24 (cur_vaddr + 20))
      arm64_encode_instr (NMatchEmpty slot) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_bl_rt 25 (cur_vaddr + 4))
      arm64_encode_instr (NMatchNonEmpty slot) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_bl_rt 26 (cur_vaddr + 4))
      arm64_encode_instr (NMatchTuple slot arity) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 arity) :: (arm64_bl_rt 29 (cur_vaddr + 20))
      arm64_encode_instr (NMatchAdt slot off len arity) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 (rodata_vaddr + off)) :: (arm64_mov_imm64 2 len) :: (arm64_mov_imm64 3 arity) :: (arm64_bl_rt 31 (cur_vaddr + 52))
      arm64_encode_instr (NListHead slot) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_bl_rt 27 (cur_vaddr + 4))
      arm64_encode_instr (NListTail slot) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_bl_rt 28 (cur_vaddr + 4))
      arm64_encode_instr (NTupleGet slot idx) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 idx) :: (arm64_bl_rt 30 (cur_vaddr + 20))
      arm64_encode_instr (NAdtField slot idx) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 slot) :: (arm64_mov_imm64 1 idx) :: (arm64_bl_rt 32 (cur_vaddr + 20))
      arm64_encode_instr (NPackSeq arity) cur_vaddr _ _ _ _ _ =
        (arm64_mov_sp_to_reg 0) :: (arm64_mov_imm64 1 arity) :: (arm64_bl_rt 19 (cur_vaddr + 20))
      arm64_encode_instr NAsBool cur_vaddr _ _ _ _ _ =
        arm64_bl_rt 20 cur_vaddr
      arm64_encode_instr NNot cur_vaddr _ _ _ _ _ =
        arm64_bl_rt 34 cur_vaddr
      arm64_encode_instr NOut cur_vaddr _ _ _ _ _ =
        arm64_bl_rt 35 cur_vaddr
      arm64_encode_instr (NBinOp op_id lhs_slot) cur_vaddr _ _ _ _ _ =
        (arm64_mov_reg 2 0) :: (arm64_mov_imm64 0 op_id) :: (arm64_lea_slot 1 lhs_slot) :: (arm64_bl_rt 37 (cur_vaddr + 24))
      arm64_encode_instr (NAdtSet rec_slot idx) cur_vaddr _ _ _ _ _ =
        (arm64_mov_reg 2 0) :: (arm64_lea_slot 0 rec_slot) :: (arm64_mov_imm64 1 idx) :: (arm64_bl_rt 33 (cur_vaddr + 24))
      arm64_encode_instr (NMakeList start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 start_slot) :: (arm64_mov_imm64 1 count) :: (arm64_bl_rt 15 (cur_vaddr + 20))
      arm64_encode_instr (NMakeTuple start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 start_slot) :: (arm64_mov_imm64 1 count) :: (arm64_bl_rt 16 (cur_vaddr + 20))
      arm64_encode_instr (NMakeTensor start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 start_slot) :: (arm64_mov_imm64 1 count) :: (arm64_bl_rt 17 (cur_vaddr + 20))
      arm64_encode_instr (NMakeAdt off len start_slot count) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + off)) :: (arm64_mov_imm64 1 len) :: (arm64_lea_slot 2 start_slot) :: (arm64_mov_imm64 3 count) :: (arm64_bl_rt 14 (cur_vaddr + 52))
      arm64_encode_instr (NEcho start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 start_slot) :: (arm64_mov_imm64 1 count) :: (arm64_bl_rt 36 (cur_vaddr + 20))
      arm64_encode_instr (NStrInterp start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 start_slot) :: (arm64_mov_imm64 1 count) :: (arm64_bl_rt 18 (cur_vaddr + 20))
      arm64_encode_instr (NIndex base_slot idx_start count) cur_vaddr _ _ _ _ _ =
        (arm64_lea_slot 0 base_slot) :: (arm64_lea_slot 1 idx_start) :: (arm64_mov_imm64 2 count) :: (arm64_bl_rt 38 (cur_vaddr + 24))
      arm64_encode_instr (NIndexSet base_slot idx_start count) cur_vaddr _ _ _ _ _ =
        (arm64_mov_reg 3 0) :: (arm64_lea_slot 0 base_slot) :: (arm64_lea_slot 1 idx_start) :: (arm64_mov_imm64 2 count) :: (arm64_bl_rt 39 (cur_vaddr + 28))
      arm64_encode_instr (NSeqSelect mask_off mask_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 1 (rodata_vaddr + mask_off)) :: (arm64_mov_imm64 2 mask_len) :: (arm64_bl_rt 40 (cur_vaddr + 32))
      arm64_encode_instr (NEinsum start_slot count spec_off spec_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_lea_slot 0 start_slot) :: (arm64_mov_imm64 1 count) :: (arm64_mov_imm64 2 (rodata_vaddr + spec_off)) :: (arm64_mov_imm64 3 spec_len) :: (arm64_bl_rt 41 (cur_vaddr + 52))
      arm64_encode_instr (NHadamard op_id lhs_slot subs_off subs_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_reg 2 0) :: (arm64_mov_imm64 0 op_id) :: (arm64_lea_slot 1 lhs_slot) :: (arm64_mov_imm64 3 (rodata_vaddr + subs_off)) :: (arm64_mov_imm64 4 subs_len) :: (arm64_bl_rt 42 (cur_vaddr + 56))
      arm64_encode_instr (NPushCtx key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_reg 2 0) :: (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 43 (cur_vaddr + 36))
      arm64_encode_instr (NPopCtx key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_reg 2 0) :: (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 44 (cur_vaddr + 36))
      arm64_encode_instr (NHasCtx key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 45 (cur_vaddr + 32))
      arm64_encode_instr (NGetCtx key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 46 (cur_vaddr + 32))
      arm64_encode_instr NEnterRegion cur_vaddr _ _ _ _ _ =
        arm64_bl_rt 47 cur_vaddr
      arm64_encode_instr (NExitRegion quota) cur_vaddr _ _ _ _ _ =
        (arm64_mov_reg 1 0) :: (arm64_mov_imm64 0 quota) :: (arm64_bl_rt 48 (cur_vaddr + 20))
      arm64_encode_instr (NHasShared key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 49 (cur_vaddr + 32))
      arm64_encode_instr (NGetShared key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 50 (cur_vaddr + 32))
      arm64_encode_instr (NInitShared key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_reg 2 0) :: (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 51 (cur_vaddr + 36))
      arm64_encode_instr (NStoreShared key_off key_len) cur_vaddr _ _ rodata_vaddr _ _ =
        (arm64_mov_reg 2 0) :: (arm64_mov_imm64 0 (rodata_vaddr + key_off)) :: (arm64_mov_imm64 1 key_len) :: (arm64_bl_rt 52 (cur_vaddr + 36))
      arm64_encode_instr (NCallFn fid start_slot _) cur_vaddr _ _ _ _ fn_table =
        target_fn = lookup_label_offset fn_table fid
        (arm64_lea_slot 0 start_slot) :: (arm64_bl target_fn (cur_vaddr + 4))
      arm64_encode_instr (NCallBuiltin b_id start_slot count) cur_vaddr _ _ _ _ _ =
        (arm64_mov_imm64 0 b_id) :: (arm64_lea_slot 1 start_slot) :: (arm64_mov_imm64 2 count) :: (arm64_bl_rt 55 (cur_vaddr + 36))
      arm64_encode_instr (NCallIndirect1 fn_slot arg_slot) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 fn_slot) :: (arm64_lea_slot 1 arg_slot) :: (arm64_bl_rt 53 (cur_vaddr + 8))
      arm64_encode_instr (NCallIndirect2 fn_slot start_slot) cur_vaddr _ _ _ _ _ =
        (arm64_ldr_slot 0 fn_slot) :: (arm64_lea_slot 1 start_slot) :: (arm64_bl_rt 54 (cur_vaddr + 8))
      arm64_encode_instr (NTailCall start_slot arity) cur_vaddr fn_vaddr num_slots _ _ _ =
        (arm64_mov_sp_to_reg 0) :: (arm64_mov_imm64 1 start_slot) :: (arm64_mov_imm64 2 arity) :: (arm64_mov_imm64 3 num_slots) :: (arm64_bl_rt 3 (cur_vaddr + 52)) :: (arm64_b (fn_vaddr + 72) (cur_vaddr + 56))
      arm64_encode_instr NReturn cur_vaddr _ num_slots _ _ _ =
        fsz = arm64_frame_size num_slots
        (arm64_mov_reg 2 0) :: (arm64_mov_sp_to_reg 0) :: (arm64_mov_imm64 1 num_slots) :: (arm64_bl_rt 2 (cur_vaddr + 24)) :: (arm64_mov_imm64 9 fsz) :: (u32_le 2334196735) :: (u32_le 2831155197) :: (u32_le 3596551104)

fn :: arm64_encode_instrs [RNativeInstr] Int Int Int Int [RLabelEntry] [RLabelEntry] [Int] => [Int]
      arm64_encode_instrs [] _ _ _ _ _ _ acc = acc
      arm64_encode_instrs (ins:rest) cur_vaddr fn_vaddr num_slots rodata_vaddr lbl_table fn_table acc =
        sz = arm64_instr_size ins
        bytes = arm64_encode_instr ins cur_vaddr fn_vaddr num_slots rodata_vaddr lbl_table fn_table
        arm64_encode_instrs rest (cur_vaddr + sz) fn_vaddr num_slots rodata_vaddr lbl_table fn_table (acc :: bytes)

fn :: arm64_encode_fns [RNativeFn] Int          [RLabelEntry] [Int] => [Int]
      arm64_encode_fns []          _            _             acc   =  acc
      arm64_encode_fns ((NativeFn fid _ arity num_slots instrs):rest) rodata_vaddr fn_table acc =
        fn_vaddr = lookup_label_offset fn_table fid
        sr = arm64_scan_instrs instrs (fn_vaddr + 72) []
        lbl_table = scan_labels sr
        pro = arm64_prologue fn_vaddr arity num_slots
        fn_bytes = arm64_encode_instrs instrs (fn_vaddr + 72) fn_vaddr num_slots rodata_vaddr lbl_table fn_table pro
        arm64_encode_fns rest rodata_vaddr fn_table (acc :: fn_bytes)

-- ── Freestanding Linux ARM64 (AArch64) Syscall Runtime Kernel (Region 1) ──
-- Each jump table slot `i` (`0..55`) at `0x401000 + i*8` is 8 bytes (two 32-bit
-- AArch64 instructions). Short 2-instruction primitives execute inline inside their
-- 8-byte jump table slot; multi-instruction routines branch (`B`) to `0x4011C0+`.

fn :: arm64_rt_slot Int => [Int]
      -- rt_0 (_start): branch to 0x4011C0 (+112 words)
      arm64_rt_slot 0   =  (u32_le 335544432) :: (u32_le 3573751839)
      -- rt_1 (rg_init_frame): branch to 0x4011E8 (+121 words from slot 1)
      arm64_rt_slot 1   =  (u32_le 335544441) :: (u32_le 3573751839)
      -- rt_2 (rg_epilogue): MOV X0, X2 ; RET
      arm64_rt_slot 2   =  (u32_le 2852258784) :: (u32_le 3596551104)
      -- rt_3 (rg_tco_copy): branch to 0x401204 (+126 words from slot 3)
      arm64_rt_slot 3   =  (u32_le 335544446) :: (u32_le 3573751839)
      -- rt_5 (rg_clone): NOP ; RET (X0 already holds value)
      arm64_rt_slot 5   =  (u32_le 3573751839) :: (u32_le 3596551104)
      -- rt_6 (rg_drop): NOP ; RET
      arm64_rt_slot 6   =  (u32_le 3573751839) :: (u32_le 3596551104)
      -- rt_7 (rg_cmm_move): LDR X0, [X0] ; RET
      arm64_rt_slot 7   =  (u32_le 4181721088) :: (u32_le 3596551104)
      -- rt_8 (rg_store_local): STR X1, [X0] ; RET
      arm64_rt_slot 8   =  (u32_le 4177526785) :: (u32_le 3596551104)
      -- rt_9 (rg_rebind_local): STR X1, [X0] ; RET
      arm64_rt_slot 9   =  (u32_le 4177526785) :: (u32_le 3596551104)
      -- rt_10 (rg_cmm_drop): STR XZR, [X0] ; RET
      arm64_rt_slot 10  =  (u32_le 4177526815) :: (u32_le 3596551104)
      -- rt_20 (rg_as_bool): UBFX X0, X0, #1, #1 ; RET
      arm64_rt_slot 20  =  (u32_le 3544253440) :: (u32_le 3596551104)
      -- rt_21 (rg_match_int): branch to 0x401220 (+94 words from slot 21)
      arm64_rt_slot 21  =  (u32_le 335544414) :: (u32_le 3573751839)
      -- rt_24 (rg_match_bool): branch to 0x401230 (+92 words from slot 24)
      arm64_rt_slot 24  =  (u32_le 335544412) :: (u32_le 3573751839)
      -- rt_34 (rg_not): EOR X0, X0, #2 ; RET
      arm64_rt_slot 34  =  (u32_le 3531538432) :: (u32_le 3596551104)
      -- rt_37 (rg_bin_op): branch to 0x401240 (+70 words from slot 37)
      arm64_rt_slot 37  =  (u32_le 335544390) :: (u32_le 3573751839)
      -- Default slot: RET ; NOP
      arm64_rt_slot _   =  (u32_le 3596551104) :: (u32_le 3573751839)

fn :: arm64_rt_stub_table Int [Int] => [Int]
      arm64_rt_stub_table idx acc
        | idx >= 56 = acc
        | otherwise =
          entry = arm64_rt_slot idx
          arm64_rt_stub_table (idx + 1) (acc :: entry)

fn :: build_arm64_rt_kernel => [Int]
      build_arm64_rt_kernel =
        jt = arm64_rt_stub_table 0 []
        -- 0x4011C0 (_start, 10 words = 40 bytes):
        -- Load main_vaddr from 0x400080, pass SP in X0, BLR X10, then SYS_exit_group(0) (X8=94, SVC #0)
        start_code = (arm64_mov_imm64 9 4194432) :: (u32_le 4181721386) :: (arm64_mov_sp_to_reg 0) :: (u32_le 3594453280) :: (u32_le 3531603968) :: (u32_le 3531605192) :: (u32_le 3556769793)
        -- 0x4011E8 (rg_init_frame, 7 words = 28 bytes):
        -- Copy X2 args from [X1] into [X0]
        init_frame_code = (u32_le 3019898978) :: (u32_le 4165009449) :: (u32_le 4160815113) :: (u32_le 3407873090) :: (u32_le 1409286141) :: (u32_le 3596551104) :: (u32_le 3573751839)
        -- 0x401204 (rg_tco_copy, 7 words = 28 bytes):
        -- Copy X2 args from [X0 + X1*8] into [X0]
        tco_code = (u32_le 2335705099) :: (u32_le 3019898978) :: (u32_le 4165009545) :: (u32_le 4160815113) :: (u32_le 3407873090) :: (u32_le 1409286141) :: (u32_le 3596551104)
        -- 0x401220 (rg_match_int, 4 words = 16 bytes): ASR X0, X0, #1 ; CMP X0, X1 ; CSET X0, EQ ; RET
        match_int_code = (u32_le 2470575104) :: (u32_le 3942711327) :: (u32_le 2594117600) :: (u32_le 3596551104)
        -- 0x401230 (rg_match_bool, 4 words = 16 bytes): UBFX X0, X0, #1, #1 ; CMP X0, X1 ; CSET X0, EQ ; RET
        match_bool_code = (u32_le 3544253440) :: (u32_le 3942711327) :: (u32_le 2594117600) :: (u32_le 3596551104)
        -- 0x401240 (rg_bin_op, 12 words = 48 bytes):
        -- LDR X9, [X1] ; ASR X9, X9, #1 ; ASR X10, X2, #1 ; ADD/SUB/MUL dispatch ; LSL X0, X0, #1 ; ORR X0, X0, #1 ; RET
        binop_code = (u32_le 4181721129) :: (u32_le 2470575399) :: (u32_le 2470575178) :: (u32_le 3942649856) :: (u32_le 1409286148) :: (u32_le 2332688681) :: (u32_le 335544323) :: (u32_le 3406430505) :: (u32_le 2583691561) :: (u32_le 3544186880) :: (u32_le 2990538752) :: (u32_le 3596551104)
        jt :: start_code :: init_frame_code :: tco_code :: match_int_code :: match_bool_code :: binop_code

-- ── Public ARM64 ELF64 Image Builder ─────────────────────────

fn :: emit_arm64_elf RNativeProg => [Int]
      emit_arm64_elf (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
        rt_bytes = build_arm64_rt_kernel
        rt_len = byte_list_len rt_bytes
        region2_vaddr = 4198400 + rt_len
        sr = arm64_scan_fns fns region2_vaddr []
        rodata_vaddr = scan_offset sr
        fn_table = scan_labels sr
        code_len = rodata_vaddr - region2_vaddr
        code_bytes = arm64_encode_fns fns rodata_vaddr fn_table []
        main_vaddr = lookup_label_offset fn_table main_fid
        spawn_vaddr = lookup_label_offset fn_table spawn_fid
        call2_vaddr = lookup_label_offset fn_table call2_fid
        binop_vaddr = lookup_label_offset fn_table binop_fid
        build_elf64_image 183 main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str
