#!/bin/bash
#SBATCH --partition=ondemand
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32GB          # default; override at submit time: sbatch --mem=12G ...
#SBATCH --time=24:00:00     # 24 h wall clock
#SBATCH --mail-user=reny23@wfu.edu
#SBATCH --mail-type=END,FAIL
#SBATCH --account=ecn372
#SBATCH --output=slurm_logs/cv_%j.out
#SBATCH --error=slurm_logs/cv_%j.err
#
# Parameterized single-model CV job.  One submission per model; no --array.
#
# Required env variable (set via --export or the submit_all_cv.sh orchestrator):
#   MODEL_INDEX   integer 1-9  (see mapping in scripts/04_model-comparison.R)
#
# Memory guidance (set --mem at submit time via submit_all_cv.sh):
#   Ridge / Lasso / ElasticNet  : 12 GB
#   LightGBM                    : 16 GB
#   XGBoost                     : 20 GB
#   Two-part any                : 24 GB
#   Random Forest               : 32 GB
#
# Sequential execution (N_CORES=1) means only one fold runs at a time — no
# fork-based data duplication.  With 6 workers forking, a 1.2 GB dataset
# becomes ~7 GB of copies before any model weights are loaded.
#
# Submit via: bash slurm/submit_all_cv.sh   (from repo root)
# Or manually: MODEL_INDEX=4 sbatch --mem=32G slurm/train_one_model.sh

set -euo pipefail

cd "${SLURM_SUBMIT_DIR:-$(pwd)}"

module load apps/r/4.3.3

# Force sequential execution — critical for HPC memory safety.
export N_CORES=1
export N_FOLDS="${N_FOLDS:-5}"
export SEED="${SEED:-42}"

# MODEL_INDEX must be supplied by the caller (via --export or environment).
if [[ -z "${MODEL_INDEX:-}" ]]; then
  echo "ERROR: MODEL_INDEX is not set. Pass it via --export=ALL,MODEL_INDEX=<n>."
  exit 1
fi

echo "=============================="
echo "JOB_ID        = ${SLURM_JOB_ID:-local}"
echo "MODEL_INDEX   = ${MODEL_INDEX}"
echo "N_CORES       = ${N_CORES}"
echo "N_FOLDS       = ${N_FOLDS}"
echo "MEM (SLURM)   = ${SLURM_MEM_PER_NODE:-unknown} MB"
echo "CPUS (SLURM)  = ${SLURM_CPUS_PER_TASK:-1}"
echo "=============================="

Rscript -e "source('src/install_packages.R')"
Rscript scripts/04_model-comparison.R

echo "Done: MODEL_INDEX=${MODEL_INDEX} job=${SLURM_JOB_ID:-local}"
