.PHONY: install clean eda process data cv cv-local train train-local evaluate

# Install all required R packages (run once before anything else).
install:
	Rscript src/install_packages.R

# 01: load raw Stata files, apply exclusions, sentinel recoding, pool → parquet.
clean:
	Rscript scripts/01_clean-data.R

# 02: per-variable stats, missingness report, target distribution plot.
#     Requires: make clean
eda:
	Rscript scripts/02_eda.R

# 03: categorical encoding, NA handling, log target → processed parquet.
#     Requires: make clean
process:
	Rscript scripts/03_process-data.R

# Full data pipeline: 01 → 02 → 03.
data:
	Rscript scripts/01_clean-data.R && Rscript scripts/02_eda.R && Rscript scripts/03_process-data.R

# Submit all 9 CV model jobs + 1 combine job on HPC (with SLURM dependencies).
# Model jobs run sequentially (N_CORES=1) to avoid OOM from fork-based parallelism.
# Requires: make data
cv:
	mkdir -p slurm_logs
	bash slurm/submit_all_cv.sh

# Run all 9 CV models + combine locally (no SLURM), fully sequential.
# Slow but useful for testing.  Requires: make data
cv-local:
	Rscript scripts/04_model-comparison.R && Rscript scripts/05_combine_cv.R

# Train the best model (by CV RMSLE) on the full dataset and save to models/.
# Requires: make cv  (and wait for combine job to finish)
train:
	mkdir -p slurm_logs models
	sbatch --mem=32G slurm/train_best.sh

# Train the best model locally (no SLURM).  Requires: make cv or make cv-local
train-local:
	Rscript scripts/06_train_best.R

# Prep test.xlsx (07) then run model and write RMSLE (08).
# Requires: make data + make train-local (or make train on HPC)
evaluate:
	Rscript scripts/07_prep-test.R && Rscript scripts/08_evaluate.R
