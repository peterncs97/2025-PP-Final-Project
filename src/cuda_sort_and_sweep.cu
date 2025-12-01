#include <algorithm>
#include <vector>
#include <cuda_runtime.h>
#include <thrust/sort.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/sequence.h>
#include <thrust/remove.h>
#include <thrust/unique.h>

#include "cuda_sort_and_sweep.cuh"

// Point structure for sweep line algorithm
struct Point {
    float value;
    uint32_t index;
    bool is_start;
};

// Device-compatible AABB structure
struct DeviceAABB {
    float min_x;
    float min_y;
    float max_x;
    float max_y;
};

// Comparator for sorting points
struct PointComparator {
    __host__ __device__
    bool operator()(const Point& a, const Point& b) const {
        if (a.value == b.value) {
            return a.is_start && !b.is_start;
        }
        return a.value < b.value;
    }
};

// Kernel to find overlapping pairs
// Each thread handles one start point and checks against all active boxes
__global__ void find_overlaps_kernel(
    const Point* points,
    const DeviceAABB* boxes,
    const uint32_t num_points,
    uint32_t* pair_first,
    uint32_t* pair_second,
    uint32_t* pair_count,
    const uint32_t max_pairs)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= num_points) return;

    const Point& p = points[idx];
    if (!p.is_start) return;

    const DeviceAABB& box_b = boxes[p.index];

    // Look backwards to find all active boxes (boxes whose start is before this point
    // and end is after this point's x value)
    for (int j = idx - 1; j >= 0; --j) {
        const Point& prev = points[j];
        
        // If we hit an end point, the box might still be active
        // If we hit a start point, check if its end point is after current x
        if (prev.is_start) {
            const DeviceAABB& box_a = boxes[prev.index];
            
            // Check if box_a is still active (its max_x >= current x)
            if (box_a.max_x >= p.value) {
                // Check y-axis overlap
                if (box_a.min_y <= box_b.max_y && box_a.max_y >= box_b.min_y) {
                    // Add pair (smaller index first)
                    uint32_t a = prev.index;
                    uint32_t b = p.index;
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
}

// Alternative: Simpler kernel that checks all pairs in parallel
__global__ void find_all_overlaps_kernel(
    const DeviceAABB* boxes,
    const uint32_t N,
    uint32_t* pair_first,
    uint32_t* pair_second,
    uint32_t* pair_count,
    const uint32_t max_pairs)
{
    // Each thread handles one pair (i, j) where i < j
    uint64_t idx = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x;
    
    // Convert linear index to pair (i, j)
    // Total pairs = N*(N-1)/2
    // idx = i*N - i*(i+1)/2 + (j - i - 1)
    // We use a simpler iteration scheme
    
    uint64_t total_pairs = (uint64_t)N * (N - 1) / 2;
    if (idx >= total_pairs) return;
    
    // Decode pair index
    // For pair (i, j) where i < j:
    // index = sum_{k=0}^{i-1}(N-1-k) + (j - i - 1)
    //       = i*N - i*(i+1)/2 + (j - i - 1)
    uint32_t i = 0;
    uint64_t cumsum = 0;
    while (cumsum + (N - 1 - i) <= idx) {
        cumsum += (N - 1 - i);
        i++;
    }
    uint32_t j = i + 1 + (idx - cumsum);
    
    const DeviceAABB& a = boxes[i];
    const DeviceAABB& b = boxes[j];
    
    // Check overlap on both axes
    bool overlap_x = (a.min_x <= b.max_x) && (a.max_x >= b.min_x);
    bool overlap_y = (a.min_y <= b.max_y) && (a.max_y >= b.min_y);
    
    if (overlap_x && overlap_y) {
        uint32_t pos = atomicAdd(pair_count, 1);
        if (pos < max_pairs) {
            pair_first[pos] = i;
            pair_second[pos] = j;
        }
    }
}

std::vector<std::pair<uint32_t, uint32_t>> cuda_sort_and_sweep(
    const uint32_t N,
    const std::vector<aabb::AABB>& boxes)
{
    if (N == 0) {
        return {};
    }

    // Convert to device-compatible format
    std::vector<DeviceAABB> h_boxes(N);
    for (uint32_t i = 0; i < N; ++i) {
        h_boxes[i].min_x = boxes[i].min_x;
        h_boxes[i].min_y = boxes[i].min_y;
        h_boxes[i].max_x = boxes[i].max_x;
        h_boxes[i].max_y = boxes[i].max_y;
    }

    // Allocate device memory
    DeviceAABB* d_boxes;
    cudaMalloc(&d_boxes, N * sizeof(DeviceAABB));
    cudaMemcpy(d_boxes, h_boxes.data(), N * sizeof(DeviceAABB), cudaMemcpyHostToDevice);

    // Estimate max pairs (worst case is N*(N-1)/2, but we'll use a reasonable limit)
    uint64_t total_possible = (uint64_t)N * (N - 1) / 2;
    uint32_t max_pairs = (uint32_t)std::min(total_possible, (uint64_t)100000000);  // 100M max

    uint32_t* d_pair_first;
    uint32_t* d_pair_second;
    uint32_t* d_pair_count;
    
    cudaMalloc(&d_pair_first, max_pairs * sizeof(uint32_t));
    cudaMalloc(&d_pair_second, max_pairs * sizeof(uint32_t));
    cudaMalloc(&d_pair_count, sizeof(uint32_t));
    cudaMemset(d_pair_count, 0, sizeof(uint32_t));

    // Launch kernel
    int block_size = 256;
    uint64_t num_checks = total_possible;
    int num_blocks = (num_checks + block_size - 1) / block_size;
    
    find_all_overlaps_kernel<<<num_blocks, block_size>>>(
        d_boxes, N, d_pair_first, d_pair_second, d_pair_count, max_pairs
    );
    
    cudaDeviceSynchronize();

    // Get pair count
    uint32_t h_pair_count;
    cudaMemcpy(&h_pair_count, d_pair_count, sizeof(uint32_t), cudaMemcpyDeviceToHost);
    
    if (h_pair_count > max_pairs) {
        h_pair_count = max_pairs;  // Truncate if overflow
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
