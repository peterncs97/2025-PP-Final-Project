#!/usr/bin/env python3
"""
Utilities for reading AABB SoA binary files (AASO).

Provides a small, dependency-free reader that other scripts can import.
"""

import struct
from typing import List, Tuple


def write_soa_bin(path: str, boxes: List[Box], width: float, height: float) -> None:
	"""Write Structure-of-Arrays (SoA) binary format.

	Layout (little-endian):
	- Header (24 bytes): magic="AASO" (4s), version(uint32)=1, count(uint32)=N,
		world_width(float32), world_height(float32), reserved(uint32)=0
	- Arrays (float32[N] each): min_x[], min_y[], max_x[], max_y[]
	"""
	os.makedirs(os.path.dirname(path), exist_ok=True) if os.path.dirname(path) else None
	n = len(boxes)
	min_xs = [float(b[0]) for b in boxes]
	min_ys = [float(b[1]) for b in boxes]
	max_xs = [float(b[2]) for b in boxes]
	max_ys = [float(b[3]) for b in boxes]

	with open(path, "wb") as f:
		header = struct.pack("<4sIIffI", b"AASO", 1, n, float(width), float(height), 0)
		f.write(header)
		# write arrays back-to-back
		f.write(struct.pack("<" + "f" * n, *min_xs)) if n else None
		f.write(struct.pack("<" + "f" * n, *min_ys)) if n else None
		f.write(struct.pack("<" + "f" * n, *max_xs)) if n else None
		f.write(struct.pack("<" + "f" * n, *max_ys)) if n else None


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
