#include <vector>
#include <utility>

#include "seq_bruteforce.h"


static inline bool intersects(float min_ax, float min_ay, float max_ax, float max_ay,
                              float min_bx, float min_by, float max_bx, float max_by) {
    return !(max_ax < min_bx || max_bx < min_ax || max_ay < min_by || max_by < min_ay);
}


std::vector<std::pair<uint32_t, uint32_t>> brute_force(
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
