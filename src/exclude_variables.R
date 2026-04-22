# ECN372 competition exclusions (MEPS Section 2.5.11 + survey design).
# Canonical R implementation; source this file from R scripts.

meps_default_yy <- function() c("19", "20", "21", "22", "23")

meps_excluded_stems_yy <- function() {
  c(
    # ---- Total charges and expenditures by source of payment ----
    # NOTE: actual suffix pair is PTR/OTH (not OPR/OPU), consistent with all other categories
    "TOTTCH", "TOTEXP", "TOTSLF", "TOTMCR", "TOTMCD", "TOTPRV", "TOTVA", "TOTTRI",
    "TOTOFD", "TOTSTL", "TOTWCP", "TOTPTR", "TOTOTH", "TOTOSR",

    # ---- Office-based visits: counts ----
    "OBTOTV", "OBDRV", "OBOTHV", "OBCHIR", "OBNURS", "OBOPTO", "OBASST", "OBTHER",

    # ---- Office-based visits: expenditures ----
    # NOTE: actual suffix pair is PTR/OTH (not OPR/OPU); confirmed in 2019 & 2023 codebooks
    "OBVTCH", "OBVEXP", "OBVSLF", "OBVMCR", "OBVMCD", "OBVPRV", "OBVVA", "OBVTRI",
    "OBVOFD", "OBVSTL", "OBVWCP", "OBVPTR", "OBVOTH", "OBVOSR",

    # ---- Outpatient visits: counts + ambulatory surgery provider counts ----
    "OPTOTV", "OPDRV", "OPOTHV", "AMCHIR", "AMNURS", "AMOPT", "AMASST", "AMTHER",

    # ---- Outpatient facility expenditures ----
    "OPFTCH", "OPFEXP", "OPFSLF", "OPFMCR", "OPFMCD", "OPFPRV", "OPFVA", "OPFTRI",
    "OPFOFD", "OPFSTL", "OPFWCP", "OPFPTR", "OPFOTH", "OPFOSR",

    # ---- Outpatient doctor expenditures ----
    "OPDTCH", "OPDEXP", "OPDSLF", "OPDMCR", "OPDMCD", "OPDPRV", "OPDVA", "OPDTRI",
    "OPDOFD", "OPDSTL", "OPDWCP", "OPDPTR", "OPDOTH", "OPDOSR",

    # ---- Outpatient visit-level combined expenditures ----
    "OPVTCH", "OPVEXP", "OPVSLF", "OPVMCR", "OPVMCD", "OPVPRV", "OPVVA", "OPVTRI",
    "OPVOFD", "OPVSTL", "OPVWCP", "OPVPTR", "OPVOTH", "OPVOSR",

    # ---- Outpatient grand-total expenditures (OPT* group — missing from original) ----
    "OPTTCH", "OPTEXP", "OPTSLF", "OPTMCR", "OPTMCD", "OPTPRV", "OPTVA", "OPTTRI",
    "OPTOFD", "OPTSTL", "OPTWCP", "OPTPTR", "OPTOTH", "OPTOSR",

    # ---- Emergency room visits: counts ----
    "ERTOT",

    # ---- ER facility expenditures ----
    "ERFTCH", "ERFEXP", "ERFSLF", "ERFMCR", "ERFMCD", "ERFPRV", "ERFVA", "ERFTRI",
    "ERFOFD", "ERFSTL", "ERFWCP", "ERFPTR", "ERFOTH", "ERFOSR",

    # ---- ER doctor expenditures ----
    "ERDTCH", "ERDEXP", "ERDSLF", "ERDMCR", "ERDMCD", "ERDPRV", "ERDVA", "ERDTRI",
    "ERDOFD", "ERDSTL", "ERDWCP", "ERDPTR", "ERDOTH", "ERDOSR",

    # ---- ER combined (FAC+DR) expenditures ----
    # NOTE: actual prefix is ERT* (not ERV*); confirmed in 2019 & 2023 codebooks
    "ERTTCH", "ERTEXP", "ERTSLF", "ERTMCR", "ERTMCD", "ERTPRV", "ERTVA", "ERTTRI",
    "ERTOFD", "ERTSTL", "ERTWCP", "ERTPTR", "ERTOTH", "ERTOSR",

    # ---- Inpatient stays: utilization ----
    "IPDIS", "IPNGTD", "IPZERO",

    # ---- Inpatient facility expenditures ----
    "IPFTCH", "IPFEXP", "IPFSLF", "IPFMCR", "IPFMCD", "IPFPRV", "IPFVA", "IPFTRI",
    "IPFOFD", "IPFSTL", "IPFWCP", "IPFPTR", "IPFOTH", "IPFOSR",

    # ---- Inpatient doctor expenditures ----
    "IPDTCH", "IPDEXP", "IPDSLF", "IPDMCR", "IPDMCD", "IPDPRV", "IPDVA", "IPDTRI",
    "IPDOFD", "IPDSTL", "IPDWCP", "IPDPTR", "IPDOTH", "IPDOSR",

    # ---- Inpatient total (FAC+DR) expenditures (IPT* group — missing from original) ----
    "IPTTCH", "IPTEXP", "IPTSLF", "IPTMCR", "IPTMCD", "IPTPRV", "IPTVA", "IPTTRI",
    "IPTOFD", "IPTSTL", "IPTWCP", "IPTPTR", "IPTOTH", "IPTOSR",

    # ---- Dental visits: counts ----
    "DVTOT", "DVGEN", "DVORTH",

    # ---- Dental expenditures ----
    # NOTE: actual prefix is DVT* (not DVV*); confirmed in 2019 & 2023 codebooks
    "DVTTCH", "DVTEXP", "DVTSLF", "DVTMCR", "DVTMCD", "DVTPRV", "DVTVA", "DVTTRI",
    "DVTOFD", "DVTSTL", "DVTWCP", "DVTPTR", "DVTOTH", "DVTOSR",

    # ---- Home health agency: utilization ----
    "HHTOTD", "HHAGD", "HHINDD", "HHINFD",

    # ---- Home health agency expenditures ----
    "HHATCH", "HHAEXP", "HHASLF", "HHAMCR", "HHAMCD", "HHAPRV", "HHAVA", "HHATRI",
    "HHAOFD", "HHASTL", "HHAWCP", "HHAPTR", "HHAOTH", "HHAOSR",

    # ---- Home health non-agency expenditures ----
    "HHNTCH", "HHNEXP", "HHNSLF", "HHNMCR", "HHNMCD", "HHNPRV", "HHNVA", "HHNTRI",
    "HHNOFD", "HHNSTL", "HHNWCP", "HHNPTR", "HHNOTH", "HHNOSR",

    # ---- Other medical expenses ----
    "OMETCH", "OMEEXP", "OMESLF", "OMEMCR", "OMEMCD", "OMEPRV", "OMEVA", "OMETRI",
    "OMEOFD", "OMESTL", "OMEWCP", "OMEPTR", "OMEOTH", "OMEOSR",

    # ---- Prescription medicines ----
    "RXTOT", "RXEXP", "RXSLF", "RXMCR", "RXMCD", "RXPRV", "RXVA", "RXTRI", "RXOFD",
    "RXSTL", "RXWCP", "RXPTR", "RXOTH", "RXOSR"
  )
}

meps_brr_names <- function() sprintf("BRR%d", 1:128)

#' All physical column names to drop as predictors (for yy in 19..23).
meps_expanded_exclusion_names <- function(yy = meps_default_yy()) {
  stems <- meps_excluded_stems_yy()
  out <- c("VARSTR", "VARPSU", meps_brr_names())
  for (suf in yy) {
    out <- c(out, paste0("PERWT", suf, "F"))
    out <- c(out, paste0(stems, suf))
  }
  unique(out)
}

meps_survey_design_present <- function(nm) {
  exc <- intersect(nm, c("VARSTR", "VARPSU", meps_brr_names()))
  perwt <- grep("^PERWT[0-9]{2}F$", nm, value = TRUE)
  sort(unique(c(exc, perwt)))
}

meps_harmonize_names <- function(df, yy) {
  old <- names(df)
  yyX <- paste0(yy, "X")

  # Strip {yy}X first (e.g. AGE23X -> AGEX, FTSTU23X -> FTSTUX),
  # then bare {yy} (e.g. FAMSZE23 -> FAMSZE).
  # Round-based suffixes (31X, 42X, 53X) are unaffected.
  new <- ifelse(
    endsWith(old, yyX) & nchar(old) > nchar(yyX),
    paste0(substring(old, 1L, nchar(old) - nchar(yyX)), "X"),
    ifelse(
      endsWith(old, yy) & nchar(old) > nchar(yy),
      substring(old, 1L, nchar(old) - nchar(yy)),
      old
    )
  )

  if (any(duplicated(new))) {
    dups <- new[duplicated(new) | duplicated(new, fromLast = TRUE)]
    stop("Harmonization produced duplicate names: ", paste(unique(head(dups, 20)), collapse = ", "))
  }
  names(df) <- new
  df
}

#' Replace MEPS sentinel codes with NA.
#'
#' MEPS reserved codes: -1 inapplicable, -7 refused, -8 don't know,
#' -9 not ascertained, -15 cannot be computed.
#' Income variables (FAMINC, BUSNP, etc.) can have legitimate negative values
#' (business losses), so ALL negatives are NOT recoded — only the five known
#' sentinel codes.
meps_recode_sentinels <- function(df) {
  sentinel <- c(-1L, -7L, -8L, -9L, -15L)
  for (j in seq_along(df)) {
    col <- df[[j]]
    if (is.numeric(col) || inherits(col, "labelled")) {
      col <- as.numeric(col)
      col[col %in% sentinel] <- NA_real_
      df[[j]] <- col
    }
  }
  df
}
