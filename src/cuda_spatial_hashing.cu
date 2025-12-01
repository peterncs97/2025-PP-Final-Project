#include <algorithm>
#include <vector>
#include <cmath>
#include <cuda_runtime.h>
#include <thrust/sort.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/unique.h>
#include <thrust/execution_policy.h>

#include "cuda_spatial_hashing.cuh"

// Device-compatible AABB structure
struct DeviceAABB {
    int id;
    float min_x;
    float min_y;
    float max_x;
    float max_y;
};

// Cell-box pair for spatial hashing
struct CellBoxPair {
    int64_t cell_hash;  // Combined hash of cell coordinates
    uint32_t box_id;
};

// Hash function for cell coordinates
__host__ __device__
int64_t compute_cell_hash(int cx, int cy) {
    // Use large primes to create a unique hash
    const int64_t P1 = 73856093LL;
    const int64_t P2 = 19349663LL;
    return (int64_t)cx * P1 ^ (int64_t)cy * P2;
}

// Comparator for sorting cell-box pairs
struct CellBoxComparator {
    __host__ __device__
    bool operator()(const CellBoxPair& a, const CellBoxPair& b) const {
        if (a.cell_hash != b.cell_hash) {
            return a.cell_hash < b.cell_hash;
        }
        return a.box_id < b.box_id;
    }
};

// AABB intersection test
__device__
bool intersects_device(const DeviceAABB& a, const DeviceAABB& b) {
    return !(a.max_x < b.min_x ||
             b.max_x < a.min_x ||
             a.max_y < b.min_y ||
             b.max_y < a.min_y);
}

// Kernel to assign boxes to cells
// Each box is assigned to the cell containing its center
__global__ void assign_boxes_to_cells_kernel(
    const DeviceAABB* boxes,
    const uint32_t N,
    const int cell_size,
    CellBoxPair* cell_box_pairs)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;

    const DeviceAABB& box = boxes[idx];
    
    // Compute cell for box center
    float cx = (box.min_x + box.max_x) * 0.5f;
    float cy = (box.min_y + box.max_y) * 0.5f;
    
    int cell_x = (int)floorf(cx / cell_size);
    int cell_y = (int)floorf(cy / cell_size);
    
    cell_box_pairs[idx].cell_hash = compute_cell_hash(cell_x, cell_y);
    cell_box_pairs[idx].box_id = idx;
}

// Kernel to find cell boundaries in the sorted array
__global__ void find_cell_boundaries_kernel(
    const CellBoxPair* sorted_pairs,
    const uint32_t N,
    uint32_t* cell_starts,
    uint32_t* cell_ends)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;

    int64_t my_hash = sorted_pairs[idx].cell_hash;
    
    // Check if this is the start of a new cell
    if (idx == 0 || sorted_pairs[idx - 1].cell_hash != my_hash) {
        cell_starts[idx] = idx;
    } else {
        cell_starts[idx] = 0xFFFFFFFF;  // Invalid marker
    }
    
    // Check if this is the end of a cell
    if (idx == N - 1 || sorted_pairs[idx + 1].cell_hash != my_hash) {
        cell_ends[idx] = idx + 1;
    } else {
        cell_ends[idx] = 0xFFFFFFFF;  // Invalid marker
    }
}

// Kernel to check collisions within cells and with neighboring cells
__global__ void check_collisions_kernel(
    const DeviceAABB* boxes,
    const CellBoxPair* sorted_pairs,
    const uint32_t N,
    const uint32_t* cell_starts,
    const int cell_size,
    uint32_t* pair_first,
    uint32_t* pair_second,
    uint32_t* pair_count,
    const uint32_t max_pairs)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;
    
    // Only process if this is the start of a cell
    if (cell_starts[idx] == 0xFFFFFFFF) return;
    
    uint32_t box_idx = sorted_pairs[idx].box_id;
    const DeviceAABB& box_a = boxes[box_idx];
    
    // Find all boxes in the same cell (starting from idx+1 to avoid duplicates)
    uint32_t j = idx + 1;
    while (j < N && sorted_pairs[j].cell_hash == sorted_pairs[idx].cell_hash) {
        uint32_t other_idx = sorted_pairs[j].box_id;
        const DeviceAABB& box_b = boxes[other_idx];
        
        if (intersects_device(box_a, box_b)) {
            uint32_t a = box_a.id;
            uint32_t b = box_b.id;
            if (a > b) {
                uint32_t tmp = a;
                a = b;
                b = tmp;
            }
            
            uint32_t pos = atomicAdd(pair_count, 1);
            if (pos < max_pairs) {
                pair_first[pos] = a;
                pair_second[pos] = b;
            }
        }
        j++;
    }
}

// Simple brute-force collision kernel with spatial hashing optimization
// Each thread checks one box against all boxes in neighboring cells
__global__ void spatial_hash_collision_kernel(
    const DeviceAABB* boxes,
    const uint32_t N,
    const int cell_size,
    uint32_t* pair_first,
    uint32_t* pair_second,
    uint32_t* pair_count,
    const uint32_t max_pairs)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;

    const DeviceAABB& box_a = boxes[idx];
    
    // Compute cell for this box
    float cx_a = (box_a.min_x + box_a.max_x) * 0.5f;
    float cy_a = (box_a.min_y + box_a.max_y) * 0.5f;
    int cell_x = (int)floorf(cx_a / cell_size);
    int cell_y = (int)floorf(cy_a / cell_size);

    // Check against all other boxes
    // Only check boxes with higher index to avoid duplicates
    for (uint32_t j = idx + 1; j < N; j++) {
        const DeviceAABB& box_b = boxes[j];
        
        // Compute cell for box_b
        float cx_b = (box_b.min_x + box_b.max_x) * 0.5f;
        float cy_b = (box_b.min_y + box_b.max_y) * 0.5f;
        int cell_x_b = (int)floorf(cx_b / cell_size);
        int cell_y_b = (int)floorf(cy_b / cell_size);
        
        // Only check if in same or neighboring cell (3x3 neighborhood)
        int dx = abs(cell_x - cell_x_b);
        int dy = abs(cell_y - cell_y_b);
        
        if (dx <= 1 && dy <= 1) {
            if (intersects_device(box_a, box_b)) {
                uint32_t a = box_a.id;
                uint32_t b = box_b.id;
                if (a > b) {
                    uint32_t tmp = a;
                    a = b;
                    b = tmp;
                }
                
                uint32_t pos = atomicAdd(pair_count, 1);
                if (pos < max_pairs) {
                    pair_first[pos] = a;
                    pair_second[pos] = b;
                }
            }
        }
    }
}

// Compute cell size from boxes (host function)
int compute_cell_size_host(const std::vector<aabb::AABB>& boxes) {
    float max_dim = 0.0f;
    for (const auto& b : boxes) {
        max_dim = std::max(max_dim, b.max_x - b.min_x);
        max_dim = std::max(max_dim, b.max_y - b.min_y);
    }
    int L = static_cast<int>(std::ceil(max_dim));
    if (L <= 0) L = 1;
    return L;
}

std::vector<std::pair<uint32_t, uint32_t>> cuda_spatial_hashing(
    const uint32_t N,
    const std::vector<aabb::AABB>& boxes)
{
    if (N == 0) {
        return {};
    }

    // Compute cell size
    int cell_size = compute_cell_size_host(boxes);

    // Convert to device-compatible format
    std::vector<DeviceAABB> h_boxes(N);
    for (uint32_t i = 0; i < N; ++i) {
        h_boxes[i].id = boxes[i].id;
        h_boxes[i].min_x = boxes[i].min_x;
        h_boxes[i].min_y = boxes[i].min_y;
        h_boxes[i].max_x = boxes[i].max_x;
        h_boxes[i].max_y = boxes[i].max_y;
    }

    // Allocate device memory for boxes
    DeviceAABB* d_boxes;
    cudaMalloc(&d_boxes, N * sizeof(DeviceAABB));
    cudaMemcpy(d_boxes, h_boxes.data(), N * sizeof(DeviceAABB), cudaMemcpyHostToDevice);

    // Estimate max pairs
    uint64_t total_possible = (uint64_t)N * (N - 1) / 2;
    uint32_t max_pairs = (uint32_t)std::min(total_possible, (uint64_t)100000000);

    uint32_t* d_pair_first;
    uint32_t* d_pair_second;
    uint32_t* d_pair_count;
    
    cudaMalloc(&d_pair_first, max_pairs * sizeof(uint32_t));
    cudaMalloc(&d_pair_second, max_pairs * sizeof(uint32_t));
    cudaMalloc(&d_pair_count, sizeof(uint32_t));
    cudaMemset(d_pair_count, 0, sizeof(uint32_t));

    // Launch spatial hashing collision kernel
    int block_size = 256;
    int num_blocks = (N + block_size - 1) / block_size;
    
    spatial_hash_collision_kernel<<<num_blocks, block_size>>>(
        d_boxes, N, cell_size,
        d_pair_first, d_pair_second, d_pair_count, max_pairs
    );
    
    cudaDeviceSynchronize();

    // Get pair count
    uint32_t h_pair_count;
    cudaMemcpy(&h_pair_count, d_pair_count, sizeof(uint32_t), cudaMemcpyDeviceToHost);
    
    if (h_pair_count > max_pairs) {
        h_pair_count = max_pairs;
    }

    // Copy results back
    std::vector<uint32_t> h_pair_first(h_pair_count);
    std::vector<uint32_t> h_pair_second(h_pair_count);
    
    if (h_pair_count > 0) {
        cudaMemcpy(h_pair_first.data(), d_pair_first, h_pair_count * sizeof(uint32_t), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_pair_second.data(), d_pair_second, h_pair_count * sizeof(uint32_t), cudaMemcpyDeviceToHost);
    }

    // Build result pairs
    std::vector<std::pair<uint32_t, uint32_t>> pairs(h_pair_count);
    for (uint32_t i = 0; i < h_pair_count; ++i) {
        pairs[i] = {h_pair_first[i], h_pair_second[i]};
    }

    // Sort and deduplicate
    std::sort(pairs.begin(), pairs.end());
    pairs.erase(std::unique(pairs.begin(), pairs.end()), pairs.end());

    // Free device memory
    cudaFree(d_boxes);
    cudaFree(d_pair_first);
    cudaFree(d_pair_second);
    cudaFree(d_pair_count);

    return pairs;
}
