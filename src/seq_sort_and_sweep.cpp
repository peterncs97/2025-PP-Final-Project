#include <algorithm>
#include <iterator>
#include <utility>
#include <vector>

#include "seq_sort_and_sweep.h"
#include <unordered_set>

// Internal helper: Project boxes onto an axis
struct Point {
    float value;
    uint32_t index;
    bool is_start;
};

std::vector<std::pair<uint32_t, uint32_t>> sort_and_sweep(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes)
{
    // Project boxes onto x-axis and perform sweep
    std::vector<Point> points_x;
    points_x.reserve(N * 2);
    for (uint32_t i = 0; i < N; ++i) {
        points_x.push_back({boxes[i].min_x, i, true});
        points_x.push_back({boxes[i].max_x, i, false});
    }
    // Sort points on x and perform sweep; check y-overlap inline to avoid
    // producing two large candidate lists and intersecting them.
    std::sort(points_x.begin(), points_x.end(), [](const Point &a, const Point &b) {
        if (a.value == b.value) {
            if (a.is_start != b.is_start) return a.is_start;
            return a.index < b.index;
        }
        return a.value < b.value;
    });

    std::unordered_set<uint32_t> active_set;
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    for (const auto &point : points_x) {
        if (point.is_start) {
            uint32_t b = point.index;
            for (const auto &a_index : active_set) {
                uint32_t a = a_index;
                // Check overlap on y-axis before accepting the pair
                const auto &A = boxes[a];
                const auto &B = boxes[b];
                if (A.min_y <= B.max_y && A.max_y >= B.min_y) {
                    uint32_t x = a;
                    uint32_t y = b;
                    if (x > y) std::swap(x, y);
                    pairs.emplace_back(x, y);
                }
            }
            active_set.insert(b);
        } else {
            active_set.erase(point.index);
        }
    }

    std::sort(pairs.begin(), pairs.end());
    pairs.erase(std::unique(pairs.begin(), pairs.end()), pairs.end());
    return pairs;
}
