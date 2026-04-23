#!/bin/bash
#SBATCH --partition=ondemand
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6
#SBATCH --mem=16GB
#SBATCH --time=00-02:00:00
#SBATCH --array=1-6
#SBATCH --mail-user=reny23@wfu.edu
#SBATCH --mail-type=END,FAIL
#SBATCH --account=ecn372
#SBATCH --job-name=meps-cv
#SBATCH --output=slurm_cv_%A_%a.out
#SBATCH --error=slurm_cv_%A_%a.err
#
# One array task per model (see MODEL_INDEX mapping in scripts/04_model-comparison.R).
# SLURM sets SLURM_ARRAY_TASK_ID=1..6; R reads it and runs only that model.
# With --cpus-per-task=5 and N_FOLDS=5, tune_grid parallelizes one worker per fold
# (parallel_over = "resamples"); each fold uses THREADS_PER_MODEL = N_CORES %/% N_FOLDS.
#
# Submit from the repo root (directory that contains scripts/ and src/):
#   make train
#   sbatch slurm/train_model_comparison.sh
#
# Optional: use 6 CPUs if your site recommends reserving one core for overhead:
#   #SBATCH --cpus-per-task=6
# and then: export N_CORES=5

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$(pwd)}"

export MODEL_INDEX="${SLURM_ARRAY_TASK_ID}"
export N_FOLDS="${N_FOLDS:-5}"

echo "JOB_ID=${SLURM_JOB_ID:-} ARRAY_JOB_ID=${SLURM_ARRAY_JOB_ID:-} TASK_ID=${SLURM_ARRAY_TASK_ID:-}"
echo "cpus-per-task=${SLURM_CPUS_PER_TASK:-} MODEL_INDEX=${MODEL_INDEX}"

Rscript -e "source('src/install_packages.R')"
Rscript scripts/04_model-comparison.R

echo "Done task ${SLURM_ARRAY_TASK_ID:-}"
