-- ============================================================
-- Ridgun Samples: Tensor Operations
-- ============================================================
-- Mutable N-dimensional numeric type (Real by default, CPU)
-- Generalizes vectors, matrices, and higher-dimensional arrays

-- Creation
v = Tensor [1, 2, 3]                    -- 1D vector, shape: (3)
m = Tensor [[1, 2], [5, 3]]             -- 2D matrix, shape: (2, 2)
t = Tensor [[[1, 2], [3, 4]],           -- 3D tensor, shape: (2, 2, 2)
             [[5, 6], [7, 8]]]

-- Indexing (chained or comma-separated)
val = m[0][1]                            -- 2.0
val = m[0, 1]                            -- equivalent
row = m[0]                               -- Tensor [1, 2]

-- Mutation (in-place, PyTorch/NumPy style)
m[0, 1] = 5.0
m[0] = Tensor [10, 20]

-- Einstein notation: subscript indices for automatic contraction
-- Shared indices are summed, unique indices survive in the result
T = A_sdf * B_ndf                        -- T has shape (s, n)

-- Multi-tensor contraction in a single expression
R = A_abc * B_abc * C_abcd               -- R has shape (d)

-- Hadamard (element-wise) operations with subscript indices
H = A_ij * B_ij                          -- element-wise multiply, same shape
S = A_ij * B_j                           -- B broadcasts along i
C = A_ij + B_ij                          -- element-wise add
D = A_ij / B_j                           -- B broadcasts along i

-- GPU-resident tensors
g = Tensor_GPU [[1, 2], [3, 4]]
result = g_ij * g_jk                     -- GPU-accelerated matmul

-- Functions over tensors
fn :: dot_product [Real] [Real] => Real
      dot_product (a) (b)        =  a_i * b_i      -- Einstein sum over i

fn :: matrix_mul [[Real]] [[Real]] => [[Real]]
      matrix_mul (A) (B)                =  A_ij * B_jk  -- result shape (i, k)

fn :: scale Real [[Real]] => [[Real]]
      scale c (M)              =  c * M_ij          -- scalar broadcast
