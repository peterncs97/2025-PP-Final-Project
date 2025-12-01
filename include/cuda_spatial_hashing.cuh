#pragma once

#include <cstdint>
#include <utility>
#include <vector>

#include "aabb_io.h"

// CUDA accelerated spatial hashing (returns sorted pairs i<j)
std::vector<std::pair<uint32_t, uint32_t>> cuda_spatial_hashing(
    const uint32_t N,
    const std::vector<aabb::AABB>& boxes);
