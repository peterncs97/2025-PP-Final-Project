#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import random
import struct
from typing import List, Tuple


Box = Tuple[float, float, float, float]  # (min_x, min_y, max_x, max_y)


def clamp(v: float, lo: float, hi: float) -> float:
	return max(lo, min(hi, v))


def gen_uniform(
	n: int,
	width: float,
	height: float,
	min_size: float,
	max_size: float,
) -> List[Box]:
	boxes: List[Box] = []
	for _ in range(n):
		hw = random.uniform(min_size * 0.5, max_size * 0.5)
		hh = random.uniform(min_size * 0.5, max_size * 0.5)
		# ensure inside world bounds
		x = random.uniform(hw, max(hw, width - hw))
		y = random.uniform(hh, max(hh, height - hh))
		min_x = x - hw
		max_x = x + hw
		min_y = y - hh
		max_y = y + hh
		# clamp to be safe
		min_x, max_x = clamp(min_x, 0.0, width), clamp(max_x, 0.0, width)
		min_y, max_y = clamp(min_y, 0.0, height), clamp(max_y, 0.0, height)
		# enforce ordering
		if max_x < min_x:
			min_x, max_x = max_x, min_x
		if max_y < min_y:
			min_y, max_y = max_y, min_y
		boxes.append((min_x, min_y, max_x, max_y))
	return boxes


def gen_clustered(
	n: int,
	width: float,
	height: float,
	min_size: float,
	max_size: float,
	k_clusters: int = 4,
	pos_sigma_ratio: float = 0.05,
) -> List[Box]:
	boxes: List[Box] = []
	# choose cluster centers
	centers = [
		(
			random.uniform(0.15 * width, 0.85 * width),
			random.uniform(0.15 * height, 0.85 * height),
		)
		for _ in range(max(1, k_clusters))
	]
	sigma_x = width * pos_sigma_ratio
	sigma_y = height * pos_sigma_ratio

	for _ in range(n):
		cx, cy = random.choice(centers)
		hw = random.uniform(min_size * 0.5, max_size * 0.5)
		hh = random.uniform(min_size * 0.5, max_size * 0.5)
		# sample around center with gaussian, then clamp to fit
		x = clamp(random.gauss(cx, sigma_x), hw, max(hw, width - hw))
		y = clamp(random.gauss(cy, sigma_y), hh, max(hh, height - hh))
		min_x = x - hw
		max_x = x + hw
		min_y = y - hh
		max_y = y + hh
		# clamp to be safe
		min_x, max_x = clamp(min_x, 0.0, width), clamp(max_x, 0.0, width)
		min_y, max_y = clamp(min_y, 0.0, height), clamp(max_y, 0.0, height)
		# enforce ordering
		if max_x < min_x:
			min_x, max_x = max_x, min_x
		if max_y < min_y:
			min_y, max_y = max_y, min_y
		boxes.append((min_x, min_y, max_x, max_y))
	return boxes


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


def positive(val: float, name: str) -> None:
	if val <= 0:
		raise ValueError(f"{name} must be positive; got {val}")


def parse_args() -> argparse.Namespace:
	p = argparse.ArgumentParser(description="Generate static 2D AABB dataset (single frame)")
	p.add_argument("--n", type=int, required=True, help="Number of AABBs to generate")
	p.add_argument("--width", type=float, default=100.0, help="World width")
	p.add_argument("--height", type=float, default=100.0, help="World height")
	p.add_argument("--min-size", type=float, default=0.5, help="Minimum box size (edge length)")
	p.add_argument("--max-size", type=float, default=5.0, help="Maximum box size (edge length)")
	p.add_argument(
		"--distribution",
		choices=["uniform", "clustered"],
		default="uniform",
		help="Position distribution for box centers",
	)
	p.add_argument("--seed", type=int, default=None, help="RNG seed for reproducibility")
	p.add_argument(
		"--out",
		type=str,
		default=os.path.join("testcase", "aabbs"),
		help="Output file base path (without extension)",
	)
	return p.parse_args()


def main() -> None:
	args = parse_args()

	if args.seed is not None:
		random.seed(args.seed)

	# validate args
	if args.n <= 0:
		raise ValueError("--n must be > 0")
	positive(args.width, "--width")
	positive(args.height, "--height")
	positive(args.min_size, "--min-size")
	positive(args.max_size, "--max-size")
	if args.min_size > args.max_size:
		raise ValueError("--min-size must be <= --max-size")
	
 	# ensure max_size isn't bigger than world in either dimension
	max_allowed = min(args.width, args.height)
	if args.max_size > max_allowed:
		# shrink to fit but keep ordering
		args.max_size = max_allowed
		if args.min_size > args.max_size:
			args.min_size = args.max_size

	# generate boxes
	if args.distribution == "uniform":
		boxes = gen_uniform(args.n, args.width, args.height, args.min_size, args.max_size)
	else:  # clustered
		boxes = gen_clustered(args.n, args.width, args.height, args.min_size, args.max_size)

	# store boxes as SoA binary
	base = args.out
	write_soa_bin(base + ".bin", boxes, width=args.width, height=args.height)
	print(f"Generated {len(boxes)} AABBs in world {args.width}x{args.height} using {args.distribution} distribution")
	print(f"Outputs: {base}.bin")


if __name__ == "__main__":
	main()

