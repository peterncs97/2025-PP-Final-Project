#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace aabb {

struct AABB {
    int id;
    float min_x;
    float min_y;
    float max_x;
    float max_y;
};

bool read_boxes(
    const std::string &path,
    std::vector<AABB> &boxes,
    std::string &err
);

bool write_pairs(
    const std::string &path,
    const std::vector<std::pair<uint32_t, uint32_t>> &pairs,
    std::string &err
);

} // namespace aabb
