# src/install_packages.R
# Check and install all R packages required by this project.
# Source this file or run it directly before running any pipeline script.
#
# Usage:
#   Rscript src/install_packages.R

pkgs <- c(
  "haven",     # read Stata .dta files
  "arrow",     # read/write Parquet
  "dplyr",     # bind_rows and data manipulation
  "glmnet",    # lasso / elastic net
  "irlba",     # truncated SVD / PCA
  "ranger",    # random forest
  "xgboost",   # gradient boosting
  "lightgbm",  # gradient boosting (LightGBM)
  "catboost",  # gradient boosting (CatBoost)
  "e1071",     # naive Bayes
  "rpart",     # regression trees
  "ggplot2",   # EDA plots
  "jsonlite"   # JSON manifest files
)

missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)]

if (length(missing) == 0L) {
  message("All packages already installed.")
} else {
  message("Installing missing packages: ", paste(missing, collapse = ", "))
  install.packages(
    setdiff(missing, c("lightgbm", "catboost")),
    repos = "https://cloud.r-project.org"
  )

  if ("lightgbm" %in% missing) {
    if (!requireNamespace("lightgbm", quietly = TRUE)) {
      install.packages("lightgbm", repos = "https://cloud.r-project.org")
    }
  }

  if ("catboost" %in% missing) {
    if (!requireNamespace("catboost", quietly = TRUE)) {
      message(
        "catboost not on CRAN. Install manually with:\n",
        "  devtools::install_url('https://github.com/catboost/catboost/releases/download/v1.2.7/catboost-R-Darwin-1.2.7.tgz')\n",
        "Skipping catboost for now."
      )
    }
  }

  still_missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(still_missing) > 0L) {
    message("Still not available after install attempt: ", paste(still_missing, collapse = ", "))
  } else {
    message("All packages now available.")
  }
}
