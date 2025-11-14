# Collision Detection

This repository includes a Python script to generate static single-frame datasets of 2D AABBs for broad-phase collision detection benchmarks.

- Script: `gen.py`
- Output: SoA (Structure-of-Arrays) binary file optimized for high-performance loading in C++

## Quick start

```
# Generate SoA binary (testcase/aabbs_soa.bin)
python ./gen.py --n 10000 --width 10000 --height 10000 --min-size 0.5 --max-size 4 --distribution uniform --out testcase/aabbs --seed 42
```

## Visualize a dataset

Render the SoA dataset to a PNG image:

```
python ./viz.py --in ./testcase/aabbs.bin --out ./testcase/aabbs_from_soa.png --dpi 160
```

Notes:
- Uses a non-interactive backend; it saves directly to PNG without opening a window.
- World size is read from the SoA header; you can override with `--width/--height` if desired.

## SoA binary format (Structure of Arrays)

Little-endian layout designed for fast C++ loading with contiguous arrays:

Header (24 bytes):
- magic: 4 bytes = `AASO`
- version: `uint32` = 1
- count:   `uint32` = N
- world_width:  `float32`
- world_height: `float32`
- reserved: `uint32` = 0

Arrays (each `float32[N]`, back-to-back):
- min_x[]; min_y[]; max_x[]; max_y[]

### C++ parsing example (SoA binary)

```cpp
#include <cstdint>
#include <cstdio>
#include <vector>
#include <cassert>
#include <cstring>

#pragma pack(push,1)
struct SoAHeader {
    char magic[4];
    uint32_t version;
    uint32_t count;
    float world_width;
    float world_height;
    uint32_t reserved;
};
#pragma pack(pop)

int main() {
    FILE* fp = std::fopen("testcase/aabbs_soa.bin", "rb");
    assert(fp);
    SoAHeader hdr{};
    assert(std::fread(&hdr, sizeof(hdr), 1, fp) == 1);
    assert(std::memcmp(hdr.magic, "AASO", 4) == 0);
    assert(hdr.version == 1);

    const size_t N = hdr.count;
    std::vector<float> min_x(N), min_y(N), max_x(N), max_y(N);
    assert(std::fread(min_x.data(), sizeof(float), N, fp) == N);
    assert(std::fread(min_y.data(), sizeof(float), N, fp) == N);
    assert(std::fread(max_x.data(), sizeof(float), N, fp) == N);
    assert(std::fread(max_y.data(), sizeof(float), N, fp) == N);
    std::fclose(fp);
    return 0;
}
```


## Options

- `--n` (required): number of boxes
- `--width`, `--height`: world dimensions (default 100x100)
- `--min-size`, `--max-size`: box edge length range (default 0.5–5.0)
- `--distribution`: `uniform` or `clustered` (default `uniform`)
- `--seed`: RNG seed for reproducibility
- `--out`: output file base path without extension (default `testcase/aabbs`)

## Notes

- Boxes are generated entirely within `[0,width] x [0,height]` and may overlap (broad-phase friendly).
- If `max-size` exceeds the world bounds, it’s reduced to fit; `min-size` is adjusted if necessary to keep `min <= max`.
- The generator uses only the Python standard library; the visualizer requires `matplotlib`.
