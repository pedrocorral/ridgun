-- @tests TS-COMP-022
-- case: a Tensor[U8] stores bytes: reads give 0..255, writes are in place, shape patterns, echo, tensor to list, equality, conversions with String, files, sha256 digest, crc32 range and sys call with a buffer
-- source: FR-COMP-022 §1-8
-- expect-output:
--   3421780262
--   3421780262
--   101
--   Hello
--   4157704578
--   500
--   Tensor(shape=[5], data=[72, 101, 108, 108, 111])
--   [72, 101, 108, 108, 111]
--   212
--   122
--   [22, 0, 0, 255]
--   True
--   False
--   [22, 5, 0, 255]
--   [1, 2, 3]
--   186
--   32
--   True
--   0
--   abc
--   4

fn :: sum bytes Tensor[U8] Int Int Int => Int
      sum bytes t i n acc
        | i >= n = acc
        | otherwise = sum bytes t (i + 1) n (acc + t_(i))

fn :: shape of Tensor[Byte] => Int
      shape of (Tensor[Byte * f * c] m) = f * 100 + c + m_(1, 2)
      shape of (Tensor[Byte * n] v) = n * 10 + v_(0)

fn :: fill frame Int => Tensor[U8]
      fill frame n =
        t = Tensor[U8 * n]
        t_(0) = 22
        t_(n - 1) = 255
        t

fn :: main => ()
      main =
        s = "123456789"
        echo (crc32 range s 0 9 0)
        a = crc32 range s 0 4 0
        echo (crc32 range s 4 9 a)
        t = tensor from str "hello"
        echo t_(1)
        t_(0) = 72
        echo (tensor to str t)
        echo (crc32 range t 0 5 0)
        echo (sum bytes t 0 5 0)
        echo t
        echo (tensor to list t)
        m = Tensor[Byte * 2 * 3] with 7
        m_(1, 2) = 9
        echo (shape of m)
        echo (shape of t)
        f = fill frame 4
        echo (tensor to list f)
        echo (f == (fill frame 4))
        f_(1) = 5
        echo (f == (fill frame 4))
        write bytes "/tmp/rg_case_bytes_u8.bin" f
        r = read bytes "/tmp/rg_case_bytes_u8.bin"
        echo (tensor to list r)
        write bytes "/tmp/rg_case_bytes_list.bin" [1, 2, 3]
        echo (tensor to list (read bytes "/tmp/rg_case_bytes_list.bin"))
        d = sha256 digest "abc"
        echo d_(0)
        echo (str len (sha256 raw t))
        echo ((sha256 raw (tensor from str "abc")) == (sha256 raw "abc"))
        ts = Tensor[U8 * 16]
        echo (sys call 228 1 ts 0)
        n = sys write from 1 (tensor from str "abc\n") 0 4
        echo n
