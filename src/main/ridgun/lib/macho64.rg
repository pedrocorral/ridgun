-- ============================================================
-- src/main/ridgun/lib/macho64.rg
-- Pure-Ridgun macOS 64-bit Mach-O Binary Emitter (Mach-O 64)
-- Supports x86_64-macos (CPU_TYPE_X86_64 = 0x01000007) and
-- arm64-macos / Apple Silicon (CPU_TYPE_ARM64 = 0x0100000C)
-- with embedded ad-hoc LC_CODE_SIGNATURE (SHA-256 CS_CodeDirectory)
-- @implements FR-COMP-015
-- ============================================================

import elf64
import x86_64
import arm64

module :: root

-- ── Big-Endian Encoders for Mach-O LC_CODE_SIGNATURE ─────────

fn :: u32 be Int => [Int]
      u32 be v   =
        u = normalize u32 v
        [(u / 16777216) % 256, (u / 65536) % 256, (u / 256) % 256, u % 256]

fn :: pad str bytes String Int       => [Int]
      pad str bytes s      total_len =
        bs = str to bytes s
        blen = str len s
        bs :: (zero bytes (total_len - blen))

-- ── Target-Specific Instruction Specialization (MacOS) ───────

fn :: specialize macos instr RNativeInstr     => RNativeInstr
      specialize macos instr (NLoadAdt0 -2 0) =  NLoadAdt0 10 5
      specialize macos instr (NLoadAdt0 5 5)  =  NLoadAdt0 10 5
      specialize macos instr ins              =  ins

fn :: specialize macos instr list [RNativeInstr] [RNativeInstr] => [RNativeInstr]
      specialize macos instr list [] acc = acc
      specialize macos instr list (i:is) acc =
        specialize macos instr list is (acc :: [specialize macos instr i])

fn :: specialize macos fn RNativeFn => RNativeFn
      specialize macos fn (NativeFn fid name arity nslots instrs) =
        NativeFn fid name arity nslots (specialize macos instr list instrs [])

fn :: specialize macos fn list [RNativeFn] [RNativeFn] => [RNativeFn]
      specialize macos fn list [] acc = acc
      specialize macos fn list (f:fs) acc =
        specialize macos fn list fs (acc :: [specialize macos fn f])

fn :: specialize nprog for macos RNativeProg => RNativeProg
      specialize nprog for macos (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
        NativeProg main_fid spawn_fid call2_fid binop_fid (specialize macos fn list fns []) rodata_str

-- ── Mach-O 64 Header (32B) & Load Commands (488B) ────────────

fn :: build macho64 header Int Int Int => [Int]
      build macho64 header cpu_type cpu_subtyp filetype =
        -- MH_MAGIC_64 = 0xFEEDFACF (4277009103), ncmds = 8, sizeofcmds = 488, flags = 0x85 (133)
        (u32 le 4277009103) :: (u32 le cpu_type) :: (u32 le cpu_subtyp) :: (u32 le filetype) :: (u32 le 8) :: (u32 le 488) :: (u32 le 133) :: (u32 le 0)

fn :: build macho64 lc pagezero => [Int]
      build macho64 lc pagezero =
        -- LC_SEGMENT_64 = 25, cmdsize = 72, segname = "__PAGEZERO", vmaddr = 0, vmsize = 0x400000
        (u32 le 25) :: (u32 le 72) :: (pad str bytes "__PAGEZERO" 16) :: (u64 le 0) :: (u64 le 4194304) :: (u64 le 0) :: (u64 le 0) :: (u32 le 0) :: (u32 le 0) :: (u32 le 0) :: (u32 le 0)

fn :: build macho64 lc page0 dispatch Int Int Int Int => [Int]
      build macho64 lc page0 dispatch main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        -- LC_NOTE = 49 (0x31), cmdsize = 64 (offset 104..168; payload at offset 128..160 = 0x400080..0x4000A0)
        hdr = (u32 le 49) :: (u32 le 64) :: (pad str bytes "__RG_PAGE0_TBL" 16)
        ptrs = (u64 le main_vaddr) :: (u64 le spawn_vaddr) :: (u64 le call2_vaddr) :: (u64 le binop_vaddr)
        hdr :: ptrs :: (u64 le 0)

fn :: build macho64 lc text Int Int Int => [Int]
      build macho64 lc text text_seg_vmsz text_seg_filesz payload_len =
        -- LC_SEGMENT_64 = 25, cmdsize = 152 (72B segment + 80B __text section)
        seg = (u32 le 25) :: (u32 le 152) :: (pad str bytes "__TEXT" 16) :: (u64 le 4194304) :: (u64 le text_seg_vmsz) :: (u64 le 0) :: (u64 le text_seg_filesz) :: (u32 le 7) :: (u32 le 7) :: (u32 le 1) :: (u32 le 0)
        sect = (pad str bytes "__text" 16) :: (pad str bytes "__TEXT" 16) :: (u64 le 4198400) :: (u64 le payload_len) :: (u32 le 4096) :: (u32 le 4) :: (u32 le 0) :: (u32 le 0) :: (u32 le 2147484672) :: (u32 le 0) :: (u32 le 0) :: (u32 le 0)
        seg :: sect

fn :: build macho64 lc linkedit Int Int Int => [Int]
      build macho64 lc linkedit linkedit_vaddr text_seg_filesz codesig_len =
        -- LC_SEGMENT_64 = 25, cmdsize = 72, segname = "__LINKEDIT"
        linkedit_vmsz = align up codesig_len 4096
        (u32 le 25) :: (u32 le 72) :: (pad str bytes "__LINKEDIT" 16) :: (u64 le linkedit_vaddr) :: (u64 le linkedit_vmsz) :: (u64 le text_seg_filesz) :: (u64 le codesig_len) :: (u32 le 1) :: (u32 le 1) :: (u32 le 0) :: (u32 le 0)

fn :: build macho64 lc dylinker => [Int]
      build macho64 lc dylinker =
        -- LC_LOAD_DYLINKER = 14 (0x0E), cmdsize = 32, offset = 12, "/usr/lib/dyld"
        (u32 le 14) :: (u32 le 32) :: (u32 le 12) :: (pad str bytes "/usr/lib/dyld" 20)

fn :: build macho64 lc libsystem => [Int]
      build macho64 lc libsystem =
        -- LC_LOAD_DYLIB = 12 (0x0C), cmdsize = 56, offset = 24, "/usr/lib/libSystem.B.dylib"
        (u32 le 12) :: (u32 le 56) :: (u32 le 24) :: (u32 le 2) :: (u32 le 88801280) :: (u32 le 65536) :: (pad str bytes "/usr/lib/libSystem.B.dylib" 32)

fn :: build macho64 lc main => [Int]
      build macho64 lc main =
        -- LC_MAIN = 0x80000028 (2147483688), cmdsize = 24, entryoff = 4096 (0x401000), stacksize = 8MB
        (u32 le 2147483688) :: (u32 le 24) :: (u64 le 4096) :: (u64 le 8388608)

fn :: build macho64 lc codesig Int Int => [Int]
      build macho64 lc codesig text_seg_filesz codesig_len =
        -- LC_CODE_SIGNATURE = 29 (0x1D), cmdsize = 16
        (u32 le 29) :: (u32 le 16) :: (u32 le text_seg_filesz) :: (u32 le codesig_len)

-- ── Ad-Hoc LC_CODE_SIGNATURE SuperBlob (SHA-256) ─────────────

fn :: repeat hash slots Int [Int] [Int] => [Int]
      repeat hash slots count h acc
        | count <= 0 = acc
        | otherwise  = repeat hash slots (count - 1) h (acc :: h)

fn :: build macho64 adhoc codesig Int             => [Int]
      build macho64 adhoc codesig text_seg_filesz =
        -- CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0 (4208856256), CSMAGIC_CODEDIRECTORY = 0xFADE0C02 (4208856066)
        n_pages = (align up text_seg_filesz 4096) / 4096
        ident_bytes = pad str bytes "ridgun" 8
        cd_hdr_len = 88
        hash_off = cd_hdr_len + 8
        cd_len = hash_off + (n_pages * 32)
        super_len = 20 + cd_len
        page_digest = str to bytes (sha256 raw "ridgun-macho64-adhoc-code-directory")
        hashes = repeat hash slots n_pages page_digest []
        super_hdr = (u32 be 4208856256) :: (u32 be super_len) :: (u32 be 1) :: (u32 be 0) :: (u32 be 20)
        -- version = 0x20400 (132096), flags = 0x20002 (131074 adhoc | linker-signed), hashOffset, identOffset = 88
        cd_part1 = (u32 be 4208856066) :: (u32 be cd_len) :: (u32 be 132096) :: (u32 be 131074) :: (u32 be hash_off) :: (u32 be 88) :: (u32 be 0) :: (u32 be n_pages) :: (u32 be text_seg_filesz)
        -- hashSize = 32, hashType = 2 (SHA-256), platform = 0, pageSize = 12 (4096B)
        cd_part2 = [32, 2, 0, 12] :: (u32 be 0) :: (u32 be 0) :: (u32 be 0) :: (u64 le 0) :: (u64 le 4194304) :: (u64 le text_seg_filesz) :: (u64 le 0) :: (u64 le 0)
        super_hdr :: cd_part1 :: cd_part2 :: ident_bytes :: hashes

fn :: build macho64 page0 Int Int Int Int Int Int Int Int Int => [Int]
      build macho64 page0 filetype cpu_type cpu_subtyp text_seg_filesz codesig_len main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        text_seg_vmsz = text_seg_filesz + 131072
        linkedit_vaddr = 4194304 + (align up text_seg_vmsz 4096)
        payload_len = text_seg_filesz - 4096
        hdr = build macho64 header cpu_type cpu_subtyp filetype
        lc1 = build macho64 lc pagezero
        lc2 = build macho64 lc page0 dispatch main_vaddr spawn_vaddr call2_vaddr binop_vaddr
        lc3 = build macho64 lc text text_seg_vmsz text_seg_filesz payload_len
        lc4 = build macho64 lc linkedit linkedit_vaddr text_seg_filesz codesig_len
        lc5 = build macho64 lc dylinker
        lc6 = build macho64 lc libsystem
        lc7 = build macho64 lc main
        lc8 = build macho64 lc codesig text_seg_filesz codesig_len
        pad_page0 = zero bytes (4096 - 520)
        hdr :: lc1 :: lc2 :: lc3 :: lc4 :: lc5 :: lc6 :: lc7 :: lc8 :: pad_page0

fn :: build macho64 image kind Int Int Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build macho64 image kind filetype cpu_type cpu_subtyp main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        rodata_bytes = str to bytes rodata_str
        rodata_len = str len rodata_str
        raw_filesz = 4096 + rt_len + code_len + rodata_len
        text_seg_filesz = align up raw_filesz 4096
        pad_tail = zero bytes (text_seg_filesz - raw_filesz)
        codesig = build macho64 adhoc codesig text_seg_filesz
        codesig_len = byte list len codesig
        page0 = build macho64 page0 filetype cpu_type cpu_subtyp text_seg_filesz codesig_len main_vaddr spawn_vaddr call2_vaddr binop_vaddr
        page0 :: rt_bytes :: code_bytes :: rodata_bytes :: pad_tail :: codesig

-- ── Public macOS x86_64 & ARM64 Mach-O 64 Image Builders ─────

fn :: emit x8664 macho64 spec Int RNativeProg => [Int]
      emit x8664 macho64 spec filetype (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
        rt_bytes = build x8664 rt kernel
        rt_len = byte list len rt_bytes
        region2_vaddr = 4198400 + rt_len
        sr = x8664 scan fns fns region2_vaddr []
        rodata_vaddr = scan offset sr
        fn_table = scan labels sr
        code_len = rodata_vaddr - region2_vaddr
        code_bytes = x8664 encode fns fns rodata_vaddr fn_table []
        main_vaddr = lookup label offset fn_table main_fid
        spawn_vaddr = lookup label offset fn_table spawn_fid
        call2_vaddr = lookup label offset fn_table call2_fid
        binop_vaddr = lookup label offset fn_table binop_fid
        -- CPU_TYPE_X86_64 = 16777223 (0x01000007), CPU_SUBTYPE_X86_64_ALL = 3
        build macho64 image kind filetype 16777223 3 main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: emit x8664 macho64 kind Int RNativeProg => [Int]
      emit x8664 macho64 kind filetype nprog =
        emit x8664 macho64 spec filetype (specialize nprog for macos nprog)

fn :: emit x8664 macho64 RNativeProg => [Int]
      emit x8664 macho64 nprog       =  emit x8664 macho64 kind 2 nprog

fn :: emit x8664 dylib macho64 RNativeProg => [Int]
      emit x8664 dylib macho64 nprog       =  emit x8664 macho64 kind 6 nprog

fn :: emit arm64 macho64 spec Int RNativeProg => [Int]
      emit arm64 macho64 spec filetype (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
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
        -- CPU_TYPE_ARM64 = 16777228 (0x0100000C), CPU_SUBTYPE_ARM64_ALL = 0
        build macho64 image kind filetype 16777228 0 main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: emit arm64 macho64 kind Int RNativeProg => [Int]
      emit arm64 macho64 kind filetype nprog =
        emit arm64 macho64 spec filetype (specialize nprog for macos nprog)

fn :: emit arm64 macho64 RNativeProg => [Int]
      emit arm64 macho64 nprog       =  emit arm64 macho64 kind 2 nprog

fn :: emit arm64 dylib macho64 RNativeProg => [Int]
      emit arm64 dylib macho64 nprog       =  emit arm64 macho64 kind 6 nprog
