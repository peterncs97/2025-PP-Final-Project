#pragma once
// Simple AABB SoA I/O utilities
// - read SoA binary files with magic "AASO"
// - write collision pair CSV files

#include <cstdint>
#include <string>
#include <vector>

namespace aabb {

struct SoAHeader {
    char magic[4];    // "AASO"
    uint32_t version; // 1
    uint32_t count;   // N
    float world_w;
    float world_h;
    uint32_t reserved;
};

// Read a SoA AABB file. On success returns true and fills the vectors and world dims.
// On failure returns false and sets err (if non-empty).
bool read_soa(
    const std::string &path,
    std::vector<float> &min_x,
    std::vector<float> &min_y,
    std::vector<float> &max_x,
    std::vector<float> &max_y,
    float &world_w,
    float &world_h,
    std::string &err
);

// Write CSV of pairs: each row "id1,id2" with a header. Returns true on success.
bool write_pairs_csv(const std::string &path, const std::vector<std::pair<uint32_t, uint32_t>> &pairs, std::string &err);

} // namespace aabb
