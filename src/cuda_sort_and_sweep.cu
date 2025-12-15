#include <algorithm>
#include <vector>
#include <cuda_runtime.h>
#include <thrust/sort.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/sequence.h>
#include <thrust/remove.h>
#include <thrust/unique.h>
#include <chrono>

#include "cuda_sort_and_sweep.cuh"

// Endpoint structure for sort-and-sweep algorithm
// Each AABB generates two endpoints: start (min_x) and end (max_x)
struct Endpoint {
    float value;       // The x-coordinate (min_x for start, max_x for end)
    uint32_t box_idx;  // Index of the AABB this endpoint belongs to
    uint32_t is_start; // 1 for start point, 0 for end point (use uint32_t for sorting)
};

// Device-compatible AABB structure
struct DeviceAABB {
    float min_x;
    float min_y;
    float max_x;
    float max_y;
};

// Comparator for sorting endpoints
// Sort by value ascending; if equal, start points come before end points
struct EndpointComparator {
    __host__ __device__
    bool operator()(const Endpoint& a, const Endpoint& b) const {
        if (a.value != b.value) {
            return a.value < b.value;
        }
        // If values are equal, start points (is_start=1) come before end points (is_start=0)
        return a.is_start > b.is_start;
    }
};

// Step 1 Kernel: Create endpoints from AABBs
// Each thread handles one AABB and writes its start and end points
__global__ void create_endpoints_kernel(
    const DeviceAABB* boxes,
    const uint32_t N,
    Endpoint* endpoints)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;

    const DeviceAABB& box = boxes[idx];
    
    // Write start point at index 2*idx
    endpoints[2 * idx].value = box.min_x;
    endpoints[2 * idx].box_idx = idx;
    endpoints[2 * idx].is_start = 1;
    
    // Write end point at index 2*idx + 1
    endpoints[2 * idx + 1].value = box.max_x;
    endpoints[2 * idx + 1].box_idx = idx;
    endpoints[2 * idx + 1].is_start = 0;
}

// Step 3 Kernel: Find overlapping pairs
// Each thread handles one endpoint in the sorted array
// If it's an end point, exit immediately
// If it's a start point, walk forward and test overlaps until hitting the corresponding end point
__global__ void sweep_find_overlaps_kernel(
    const Endpoint* endpoints,
    const DeviceAABB* boxes,
    const uint32_t num_endpoints,
    uint32_t* pair_first,
    uint32_t* pair_second,
    uint32_t* pair_count,
    const uint32_t max_pairs)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= num_endpoints) return;

    const Endpoint& ep = endpoints[idx];
    
    // If this is an end point, exit immediately
    if (ep.is_start == 0) return;
    
    // This is a start point - get our box
    const uint32_t my_box_idx = ep.box_idx;
    const DeviceAABB& my_box = boxes[my_box_idx];
    const float my_end_x = my_box.max_x;
    
    // Walk forward through the sorted array
    // Test overlaps until we hit our own end point (where value > my_end_x)
    for (uint32_t j = idx + 1; j < num_endpoints; ++j) {
        const Endpoint& other_ep = endpoints[j];
        
        // Stop when we pass our end point
        if (other_ep.value > my_end_x) {
            break;
        }
        
        // Only test against start points of other boxes (avoid duplicates)
        if (other_ep.is_start == 0) continue;
        
        const uint32_t other_box_idx = other_ep.box_idx;
        
        // Skip if same box (shouldn't happen but be safe)
        if (other_box_idx == my_box_idx) continue;
        
        const DeviceAABB& other_box = boxes[other_box_idx];
        
        // X-axis overlap is guaranteed since:
        // - other_ep.value (other's min_x) <= my_end_x (my max_x)
        // - my_box.min_x (current position) <= other_ep.value (other's min_x)
        // So we only need to check if other's max_x >= my min_x for full x-overlap
        // But since we're at a start point of other, and we haven't passed our end,
        // we need to verify x-overlap more carefully
        
        // Check y-axis overlap
        bool overlap_y = (my_box.min_y <= other_box.max_y) && (my_box.max_y >= other_box.min_y);
        
        if (overlap_y) {
            // Ensure pair is ordered (smaller index first)
            uint32_t a = my_box_idx;
            uint32_t b = other_box_idx;
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

    // Allocate device memory for boxes
    DeviceAABB* d_boxes;
    cudaMalloc(&d_boxes, N * sizeof(DeviceAABB));
    cudaMemcpy(d_boxes, h_boxes.data(), N * sizeof(DeviceAABB), cudaMemcpyHostToDevice);

    // Record Computation Start Time
    auto start = std::chrono::high_resolution_clock::now();

    // =========================================================================
    // Step 1: Create endpoints (2 per AABB: start and end)
    // =========================================================================
    const uint32_t num_endpoints = 2 * N;
    Endpoint* d_endpoints;
    cudaMalloc(&d_endpoints, num_endpoints * sizeof(Endpoint));
    
    int block_size = 256;
    int num_blocks = (N + block_size - 1) / block_size;
    
    create_endpoints_kernel<<<num_blocks, block_size>>>(d_boxes, N, d_endpoints);
    cudaDeviceSynchronize();

    // =========================================================================
    // Step 2: Sort endpoints using parallel sort (Thrust radix sort)
    // =========================================================================
    thrust::device_ptr<Endpoint> endpoints_ptr(d_endpoints);
    thrust::sort(endpoints_ptr, endpoints_ptr + num_endpoints, EndpointComparator());
    cudaDeviceSynchronize();

    // =========================================================================
    // Step 3: Sweep to find overlapping pairs
    // =========================================================================
    // Estimate max pairs
    uint64_t total_possible = (uint64_t)N * (N - 1) / 2;
    uint32_t max_pairs = (uint32_t)std::min(total_possible, (uint64_t)100000000);  // 100M max

    uint32_t* d_pair_first;
    uint32_t* d_pair_second;
    uint32_t* d_pair_count;
    
    cudaMalloc(&d_pair_first, max_pairs * sizeof(uint32_t));
    cudaMalloc(&d_pair_second, max_pairs * sizeof(uint32_t));
    cudaMalloc(&d_pair_count, sizeof(uint32_t));
    cudaMemset(d_pair_count, 0, sizeof(uint32_t));

    // Launch sweep kernel - one thread per endpoint
    num_blocks = (num_endpoints + block_size - 1) / block_size;
    
    sweep_find_overlaps_kernel<<<num_blocks, block_size>>>(
        d_endpoints, d_boxes, num_endpoints,
        d_pair_first, d_pair_second, d_pair_count, max_pairs
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
    cudaFree(d_endpoints);
    cudaFree(d_pair_first);
    cudaFree(d_pair_second);
    cudaFree(d_pair_count);

    // Record Computation End Time
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed = end - start;
    std::cout << "Computation Time: " << elapsed.count() << " seconds\n";

    return pairs;
}
