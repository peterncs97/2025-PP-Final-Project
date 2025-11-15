// sequential implementations to find all intersecting AABB pairs

#include <iostream>
#include <vector>
#include <string>
#include <chrono>

#include "aabb_io.h"


static inline bool intersects(float min_ax, float min_ay, float max_ax, float max_ay,
                             float min_bx, float min_by, float max_bx, float max_by) {
    return !(max_ax < min_bx || max_bx < min_ax || max_ay < min_by || max_by < min_ay);
}


static std::vector<std::pair<uint32_t, uint32_t>> brute_force(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes) 
{
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    for (uint32_t i = 0; i < N; ++i) {
        for (uint32_t j = i + 1; j < N; ++j) {
            if (intersects(boxes[i].min_x, boxes[i].min_y, boxes[i].max_x, boxes[i].max_y,
                           boxes[j].min_x, boxes[j].min_y, boxes[j].max_x, boxes[j].max_y)) {
                pairs.emplace_back(i, j);
            }
        }
    }

    return pairs;
}


static std::vector<std::pair<uint32_t, uint32_t>> sort_and_sweep(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes) 
{
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);
    
    // TODO

    return pairs;
}


static std::vector<std::pair<uint32_t, uint32_t>> spatial_hashing(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes) 
{
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);
    
    // TODO

    return pairs;
}


int main(int argc, char **argv) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <testcase number> <algorithm>\n";
        return 1;
    }

    // Prepare file paths
    std::string testcase = argv[1];
    std::string in_path = "testcase/" + testcase + ".in";
    std::string out_path = "out/" + testcase + ".out";

    // Read boxes from input file
    std::vector<aabb::AABB> boxes;
    std::string err;
    if (!aabb::read_boxes(in_path, boxes, err)) {
        std::cerr << "Failed to read file: " << err << '\n';
        return 2;
    }
    const uint32_t N = static_cast<uint32_t>(boxes.size());

    // ----------- Detection start ------------
    auto start = std::chrono::high_resolution_clock::now();

    // Select and run the algorithm
    std::string algorithm = argv[2];
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    if (algorithm == "brute_force") {
        pairs = brute_force(N, boxes);
    } else if (algorithm == "sort_and_sweep") {
        pairs = sort_and_sweep(N, boxes);
    } else if (algorithm == "spatial_hashing") {
        pairs = spatial_hashing(N, boxes);
    } else {
        std::cerr << "Unknown algorithm: " << algorithm << '\n';
        return 4;
    }

    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> elapsed = end - start;
    std::cout << "Algorithm: " << algorithm << ", Time elapsed: " << elapsed.count() << " seconds\n";
    // ----------- Detection end ------------

    // Write output pairs to file
    if (!aabb::write_pairs(out_path, pairs, err)) {
        std::cerr << "Failed to write pairs: " << err << '\n';
        return 3;
    }

    std::cout << "Read " << N << " boxes, found " << pairs.size() << " pairs. Wrote: " << out_path << "\n";
    return 0;
}
