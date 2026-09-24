# 00_install.R ---------------------------------------------------------------
# Run ONCE, from a fresh R session (Session > Restart R first), BEFORE loading
# any of these packages, to avoid the Windows "cannot remove prior installation
# / permission denied" locked-DLL problem.
# ---------------------------------------------------------------------------

pkgs <- c(
  # data + wrangling  (tidyverse pulls in dplyr/tidyr/stringr/lubridate/timechange)
  "httr", "jsonlite", "tidyverse", "dplyr", "tidyr", "stringr",
  # optimisation
  "ompr", "ompr.roi", "ROI", "ROI.plugin.glpk",
  # reporting
  "ggplot2", "scales", "ggrepel"
)

to_install <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(to_install)) {
  install.packages(to_install)
} else {
  message("All required packages already installed.")
}

# Quick check that the MILP solver is wired up correctly.
if (requireNamespace("ROI", quietly = TRUE)) {
  message("ROI solvers available: ",
          paste(ROI::ROI_installed_solvers(), collapse = ", "))
}
