#include "aabb_io.h"

#include <cstdio>
#include <cstring>
#include <fstream>
#ifdef _WIN32
    #include <direct.h>
#else
    #include <sys/stat.h>
#endif

namespace aabb {

bool read_boxes(
    const std::string &path,
    std::vector<AABB> &boxes,
    std::string &err
) {
    err.clear();
    std::ifstream in(path, std::ios::in);
    if (!in) {
        err = "failed to open input file: " + path;
        return false;
    }

    int n;
    in >> n;
    boxes.resize(n);

    for (int i = 0; i < n; ++i) {
        boxes[i].id = i;
        in >> boxes[i].min_x >> boxes[i].min_y >> boxes[i].max_x >> boxes[i].max_y;
    }

    in.close();
    return true;
}


bool write_pairs(const std::string &path, const std::vector<std::pair<uint32_t, uint32_t>> &pairs, std::string &err) {
    err.clear();
    
    // If directory does not exist, create it
    size_t last_slash = path.find_last_of("/\\");
    if (last_slash != std::string::npos) {
        std::string dir = path.substr(0, last_slash);
        #ifdef _WIN32
            _mkdir(dir.c_str());
        #else
            mkdir(dir.c_str(), 0755);
        #endif
    }

    std::ofstream out(path, std::ios::out);
    if (!out) {
        err = "failed to open output file: " + path;
        return false;
    }
    for (const auto &p : pairs) {
        out << p.first << ' ' << p.second << '\n';
    }
    out.close();
    return true;
}

} // namespace aabb
