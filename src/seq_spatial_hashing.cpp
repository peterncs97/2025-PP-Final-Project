#include <utility>
#include <vector>

#include "seq_spatial_hashing.h"

std::vector<std::pair<uint32_t, uint32_t>> spatial_hashing(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes)
{
    (void)N;
    (void)boxes;

    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    // TODO: Implement spatial hashing broad-phase
    return pairs;
}
