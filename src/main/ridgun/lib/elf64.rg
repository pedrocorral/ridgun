-- ============================================================
-- src/main/ridgun/lib/elf64.rg
-- Pure-Ridgun Native IR & Static Linux ELF64 Binary Emitter
-- Supports x86_64 (EM_X86_64 = 62) & ARM64 (EM_AARCH64 = 183)
-- @implements FR-COMP-004
-- @implements FR-COMP-006
-- ============================================================

type RNativeInstr = NLabel Int | NJump Int | NJumpIfZero Int | NJumpIfNonZero Int | NLoadImmInt Int | NLoadImmRaw Int | NLoadRealLit Int Int | NLoadStrLit Int Int | NLoadAdt0 Int Int | NCloneSlot Int | NMoveSlot Int | NStoreSlot Int | NRebindSlot Int | NCmmDropSlot Int | NDropVal | NClearLocals Int Int | NMatchInt Int Int | NMatchReal Int Int Int | NMatchStr Int Int Int | NMatchBool Int Int | NMatchEmpty Int | NMatchNonEmpty Int | NMatchTuple Int Int | NMatchAdt Int Int Int Int | NListHead Int | NListTail Int | NTupleGet Int Int | NAdtField Int Int | NPackSeq Int | NAsBool | NNot | NOut | NBinOp Int Int | NAdtSet Int Int | NMakeList Int Int | NMakeTuple Int Int | NMakeTensor Int Int | NMakeAdt Int Int Int Int | NEcho Int Int | NStrInterp Int Int | NIndex Int Int Int | NIndexSet Int Int Int | NSeqSelect Int Int | NEinsum Int Int Int Int | NHadamard Int Int Int Int | NPushCtx Int Int | NPopCtx Int Int | NHasCtx Int Int | NGetCtx Int Int | NEnterRegion | NExitRegion Int | NHasShared Int Int | NGetShared Int Int | NInitShared Int Int | NStoreShared Int Int | NCallFn Int Int Int | NCallBuiltin Int Int Int | NCallIndirect1 Int Int | NCallIndirect2 Int Int | NTailCall Int Int | NReturn

type RNativeFn = NativeFn Int String Int Int [RNativeInstr]

type RNativeProg = NativeProg Int Int Int Int [RNativeFn] String

type RLabelEntry = LabelEntry Int Int

type RScanResult = ScanResult Int [RLabelEntry]

fn :: scan_offset RScanResult        => Int
      scan_offset (ScanResult off _) =  off

fn :: scan_labels RScanResult => [RLabelEntry]
      scan_labels (ScanResult _ lbls) = lbls

-- ── Little-Endian Integer Encoders ───────────────────────────

fn :: u16_le Int => [Int]
      u16_le v   =
        u = normalize_u32 v
        [u % 256, (u / 256) % 256]

fn :: normalize_u32 Int => Int
      normalize_u32 v
        | v < 0 = v + 4294967296
        | otherwise = v

fn :: u32_le Int => [Int]
      u32_le v   =
        u = normalize_u32 v
        [u % 256, (u / 256) % 256, (u / 65536) % 256, (u / 16777216) % 256]

fn :: i32_le Int => [Int]
      i32_le v   =  u32_le v

fn :: u64_le Int => [Int]
      u64_le v
        | v < 0 = (u32_le (v + 4294967296)) :: [255, 255, 255, 255]
        | otherwise = (u32_le (v % 4294967296)) :: (u32_le (v / 4294967296))

fn :: align_up Int Int   => Int
      align_up val align =
        rem = val % align
        align_up_rem val align rem

fn :: align_up_rem Int Int   Int => Int
      align_up_rem val _     0   =  val
      align_up_rem val align rem =  val + (align - rem)

-- ── Fast Label Lookup Table ──────────────────────────────────

fn :: lookup_label_offset [RLabelEntry] Int       => Int
      lookup_label_offset []            _         =  0
      lookup_label_offset ((LabelEntry id off):rest) target_id
        | id == target_id = off
        | otherwise = lookup_label_offset rest target_id

-- ── Fast Hex String & Raw String Byte Converters ─────────────

fn :: hex_nibble Int => Int
      hex_nibble c
        | c >= 48 AND c <= 57 = c - 48
        | c >= 97 AND c <= 102 = c - 87
        | c >= 65 AND c <= 70 = c - 55
        | otherwise = 0

fn :: hex_byte_at String Int => Int
      hex_byte_at s      pos =
        ((hex_nibble (str_char_at s pos)) * 16) + (hex_nibble (str_char_at s (pos + 1)))

fn :: hex_to_bytes_chunk String Int       Int [Int] => [Int]
      hex_to_bytes_chunk s      pos       end acc
        | pos >= end = acc
        | (pos + 8) <= end =
          b0 = hex_byte_at s pos
          b1 = hex_byte_at s (pos + 2)
          b2 = hex_byte_at s (pos + 4)
          b3 = hex_byte_at s (pos + 6)
      hex_to_bytes_chunk s      (pos + 8) end (acc :: [b0, b1, b2, b3])
        | otherwise =
          hex_to_bytes_chunk s (pos + 2) end (acc :: [hex_byte_at s pos])

fn :: hex_to_bytes_range String Int   Int => [Int]
      hex_to_bytes_range s      start end
        | start >= end = []
        | (end - start) <= 64 = hex_to_bytes_chunk s start end []
        | otherwise =
          half_pairs = ((end - start) / 4) * 2
          mid = start + half_pairs
          (hex_to_bytes_range s start mid) :: (hex_to_bytes_range s mid end)

fn :: hex_to_bytes String => [Int]
      hex_to_bytes s      =  hex_to_bytes_range s 0 (str_len s)

fn :: str_to_bytes_chunk String Int       Int [Int] => [Int]
      str_to_bytes_chunk s      pos       end acc
        | pos >= end = acc
        | (pos + 4) <= end =
          b0 = str_char_at s pos
          b1 = str_char_at s (pos + 1)
          b2 = str_char_at s (pos + 2)
          b3 = str_char_at s (pos + 3)
      str_to_bytes_chunk s      (pos + 4) end (acc :: [b0, b1, b2, b3])
        | otherwise =
          str_to_bytes_chunk s (pos + 1) end (acc :: [str_char_at s pos])

fn :: str_to_bytes_range String Int   Int => [Int]
      str_to_bytes_range s      start end
        | start >= end = []
        | (end - start) <= 32 = str_to_bytes_chunk s start end []
        | otherwise =
          mid = start + ((end - start) / 2)
          (str_to_bytes_range s start mid) :: (str_to_bytes_range s mid end)

fn :: str_to_bytes String => [Int]
      str_to_bytes s      =  str_to_bytes_range s 0 (str_len s)

fn :: zero_bytes_loop Int   [Int] => [Int]
      zero_bytes_loop count acc
        | count <= 0 = acc
        | count >= 16 = zero_bytes_loop (count - 16) (acc :: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        | otherwise = zero_bytes_loop (count - 1) (acc :: [0])

fn :: zero_bytes Int   => [Int]
      zero_bytes count =  zero_bytes_loop count []

fn :: byte_list_len_loop [Int]  Int => Int
      byte_list_len_loop []     acc =  acc
      byte_list_len_loop (_:xs) acc =  byte_list_len_loop xs (acc + 1)

fn :: byte_list_len [Int] => Int
      byte_list_len xs    =  byte_list_len_loop xs 0

-- ── ELF64 Header (64B) + Program Header (56B) + Page 0 ───────

fn :: build_elf64_ehdr_type Int    Int     Int     => [Int]
      build_elf64_ehdr_type e_type machine e_entry =
        e_ident = [127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        e_ident :: (u16_le e_type) :: (u16_le machine) :: (u32_le 1) :: (u64_le e_entry) :: (u64_le 64) :: (u64_le 0) :: (u32_le 0) :: (u16_le 64) :: (u16_le 56) :: (u16_le 1) :: (u16_le 64) :: (u16_le 0) :: (u16_le 0)

fn :: build_elf64_ehdr Int     Int     => [Int]
      build_elf64_ehdr machine e_entry =  build_elf64_ehdr_type 2 machine e_entry

fn :: build_elf64_phdr Int          => [Int]
      build_elf64_phdr total_filesz =
        total_memsz = total_filesz + 131072
        (u32_le 1) :: (u32_le 7) :: (u64_le 0) :: (u64_le 4194304) :: (u64_le 4194304) :: (u64_le total_filesz) :: (u64_le total_memsz) :: (u64_le 4096)

fn :: build_elf64_page0_type Int Int Int Int Int Int Int => [Int]
      build_elf64_page0_type e_type machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        ehdr = build_elf64_ehdr_type e_type machine 4198400
        phdr = build_elf64_phdr total_filesz
        pad8 = [0, 0, 0, 0, 0, 0, 0, 0]
        table_ptrs = (u64_le main_vaddr) :: (u64_le spawn_vaddr) :: (u64_le call2_vaddr) :: (u64_le binop_vaddr)
        bss_pad = zero_bytes 3936
        ehdr :: phdr :: pad8 :: table_ptrs :: bss_pad

fn :: build_elf64_page0 Int Int Int Int Int Int => [Int]
      build_elf64_page0 machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        build_elf64_page0_type 2 machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr

fn :: build_elf64_image_type Int Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build_elf64_image_type e_type machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        rodata_bytes = str_to_bytes rodata_str
        rodata_len = str_len rodata_str
        total_filesz = 4096 + rt_len + code_len + rodata_len
        page0 = build_elf64_page0_type e_type machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr
        page0 :: rt_bytes :: code_bytes :: rodata_bytes

fn :: build_elf64_image Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build_elf64_image machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        build_elf64_image_type 2 machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: build_elf64_shared_image Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build_elf64_shared_image machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        build_elf64_image_type 3 machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: write_elf64_executable String     [Int]     => Int
      write_elf64_executable output_bin elf_bytes =
        _ = write_bytes output_bin elf_bytes
        _ = sys_chmod output_bin 493
        0
