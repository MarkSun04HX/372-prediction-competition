#!/bin/bash
# submit_all_cv.sh
# Orchestrator: submit all 9 CV model jobs + 1 combine job with SLURM dependencies.
#
# Dependency graph:
#   ridge, lasso, elasticnet, random_forest, xgboost, lightgbm  → submitted immediately
#   two_part_rf_rf   → depends on random_forest (needs its cv_full.rds)
#   two_part_rf_xgb  → depends on xgboost
#   two_part_rf_en   → depends on elasticnet
#   combine          → depends on ALL 9 model jobs
#
# Usage (from repo root):
#   bash slurm/submit_all_cv.sh
#   make cv            ← calls this script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"
mkdir -p slurm_logs

SEED="${SEED:-42}"
N_FOLDS="${N_FOLDS:-5}"

submit() {
  # submit <mem_GB> <job_name> <MODEL_INDEX> [--dependency=...]
  local mem=$1; local jname=$2; local midx=$3; shift 3
  sbatch \
    --parsable \
    --mem="${mem}G" \
    --job-name="${jname}" \
    --export="ALL,MODEL_INDEX=${midx},N_CORES=1,SEED=${SEED},N_FOLDS=${N_FOLDS}" \
    "$@" \
    slurm/train_one_model.sh
}

echo "Submitting single-stage model jobs (1-6) ..."
J1=$(submit 12  meps-ridge   1)
J2=$(submit 12  meps-lasso   2)
J3=$(submit 24  meps-enet    3)
J4=$(submit 32  meps-rf      4)
J5=$(submit 20  meps-xgb     5)
J6=$(submit 16  meps-lgbm    6)

echo "  ridge        job $J1"
echo "  lasso        job $J2"
echo "  elasticnet   job $J3"
echo "  random_forest job $J4"
echo "  xgboost      job $J5"
echo "  lightgbm     job $J6"

echo ""
echo "Submitting two-part model jobs (7-9) with dependencies ..."
J7=$(submit 24  meps-tp-rf-rf  7 --dependency=afterok:"${J4}")
J8=$(submit 24  meps-tp-rf-xgb 8 --dependency=afterok:"${J5}")
J9=$(submit 16  meps-tp-rf-en  9 --dependency=afterok:"${J3}")

echo "  two_part_rf_rf  job $J7  (after $J4)"
echo "  two_part_rf_xgb job $J8  (after $J5)"
echo "  two_part_rf_en  job $J9  (after $J3)"

echo ""
echo "Submitting combine job (after all 9) ..."
J_ALL="${J1}:${J2}:${J3}:${J4}:${J5}:${J6}:${J7}:${J8}:${J9}"
J_COMBINE=$(sbatch \
  --parsable \
  --dependency=afterok:"${J_ALL}" \
  slurm/combine_cv.sh)

echo "  combine      job $J_COMBINE"

echo ""
echo "All submitted. Monitor with:"
echo "  squeue -u \$USER"
echo "  tail -f slurm_logs/cv_<JOB_ID>.out"
