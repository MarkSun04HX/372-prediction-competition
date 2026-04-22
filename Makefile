.PHONY: clean

clean:
	Rscript -e "source('src/install_packages.R')" && Rscript scripts/01_clean-data.R && Rscript scripts/03_process-data.R
