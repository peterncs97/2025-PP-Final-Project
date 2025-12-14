// CUDA implementation to find all intersecting AABB pairs

#include <iostream>
#include <vector>
#include <string>
#include <chrono>

#include "cuda_sort_and_sweep.cuh"
#include "cuda_spatial_hashing.cuh"
#include "aabb_io.h"

int main(int argc, char **argv) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <algorithm> <testcase number>\n";
        std::cerr << "  algorithm: SS (Sort-and-Sweep) or SH (Spatial Hashing)\n";
        return 1;
    }

    // Prepare file paths
    std::string algorithm = argv[1];
    std::string testcase = argv[2];
    std::string in_path = "testcase/" + testcase + ".in";
    std::string out_path = "out/" + testcase + "_cuda.out";

    // Read boxes from input file
    std::vector<aabb::AABB> boxes;
    std::string err;
    if (!aabb::read_boxes(in_path, boxes, err)) {
        std::cerr << "Failed to read file: " << err << '\n';
        return 2;
    }
    std::cout << "Loaded " << boxes.size() << " boxes from " << in_path << "\n";
    const uint32_t N = static_cast<uint32_t>(boxes.size());

    // ----------- Detection start ------------
    auto start = std::chrono::high_resolution_clock::now();

    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    if (algorithm == "SS") {
        pairs = cuda_sort_and_sweep(N, boxes);
    } else if (algorithm == "SH") {
        pairs = cuda_spatial_hashing(N, boxes);
    } else {
        std::cerr << "Unknown algorithm: " << algorithm << '\n';
        std::cerr << "Valid options are: SS, SH\n";
        return 4;
    }

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed = end - start;
    std::cout << "Algorithm: CUDA " << (algorithm == "SS" ? "Sort-and-Sweep" : "Spatial Hashing")
              << ", Time elapsed: " << elapsed.count() << " seconds\n";
    // ----------- Detection end ------------

    // Write output pairs to file
    if (!aabb::write_pairs(out_path, pairs, err)) {
        std::cerr << "Failed to write pairs: " << err << '\n';
        return 3;
    }

    std::cout << "Read " << N << " boxes, found " << pairs.size() << " pairs. Wrote: " << out_path << "\n";
    return 0;
}
