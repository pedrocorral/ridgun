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

fn :: scan offset RScanResult        => Int
      scan offset (ScanResult off _) =  off

fn :: scan labels RScanResult => [RLabelEntry]
      scan labels (ScanResult _ lbls) = lbls

-- ── Little-Endian Integer Encoders ───────────────────────────

fn :: u16 le Int => [Int]
      u16 le v   =
        u = normalize u32 v
        [u % 256, (u / 256) % 256]

fn :: normalize u32 Int => Int
      normalize u32 v
        | v < 0 = v + 4294967296
        | otherwise = v

fn :: u32 le Int => [Int]
      u32 le v   =
        u = normalize u32 v
        [u % 256, (u / 256) % 256, (u / 65536) % 256, (u / 16777216) % 256]

fn :: i32 le Int => [Int]
      i32 le v   =  u32 le v

fn :: u64 le Int => [Int]
      u64 le v
        | v < 0 = (u32 le (v + 4294967296)) :: [255, 255, 255, 255]
        | otherwise = (u32 le (v % 4294967296)) :: (u32 le (v / 4294967296))

fn :: align up Int Int   => Int
      align up val align =
        rem = val % align
        align up rem val align rem

fn :: align up rem Int Int Int => Int
      align up rem val _ 0 = val
      align up rem val align rem = val + (align - rem)

-- ── Fast Label Lookup Table ──────────────────────────────────

fn :: lookup label offset [RLabelEntry] Int       => Int
      lookup label offset []            _         =  0
      lookup label offset ((LabelEntry id off):rest) target_id
        | id == target_id = off
        | otherwise = lookup label offset rest target_id

-- ── Raw String Byte Converters ───────────────────────────────

fn :: str to bytes chunk String Int Int [Int] => [Int]
      str to bytes chunk s pos end acc
        | pos >= end = acc
        | (pos + 4) <= end =
          b0 = str char at s pos
          b1 = str char at s (pos + 1)
          b2 = str char at s (pos + 2)
          b3 = str char at s (pos + 3)
      str to bytes chunk s (pos + 4) end (acc :: [b0, b1, b2, b3])
        | otherwise =
          str to bytes chunk s (pos + 1) end (acc :: [str char at s pos])

fn :: str to bytes range String Int Int => [Int]
      str to bytes range s start end
        | start >= end = []
        | (end - start) <= 32 = str to bytes chunk s start end []
        | otherwise =
          mid = start + ((end - start) / 2)
          (str to bytes range s start mid) :: (str to bytes range s mid end)

fn :: str to bytes String => [Int]
      str to bytes s      =  str to bytes range s 0 (str len s)

fn :: zero bytes loop Int   [Int] => [Int]
      zero bytes loop count acc
        | count <= 0 = acc
        | count >= 16 = zero bytes loop (count - 16) (acc :: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        | otherwise = zero bytes loop (count - 1) (acc :: [0])

fn :: zero bytes Int   => [Int]
      zero bytes count =  zero bytes loop count []

fn :: byte list len loop [Int] Int => Int
      byte list len loop [] acc = acc
      byte list len loop (_:xs) acc = byte list len loop xs (acc + 1)

fn :: byte list len [Int] => Int
      byte list len xs    =  byte list len loop xs 0

-- ── ELF64 Header (64B) + Program Header (56B) + Page 0 ───────

fn :: build elf64 ehdr kind Int Int Int => [Int]
      build elf64 ehdr kind e_type machine e_entry =
        e_ident = [127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        e_ident :: (u16 le e_type) :: (u16 le machine) :: (u32 le 1) :: (u64 le e_entry) :: (u64 le 64) :: (u64 le 0) :: (u32 le 0) :: (u16 le 64) :: (u16 le 56) :: (u16 le 1) :: (u16 le 64) :: (u16 le 0) :: (u16 le 0)

fn :: build elf64 ehdr Int     Int     => [Int]
      build elf64 ehdr machine e_entry =  build elf64 ehdr kind 2 machine e_entry

fn :: build elf64 phdr Int          => [Int]
      build elf64 phdr total_filesz =
        total_memsz = total_filesz + 131072
        (u32 le 1) :: (u32 le 7) :: (u64 le 0) :: (u64 le 4194304) :: (u64 le 4194304) :: (u64 le total_filesz) :: (u64 le total_memsz) :: (u64 le 4096)

fn :: build elf64 page0 kind Int Int Int Int Int Int Int => [Int]
      build elf64 page0 kind e_type machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        ehdr = build elf64 ehdr kind e_type machine 4198400
        phdr = build elf64 phdr total_filesz
        pad8 = [0, 0, 0, 0, 0, 0, 0, 0]
        table_ptrs = (u64 le main_vaddr) :: (u64 le spawn_vaddr) :: (u64 le call2_vaddr) :: (u64 le binop_vaddr)
        bss_pad = zero bytes 3936
        ehdr :: phdr :: pad8 :: table_ptrs :: bss_pad

fn :: build elf64 page0 Int Int Int Int Int Int => [Int]
      build elf64 page0 machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr =
        build elf64 page0 kind 2 machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr

fn :: build elf64 image kind Int Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build elf64 image kind e_type machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        rodata_bytes = str to bytes rodata_str
        rodata_len = str len rodata_str
        total_filesz = 4096 + rt_len + code_len + rodata_len
        page0 = build elf64 page0 kind e_type machine total_filesz main_vaddr spawn_vaddr call2_vaddr binop_vaddr
        page0 :: rt_bytes :: code_bytes :: rodata_bytes

fn :: build elf64 image Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build elf64 image machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        build elf64 image kind 2 machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: build elf64 shared image Int Int Int Int Int [Int] Int [Int] Int String => [Int]
      build elf64 shared image machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str =
        build elf64 image kind 3 machine main_vaddr spawn_vaddr call2_vaddr binop_vaddr rt_bytes rt_len code_bytes code_len rodata_str

fn :: write elf64 executable String     [Int]     => Int
      write elf64 executable output_bin elf_bytes =
        _ = write bytes output_bin elf_bytes
        _ = sys chmod output_bin 493
        0
