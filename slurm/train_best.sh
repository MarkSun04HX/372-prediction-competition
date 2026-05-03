#!/bin/bash
#SBATCH --partition=ondemand
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32GB          # sized for worst-case best model (RF)
#SBATCH --time=24:00:00
#SBATCH --mail-user=reny23@wfu.edu
#SBATCH --mail-type=END,FAIL
#SBATCH --account=ecn372
#SBATCH --job-name=meps-train-best
#SBATCH --output=slurm_logs/train_best_%j.out
#SBATCH --error=slurm_logs/train_best_%j.err
#
# Fit the best model (by RMSLE) on the full processed dataset.
# Reads outputs/cv/cv_summary_all.csv — run `make cv` first.
# Saves trained model to models/{best_model}/.

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$(pwd)}"

module load apps/r/4.3.3

export N_CORES=1
export SEED="${SEED:-42}"

echo "JOB_ID = ${SLURM_JOB_ID:-local}"

Rscript -e "source('src/install_packages.R')"
Rscript scripts/06_train_best.R

echo "Done: train_best job ${SLURM_JOB_ID:-local}"
