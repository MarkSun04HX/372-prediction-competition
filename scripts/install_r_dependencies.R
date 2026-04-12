#!/usr/bin/env Rscript
# One-shot CRAN installs for this repo (run once per machine / R library).

pkgs <- c("haven", "arrow", "dplyr", "jsonlite", "glmnet", "irlba")
miss <- pkgs[!vapply(pkgs, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
if (length(miss)) {
  install.packages(miss, repos = "https://cloud.r-project.org")
}
message("OK: ", paste(pkgs, collapse = ", "))
