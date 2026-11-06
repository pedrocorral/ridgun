-- ============================================================
-- src/main/ridgun/lib/pe64.rg
-- Pure-Ridgun Windows 64-bit PE32+ (.exe & .dll) Binary Emitter
-- Supports x86_64-windows (IMAGE_FILE_MACHINE_AMD64 = 0x8664)
-- and arm64-windows (IMAGE_FILE_MACHINE_ARM64 = 0xAA64)
-- with KERNEL32.dll Import Directory / IAT (.idata)
-- @implements FR-COMP-015
-- ============================================================

import elf64
import x86_64
import arm64

module :: root

fn :: pad pe str String Int       => [Int]
      pad pe str s      total_len =
        bs = str to bytes s
        blen = str len s
        bs :: (zero bytes (total_len - blen))

-- ── Target-Specific Instruction Specialization (Windows) ─────

fn :: specialize windows instr RNativeInstr     => RNativeInstr
      specialize windows instr (NLoadAdt0 -2 0) =  NLoadAdt0 15 7
      specialize windows instr (NLoadAdt0 5 5)  =  NLoadAdt0 15 7
      specialize windows instr ins              =  ins

fn :: specialize windows instr list [RNativeInstr] [RNativeInstr] => [RNativeInstr]
      specialize windows instr list [] acc = acc
      specialize windows instr list (i:is) acc =
        specialize windows instr list is (acc :: [specialize windows instr i])

fn :: specialize windows fn RNativeFn => RNativeFn
      specialize windows fn (NativeFn fid name arity nslots instrs) =
        NativeFn fid name arity nslots (specialize windows instr list instrs [])

fn :: specialize windows fn list [RNativeFn] [RNativeFn] => [RNativeFn]
      specialize windows fn list [] acc = acc
      specialize windows fn list (f:fs) acc =
        specialize windows fn list fs (acc :: [specialize windows fn f])

fn :: specialize nprog for windows RNativeProg => RNativeProg
      specialize nprog for windows (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
        NativeProg main_fid spawn_fid call2_fid binop_fid (specialize windows fn list fns []) rodata_str

-- ── DOS Header (64B) + Stub (64B) + Page0 Dispatch (32B) ─────

fn :: build pe64 dos and page0 Int Int Int Int => [Int]
      build pe64 dos and page0 main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        -- Offset 0..64: IMAGE_DOS_HEADER ('MZ' at 0, e_lfanew = 256 at 0x3C)
        dos_hdr = [77, 90, 144, 0, 3, 0, 0, 0, 4, 0, 0, 0, 255, 255, 0, 0, 184, 0, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 0, 0, 0, 0] :: (zero bytes 28) :: (u32 le 256)
        -- Offset 64..128: 64-byte DOS stub
        dos_stub = [14, 31, 186, 14, 0, 180, 9, 205, 33, 184, 1, 76, 205, 33] :: (pad pe str "This program requires 64-bit Windows.\r\n$" 50)
        -- Offset 128..160 (0x400080..0x4000A0): Ridgun page-0 dispatch table pointers
        table_ptrs = (u64 le main_vaddr) :: (u64 le spawn_vaddr) :: (u64 le call2_vaddr) :: (u64 le binop_vaddr)
        -- Offset 160..256: 96 zero bytes before PE\0\0 at 256 (0x100)
        dos_hdr :: dos_stub :: table_ptrs :: (zero bytes 96)

-- ── COFF Header (20B) + Optional Header PE32+ (240B) ─────────

fn :: build pe64 coff header Int Int => [Int]
      build pe64 coff header machine chars =
        -- "PE\0\0" (4B) + Machine (2B) + NumberOfSections=2 (2B) + TimeDateStamp=0 (4B) + SymTable=0 (8B) + SizeOfOpt=240 (2B) + Characteristics (2B)
        [80, 69, 0, 0] :: (u16 le machine) :: (u16 le 2) :: (u32 le 0) :: (u32 le 0) :: (u32 le 0) :: (u16 le 240) :: (u16 le chars)

fn :: build pe64 data directories Int       => [Int]
      build pe64 data directories idata_rva =
        -- 16 IMAGE_DATA_DIRECTORY entries (128 bytes): [1] = Import Table (40B), [12] = IAT (64B)
        dir0 = (u32 le 0) :: (u32 le 0)
        dir1_import = (u32 le idata_rva) :: (u32 le 40)
        dir2_to_11 = zero bytes 80
        dir12_iat = (u32 le (idata_rva + 128)) :: (u32 le 64)
        dir13_to_15 = zero bytes 24
        dir0 :: dir1_import :: dir2_to_11 :: dir12_iat :: dir13_to_15

fn :: build pe64 optional header Int Int => [Int]
      build pe64 optional header text_aligned idata_rva =
        -- Magic = 0x020B (523), EntryPoint = 0x1000 (4096), ImageBase = 0x400000 (4194304)
        size_of_image = 4096 + text_aligned + 4096 + 131072
        std_fields = (u16 le 523) :: [14, 0] :: (u32 le text_aligned) :: (u32 le 4096) :: (u32 le 131072) :: (u32 le 4096) :: (u32 le 4096)
        win_fields1 = (u64 le 4194304) :: (u32 le 4096) :: (u32 le 4096) :: (u16 le 6) :: (u16 le 0) :: (u16 le 0) :: (u16 le 0) :: (u16 le 6) :: (u16 le 0) :: (u32 le 0)
        win_fields2 = (u32 le size_of_image) :: (u32 le 4096) :: (u32 le 0) :: (u16 le 3) :: (u16 le 0) :: (u64 le 8388608) :: (u64 le 65536) :: (u64 le 16777216) :: (u64 le 65536) :: (u32 le 0) :: (u32 le 16)
        std_fields :: win_fields1 :: win_fields2 :: (build pe64 data directories idata_rva)

fn :: build pe64 section headers Int Int Int => [Int]
      build pe64 section headers payload_len text_aligned idata_rva =
        -- Section 1: .text (RVA = 4096, VirtualSize = text_aligned + 131072, RawData = 4096, Characteristics = 0xE0000060 = 3758096480)
        text_vsize = text_aligned + 131072
        s_text = (pad pe str ".text" 8) :: (u32 le text_vsize) :: (u32 le 4096) :: (u32 le text_aligned) :: (u32 le 4096) :: (u32 le 0) :: (u32 le 0) :: (u16 le 0) :: (u16 le 0) :: (u32 le 3758096480)
        -- Section 2: .idata (RVA = idata_rva, VirtualSize = 4096, RawOffset = 4096 + text_aligned, Characteristics = 0xC0000040 = 3221225536)
        idata_raw_off = 4096 + text_aligned
        s_idata = (pad pe str ".idata" 8) :: (u32 le 4096) :: (u32 le idata_rva) :: (u32 le 4096) :: (u32 le idata_raw_off) :: (u32 le 0) :: (u32 le 0) :: (u16 le 0) :: (u16 le 0) :: (u32 le 3221225536)
        s_text :: s_idata

-- ── KERNEL32.dll Import Section (.idata, 4096B) ──────────────

fn :: build pe64 hint name String Int => [Int]
      build pe64 hint name sym padded_len =
        (u16 le 0) :: (pad pe str sym (padded_len - 2))

fn :: build pe64 idata section Int       => [Int]
      build pe64 idata section idata_rva =
        -- Layout inside .idata (4096 bytes at RVA = idata_rva):
        -- 0..40   : IMAGE_IMPORT_DESCRIPTOR for KERNEL32.dll + null terminator descriptor
        -- 40..64  : "KERNEL32.dll\0" padded to 24 bytes
        -- 64..128 : Import Lookup Table (ILT: 7 x u64 + null u64 = 64 bytes)
        -- 128..192: Import Address Table (IAT: 7 x u64 + null u64 = 64 bytes)
        -- 192..416: Hint/Name entries (7 x 32 bytes = 224 bytes)
        ilt_rva = idata_rva + 64
        name_rva = idata_rva + 40
        iat_rva = idata_rva + 128
        hn_base = idata_rva + 192
        imp_desc = (u32 le ilt_rva) :: (u32 le 0) :: (u32 le 0) :: (u32 le name_rva) :: (u32 le iat_rva) :: (zero bytes 20)
        dll_name = pad pe str "KERNEL32.dll" 24
        thunks = (u64 le (hn_base + 0)) :: (u64 le (hn_base + 32)) :: (u64 le (hn_base + 64)) :: (u64 le (hn_base + 96)) :: (u64 le (hn_base + 128)) :: (u64 le (hn_base + 160)) :: (u64 le (hn_base + 192)) :: (u64 le 0)
        hns = (build pe64 hint name "GetStdHandle" 32) :: (build pe64 hint name "WriteFile" 32) :: (build pe64 hint name "ReadFile" 32) :: (build pe64 hint name "CreateFileA" 32) :: (build pe64 hint name "CloseHandle" 32) :: (build pe64 hint name "VirtualAlloc" 32) :: (build pe64 hint name "ExitProcess" 32)
        imp_desc :: dll_name :: thunks :: thunks :: hns :: (zero bytes (4096 - 416))

fn :: build pe64 page0 Int Int Int Int Int Int Int Int Int => [Int]
      build pe64 page0 machine chars payload_len text_aligned idata_rva main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        dos_block = build pe64 dos and page0 main_vaddr spawn_vaddr call2_vaddr binop_vaddr
        coff = build pe64 coff header machine chars
        opt = build pe64 optional header text_aligned idata_rva
        sects = build pe64 section headers payload_len text_aligned idata_rva
        -- 256 + 24 + 240 + 80 = 600 bytes; pad 3496 bytes to reach 4096 (0x1000)
        dos_block :: coff :: opt :: sects :: (zero bytes (4096 - 600))

fn :: build pe64 image kind Int Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build pe64 image kind machine chars main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        rodata_bytes = str to bytes rodata_str
        rodata_len = str len rodata_str
        payload_len = rt_len + code_len + rodata_len
        text_aligned = align up payload_len 4096
        pad_text = zero bytes (text_aligned - payload_len)
        idata_rva = 4096 + text_aligned + 131072
        page0 = build pe64 page0 machine chars payload_len text_aligned idata_rva main_vaddr spawn_vaddr call2_vaddr binop_vaddr
        idata = build pe64 idata section idata_rva
        page0 :: rt_bytes :: code_bytes :: rodata_bytes :: pad_text :: idata

-- ── Public Windows x86_64 & ARM64 PE32+ Image Builders ───────

fn :: emit x8664 pe64 spec Int RNativeProg => [Int]
      emit x8664 pe64 spec chars (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
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
        -- IMAGE_FILE_MACHINE_AMD64 = 34404 (0x8664)
        build pe64 image kind 34404 chars main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: emit x8664 pe64 kind Int RNativeProg => [Int]
      emit x8664 pe64 kind chars nprog =
        emit x8664 pe64 spec chars (specialize nprog for windows nprog)

fn :: emit x8664 pe64 RNativeProg => [Int]
      emit x8664 pe64 nprog       =  emit x8664 pe64 kind 34 nprog

fn :: emit x8664 dll pe64 RNativeProg => [Int]
      emit x8664 dll pe64 nprog       =  emit x8664 pe64 kind 8226 nprog

fn :: emit arm64 pe64 spec Int RNativeProg => [Int]
      emit arm64 pe64 spec chars (NativeProg main_fid spawn_fid call2_fid binop_fid fns rodata_str) =
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
        -- IMAGE_FILE_MACHINE_ARM64 = 43620 (0xAA64)
        build pe64 image kind 43620 chars main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: emit arm64 pe64 kind Int RNativeProg => [Int]
      emit arm64 pe64 kind chars nprog =
        emit arm64 pe64 spec chars (specialize nprog for windows nprog)

fn :: emit arm64 pe64 RNativeProg => [Int]
      emit arm64 pe64 nprog       =  emit arm64 pe64 kind 34 nprog

fn :: emit arm64 dll pe64 RNativeProg => [Int]
      emit arm64 dll pe64 nprog       =  emit arm64 pe64 kind 8226 nprog
