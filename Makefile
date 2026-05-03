.PHONY: install clean eda process data train train-local

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

# Submit six Slurm array tasks (one tuned model each); run on cluster login node.
train:
	mkdir -p slurm_logs
	sbatch slurm/train_model_comparison.sh

# Run all six models in one local R session (no Slurm).
train-local:
	Rscript scripts/04_model-comparison.R
