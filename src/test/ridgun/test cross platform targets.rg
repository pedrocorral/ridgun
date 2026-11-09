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
        assert true ((byte list len m_x86) > 8192)
        assert true ((byte list len m_arm) > 8192)

fn :: test pe64 x8664 and arm64 headers => ()
      test pe64 x8664 and arm64 headers =
        echo "--- 2. Testing Windows PE32+ (.exe & .dll) (x86_64-windows & arm64-windows) Emission ---"
        src = "fn :: current os => SysOs\n      current os =  sys os\n\nfn :: main => ()\n      main =  echo (current os)\n"
        nprog = lower sample prog src
        pe_x86 = emit x8664 pe64 nprog
        pe_arm = emit arm64 pe64 nprog
        pe_dll = emit x8664 dll pe64 nprog
        -- DOS 'MZ' magic [77, 90] at 0..2 and e_lfanew = 256 ([0, 1, 0, 0]) at 60..64
        assert equals (byte at idx pe_x86 0) 77
        assert equals (byte at idx pe_x86 1) 90
        assert equals (byte at idx pe_x86 60) 0
        assert equals (byte at idx pe_x86 61) 1
        -- 'PE\0\0' signature [80, 69, 0, 0] at 256..260
        assert equals (byte at idx pe_x86 256) 80
        assert equals (byte at idx pe_x86 257) 69
        assert equals (byte at idx pe_x86 258) 0
        assert equals (byte at idx pe_x86 259) 0
        -- COFF Machine: 0x8664 ([100, 134]) for x86_64-windows, 0xAA64 ([100, 170]) for arm64-windows
        assert equals (byte at idx pe_x86 260) 100
        assert equals (byte at idx pe_x86 261) 134
        assert equals (byte at idx pe_arm 260) 100
        assert equals (byte at idx pe_arm 261) 170
        -- Optional Header Magic: 0x020B ([11, 2] PE32+) at 280..282
        assert equals (byte at idx pe_x86 280) 11
        assert equals (byte at idx pe_x86 281) 2
        assert equals (byte at idx pe_dll 280) 11
        assert true ((byte list len pe_x86) > 8192)
        assert true ((byte list len pe_arm) > 8192)

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

fn :: main => ()
      main =
        echo "=== Ridgun Cross-Platform Target Codegen Test Suite (FR-COMP-015) ==="
        test macho64 x8664 and arm64 headers
        test pe64 x8664 and arm64 headers
        test llvm triples and disk target builds
        test arm64 immediates
        echo "=== All Cross-Platform Target Codegen Tests Passed! ==="
