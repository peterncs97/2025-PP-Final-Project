# Collision Detection
This repository contains code for generating datasets of 2D axis-aligned bounding boxes (AABBs) and implementing various collision detection algorithms to find overlapping box pairs.

# Sequential Broad-Phase Algorithms
The following sequential broad-phase collision detection algorithms are implemented:
- Brute Force (BF)
- Sort-and-Sweep (SS)
- Spatial Hashing (SH)

## Execution
To compile and run the sequential implementations, use the following commands:
```
make 
./bin/seq <algorithm> <testcase number>
```
Replace `<algorithm>` with one of `BF`, `SS`, or `SH`, and `<testcase number>` with the number of the dataset file.

Example:
```
./bin/seq SS 1
```

Run with slurming for large testcases:
```
sbatch scripts/run_seq.sh <algorithm> <testcase number>
```

## Sequential implementation benchmarks
| Testcase | Distribution                | Sort-and-Sweep Time (s) | Spatial Hashing Time (s) |
|----------|-----------------------------|-------------------------|--------------------------|
| 11       | Sparse uniform 			 | 0.0707318           	   | 0.289908                 |
| 12       | Dense uniform  			 | 0.245062                | 0.113961             	  |
| 13       | Clustered medium occupancy  | 0.571056                | 0.185043            	  |
| 14       | Packed high-overlap 		 | 0.198852                | 0.0464638                |
| 15       | Grid low-overlap baseline 	 | 0.0948492               | 0.139919                 |
| 16       | Skewed sizes few huge boxes | 0.0918866               | 0.17984                  |
| 17       | Wide world 				 | 0.0484513               | 0.167596                 |
| 18       | Tall world 				 | 14.8628                 | 0.169694                 |
| 19       | Packed + skewed 			 | 0.220941                | 0.199657                 |
| 20       | Moderate occupancy 		 | 0.393519                | 0.336246                 |

Noted that SS run very slow on testcase 18 due to extreme aspect ratio. The implementation sweeps along the X-axis, which has very long intervals due to the tall world.

# Dataset

## Dataset Format
The generated dataset is a text file (`.in`) with the following format:
- First line: single integer `N`, the number of boxes.
- Next `N` lines: each line contains four floating-point numbers `min_x min_y max_x max_y`, representing the coordinates of the bottom-left and top-right corners of each axis-aligned bounding box (AABB).


## Dataset Generation

Check `scripts/gen.sh` for example usages.

### Options

- `--n` (required): number of boxes
- `--width`, `--height`: world dimensions (default 100x100)
- `--min-size`, `--max-size`: base box edge length range (default 0.5–5.0)
- `--distribution`: spatial layout of boxes: `uniform`, `clustered`, `grid`, `packed` (default `uniform`)
	- `grid`: near-square grid (low overlap)
	- `packed`: jittered grid with enlarged boxes for high overlap
- `--size-dist`: size distribution scheme: `uniform` (independent uniform sampling) or `skewed` (mixture of many small + few large) (default `uniform`)
- `--big-fraction`: fraction of boxes that are considered "large" when `--size-dist=skewed` (default 0.05)
- `--big-size-mult`: multiplier on `--max-size` for large boxes (clamped to world) (default 3.0)
- `--occupancy`: approximate target occupancy ratio = (sum of box areas)/(world area); boxes are uniformly rescaled post generation to approach this value.
- `--packed-overlap-mult`: size multiplier used only for `packed` distribution to inflate boxes (default 1.5)
- `--seed`: RNG seed for reproducibility
- `--out`: output file base path without extension (default `testcase/0`)

### Notes

- Boxes always lie within `[0,width] x [0,height]`.
- Occupancy scaling attempts to match the target; due to clamping at world boundaries the final occupancy printed may be slightly lower.
- In `packed` distribution, larger `--packed-overlap-mult` increases overlaps but extreme values may saturate occupancy early.
- If `max-size` exceeds the world bounds, it’s reduced to fit; `min-size` is adjusted if necessary to keep `min <= max`.

## Testcases
Pre-generated testcases are available in the `testcase/` directory for convenience.
| Testcase         | Distribution | Config |
|------------------|--------------|--------|
| 1  | Sample |100 boxes, uniform distribution |
| 2-6| Edge cases | Hand-crafted edge cases |
| 11 | Sparse uniform | 100k boxes, uniform sparse (low occupancy ~0.05). Benchmark sweep minimal overlaps vs hashing empty-cell overhead |
| 12 | Dense uniform | 100k boxes, uniform dense (high occupancy ~0.9). Stress broad-phase pair explosion; compare hashing vs sweep cost scaling |
| 13 | Clustered medium occupancy  | 100k boxes, clustered medium occupancy (~0.4). Hot spots highlight hashing cell concentration vs sweep sorting locality |
| 14 | Packed high-overlap | 100k boxes, packed high-overlap (occupancy ~0.95). Worst-case overlap load for both; hashing duplicate cell listings vs sweep interval checks |
| 15 | Grid low-overlap baseline | 100k boxes, grid low-overlap baseline (near 0.15 occupancy). Ideal for sweep (few active intervals) and shows hashing overhead when few collisions occur |
| 16 | Skewed sizes few huge boxes | 100k boxes, uniform skewed sizes (1% huge, size mult 5). Tests impact of large boxes spanning many hash cells vs sweep long intervals |
| 17 | Wide world | 120k boxes, uniform in very wide world (width>>height). Sort-and-sweep excels on X; hashing cell aspect ratio sensitivity |
| 18 | Tall world | 120k boxes, uniform in very tall world (height>>width). Complement to 17, Y-axis sweep vs hash distribution |
| 19 | Packed + skewed | 150k boxes, packed + skewed (few huge boxes + dense small). Mixed stress: large cell coverage + local density |
| 20 | Moderate occupancy | 200k boxes, uniform moderate occupancy (~0.4). Scaling test for algorithm throughput/memory |

### Generating Large-Scale Testcases
To generate the large testcases (11–20), use the helper script:

```
# generate all 11..20
scripts/generate_large_testcases.sh

# or generate selected ones
scripts/generate_large_testcases.sh 12 15 20
```

Notes:
- Seeds and parameters in the script match the table above; tweak the script if you want different seeds.
- Some occupancy targets may settle slightly below requested due to world boundary clamping.

### Comparison Rationale
- Sparse vs Dense: Sort-and-sweep cost scales with active interval overlaps; hashing may pay constant per cell even if empty.
- Clustered: Highlights how hashing benefits when collisions are spatially localized; sweep still handles via ordering but can see worse interval lifetimes.
- Packed: Approaches worst-case collision counts; evaluates broad-phase pruning limits.
- Grid: Near best-case for sweep (short interval overlap windows) and reveals hashing overhead baseline.
- Skewed sizes: Large boxes stress hashing (multi-cell insertions) and sweep (long spans increasing active set size).
- Extreme aspect ratios: Sort-and-sweep excels along dominant axis; hashing may require tuned cell sizes/aspect.
- Mixed stress: Combines size skew + dense packing to explore algorithm robustness.
- Throughput scaling: Measures algorithmic complexity trends at higher N.

## Visualize a dataset

Render the dataset to a PNG image:

```
python viz.py --in testcase/1.in --out testcase/1.png --dpi 160
```

Render with highlighted colliding pairs from a `.out` file:

```
python viz.py --in testcase/1.in --pairs testcase/1.out --out testcase/1_highlighted.png --dpi 160
```

### Note
- The generator uses only the Python standard library; the visualizer requires `matplotlib`.
- Advised to use conda to manage dependencies.
- Might run slowly for very large datasets (testcases 11-20).