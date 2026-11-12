-- @tests TS-COMP-022
-- case: read bytes reads every byte of a file without a size: a pipe (which can be read only once) and a procfs file (libs report tensor-u8, 2026-11-09, item 6)
-- source: FR-COMP-022 §4
-- expect-output:
--   3000 97 122
--   0
--   procfs: True

fn :: repeat str String Int String => String
      repeat str s n acc =
        | n <= 0    = acc
        | otherwise = repeat str s (n - 1) (acc + s)

fn :: bool text Bool => String
      bool text True  =  "True"
      bool text False =  "False"

fn :: size of Tensor[U8] => Int
      size of (Tensor[U8 * n] _) = n

fn :: fd path Int => String
      fd path fd =  "/dev/fd/" + (int to str fd)

-- Writes body to a new pipe, closes its write end and reads the read end.
fn :: read back (Int, Int) String => Tensor[U8]
      read back (r, w) body =
        _ = sys write fd w body
        _ = sys close w
        read bytes (fd path r)

fn :: main => ()
      main =
        t = read back (sys pipe) ("a" + (repeat str "m" 2998 "") + "z")
        echo (size of t) (t_(0)) (t_(2999))
        echo (size of (read back (sys pipe) ""))
        echo ("procfs: " + (bool text ((size of (read bytes "/proc/self/status")) > 0)))
