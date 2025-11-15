#!/usr/bin/env bash
set -Eeuo pipefail

# Generate large-scale AABB datasets for testcases 11-20.
# Usage:
#   scripts/generate_large_testcases.sh           # generate all 11..20
#   scripts/generate_large_testcases.sh 12 15 20  # generate selected IDs

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

gen_11() { python gen.py --n 100000 --distribution uniform --width 4000 --height 4000 \
  --min-size 0.5 --max-size 6 --occupancy 0.05 --out testcase/11 --seed 11; }

gen_12() { python gen.py --n 100000 --distribution uniform --width 1000 --height 1000 \
  --min-size 0.5 --max-size 8 --occupancy 0.9 --out testcase/12 --seed 12; }

gen_13() { python gen.py --n 100000 --distribution clustered --width 2000 --height 2000 \
  --min-size 0.5 --max-size 10 --occupancy 0.4 --out testcase/13 --seed 13; }

gen_14() { python gen.py --n 100000 --distribution packed --packed-overlap-mult 1.9 \
  --width 1200 --height 1200 --min-size 0.5 --max-size 6 --occupancy 0.95 \
  --out testcase/14 --seed 14; }

gen_15() { python gen.py --n 100000 --distribution grid --width 1800 --height 1800 \
  --min-size 0.5 --max-size 5 --occupancy 0.15 --out testcase/15 --seed 15; }

gen_16() { python gen.py --n 100000 --distribution uniform --size-dist skewed --big-fraction 0.01 --big-size-mult 5 \
  --width 2500 --height 2500 --min-size 0.5 --max-size 6 --occupancy 0.3 --out testcase/16 --seed 16; }

gen_17() { python gen.py --n 120000 --distribution uniform --width 100000 --height 12 \
  --min-size 0.2 --max-size 1.2 --occupancy 0.5 --out testcase/17 --seed 17; }

gen_18() { python gen.py --n 120000 --distribution uniform --width 12 --height 100000 \
  --min-size 0.2 --max-size 1.2 --occupancy 0.5 --out testcase/18 --seed 18; }

gen_19() { python gen.py --n 150000 --distribution packed --packed-overlap-mult 1.7 --size-dist skewed \
  --big-fraction 0.02 --big-size-mult 4 --width 1600 --height 1600 --min-size 0.5 --max-size 7 \
  --occupancy 0.85 --out testcase/19 --seed 19; }

gen_20() { python gen.py --n 200000 --distribution uniform --width 3000 --height 3000 \
  --min-size 0.5 --max-size 6 --occupancy 0.4 --out testcase/20 --seed 20; }

run_one() {
  local id="$1"
  echo "[generate] testcase/${id}.in"
  case "$id" in
    11) gen_11 ;;
    12) gen_12 ;;
    13) gen_13 ;;
    14) gen_14 ;;
    15) gen_15 ;;
    16) gen_16 ;;
    17) gen_17 ;;
    18) gen_18 ;;
    19) gen_19 ;;
    20) gen_20 ;;
    *) echo "Unknown testcase id: $id" >&2; exit 1 ;;
  esac
}

if [[ $# -eq 0 ]]; then
  # generate all
  for id in {11..20}; do
    run_one "$id"
  done
else
  for id in "$@"; do
    run_one "$id"
  done
fi
