-- ============================================================
-- src/test/ridgun/test cross platform targets.rg
-- Automated Verification for macOS Mach-O 64 & Windows PE32+
-- Cross-Platform Native Binary Emission (`FR-COMP-015`)
-- @implements FR-COMP-015
-- ============================================================
import test
import ast
import lexer
import parser
import typecheck
import compiler
import elf64
import macho64
import pe64
import x86_64
import llvm
import arm64

fn :: byte at idx [Int]  Int => Int
      byte at idx []     _   =  0 - 1
      byte at idx (b:bs) idx
        | idx <= 0  = b
        | otherwise = byte at idx bs (idx - 1)

fn :: lower sample prog String => RNativeProg
      lower sample prog src    =
        lower program to native (parse tokens (tokenize src src)) []

fn :: test macho64 x8664 and arm64 headers => ()
      test macho64 x8664 and arm64 headers =
        echo "--- 1. Testing macOS Mach-O 64 (x86_64-macos & arm64-macos) Emission ---"
        src = "fn :: current os => SysOs\n      current os =  sys os\n\nfn :: main => ()\n      main =  echo (current os)\n"
        nprog = lower sample prog src
        m_x86 = emit x8664 macho64 nprog
        m_arm = emit arm64 macho64 nprog
        m_dylib = emit x8664 dylib macho64 nprog
        -- MH_MAGIC_64 = 0xFEEDFACF -> [207, 250, 237, 254]
        assert equals (byte at idx m_x86 0) 207
        assert equals (byte at idx m_x86 1) 250
        assert equals (byte at idx m_x86 2) 237
        assert equals (byte at idx m_x86 3) 254
        -- CPU_TYPE_X86_64 = 0x01000007 -> [7, 0, 0, 1] at offset 4..8
        assert equals (byte at idx m_x86 4) 7
        assert equals (byte at idx m_x86 7) 1
        -- filetype: MH_EXECUTE = 2 at offset 12, MH_DYLIB = 6
        assert equals (byte at idx m_x86 12) 2
        assert equals (byte at idx m_dylib 12) 6
        -- CPU_TYPE_ARM64 = 0x0100000C -> [12, 0, 0, 1] at offset 4..8
        assert equals (byte at idx m_arm 0) 207
        assert equals (byte at idx m_arm 4) 12
        assert equals (byte at idx m_arm 7) 1
        assert true ((list len m_x86) > 8192)
        assert true ((list len m_arm) > 8192)

fn :: test pe64 x8664 and arm64 headers => ()
      test pe64 x8664 and arm64 headers =
        echo "--- 2. Testing Windows PE32+ (.exe & .dll) (x86_64-windows & arm64-windows) Emission ---"
        src = "fn :: current os => SysOs\n      current os =  sys os\n\nfn :: main => ()\n      main =  echo (current os)\n"
        nprog = lower sample prog src
        pe_x86 = emit x8664 pe64 nprog
        pe_arm = emit arm64 pe64 nprog
        pe_dll = emit x8664 dll pe64 nprog
        -- DOS 'MZ' magic [77, 90] at 0..2; e_lfanew = 1024 ([0, 4, 0, 0]) on x86_64 (ADR-0007), 256 on arm64
        assert equals (byte at idx pe_x86 0) 77
        assert equals (byte at idx pe_x86 1) 90
        assert equals (byte at idx pe_x86 60) 0
        assert equals (byte at idx pe_x86 61) 4
        assert equals (byte at idx pe_arm 61) 1
        -- 'PE\0\0' signature [80, 69, 0, 0] at 1024..1028
        assert equals (byte at idx pe_x86 1024) 80
        assert equals (byte at idx pe_x86 1025) 69
        assert equals (byte at idx pe_x86 1026) 0
        assert equals (byte at idx pe_x86 1027) 0
        -- COFF Machine: 0x8664 ([100, 134]) for x86_64-windows, 0xAA64 ([100, 170]) for arm64-windows
        assert equals (byte at idx pe_x86 1028) 100
        assert equals (byte at idx pe_x86 1029) 134
        assert equals (byte at idx pe_arm 260) 100
        assert equals (byte at idx pe_arm 261) 170
        -- Three sections (.text, .idata, .rgsys); relocations stripped (0x23)
        assert equals (byte at idx pe_x86 1030) 3
        assert equals (byte at idx pe_x86 1046) 35
        -- Optional Header Magic: 0x020B ([11, 2] PE32+) at 1048..1050
        assert equals (byte at idx pe_x86 1048) 11
        assert equals (byte at idx pe_x86 1049) 2
        assert equals (byte at idx pe_dll 1048) 11
        -- Stack committed in full: SizeOfStackCommit = 0x800000 at 1128
        assert equals (byte at idx pe_x86 1130) 128
        -- The runtime's page-0 variables (0x158..0x178, 0xF00..0x1000) are zero
        assert equals (byte at idx pe_x86 368) 0
        assert equals (byte at idx pe_x86 3840) 0
        assert true ((list len pe_x86) > 8192)
        assert true ((list len pe_arm) > 8192)

fn :: test llvm triples and disk target builds => ()
      test llvm triples and disk target builds =
        echo "--- 3. Testing LLVM Target Triples & Cross-Platform Disk Emission ---"
        assert equals (llvm target triple "x86_64-macos") "x86_64-apple-macosx11.0.0"
        assert equals (llvm target triple "arm64-macos") "arm64-apple-macosx11.0.0"
        assert equals (llvm target triple "x86_64-windows") "x86_64-pc-windows-msvc"
        assert equals (llvm target triple "arm64-windows") "aarch64-pc-windows-msvc"
        tmp_rg = "/tmp/__rg_test_xplat.rg"
        out_macos = "/tmp/__rg_test_xplat_macos"
        out_win = "/tmp/__rg_test_xplat_win.exe"
        write file tmp_rg "fn :: main => ()\n      main =  echo \"hello cross-platform\"\n"
        st_mac = build native target executable tmp_rg out_macos "arm64-macos"
        st_win = build native target executable tmp_rg out_win "x86_64-windows"
        assert equals st_mac 0
        assert equals st_win 0
        mac_bytes = read bytes out_macos
        win_bytes = read bytes out_win
        assert equals mac_bytes_(0) 207
        assert equals mac_bytes_(1) 250
        assert equals win_bytes_(0) 77
        assert equals win_bytes_(1) 90
        shell exec ("rm -f \"" + tmp_rg + "\" \"" + out_macos + "\" \"" + out_win + "\"") -> ()

-- MOVZ/MOVK sequence for rd 5: halfword k of the two's complement of the value,
-- MOVZ = 0xD2800000, MOVK = 0xF2800000, hw << 21, imm16 << 5 (Arm ARM C6.2).
fn :: test arm64 immediates => ()
      test arm64 immediates =
        echo "--- 4. Testing ARM64 64-bit immediate loads (MOVZ/MOVK) ---"
        assert equals (arm64 mov imm64 5 0) [5, 0, 128, 210, 5, 0, 160, 242, 5, 0, 192, 242, 5, 0, 224, 242]
        assert equals (arm64 mov imm64 5 1) [37, 0, 128, 210, 5, 0, 160, 242, 5, 0, 192, 242, 5, 0, 224, 242]
        assert equals (arm64 mov imm64 5 (0 - 1)) [229, 255, 159, 210, 229, 255, 191, 242, 229, 255, 223, 242, 229, 255, 255, 242]
        assert equals (arm64 mov imm64 5 (0 - 65537)) [229, 255, 159, 210, 197, 255, 191, 242, 229, 255, 223, 242, 229, 255, 255, 242]
        assert equals (arm64 mov imm64 5 (0 - 4294967297)) [229, 255, 159, 210, 229, 255, 191, 242, 197, 255, 223, 242, 229, 255, 255, 242]
        assert equals (arm64 mov imm64 5 4294967296) [5, 0, 128, 210, 5, 0, 160, 242, 37, 0, 192, 242, 5, 0, 224, 242]
        assert equals (arm64 mov imm64 5 9223372036854775807) [229, 255, 159, 210, 229, 255, 191, 242, 229, 255, 223, 242, 229, 255, 239, 242]
        assert equals (arm64 mov imm64 5 ((0 - 9223372036854775807) - 1)) [5, 0, 128, 210, 5, 0, 160, 242, 5, 0, 192, 242, 5, 0, 240, 242]

-- Number of 15, 5 byte pairs (`syscall`).
fn :: count syscall pairs [Int] Int => Int
      count syscall pairs []     n =  n
      count syscall pairs (b:bs) n
        | b == 15 and (list nth or bs 0 0) == 5 = count syscall pairs bs (n + 1)
        | otherwise = count syscall pairs bs n

fn :: win sample instrs => [RNativeInstr]
      win sample instrs =  [NSortBy 1 0, NListGet 1 2, NIndex 1 2 (0 - 1), NIndex 1 2 (0 - 2), NIndex 1 2 2, NIndexSet 1 2 1, NIndexSet 1 2 2, NIndexSet 1 2 3, NCallBuiltin 86 1 0, NCallBuiltin 87 1 1, NCallBuiltin 96 1 0, NCallBuiltin 97 1 1, NCallBuiltin 98 1 2, NCallBuiltin 99 1 1, NCallBuiltin 1 1 0, NCallBuiltin 32 1 0, NCallBuiltin 32 1 1, NCallBuiltin 33 1 1, NCallBuiltin 50 1 2, NCallBuiltin 57 1 1, NCallBuiltin 90 1 1, NListSet 1 2]

fn :: check win sites [RNativeInstr] => ()
      check win sites []         =  ()
      check win sites (ins:rest) =
        bytes = x8664 encode instr ins 4300000 4300000 16 4400000 [] []
        sites = win sys sites ins
        assert equals (list len bytes) (x8664 instr size ins)
        assert equals (count syscall pairs bytes 0) (list len sites)
        assert equals (count syscall pairs (patch ud2 bytes sites) 0) 0
        check win sites rest

-- FR-COMP-015 / ADR-0007: every `syscall` of a Windows image becomes `ud2`.
fn :: test windows syscall sites => ()
      test windows syscall sites =
        echo "--- 5. Testing Windows system layer: syscall sites become ud2 ---"
        rt = build x8664 rt kernel
        assert equals (list len (win rt sites)) 130
        assert equals (count syscall pairs rt 0) 132
        -- the two pairs left are inside `mov edi, 0x50F00` (not instructions)
        assert equals (count syscall pairs (patch ud2 rt (win rt sites)) 0) 2
        check win sites (win sample instrs)
        assert true ((win iat size) <= 640)
        assert equals (list len (win layer 4096)) ((list len (win layer head)) + 640 + (list len (win layer body)))

fn :: adt0 offset RNativeInstr => Int
      adt0 offset (NLoadAdt0 off _) =  off
      adt0 offset _                 =  0 - 100

-- `sys os` is the marker -2; only it is specialized. A `Linux` written in the
-- program (rodata offset 5) stays `Linux` in Windows and macOS images
-- (Solstice report sysos-literal-rewritten, 2026-11-12).
fn :: test sys os specialization => ()
      test sys os specialization =
        echo "--- 6. Testing sys os: only its marker is specialized ---"
        assert equals (adt0 offset (specialize windows instr (NLoadAdt0 (0 - 2) 0))) 15
        assert equals (adt0 offset (specialize macos instr (NLoadAdt0 (0 - 2) 0))) 10
        assert equals (adt0 offset (specialize windows instr (NLoadAdt0 5 5))) 5
        assert equals (adt0 offset (specialize macos instr (NLoadAdt0 5 5))) 5
        assert equals (adt0 offset (specialize windows instr (NLoadAdt0 10 5))) 10

fn :: main => ()
      main =
        echo "=== Ridgun Cross-Platform Target Codegen Test Suite (FR-COMP-015) ==="
        test macho64 x8664 and arm64 headers
        test pe64 x8664 and arm64 headers
        test llvm triples and disk target builds
        test arm64 immediates
        test windows syscall sites
        test sys os specialization
        echo "=== All Cross-Platform Target Codegen Tests Passed! ==="
