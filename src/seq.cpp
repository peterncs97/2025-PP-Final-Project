// sequential implementations to find all intersecting AABB pairs

#include <iostream>
#include <vector>
#include <string>
#include <algorithm>
#include <chrono>

#include "seq_sort_and_sweep.h"
#include "seq_bruteforce.h"
#include "seq_spatial_hashing.h"

#include "aabb_io.h"

int main(int argc, char **argv) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <testcase number> <algorithm>\n";
        return 1;
    }

    // Prepare file paths
    std::string testcase = argv[2];
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
    std::string algorithm = argv[1];
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    if (algorithm == "BF") {
        pairs = brute_force(N, boxes);
    } else if (algorithm == "SS") {
        pairs = sort_and_sweep(N, boxes);
    } else if (algorithm == "SH") {
        pairs = spatial_hashing(boxes);
    } else {
        std::cerr << "Unknown algorithm: " << algorithm << '\n';
        std::cerr << "Valid options are: BF, SS, SH\n";
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
