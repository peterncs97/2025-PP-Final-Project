#include <algorithm>
#include <vector>
#include <cmath>
#include <cuda_runtime.h>
#include <thrust/device_vector.h>
#include <thrust/sort.h>
#include <thrust/copy.h>
#include <thrust/scan.h>
#include <iostream>
#include <chrono>
#include <iomanip>

#include "cuda_spatial_hashing.cuh"

struct DeviceAABB {
    int id;
    float min_x;
    float min_y;
    float max_x;
    float max_y;
};

struct CellBoxPair {
    int64_t cell_hash;
    int32_t cell_x;
    int32_t cell_y;
    uint32_t box_id;
};

__host__ __device__ inline int64_t compute_cell_hash(int cx, int cy) {
    const int64_t P1 = 73856093LL;
    const int64_t P2 = 19349663LL;
    return int64_t(cx) * P1 ^ int64_t(cy) * P2;
}

struct CellBoxComparator {
    __host__ __device__ bool operator()(const CellBoxPair& a, const CellBoxPair& b) const {
        if (a.cell_hash != b.cell_hash) return a.cell_hash < b.cell_hash;
        return a.box_id < b.box_id;
    }
};

struct IsValidStart {
    __host__ __device__ bool operator()(uint32_t v) const { return v != 0xFFFFFFFFu; }
};

__device__ inline bool intersects_device(const DeviceAABB& a, const DeviceAABB& b) {
    return !(a.max_x < b.min_x || b.max_x < a.min_x || a.max_y < b.min_y || b.max_y < a.min_y);
}

__global__ void assign_boxes_to_cells_kernel(
    const DeviceAABB* boxes, uint32_t N, int cell_size, CellBoxPair* out_pairs)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;
    const DeviceAABB& box = boxes[idx];
    const float cx = (box.min_x + box.max_x) * 0.5f;
    const float cy = (box.min_y + box.max_y) * 0.5f;
    const int cell_x = (int)floorf(cx / cell_size);
    const int cell_y = (int)floorf(cy / cell_size);
    out_pairs[idx].cell_x = cell_x;
    out_pairs[idx].cell_y = cell_y;
    out_pairs[idx].cell_hash = compute_cell_hash(cell_x, cell_y);
    out_pairs[idx].box_id = idx;
}

__global__ void find_cell_starts_kernel(
    const CellBoxPair* sorted_pairs, uint32_t N, uint32_t* cell_starts_flags)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= N) return;
    const int64_t my_hash = sorted_pairs[idx].cell_hash;
    if (idx == 0 || sorted_pairs[idx - 1].cell_hash != my_hash) {
        cell_starts_flags[idx] = idx;
    } else {
        cell_starts_flags[idx] = 0xFFFFFFFFu;
    }
}

__global__ void compute_cell_lengths_kernel(
    const uint32_t* cell_starts,
    uint32_t num_cells,
    uint32_t total_entries,
    uint32_t* out_lengths)
{
    uint32_t cell_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (cell_idx >= num_cells) return;
    const uint32_t start = cell_starts[cell_idx];
    const uint32_t end = (cell_idx + 1 < num_cells) ? cell_starts[cell_idx + 1] : total_entries;
    out_lengths[cell_idx] = end - start;
}

__global__ void fill_cell_hashes_kernel(
    const CellBoxPair* sorted_pairs,
    const uint32_t* cell_starts,
    uint32_t num_cells,
    int64_t* out_hashes)
{
    uint32_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= num_cells) return;
    out_hashes[idx] = sorted_pairs[cell_starts[idx]].cell_hash;
}

__device__ int find_cell_index(
    const int64_t* cell_hashes, uint32_t num_cells, int64_t target_hash)
{
    int left = 0;
    int right = (int)num_cells - 1;
    while (left <= right) {
        int mid = (left + right) >> 1;
        const int64_t val = cell_hashes[mid];
        if (val == target_hash) return mid;
        if (val < target_hash) left = mid + 1;
        else right = mid - 1;
    }
    return -1;
}

__global__ void count_collisions_kernel(
    const DeviceAABB* boxes,
    const CellBoxPair* pairs,
    const int64_t* cell_hashes,
    const uint32_t* cell_starts,
    const uint32_t* cell_lengths,
    uint32_t num_cells,
    uint64_t* counts)
{
    uint32_t cell_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (cell_idx >= num_cells) return;

    const uint32_t start = cell_starts[cell_idx];
    const uint32_t len = cell_lengths[cell_idx];
    if (len == 0) return;

    const int cx = pairs[start].cell_x;
    const int cy = pairs[start].cell_y;

    uint64_t local_count = 0;

    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            const int nx = cx + dx;
            const int ny = cy + dy;
            if (!(dx > 0 || (dx == 0 && dy >= 0))) continue; // avoid duplicates

            const int64_t nh = compute_cell_hash(nx, ny);
            const int neigh_idx = find_cell_index(cell_hashes, num_cells, nh);
            if (neigh_idx < 0) continue;

            const uint32_t nstart = cell_starts[neigh_idx];
            const uint32_t nlen = cell_lengths[neigh_idx];
            if (nlen == 0) continue;

            if (neigh_idx == (int)cell_idx) {
                for (uint32_t i = 0; i < len; ++i) {
                    for (uint32_t j = i + 1; j < len; ++j) {
                        const DeviceAABB& A = boxes[pairs[start + i].box_id];
                        const DeviceAABB& B = boxes[pairs[start + j].box_id];
                        if (intersects_device(A, B)) local_count++;
                    }
                }
            } else {
                for (uint32_t i = 0; i < len; ++i) {
                    const DeviceAABB& A = boxes[pairs[start + i].box_id];
                    for (uint32_t j = 0; j < nlen; ++j) {
                        const DeviceAABB& B = boxes[pairs[nstart + j].box_id];
                        if (intersects_device(A, B)) local_count++;
                    }
                }
            }
        }
    }

    counts[cell_idx] = local_count;
}

__global__ void scatter_collisions_kernel(
    const DeviceAABB* boxes,
    const CellBoxPair* pairs,
    const int64_t* cell_hashes,
    const uint32_t* cell_starts,
    const uint32_t* cell_lengths,
    uint32_t num_cells,
    const uint64_t* offsets,
    uint32_t* out_a,
    uint32_t* out_b)
{
    uint32_t cell_idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (cell_idx >= num_cells) return;

    const uint32_t start = cell_starts[cell_idx];
    const uint32_t len = cell_lengths[cell_idx];
    if (len == 0) return;

    const int cx = pairs[start].cell_x;
    const int cy = pairs[start].cell_y;

    uint64_t write_pos = offsets[cell_idx];

    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            const int nx = cx + dx;
            const int ny = cy + dy;
            if (!(dx > 0 || (dx == 0 && dy >= 0))) continue;

            const int64_t nh = compute_cell_hash(nx, ny);
            const int neigh_idx = find_cell_index(cell_hashes, num_cells, nh);
            if (neigh_idx < 0) continue;

            const uint32_t nstart = cell_starts[neigh_idx];
            const uint32_t nlen = cell_lengths[neigh_idx];
            if (nlen == 0) continue;

            if (neigh_idx == (int)cell_idx) {
                for (uint32_t i = 0; i < len; ++i) {
                    for (uint32_t j = i + 1; j < len; ++j) {
                        const DeviceAABB& A = boxes[pairs[start + i].box_id];
                        const DeviceAABB& B = boxes[pairs[start + j].box_id];
                        if (!intersects_device(A, B)) continue;
                        uint32_t a = static_cast<uint32_t>(A.id);
                        uint32_t b = static_cast<uint32_t>(B.id);
                        if (a > b) { uint32_t t = a; a = b; b = t; }
                        out_a[write_pos] = a;
                        out_b[write_pos] = b;
                        write_pos++;
                    }
                }
            } else {
                for (uint32_t i = 0; i < len; ++i) {
                    const DeviceAABB& A = boxes[pairs[start + i].box_id];
                    for (uint32_t j = 0; j < nlen; ++j) {
                        const DeviceAABB& B = boxes[pairs[nstart + j].box_id];
                        if (!intersects_device(A, B)) continue;
                        uint32_t a = static_cast<uint32_t>(A.id);
                        uint32_t b = static_cast<uint32_t>(B.id);
                        if (a > b) { uint32_t t = a; a = b; b = t; }
                        out_a[write_pos] = a;
                        out_b[write_pos] = b;
                        write_pos++;
                    }
                }
            }
        }
    }
}

__host__ int compute_cell_size_host(const std::vector<aabb::AABB>& boxes) {
    float max_dim = 0.0f;
    for (const auto& b : boxes) {
        max_dim = std::max(max_dim, b.max_x - b.min_x);
        max_dim = std::max(max_dim, b.max_y - b.min_y);
    }
    int L = static_cast<int>(std::ceil(max_dim));
    return (L <= 0) ? 1 : L;
}

__host__ bool check_cuda(cudaError_t err, const char* msg) {
    if (err != cudaSuccess) {
        std::cerr << "[cuda_spatial_hashing] CUDA error: " << msg << " : "
                  << cudaGetErrorString(err) << "\n";
        return false;
    }
    return true;
}

std::vector<std::pair<uint32_t, uint32_t>> cuda_spatial_hashing(
    const uint32_t N,
    const std::vector<aabb::AABB>& boxes)
{
    if (N == 0) return {};

    auto t0 = std::chrono::high_resolution_clock::now();

    const int cell_size = compute_cell_size_host(boxes);
    std::cerr << "[cuda_sh] cell_size=" << cell_size << ", N=" << N << std::endl;

    int dev_count = 0;
    if (!check_cuda(cudaGetDeviceCount(&dev_count), "cudaGetDeviceCount")) return {};
    std::cerr << "[cuda_sh] device_count=" << dev_count << std::endl;

    // 使用 pinned host memory 提升 H2D 拷貝效率
    DeviceAABB* h_boxes = nullptr;
    if (!check_cuda(cudaHostAlloc(&h_boxes, N * sizeof(DeviceAABB), cudaHostAllocDefault), "cudaHostAlloc h_boxes")) {
        return {};
    }
    for (uint32_t i = 0; i < N; ++i) {
        h_boxes[i].id = boxes[i].id;
        h_boxes[i].min_x = boxes[i].min_x;
        h_boxes[i].min_y = boxes[i].min_y;
        h_boxes[i].max_x = boxes[i].max_x;
        h_boxes[i].max_y = boxes[i].max_y;
    }
    // 重用 device buffer
    static DeviceAABB* d_boxes = nullptr;
    static size_t d_boxes_capacity = 0;
    const size_t needed_boxes = static_cast<size_t>(N) * sizeof(DeviceAABB);
    if (needed_boxes > d_boxes_capacity) {
        if (d_boxes) cudaFreeAsync(d_boxes, 0);
        std::cerr << "[cuda_sh] cudaMalloc d_boxes..." << std::endl;
        if (!check_cuda(cudaMallocAsync(&d_boxes, needed_boxes, 0), "cudaMallocAsync d_boxes")) {
            cudaFreeHost(h_boxes);
            return {};
        }
        d_boxes_capacity = needed_boxes;
    }
    std::cerr << "[cuda_sh] cudaMemcpy boxes..." << std::endl;
    if (!check_cuda(cudaMemcpyAsync(d_boxes, h_boxes, needed_boxes, cudaMemcpyHostToDevice, 0), "memcpy boxes")) {
        cudaFreeHost(h_boxes);
        return {};
    }
    cudaStreamSynchronize(0);
    cudaFreeHost(h_boxes);

    // Record Computation Start Time
    auto start = std::chrono::high_resolution_clock::now();

    auto t_prep = std::chrono::high_resolution_clock::now();
    std::cerr << "[cuda_sh] prep done" << std::endl;

    thrust::device_vector<CellBoxPair> d_pairs(N);
    const int block = 256;
    const int grid = (N + block - 1) / block;
    std::cerr << "[cuda_sh] launch assign kernel" << std::endl;
    assign_boxes_to_cells_kernel<<<grid, block>>>(d_boxes, N, cell_size, thrust::raw_pointer_cast(d_pairs.data()));
    if (!check_cuda(cudaDeviceSynchronize(), "assign_boxes_to_cells_kernel")) {
        cudaFree(d_boxes);
        return {};
    }
    auto t_assign = std::chrono::high_resolution_clock::now();
    std::cerr << "[cuda_sh] assign done" << std::endl;

    thrust::sort(d_pairs.begin(), d_pairs.end(), CellBoxComparator());
    auto t_sort = std::chrono::high_resolution_clock::now();
    std::cerr << "[cuda_sh] sort done" << std::endl;

    thrust::device_vector<uint32_t> d_cell_starts_flags(N);
    find_cell_starts_kernel<<<grid, block>>>(thrust::raw_pointer_cast(d_pairs.data()), N,
                                             thrust::raw_pointer_cast(d_cell_starts_flags.data()));
    if (!check_cuda(cudaDeviceSynchronize(), "find_cell_starts_kernel")) {
        cudaFree(d_boxes);
        return {};
    }

    thrust::device_vector<uint32_t> d_cell_starts(N);
    auto end_it = thrust::copy_if(
        thrust::counting_iterator<uint32_t>(0),
        thrust::counting_iterator<uint32_t>(N),
        d_cell_starts_flags.begin(),
        d_cell_starts.begin(),
        IsValidStart());
    const uint32_t num_cells = static_cast<uint32_t>(end_it - d_cell_starts.begin());
    std::cerr << "[cuda_sh] num_cells=" << num_cells << "\n";
    d_cell_starts.resize(num_cells);

    thrust::device_vector<uint32_t> d_cell_lengths(num_cells);
    if (num_cells > 0) {
        const int grid_cells = (num_cells + block - 1) / block;
        compute_cell_lengths_kernel<<<grid_cells, block>>>(
            thrust::raw_pointer_cast(d_cell_starts.data()),
            num_cells,
            N,
            thrust::raw_pointer_cast(d_cell_lengths.data()));
        if (!check_cuda(cudaDeviceSynchronize(), "compute_cell_lengths_kernel")) {
            cudaFree(d_boxes);
            return {};
        }
    }
    auto t_bucket = std::chrono::high_resolution_clock::now();
    std::cerr << "[cuda_sh] bucket done\n";

    thrust::device_vector<int64_t> d_cell_hashes(num_cells);
    if (num_cells > 0) {
        const int grid_cells = (num_cells + block - 1) / block;
        fill_cell_hashes_kernel<<<grid_cells, block>>>(
            thrust::raw_pointer_cast(d_pairs.data()),
            thrust::raw_pointer_cast(d_cell_starts.data()),
            num_cells,
            thrust::raw_pointer_cast(d_cell_hashes.data()));
        if (!check_cuda(cudaDeviceSynchronize(), "fill_cell_hashes_kernel")) {
            cudaFree(d_boxes);
            return {};
        }
    }
    auto t_hashes = std::chrono::high_resolution_clock::now();
    std::cerr << "[cuda_sh] hashes done\n";

    thrust::device_vector<uint64_t> d_counts(num_cells, 0);
    if (num_cells > 0) {
        const int grid_cells = (num_cells + block - 1) / block;
        count_collisions_kernel<<<grid_cells, block>>>(
            d_boxes,
            thrust::raw_pointer_cast(d_pairs.data()),
            thrust::raw_pointer_cast(d_cell_hashes.data()),
            thrust::raw_pointer_cast(d_cell_starts.data()),
            thrust::raw_pointer_cast(d_cell_lengths.data()),
            num_cells,
            thrust::raw_pointer_cast(d_counts.data()));
        if (!check_cuda(cudaDeviceSynchronize(), "count_collisions_kernel")) {
            cudaFree(d_boxes);
            return {};
        }
    }
    auto t_count = std::chrono::high_resolution_clock::now();
    std::cerr << "[cuda_sh] count done\n";

    thrust::device_vector<uint64_t> d_offsets(num_cells + 1, 0);
    if (num_cells > 0) {
        thrust::exclusive_scan(d_counts.begin(), d_counts.end(), d_offsets.begin());
    }
    uint64_t total_pairs = 0;
    if (num_cells > 0) {
        uint64_t last_offset = 0;
        uint64_t last_count = 0;
        cudaMemcpy(&last_offset,
                   thrust::raw_pointer_cast(d_offsets.data()) + (num_cells - 1),
                   sizeof(uint64_t),
                   cudaMemcpyDeviceToHost);
        cudaMemcpy(&last_count,
                   thrust::raw_pointer_cast(d_counts.data()) + (num_cells - 1),
                   sizeof(uint64_t),
                   cudaMemcpyDeviceToHost);
        total_pairs = last_offset + last_count;
        cudaMemcpy(thrust::raw_pointer_cast(d_offsets.data()) + num_cells,
                   &total_pairs,
                   sizeof(uint64_t),
                   cudaMemcpyHostToDevice);
    }
    auto t_scan = std::chrono::high_resolution_clock::now();
    std::cerr << "[cuda_sh] scan done, total_pairs=" << total_pairs << "\n";

    auto t_scatter = t_scan;
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    if (total_pairs > 0) {
        thrust::device_vector<uint32_t> d_pair_a(total_pairs);
        thrust::device_vector<uint32_t> d_pair_b(total_pairs);

        const int grid_cells = (num_cells + block - 1) / block;
        scatter_collisions_kernel<<<grid_cells, block>>>(
            d_boxes,
            thrust::raw_pointer_cast(d_pairs.data()),
            thrust::raw_pointer_cast(d_cell_hashes.data()),
            thrust::raw_pointer_cast(d_cell_starts.data()),
            thrust::raw_pointer_cast(d_cell_lengths.data()),
            num_cells,
            thrust::raw_pointer_cast(d_offsets.data()),
            thrust::raw_pointer_cast(d_pair_a.data()),
            thrust::raw_pointer_cast(d_pair_b.data()));
        if (!check_cuda(cudaDeviceSynchronize(), "scatter_collisions_kernel")) {
            cudaFree(d_boxes);
            return {};
        }

        std::vector<uint32_t> h_a(total_pairs);
        std::vector<uint32_t> h_b(total_pairs);
        if (!check_cuda(cudaMemcpy(h_a.data(), thrust::raw_pointer_cast(d_pair_a.data()),
                   total_pairs * sizeof(uint32_t), cudaMemcpyDeviceToHost), "copy pair_a") ||
            !check_cuda(cudaMemcpy(h_b.data(), thrust::raw_pointer_cast(d_pair_b.data()),
                   total_pairs * sizeof(uint32_t), cudaMemcpyDeviceToHost), "copy pair_b")) {
            cudaFree(d_boxes);
            return {};
        }

        pairs.reserve(static_cast<size_t>(total_pairs));
        for (uint64_t i = 0; i < total_pairs; ++i) {
            pairs.emplace_back(h_a[i], h_b[i]);
        }
        t_scatter = std::chrono::high_resolution_clock::now();
        std::cerr << "[cuda_sh] scatter done\n";
    } else {
        std::cerr << "[cuda_sh] total_pairs=0\n";
    }

    auto t_end = std::chrono::high_resolution_clock::now();
    auto ms = [](auto a, auto b) {
        return std::chrono::duration<double, std::milli>(b - a).count();
    };
    std::cerr << "[cuda_sh] timings (ms):\n"
              << "  prep     : " << std::fixed << std::setprecision(3) << ms(t0, t_prep) << "\n"
              << "  assign   : " << std::fixed << std::setprecision(3) << ms(t_prep, t_assign) << "\n"
              << "  sort     : " << std::fixed << std::setprecision(3) << ms(t_assign, t_sort) << "\n"
              << "  bucket   : " << std::fixed << std::setprecision(3) << ms(t_sort, t_bucket) << "\n"
              << "  hashes   : " << std::fixed << std::setprecision(3) << ms(t_bucket, t_hashes) << "\n"
              << "  count    : " << std::fixed << std::setprecision(3) << ms(t_hashes, t_count) << "\n"
              << "  scan     : " << std::fixed << std::setprecision(3) << ms(t_count, t_scan) << "\n"
              << "  scatter  : " << std::fixed << std::setprecision(3) << ms(t_scan, t_scatter) << "\n"
              << "  finalize : " << std::fixed << std::setprecision(3) << ms(t_scatter, t_end) << "\n"
              << "  total    : " << std::fixed << std::setprecision(3) << ms(t0, t_end) << "\n";

    cudaFree(d_boxes);
    std::cerr << "[cuda_sh] return pairs=" << pairs.size() << "\n";

    // Record Computation End Time
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed = end - start;
    std::cout << "Computation Time: " << elapsed.count() << " seconds\n";

    return pairs;
}
