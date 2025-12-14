#!/bin/bash
# Simple srun wrapper: run CUDA binary directly without job scheduling
# Usage: ./scripts/run_cuda_srun.sh <algorithm> <testcase>

./bin/cuda "$1" "$2"
