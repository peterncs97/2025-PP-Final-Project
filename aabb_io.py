#!/usr/bin/env python3
"""
Utilities for reading AABB plain text files.

Provides a small, dependency-free reader that other scripts can import.
"""

import os
import csv
import struct
from typing import List, Tuple


Box = Tuple[float, float, float, float]  # (min_x, min_y, max_x, max_y)


def write_boxes(path: str, boxes: List[Box]) -> None:
    """Write boxes in plain text format.

    Format:
    - First line: number of boxes (N)
    - Next N lines: min_x min_y max_x max_y (space-separated floats)
    
    """
    # ensure parent dir exists
    os.makedirs(os.path.dirname(path), exist_ok=True) if os.path.dirname(path) else None

    with open(path, "w") as f:
        # number of boxes
        n = len(boxes)
        f.write(f"{n}\n")
        # one box per line
        for b in boxes:
            f.write(f"{float(b[0])} {float(b[1])} {float(b[2])} {float(b[3])}\n")


def read_boxes(path: str) -> List[Box]:
    """Helper that returns list of boxes."""
    boxes: List[Box] = []
    with open(path, "r") as f:
        n = int(f.readline().strip())
        
        if n <= 0:
            return boxes
        
        for _ in range(n):
            line = f.readline().strip()
            if not line:
                break
            parts = line.split()
            if len(parts) != 4:
                raise ValueError("Invalid box line format")
            min_x, min_y, max_x, max_y = map(float, parts)
            boxes.append((min_x, min_y, max_x, max_y))
    return boxes


def read_pairs(path: str) -> List[Tuple[int, int]]:
    """Read ID pairs from txt file."""
    pairs_list: List[Tuple[int, int]] = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 2:
                raise ValueError("Invalid pair line format")
            a, b = map(int, parts)
            pairs_list.append((a, b))
            
    return pairs_list