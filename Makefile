.PHONY: clean train train-local

clean:
	Rscript -e "source('src/install_packages.R')" && Rscript scripts/01_clean-data.R && Rscript scripts/03_process-data.R

# Submit six Slurm array tasks (one tuned model each); run from repo root on the cluster login/submit node.
train:
	sbatch slurm/train_model_comparison.sh

# Run all six models in one local R session (no Slurm).
train-local:
	Rscript -e "source('src/install_packages.R')" && Rscript scripts/04_model-comparison.R
