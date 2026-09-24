# 03_optimise_squad.R --------------------------------------------------------
# Single optimal 15-man squad + starting XI + captain that MAXIMISES expected
# points (xp) under the official FPL rules, solved as a mixed-integer program.
#
# This is the FPL analogue of the mean-variance efficient portfolio: instead of
# continuous asset weights we choose binary "own / don't own" decisions, and
# instead of a covariance-constrained return we maximise expected points subject
# to budget, squad-composition, club and formation constraints.
#
# Engine: ompr (modelling DSL) + ROI + GLPK solver.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(ompr)
  library(ompr.roi)
  library(ROI.plugin.glpk)
  library(dplyr)
  library(tidyr)
})

# Official FPL squad rules ---------------------------------------------------
FPL_RULES <- list(
  budget       = 100.0,                          # GBP m
  squad_size   = 15,
  per_club_max = 3,
  squad  = c(GKP = 2, DEF = 5, MID = 5, FWD = 3), # 15-man composition (fixed)
  xi_min = c(GKP = 1, DEF = 3, MID = 2, FWD = 1), # starting-XI lower bounds
  xi_max = c(GKP = 1, DEF = 5, MID = 5, FWD = 3), # starting-XI upper bounds
  xi_size = 11
)

# players     : tidy table from get_players() with an xp column
# xp_col      : which column to maximise (default "xp")
# budget      : override budget (e.g. to trace a value curve)
# exclude_ids : player ids to force out (injuries, personal blocks)
# lock_ids    : player ids to force INTO the 15-man squad
# bench_weight: how much the 4 bench players' xP counts in the objective.
#               0   = bench is pure fodder (cheapest legal bench; best for a
#                     normal week where the bench rarely plays).
#               0-1 = value the bench too, so among equally-good XIs the
#                     optimiser buys a bench that can actually score (auto-subs).
#               1   = bench counts as much as the XI (use for a Bench Boost week).
optimise_squad <- function(players,
                           rules        = FPL_RULES,
                           xp_col       = "xp",
                           budget       = rules$budget,
                           exclude_ids  = integer(0),
                           lock_ids     = integer(0),
                           bench_weight = 0) {

  df <- players %>%
    dplyr::filter(!is.na(.data[[xp_col]]),
                  !is.na(price),
                  !(id %in% exclude_ids)) %>%
    dplyr::mutate(.xp = .data[[xp_col]]) %>%
    dplyr::arrange(id)

  n     <- nrow(df)
  xp    <- df$.xp
  price <- df$price
  # Objective weights: XI players get (1-bw)*xp via xi + bw*xp via sq = full xp;
  # bench players (in sq, not in xi) get only bw*xp. So the XI + captain value is
  # preserved exactly and the bench is worth `bench_weight` of its xP.
  w_xi  <- (1 - bench_weight) * xp
  w_sq  <- bench_weight * xp
  gk    <- as.integer(df$pos == "GKP")
  de    <- as.integer(df$pos == "DEF")
  mi    <- as.integer(df$pos == "MID")
  fw    <- as.integer(df$pos == "FWD")
  teams <- sort(unique(df$team))

  model <- MIPModel() %>%
    add_variable(sq[i],  i = 1:n, type = "binary") %>%   # in 15-man squad
    add_variable(xi[i],  i = 1:n, type = "binary") %>%   # in starting XI
    add_variable(cap[i], i = 1:n, type = "binary") %>%   # captain

    # Objective: XI points + captain's points AGAIN (captain doubled) + a
    # bench_weight share of the bench. (See w_xi / w_sq above.)
    set_objective(sum_expr(w_xi[i] * xi[i],  i = 1:n) +
                  sum_expr(xp[i]   * cap[i], i = 1:n) +
                  sum_expr(w_sq[i] * sq[i],  i = 1:n), "max") %>%

    # --- 15-man squad: size, budget, composition ---------------------------
    add_constraint(sum_expr(sq[i], i = 1:n) == rules$squad_size) %>%
    add_constraint(sum_expr(price[i] * sq[i], i = 1:n) <= budget) %>%
    add_constraint(sum_expr(gk[i] * sq[i], i = 1:n) == rules$squad[["GKP"]]) %>%
    add_constraint(sum_expr(de[i] * sq[i], i = 1:n) == rules$squad[["DEF"]]) %>%
    add_constraint(sum_expr(mi[i] * sq[i], i = 1:n) == rules$squad[["MID"]]) %>%
    add_constraint(sum_expr(fw[i] * sq[i], i = 1:n) == rules$squad[["FWD"]]) %>%

    # --- Starting XI: subset of squad, size 11, valid formation ------------
    add_constraint(xi[i] <= sq[i], i = 1:n) %>%
    add_constraint(sum_expr(xi[i], i = 1:n) == rules$xi_size) %>%
    add_constraint(sum_expr(gk[i] * xi[i], i = 1:n) == rules$xi_min[["GKP"]]) %>%
    add_constraint(sum_expr(de[i] * xi[i], i = 1:n) >= rules$xi_min[["DEF"]]) %>%
    add_constraint(sum_expr(de[i] * xi[i], i = 1:n) <= rules$xi_max[["DEF"]]) %>%
    add_constraint(sum_expr(mi[i] * xi[i], i = 1:n) >= rules$xi_min[["MID"]]) %>%
    add_constraint(sum_expr(mi[i] * xi[i], i = 1:n) <= rules$xi_max[["MID"]]) %>%
    add_constraint(sum_expr(fw[i] * xi[i], i = 1:n) >= rules$xi_min[["FWD"]]) %>%
    add_constraint(sum_expr(fw[i] * xi[i], i = 1:n) <= rules$xi_max[["FWD"]]) %>%

    # --- Captain: exactly one, must be a starter ---------------------------
    add_constraint(sum_expr(cap[i], i = 1:n) == 1) %>%
    add_constraint(cap[i] <= xi[i], i = 1:n)

  # Max 3 players per club (one constraint per club)
  for (t in teams) {
    ind   <- as.integer(df$team == t)
    model <- model %>%
      add_constraint(sum_expr(ind[i] * sq[i], i = 1:n) <= rules$per_club_max)
  }

  # Force locked players into the squad
  if (length(lock_ids)) {
    for (pid in lock_ids) {
      k <- which(df$id == pid)
      if (length(k) == 1) model <- model %>% add_constraint(sq[k] == 1)
    }
  }

  sol <- solve_model(model, with_ROI(solver = "glpk", verbose = FALSE))

  if (!identical(solver_status(sol), "success") &&
      !identical(solver_status(sol), "optimal")) {
    warning("Solver status: ", solver_status(sol),
            " - check budget/constraints feasibility.")
  }

  sq_i  <- get_solution(sol, sq[i])  %>% filter(value > 0.5) %>% pull(i)
  xi_i  <- get_solution(sol, xi[i])  %>% filter(value > 0.5) %>% pull(i)
  cap_i <- get_solution(sol, cap[i]) %>% filter(value > 0.5) %>% pull(i)

  squad <- df[sq_i, ] %>%
    mutate(
      in_xi   = id %in% df$id[xi_i],
      captain = id %in% df$id[cap_i],
      role    = dplyr::case_when(captain ~ "Captain (2x)",
                                 in_xi   ~ "Starter",
                                 TRUE    ~ "Bench")
    ) %>%
    select(id, web_name, pos, team_short, price, xp = .xp,
           in_xi, captain, role, ep_next, form, sel_pct, status, cop_next, news) %>%
    arrange(match(pos, c("GKP", "DEF", "MID", "FWD")), desc(in_xi), desc(xp))

  formation <- squad %>% filter(in_xi) %>% count(pos) %>%
    tidyr::pivot_wider(names_from = pos, values_from = n)

  list(
    status    = solver_status(sol),
    objective = objective_value(sol),                 # expected XI + captain pts
    squad     = squad,
    spend     = round(sum(squad$price), 1),
    bank      = round(budget - sum(squad$price), 1),
    xi_xp     = round(sum(squad$xp[squad$in_xi]) + sum(squad$xp[squad$captain]), 2),
    bench_xp  = round(sum(squad$xp[!squad$in_xi]), 2),   # sum of the 4 bench players
    formation = formation
  )
}
