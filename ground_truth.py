#!/usr/bin/env python3
"""
Compute ground-truth colliding AABB pairs using brute-force O(N^2).

Reads the SoA binary format produced by `gen.py` (magic "AASO").
Outputs a CSV with rows: id1,id2 (id1 < id2).

Usage:
  python ground_truth.py --in testcase/aabbs_soa.bin --out testcase/pairs.csv

Options:
  --force    skip the safety N^2 warning for large N
"""

from __future__ import annotations

import argparse
import csv
import sys
from typing import List, Tuple

from aabb_io import read_soa_arrays


def intersects(i: int, j: int, min_x, min_y, max_x, max_y) -> bool:
    # AABB intersection (closed intervals): overlap in x and y
    return not (max_x[i] < min_x[j] or max_x[j] < min_x[i] or max_y[i] < min_y[j] or max_y[j] < min_y[i])


def parse_args():
    p = argparse.ArgumentParser(description="Brute-force ground-truth AABB pairs (SoA input)")
    p.add_argument("--in", dest="inp", required=True, help="Input SoA .bin file (AASO)")
    p.add_argument("--out", dest="out", default="testcase/pairs.csv", help="Output CSV path")
    p.add_argument("--force", action="store_true", help="Skip N^2 safety check for large N")
    return p.parse_args()


def brute_force_pairs(min_x, min_y, max_x, max_y, n) -> List[Tuple[int, int]]:
    pairs: List[Tuple[int, int]] = []
    # brute-force
    for i in range(n):
        for j in range(i + 1, n):
            if intersects(i, j, min_x, min_y, max_x, max_y):
                pairs.append((i, j))
    return pairs


def main():
    args = parse_args()
    min_x, min_y, max_x, max_y, n, w, h = read_soa_arrays(args.inp)
    print(f"Loaded {n} boxes (world {w}x{h})")

    max_checks = 200_000_000  # heuristic: avoid >200M checks unless forced
    est_checks = n * (n - 1) // 2
    if est_checks > max_checks and not args.force:
        print(f"Refusing to run brute-force: estimated {est_checks:,} pair checks > {max_checks:,}. Use --force to override.")
        sys.exit(2)

    pairs: List[Tuple[int, int]] = brute_force_pairs(min_x, min_y, max_x, max_y, n)

    print(f"Found {len(pairs)} colliding pairs")

    # write CSV
    with open(args.out, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id1", "id2"])
        for a, b in pairs:
            writer.writerow([a, b])

    print(f"Wrote pairs to {args.out}")