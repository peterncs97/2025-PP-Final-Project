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

static std::vector<std::pair<uint32_t, uint32_t>> sweep_points(
    std::vector<Point> points)
{
    // Sort points by value, with start points before end points in case of tie
    std::sort(points.begin(), points.end(), [](const Point &a, const Point &b) {
        if (a.value == b.value) {
            return a.is_start && !b.is_start;
        }
        return a.value < b.value;
    });

    // Sweep line algorithm
    std::vector<uint32_t> active_set;
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    for (const auto &point : points) {
        if (point.is_start) {
            for (const auto &active_index : active_set) {
                uint32_t a = active_index;
                uint32_t b = point.index;
                if (a > b) std::swap(a, b);
                pairs.emplace_back(a, b);
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
    auto candidate_pairs_x = sweep_points(points_x);

    // Project boxes onto y-axis and perform sweep
    std::vector<Point> points_y;
    points_y.reserve(N * 2);
    for (uint32_t i = 0; i < N; ++i) {
        points_y.push_back({boxes[i].min_y, i, true});
        points_y.push_back({boxes[i].max_y, i, false});
    }
    auto candidate_pairs_y = sweep_points(points_y);

    // Intersect candidate sets to ensure overlap on both axes
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(std::min(candidate_pairs_x.size(), candidate_pairs_y.size()));
    std::set_intersection(
        candidate_pairs_x.begin(), candidate_pairs_x.end(),
        candidate_pairs_y.begin(), candidate_pairs_y.end(),
        std::back_inserter(pairs)
    );

    return pairs;
}
