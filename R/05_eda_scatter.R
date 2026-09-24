# 05_eda_scatter.R -----------------------------------------------------------
# Exploratory scatter plots of every numeric variable against total_points,
# coloured by position, with a fitted trend line and the Pearson correlation
# shown in each facet title. Also produces a correlation-ranking chart so you
# can see at a glance which variables track total points most strongly.
#
# Usage:
#   source("R/FPL.R")            # or 01_fetch_data.R (defines get_players)
#   source("R/05_eda_scatter.R")
#   players <- get_players()
#   cors <- eda_scatter(players)                 # all players
#   cors <- eda_scatter(players, min_minutes = 1)# drop players who never played
#   print(cors)                                  # correlation table (sorted)
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

# players     : tidy table from get_players()
# target      : y-axis variable (default total_points)
# min_minutes : keep only players with at least this many minutes
# exclude     : numeric columns that are identifiers / not meaningful predictors
# ncol        : facets per row in the scatter grid
# out_dir     : where to save the PNGs
eda_scatter <- function(players,
                        target      = "total_points",
                        min_minutes = 0,
                        position    = NULL,   # e.g. "DEF" or c("MID","FWD"); NULL = all
                        exclude     = c("id", "code", "team_code", "photo",
                                        "element_type", "team", "squad_number",
                                        "opta_code", "region", "now_cost"),
                        ncol        = 6,
                        out_dir     = ".") {

  stopifnot(target %in% names(players))

  df <- players %>% dplyr::filter(minutes >= min_minutes)
  if (!is.null(position)) df <- df %>% dplyr::filter(pos %in% position)
  pos_tag <- if (is.null(position)) "all" else paste(position, collapse = "-")
  if (nrow(df) < 3) stop("Too few players after filtering (n = ", nrow(df), ").")

  # Pick numeric predictors automatically
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  num_cols <- setdiff(num_cols, c(target, exclude))
  # Drop zero-variance / all-NA columns (nothing to plot)
  keep <- vapply(num_cols, function(v) {
    x <- df[[v]]; sum(!is.na(x)) > 2 && stats::sd(x, na.rm = TRUE) > 0
  }, logical(1))
  num_cols <- num_cols[keep]

  message(sprintf("Plotting %d numeric variables vs %s | position = %s (n = %d players).",
                  length(num_cols), target, pos_tag, nrow(df)))

  long <- df %>%
    dplyr::select(dplyr::all_of(c(target, "pos", num_cols))) %>%
    tidyr::pivot_longer(dplyr::all_of(num_cols),
                        names_to = "variable", values_to = "value") %>%
    dplyr::filter(!is.na(value))

  # Correlation of each variable with the target (Pearson + Spearman)
  cors <- long %>%
    dplyr::group_by(variable) %>%
    dplyr::summarise(
      r   = suppressWarnings(cor(value, .data[[target]], use = "complete.obs")),
      rho = suppressWarnings(cor(value, .data[[target]],
                                 method = "spearman", use = "complete.obs")),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(abs(r)))

  # Facet title = "variable (r=..)"; order facets by |r| so the strongest
  # relationships appear first.
  ord <- cors$variable
  long <- long %>%
    dplyr::left_join(cors, by = "variable") %>%
    dplyr::mutate(
      facet = sprintf("%s  (r=%.2f)", variable, r),
      facet = factor(facet, levels = sprintf("%s  (r=%.2f)",
                                             ord, cors$r[match(ord, cors$variable)]))
    )

  # --- scatter grid ---------------------------------------------------------
  n_rows <- ceiling(length(num_cols) / ncol)
  grid <- ggplot(long, aes(value, .data[[target]])) +
    geom_point(aes(colour = pos), alpha = 0.5, size = 0.8) +
    geom_smooth(method = "lm", formula = y ~ x, se = FALSE,
                colour = "black", linewidth = 0.4) +
    facet_wrap(~ facet, scales = "free_x", ncol = ncol) +
    labs(title = sprintf("FPL variables vs %s  [%s]", target, pos_tag),
         subtitle = "Facets ordered by |Pearson r|; black line = linear fit",
         x = NULL, y = target, colour = "Position") +
    theme_minimal(base_size = 10) +
    theme(legend.position = "top",
          strip.text = element_text(size = 8),
          panel.spacing = unit(0.6, "lines"))

  grid_file <- file.path(out_dir, sprintf("eda_scatter_grid_%s_%s.png", target, pos_tag))
  ggsave(grid_file, grid, width = ncol * 2.6, height = n_rows * 2.2,
         dpi = 130, limitsize = FALSE)
  message("Saved ", grid_file)

  # --- correlation ranking --------------------------------------------------
  rank_plot <- cors %>%
    dplyr::mutate(variable = reorder(variable, r)) %>%
    ggplot(aes(r, variable, fill = r > 0)) +
    geom_col() +
    geom_vline(xintercept = 0, colour = "grey40") +
    scale_fill_manual(values = c("TRUE" = "#1f77b4", "FALSE" = "#d62728"),
                      guide = "none") +
    labs(title = sprintf("Correlation with %s (Pearson r)  [%s]", target, pos_tag),
         x = "r", y = NULL) +
    theme_minimal(base_size = 10)

  rank_file <- file.path(out_dir, sprintf("eda_corr_ranking_%s_%s.png", target, pos_tag))
  ggsave(rank_file, rank_plot, width = 7,
         height = max(4, nrow(cors) * 0.22), dpi = 130, limitsize = FALSE)
  message("Saved ", rank_file)

  invisible(cors)
}


# Convenience: run the EDA separately for each position and return a named list
# of correlation tables (one per position). Writes a labelled pair of PNGs per
# position, e.g. eda_scatter_grid_total_points_DEF.png. Extra args (min_minutes,
# target, out_dir, ...) pass straight through to eda_scatter().
eda_scatter_by_position <- function(players,
                                    positions = c("GKP", "DEF", "MID", "FWD"),
                                    ...) {
  stats::setNames(lapply(positions, function(p) {
    message("\n=== ", p, " ===")
    eda_scatter(players, position = p, ...)
  }), positions)
}


# --- example usage (commented so sourcing only DEFINES the functions) -------
# source("R/FPL.R")
# players <- get_players()
#
# # all positions pooled:
# cors <- eda_scatter(players, min_minutes = 1)
#
# # one position in isolation (writes eda_*_total_points_DEF.png):
# eda_scatter(players, position = "DEF", min_minutes = 90)
#
# # every position at once (returns a named list of correlation tables):
# cors_by_pos <- eda_scatter_by_position(players, min_minutes = 90)
# cors_by_pos$FWD
