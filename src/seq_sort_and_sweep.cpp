#include <algorithm>
#include <iterator>
#include <utility>
#include <vector>

#include "seq_sort_and_sweep.h"

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
    // Single-pass sort-and-sweep on the x-axis that filters by y-overlap
    // This avoids materializing two potentially large candidate sets
    std::vector<Point> points_x;
    points_x.reserve(N * 2);
    for (uint32_t i = 0; i < N; ++i) {
        points_x.push_back({boxes[i].min_x, i, true});
        points_x.push_back({boxes[i].max_x, i, false});
    }

    // Sort points by x value (start points before end points on tie)
    std::sort(points_x.begin(), points_x.end(), [](const Point &a, const Point &b) {
        if (a.value == b.value) {
            return a.is_start && !b.is_start;
        }
        return a.value < b.value;
    });

    std::vector<uint32_t> active_set;
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    for (const auto &point : points_x) {
        if (point.is_start) {
            for (const auto &active_index : active_set) {
                uint32_t a = active_index;
                uint32_t b = point.index;

                // Quick y-axis overlap test to ensure overlap on both axes
                const auto &A = boxes[a];
                const auto &B = boxes[b];
                // inclusive overlap: [min_y, max_y] intersects
                if (A.min_y <= B.max_y && A.max_y >= B.min_y) {
                    if (a > b) std::swap(a, b);
                    pairs.emplace_back(a, b);
                }
            }
            active_set.push_back(point.index);
        } else {
            active_set.erase(std::remove(active_set.begin(), active_set.end(), point.index), active_set.end());
        }
    }

    std::sort(pairs.begin(), pairs.end());
    pairs.erase(std::unique(pairs.begin(), pairs.end()), pairs.end());
    return pairs;
}
