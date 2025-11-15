#include <unordered_map>
#include <cmath>
#include <algorithm>

#include "seq_spatial_hashing.h"


struct CellCoord {
    int x;
    int y;
    bool operator==(const CellCoord& other) const noexcept {
        return x == other.x && y == other.y;
    }
};

struct CellCoordHash {
    size_t operator()(const CellCoord& k) const noexcept {
        const size_t P1 = 73856093u;
        const size_t P2 = 19349663u;
        return size_t(k.x) * P1 ^ size_t(k.y) * P2;
    }
};

using Bucket = std::vector<const aabb::AABB*>;


// Basic AABB intersection test
static inline bool intersects(const aabb::AABB& box_a, const aabb::AABB& box_b) {
    return !(box_a.max_x < box_b.min_x ||
             box_b.max_x < box_a.min_x ||
             box_a.max_y < box_b.min_y ||
             box_b.max_y < box_a.min_y);
}


// Compute a reasonable cell size from the input boxes (>= 1)
static inline int compute_cell_size(const std::vector<aabb::AABB>& boxes) {
    float max_dim = 0.0f;
    for (const auto& b : boxes) {
        max_dim = std::max(max_dim, b.max_x - b.min_x);
        max_dim = std::max(max_dim, b.max_y - b.min_y);
    }
    int L = static_cast<int>(std::ceil(max_dim));
    if (L <= 0) L = 1;
    return L;
}

// Build the spatial hash grid mapping cell coordinates to box pointers
static std::unordered_map<CellCoord, Bucket, CellCoordHash>
build_grid(const std::vector<aabb::AABB>& boxes, int L) 
{
    std::unordered_map<CellCoord, Bucket, CellCoordHash> grid;
    grid.reserve(boxes.size());

    for (const auto& box : boxes) {
        // Compute cell coordinate for box center
        const float cx = (box.min_x + box.max_x) * 0.5f;
        const float cy = (box.min_y + box.max_y) * 0.5f;
        const CellCoord c{
            static_cast<int>(std::floor(cx / L)),
            static_cast<int>(std::floor(cy / L))
        };
        grid[c].push_back(&box);
    }
    return grid;
}


// Get the 3x3 neighboring cell coordinates around a given cell
void get_neighboring_cells(const CellCoord& cell, std::vector<CellCoord>& neighbors) {
    for (int dx = -1; dx <= 1; ++dx) {
        for (int dy = -1; dy <= 1; ++dy) {
            neighbors.push_back(CellCoord{cell.x + dx, cell.y + dy});
        }
    }
}


// Collect pointers to boxes in the 3x3 neighborhood around a cell
static inline void gather_neighbor_boxes(
    const std::unordered_map<CellCoord, Bucket, CellCoordHash>& grid,
    const CellCoord& center,
    Bucket& out_neighbor_boxes) 
{
    std::vector<CellCoord> neighbor_cells;
    neighbor_cells.reserve(9);
    get_neighboring_cells(center, neighbor_cells);

    for (const auto& coord : neighbor_cells) {
        auto it = grid.find(coord);
        if (it != grid.end()) {
            const auto& neighbor_bucket = it->second;
            out_neighbor_boxes.insert(out_neighbor_boxes.end(),
                                      neighbor_bucket.begin(), neighbor_bucket.end());
        }
    }
}


std::vector<std::pair<uint32_t,uint32_t>> spatial_hashing(
    const std::vector<aabb::AABB> boxes)
{
    // 1) Determine cell size
    const int L = compute_cell_size(boxes);

    // 2) Build spatial grid
    auto grid = build_grid(boxes, L);

    // 3) Detect collisions
    std::vector<std::pair<uint32_t, uint32_t>> pairs;
    pairs.reserve(64);

    // Check 3x3 neighboring cells (including own cell)
    for (const auto& kv : grid) {
        Bucket neighbor_boxes;
        neighbor_boxes.reserve(32);
        gather_neighbor_boxes(grid, kv.first, neighbor_boxes);

        // Check for intersections between boxes in current cell and neighboring boxes
        const auto& bucket = kv.second;
        for (const auto* box_a_ptr : bucket) {
            for (const auto* box_b_ptr : neighbor_boxes) {
                if (box_a_ptr->id >= box_b_ptr->id) continue; // ensure i<j
                if (!intersects(*box_a_ptr, *box_b_ptr)) continue;
                pairs.emplace_back(box_a_ptr->id, box_b_ptr->id);
            }
        }
    }

    std::sort(pairs.begin(), pairs.end());
    pairs.erase(std::unique(pairs.begin(), pairs.end()), pairs.end());
    return pairs;
}
