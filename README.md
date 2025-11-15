# Collision Detection
This repository contains code for generating datasets of 2D axis-aligned bounding boxes (AABBs) and implementing various collision detection algorithms to find overlapping box pairs.

# Dataset

## Dataset Format
The generated dataset is a text file (`.in`) with the following format:
- First line: single integer `N`, the number of boxes.
- Next `N` lines: each line contains four floating-point numbers `min_x min_y max_x max_y`, representing the coordinates of the bottom-left and top-right corners of each axis-aligned bounding box (AABB).


## Dataset Generation

Generate a dataset with 100 boxes in a 100x100 world with box sizes between 0.5 and 4, using a uniform distribution, and save to `testcase/0.in`:

```
python ./gen.py --n 100 --width 100 --height 100 --min-size 0.5 --max-size 4 --distribution uniform --out testcase/0 --seed 42
```

### Options

- `--n` (required): number of boxes
- `--width`, `--height`: world dimensions (default 100x100)
- `--min-size`, `--max-size`: box edge length range (default 0.5–5.0)
- `--distribution`: `uniform` or `clustered` (default `uniform`)
- `--seed`: RNG seed for reproducibility
- `--out`: output file base path without extension (default `testcase/0`)

### Notes

- Boxes are generated entirely within `[0,width] x [0,height]` and may overlap (broad-phase friendly).
- If `max-size` exceeds the world bounds, it’s reduced to fit; `min-size` is adjusted if necessary to keep `min <= max`.

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