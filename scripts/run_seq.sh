#!/bin/bash
#SBATCH -A ACD114118
#SBATCH -n 1
#SBATCH -c 1
#SBATCH -t 1
#SBATCH --output=log/seq_%j.out

srun ./bin/seq $1 $2