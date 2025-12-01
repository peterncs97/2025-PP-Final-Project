#!/bin/bash
#SBATCH -A ACD114118
#SBATCH -n 1
#SBATCH -c 1
#SBATCH --gres=gpu:1
#SBATCH -t 5
#SBATCH --output=log/cuda_%j.out

srun ./bin/cuda $1 $2
