#pragma once

#include <cstdint>
#include <utility>
#include <vector>

#include "aabb_io.h"

// Spatial hashing broad-phase (returns sorted pairs i<j)
std::vector<std::pair<uint32_t, uint32_t>> spatial_hashing(
    const std::vector<aabb::AABB> boxes);
