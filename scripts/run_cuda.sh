#!/bin/bash
#SBATCH -A ACD114118
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --gpus-per-node=1
#SBATCH -t 5
#SBATCH --output=log/cuda_%j.out

srun ./bin/cuda $1 $2
