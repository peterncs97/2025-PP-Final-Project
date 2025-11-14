// Small example program: reads SoA AABB file, performs brute-force pair detection,
// and writes pairs CSV. Usage:
//   soa_tool <in_soa.bin> <out_pairs.csv>

#include <iostream>
#include <vector>
#include <string>

#include "aabb_io.h"

static inline bool intersects(float min_ax, float min_ay, float max_ax, float max_ay,
                             float min_bx, float min_by, float max_bx, float max_by) {
    return !(max_ax < min_bx || max_bx < min_ax || max_ay < min_by || max_by < min_ay);
}

// Extracted helper: compute all intersecting pairs (i < j)
static std::vector<std::pair<uint32_t, uint32_t>> find_intersecting_pairs(
    const uint32_t N,
    const std::vector<float> &min_x,
    const std::vector<float> &min_y,
    const std::vector<float> &max_x,
    const std::vector<float> &max_y) {
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    for (uint32_t i = 0; i < N; ++i) {
        for (uint32_t j = i + 1; j < N; ++j) {
            if (intersects(min_x[i], min_y[i], max_x[i], max_y[i],
                           min_x[j], min_y[j], max_x[j], max_y[j])) {
                pairs.emplace_back(i, j);
            }
        }
    }

    return pairs;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <testcase number>\n";
        return 1;
    }

    std::string testcase = argv[1];
    std::string in_path = "testcase/" + testcase + ".bin";
    std::string out_path = "out/" + testcase + ".csv";

    std::vector<float> min_x, min_y, max_x, max_y;
    float world_w = 0.0f, world_h = 0.0f;
    std::string err;

    if (!aabb::read_soa(in_path, min_x, min_y, max_x, max_y, world_w, world_h, err)) {
        std::cerr << "Failed to read SoA file: " << err << '\n';
        return 2;
    }

    const uint32_t N = static_cast<uint32_t>(min_x.size());
    auto pairs = find_intersecting_pairs(N, min_x, min_y, max_x, max_y);

    if (!aabb::write_pairs_csv(out_path, pairs, err)) {
        std::cerr << "Failed to write pairs CSV: " << err << '\n';
        return 3;
    }

    std::cout << "Read " << N << " boxes, found " << pairs.size() << " pairs. Wrote: " << out_path << "\n";
    return 0;
}
