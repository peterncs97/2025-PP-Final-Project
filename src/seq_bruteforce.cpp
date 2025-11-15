#include "seq_bruteforce.h"


// Basic AABB intersection test
static inline bool intersects(const aabb::AABB& box_a, const aabb::AABB& box_b) {
    return !(box_a.max_x < box_b.min_x ||
             box_b.max_x < box_a.min_x ||
             box_a.max_y < box_b.min_y ||
             box_b.max_y < box_a.min_y);
}

std::vector<std::pair<uint32_t, uint32_t>> brute_force(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes)
{
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    for (uint32_t i = 0; i < N; ++i)
        for (uint32_t j = i + 1; j < N; ++j)
            if (intersects(boxes[i], boxes[j]))
                pairs.emplace_back(i, j);

    return pairs;
}
