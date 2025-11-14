#!/usr/bin/env python3
"""
Utilities for reading AABB SoA binary files (AASO).

Provides a small, dependency-free reader that other scripts can import.
"""

from __future__ import annotations

import struct
from typing import List, Tuple


def read_soa_arrays(path: str) -> Tuple[List[float], List[float], List[float], List[float], int, float, float]:
    """Read SoA AABB binary (magic 'AASO').

    Returns: min_x, min_y, max_x, max_y, n, world_w, world_h
    """
    with open(path, "rb") as f:
        hdr = f.read(24)
        if len(hdr) != 24:
            raise ValueError("SoA file too small for header")
        magic, version, count, world_w, world_h, _res = struct.unpack("<4sIIffI", hdr)
        if magic != b"AASO":
            raise ValueError("Invalid SoA magic; expected b'AASO'")
        if version != 1:
            raise ValueError(f"Unsupported SoA version: {version}")
        n = int(count)

        def read_f32(n_):
            if n_ == 0:
                return []
            buf = f.read(4 * n_)
            if len(buf) != 4 * n_:
                raise ValueError("Unexpected EOF reading SoA array")
            return list(struct.unpack("<" + ("f" * n_), buf))

        min_x = read_f32(n)
        min_y = read_f32(n)
        max_x = read_f32(n)
        max_y = read_f32(n)

    return min_x, min_y, max_x, max_y, n, float(world_w), float(world_h)


def read_soa_boxes(path: str):
    """Helper that returns list of boxes (min_x,min_y,max_x,max_y) and world dims."""
    min_x, min_y, max_x, max_y, n, w, h = read_soa_arrays(path)
    boxes = list(zip(min_x, min_y, max_x, max_y))
    return boxes, w, h
