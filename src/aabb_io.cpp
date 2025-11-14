#include "../include/aabb_io.h"

#include <cstdio>
#include <cstring>
#include <fstream>

namespace aabb {

bool read_soa(
    const std::string &path,
    std::vector<float> &min_x,
    std::vector<float> &min_y,
    std::vector<float> &max_x,
    std::vector<float> &max_y,
    float &world_w,
    float &world_h,
    std::string &err
) {
    err.clear();
    FILE *fp = std::fopen(path.c_str(), "rb");
    if (!fp) {
        err = "failed to open file: " + path;
        return false;
    }

    SoAHeader hdr{};
    if (std::fread(&hdr, sizeof(hdr), 1, fp) != 1) {
        err = "failed to read header or file too small";
        std::fclose(fp);
        return false;
    }

    if (std::memcmp(hdr.magic, "AASO", 4) != 0) {
        err = "invalid magic; expected 'AASO'";
        std::fclose(fp);
        return false;
    }
    if (hdr.version != 1) {
        err = "unsupported version: " + std::to_string(hdr.version);
        std::fclose(fp);
        return false;
    }

    uint32_t N = hdr.count;
    world_w = hdr.world_w;
    world_h = hdr.world_h;

    // Allocate vectors
    try {
        min_x.resize(N);
        min_y.resize(N);
        max_x.resize(N);
        max_y.resize(N);
    } catch (const std::bad_alloc &) {
        err = "out of memory allocating arrays";
        std::fclose(fp);
        return false;
    }

    // Read arrays sequentially: min_x, min_y, max_x, max_y
    if (N > 0) {
        if (std::fread(min_x.data(), sizeof(float), N, fp) != N) {
            err = "unexpected EOF while reading min_x";
            std::fclose(fp);
            return false;
        }
        if (std::fread(min_y.data(), sizeof(float), N, fp) != N) {
            err = "unexpected EOF while reading min_y";
            std::fclose(fp);
            return false;
        }
        if (std::fread(max_x.data(), sizeof(float), N, fp) != N) {
            err = "unexpected EOF while reading max_x";
            std::fclose(fp);
            return false;
        }
        if (std::fread(max_y.data(), sizeof(float), N, fp) != N) {
            err = "unexpected EOF while reading max_y";
            std::fclose(fp);
            return false;
        }
    }

    std::fclose(fp);
    return true;
}

bool write_pairs_csv(const std::string &path, const std::vector<std::pair<uint32_t, uint32_t>> &pairs, std::string &err) {
    err.clear();
    std::ofstream out(path, std::ios::out);
    if (!out) {
        err = "failed to open output file: " + path;
        return false;
    }
    out << "id1,id2\n";
    for (const auto &p : pairs) {
        out << p.first << ',' << p.second << '\n';
    }
    out.close();
    return true;
}

} // namespace aabb
