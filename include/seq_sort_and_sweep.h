#pragma once

#include <cstdint>
#include <utility>
#include <vector>

#include "aabb_io.h"

// Public API: find all intersecting AABB pairs using sort-and-sweep on both axes
// Returns a sorted unique list of pairs (i < j)
std::vector<std::pair<uint32_t, uint32_t>> sort_and_sweep(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes);
