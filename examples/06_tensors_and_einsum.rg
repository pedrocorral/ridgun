-- ============================================================
-- 06_tensors_and_einsum.rg
-- Shaped Tensor(i, j), Einstein summation A_ij @ B_jk,
-- Hadamard broadcasting A_ij * B_j, chained indexing & block mut
-- ============================================================

fn :: matmul_einsum Tensor(i, j) Tensor(j, k) => Tensor(i, k)
matmul_einsum A B = A_ij @ B_jk

fn :: broadcast_row_scale Tensor(i, j) Tensor(j) => Tensor(i, j)
broadcast_row_scale A B = A_ij * B_j

fn :: hadamard_add Tensor(i, j) Tensor(i, j) => Tensor(i, j)
hadamard_add A B = A_ij + B_ij

fn :: tensor_demo => Int
tensor_demo =
  m = Tensor_GPU [[1, 2], [3, 4]]
  m[0, 1] = 99
  m[0][1] + m[1][0]

fn :: main => ()
main =
  echo "=== Ridgun 06: Tensors, Einsum & Broadcasting ==="
  a = Tensor [[1, 2], [3, 4]]
  b = Tensor [[5, 6], [7, 8]]
  prod = matmul_einsum a b
  echo "A_ij @ B_jk       =>" prod
  echo "A_ij + B_ij       =>" (hadamard_add a b)
  echo "tensor_demo (mut) =>" tensor_demo
