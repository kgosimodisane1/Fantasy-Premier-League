# main.R ---------------------------------------------------------------------
# FPL Squad Optimiser - end-to-end run.
#   1. fetch + clean the live player table
#   2. score every player with the per-position expected-points model
#   3. solve the MILP for the single optimal 15 + XI + captain
#   4. report
#
# First time only: restart R, then run  source("R/00_install.R")
# ---------------------------------------------------------------------------

# Work from the project root (edit if needed)
# setwd("path/to/FPL-Optimiser")

source("R/FPL.R")               # data fetch + cleaning (was 01_fetch_data.R)
source("R/02_expected_points.R")
source("R/03_optimise_squad.R")
source("R/04_analysis.R")
source("R/05_eda_scatter.R")    # optional: exploratory scatter / correlations
source("R/06_tracker.R")        # optional: gameweek decision tracker
source("R/07_watchlist.R")      # optional: watchlist + transfer targets
source("R/08_fixtures.R")       # optional: fixture-difficulty weighting

# 1. Data --------------------------------------------------------------------
players <- get_players()
message(sprintf("Fetched %d players across %d clubs.",
                nrow(players), dplyr::n_distinct(players$team)))

# 2. Expected points ---------------------------------------------------------
players <- expected_points(players)                 # durability + shrinkage on
# durability_weight: 1 = fully discount injury/rotation-prone players (default), 0 = ignore.
# shrinkage_k: early-season shrinkage of per-90 rates toward positional priors
#   (default 6). Kills one-game mirages; lower it as the season matures.
#   e.g. expected_points(players, durability_weight = 0.5, shrinkage_k = 4)
# Optional: anchor toward FPL's own ep_next (0 = pure model, 1 = pure FPL)
# players <- blend_ep(players, w = 0.3)

# Peek at the model output
print(top_by_position(players, n = 5))

# 3. Optimise ----------------------------------------------------------------
res <- optimise_squad(players, xp_col = "xp")

# Fixture-weighted alternative (re-prices xP for a specific GW's opponents):
#   players <- apply_fixtures(players, gw = 1)
#   res     <- optimise_squad(players, xp_col = "xp_fixture")

# 4. Report ------------------------------------------------------------------
print_squad(res)

# Value map (requires ggplot2 + ggrepel)
p <- plot_value(players, res)
ggplot2::ggsave("value_map.png", p, width = 11, height = 7, dpi = 150)
message("Saved value_map.png")

# ---------------------------------------------------------------------------
# Handy variations:
#   optimise_squad(players, budget = 95)                # cheaper squad
#   optimise_squad(players, exclude_ids = c(1, 2))      # block players by id
#   optimise_squad(players, lock_ids = c(some_id))      # force a player in
#
# Trace a value curve (points achievable at each budget) -- a poor-man's
# efficient frontier over the budget axis:
#   curve <- purrr::map_dfr(seq(80, 100, by = 2), function(b) {
#     r <- optimise_squad(players, budget = b)
#     tibble::tibble(budget = b, xi_xp = r$xi_xp, spend = r$spend)
#   })
#   print(curve)
# ---------------------------------------------------------------------------
