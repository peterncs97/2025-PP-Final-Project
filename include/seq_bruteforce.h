#pragma once

#include <cstdint>
#include <utility>
#include <vector>

#include "aabb_io.h"

// Brute force intersection of all AABB pairs (returns sorted pairs i<j)
std::vector<std::pair<uint32_t, uint32_t>> brute_force(
    const uint32_t N,
    const std::vector<aabb::AABB> boxes);
