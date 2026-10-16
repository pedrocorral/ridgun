-- ============================================================
-- 10_bare_metal_systems.rg
-- Systems types (U8..U64), @packed, @repr(C),
-- hardware :: MMIO blocks, and with region limit quotas
-- ============================================================

@packed
@repr(C)
type GpioConfig = mode U8, speed U8, pull U16, mask U32

hardware :: GpioPortA @ 0x4002_0000
  MODER : U32 @ 0x00
  IDR   : U32 @ 0x10
  ODR   : U32 @ 0x14

fn :: get_odr_address => Int
get_odr_address = ODR

fn :: alloc_within_quota => Result
alloc_within_quota =
  with region limit 16_KB do
    xs = [10, 20, 30]
    xs

fn :: alloc_exceeding_quota => Result
alloc_exceeding_quota =
  with region limit 16 do
    xs = [1, 2, 3, 4, 5, 6]
    xs

fn :: main => ()
main =
  echo "=== Ridgun 10: Bare-Metal Systems Profile ==="
  echo "GPIO Port A ODR MMIO address =>" get_odr_address
  echo "alloc_within_quota (16_KB)   =>" alloc_within_quota
  echo "alloc_exceeding_quota (16 B) =>" alloc_exceeding_quota
