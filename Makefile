.PHONY: clean

clean:
	Rscript -e "source('src/install_packages.R')" && Rscript scripts/01_clean-data.R
