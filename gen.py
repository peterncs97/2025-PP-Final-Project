#!/usr/bin/env python3

import argparse
import os
import random
import math
from typing import List, Tuple

from aabb_io import write_boxes

Box = Tuple[float, float, float, float]  # (min_x, min_y, max_x, max_y)


def clamp(v: float, lo: float, hi: float) -> float:
	return max(lo, min(hi, v))


def sample_size(
	min_size: float,
	max_size: float,
	width: float,
	height: float,
	size_dist: str,
	big_fraction: float,
	big_size_mult: float,
) -> Tuple[float, float]:
	"""Return half-width, half-height according to size distribution settings.

	For 'uniform', sizes are drawn independently uniform in [min_size/2, max_size/2].
	For 'skewed', most boxes are small (near min_size) while a fraction are large (up to big_size_mult * max_size, clamped to world).
	"""
	max_edge_world = min(width, height)
	if size_dist == "uniform":
		hw = random.uniform(min_size * 0.5, max_size * 0.5)
		hh = random.uniform(min_size * 0.5, max_size * 0.5)
		return hw, hh
	# skewed
	if random.random() < big_fraction:
		# big box
		big_max = min(max_edge_world, max_size * big_size_mult)
		edge = random.uniform(max_size * 0.5, big_max * 0.5)
	else:
		# small box (biased toward min_size, limit upper small size to 30% of range)
		upper_small = min(max_size, min_size + (max_size - min_size) * 0.3)
		edge = random.uniform(min_size * 0.5, upper_small * 0.5)
	# allow slight rectangular aspect ratio variation
	aspect = random.uniform(0.8, 1.25)
	hw = edge * aspect
	hh = edge / aspect
	return hw, hh


def gen_uniform(
	n: int,
	width: float,
	height: float,
	min_size: float,
	max_size: float,
	size_dist: str,
	big_fraction: float,
	big_size_mult: float,
) -> List[Box]:
	boxes: List[Box] = []
	for _ in range(n):
		hw, hh = sample_size(min_size, max_size, width, height, size_dist, big_fraction, big_size_mult)
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
	size_dist: str,
	big_fraction: float,
	big_size_mult: float,
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
		hw, hh = sample_size(min_size, max_size, width, height, size_dist, big_fraction, big_size_mult)
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


def gen_grid(
	n: int,
	width: float,
	height: float,
	min_size: float,
	max_size: float,
	size_dist: str,
	big_fraction: float,
	big_size_mult: float,
) -> List[Box]:
	"""Generate boxes laid out on a near-square grid (low overlap)."""
	boxes: List[Box] = []
	cols = math.ceil(math.sqrt(n * (width / height))) if height > 0 else n
	rows = math.ceil(n / cols) if cols > 0 else 1
	cell_w = width / cols
	cell_h = height / rows
	idx = 0
	for r in range(rows):
		for c in range(cols):
			if idx >= n:
				break
			hw, hh = sample_size(min_size, max_size, width, height, size_dist, big_fraction, big_size_mult)
			# keep box inside its cell to minimize overlap
			hw = min(hw, cell_w * 0.45)
			hh = min(hh, cell_h * 0.45)
			center_x = (c + 0.5) * cell_w
			center_y = (r + 0.5) * cell_h
			min_x = clamp(center_x - hw, 0.0, width)
			max_x = clamp(center_x + hw, 0.0, width)
			min_y = clamp(center_y - hh, 0.0, height)
			max_y = clamp(center_y + hh, 0.0, height)
			boxes.append((min_x, min_y, max_x, max_y))
			idx += 1
	return boxes


def gen_packed(
	n: int,
	width: float,
	height: float,
	min_size: float,
	max_size: float,
	size_dist: str,
	big_fraction: float,
	big_size_mult: float,
	packed_overlap_mult: float,
) -> List[Box]:
	"""Generate densely packed boxes producing high overlap.

	Strategy: place boxes on a jittered grid but enlarge their size by packed_overlap_mult
	(while staying within world bounds) so adjacent cells overlap.
	"""
	boxes: List[Box] = []
	cols = math.ceil(math.sqrt(n))
	rows = math.ceil(n / cols)
	cell_w = width / cols
	cell_h = height / rows
	idx = 0
	for r in range(rows):
		for c in range(cols):
			if idx >= n:
				break
			hw, hh = sample_size(min_size, max_size, width, height, size_dist, big_fraction, big_size_mult)
			# enlarge for overlap
			hw *= packed_overlap_mult
			hh *= packed_overlap_mult
			# jitter center within cell to vary overlaps
			jitter_x = random.uniform(-0.25, 0.25) * cell_w
			jitter_y = random.uniform(-0.25, 0.25) * cell_h
			center_x = (c + 0.5) * cell_w + jitter_x
			center_y = (r + 0.5) * cell_h + jitter_y
			# clamp center to keep some part in world
			center_x = clamp(center_x, 0.0 + hw, width - hw)
			center_y = clamp(center_y, 0.0 + hh, height - hh)
			min_x = center_x - hw
			max_x = center_x + hw
			min_y = center_y - hh
			max_y = center_y + hh
			boxes.append((min_x, min_y, max_x, max_y))
			idx += 1
	return boxes


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
		choices=["uniform", "clustered", "grid", "packed"],
		default="uniform",
		help="Spatial distribution of boxes",
	)
	p.add_argument(
		"--size-dist",
		choices=["uniform", "skewed"],
		default="uniform",
		help="Size distribution scheme",
	)
	p.add_argument("--big-fraction", type=float, default=0.05, help="Fraction of large boxes when --size-dist=skewed")
	p.add_argument("--big-size-mult", type=float, default=3.0, help="Max size multiplier for large boxes (clamped to world)")
	p.add_argument("--occupancy", type=float, default=None, help="Approx target occupancy (sum box areas / world area); boxes uniformly rescaled to approach this")
	p.add_argument("--packed-overlap-mult", type=float, default=1.5, help="Size multiplier applied in packed distribution to induce overlap")
	p.add_argument("--seed", type=int, default=None, help="RNG seed for reproducibility")
	p.add_argument(
		"--out",
		type=str,
		default=os.path.join("testcase", "0.in"),
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
	dist = args.distribution
	if dist == "uniform":
		boxes = gen_uniform(
			args.n, args.width, args.height, args.min_size, args.max_size,
			args.size_dist, args.big_fraction, args.big_size_mult,
		)
	elif dist == "clustered":
		boxes = gen_clustered(
			args.n, args.width, args.height, args.min_size, args.max_size,
			args.size_dist, args.big_fraction, args.big_size_mult,
		)
	elif dist == "grid":
		boxes = gen_grid(
			args.n, args.width, args.height, args.min_size, args.max_size,
			args.size_dist, args.big_fraction, args.big_size_mult,
		)
	elif dist == "packed":
		boxes = gen_packed(
			args.n, args.width, args.height, args.min_size, args.max_size,
			args.size_dist, args.big_fraction, args.big_size_mult,
			args.packed_overlap_mult,
		)
	else:
		raise ValueError(f"Unknown distribution: {dist}")

	def scale_to_occupancy(boxes: List[Box]) -> List[Box]:
		if args.occupancy is None:
			return boxes
		world_area = args.width * args.height
		if world_area <= 0:
			return boxes
		current_area = 0.0
		for b in boxes:
			current_area += (b[2] - b[0]) * (b[3] - b[1])
		if current_area <= 0:
			return boxes
		desired_area = args.occupancy * world_area
		if desired_area <= 0:
			return boxes
		scale = math.sqrt(desired_area / current_area)
		if scale == 1.0:
			return boxes
		new_boxes: List[Box] = []
		for (min_x, min_y, max_x, max_y) in boxes:
			cx = (min_x + max_x) * 0.5
			cy = (min_y + max_y) * 0.5
			hw = (max_x - min_x) * 0.5 * scale
			hh = (max_y - min_y) * 0.5 * scale
			# clamp extents to world
			hw = min(hw, cx, args.width - cx)
			hh = min(hh, cy, args.height - cy)
			new_boxes.append((cx - hw, cy - hh, cx + hw, cy + hh))
		return new_boxes

	boxes = scale_to_occupancy(boxes)
	final_area = sum((b[2]-b[0])*(b[3]-b[1]) for b in boxes)
	final_occupancy = final_area / (args.width * args.height) if args.width*args.height > 0 else 0.0

	# store boxes as .txt
	base = args.out
	write_boxes(base + ".in", boxes)
	print(
		f"Generated {len(boxes)} AABBs in world {args.width}x{args.height} "
		f"distribution={args.distribution} size_dist={args.size_dist} occupancy={final_occupancy:.4f}"
	)
	print(f"Outputs: {base}.in")


if __name__ == "__main__":
	main()

