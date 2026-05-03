#!/bin/bash
#SBATCH --partition=ondemand
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4GB
#SBATCH --time=24:00:00
#SBATCH --mail-user=reny23@wfu.edu
#SBATCH --mail-type=END,FAIL
#SBATCH --account=ecn372
#SBATCH --job-name=meps-combine
#SBATCH --output=slurm_logs/combine_%j.out
#SBATCH --error=slurm_logs/combine_%j.err
#
# Combine all per-model CV summaries into a single leaderboard CSV and plot.
# Submitted by submit_all_cv.sh with --dependency=afterok on all 9 model jobs.

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$(pwd)}"

module load apps/r/4.3.3

echo "JOB_ID = ${SLURM_JOB_ID:-local}"

Rscript scripts/05_combine_cv.R

echo "Done: combine job ${SLURM_JOB_ID:-local}"
