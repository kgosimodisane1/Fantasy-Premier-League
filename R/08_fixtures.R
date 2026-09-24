# 08_fixtures.R --------------------------------------------------------------
# Fixture-difficulty weighting. Re-prices each player's xP for the SPECIFIC
# opponent in a given gameweek, instead of the neutral, season-average xP.
#
# Logic (opponent- and venue-aware, using FPL team strength ratings):
#   * attacking output (goals/assists) scales with how WEAK the opponent's
#     DEFENCE is  -> att_mult
#   * clean-sheet / goalkeeper value scales with how WEAK the opponent's
#     ATTACK is   -> def_mult
#   * appearance points are opponent-neutral (scaled only by number of fixtures)
#   * a small home-advantage bump is applied at home
# Blank GW (0 fixtures) -> xP 0; double GW (2 fixtures) -> multipliers sum.
#
# ROBUSTNESS: if strength ratings are missing/NA it auto-falls back to FPL's FDR;
# if a specific multiplier can't be computed it defaults to NEUTRAL (1 per
# fixture), never to 0 - so xp_fixture can't collapse to appearance-only.
#
# Requires FPL.R and a table scored by expected_points() (needs xp_appear /
# xp_attack / xp_defence).
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

# Fixtures (optionally one GW) -----------------------------------------------
fetch_fixtures <- function(gw = NULL) {
  fx <- fpl_get("fixtures/")
  out <- tibble::tibble(
    event    = fx$event,
    team_h   = fx$team_h, team_a = fx$team_a,
    fdr_h    = fx$team_h_difficulty, fdr_a = fx$team_a_difficulty,
    finished = fx$finished
  )
  if (!is.null(gw)) out <- dplyr::filter(out, event == gw)
  out
}

# Team attack/defence strengths; NULL if the fields are absent OR all-NA -------
team_strengths <- function(boot = fetch_bootstrap()) {
  t <- boot$teams
  need <- c("strength_attack_home", "strength_attack_away",
            "strength_defence_home", "strength_defence_away")
  if (!all(need %in% names(t))) return(NULL)
  ts <- tibble::tibble(
    team = t$id, short = t$short_name,
    att_h = as.numeric(t$strength_attack_home), att_a = as.numeric(t$strength_attack_away),
    def_h = as.numeric(t$strength_defence_home), def_a = as.numeric(t$strength_defence_away)
  )
  if (all(is.na(c(ts$att_h, ts$att_a, ts$def_h, ts$def_a)))) return(NULL)  # -> FDR fallback
  ts
}

# Per-team multipliers for a gameweek ----------------------------------------
fixture_multipliers <- function(gw, method = c("auto", "strength", "fdr"),
                                clamp = c(0.7, 1.3), home_bump = 1.05,
                                fdr_sens = 0.10, boot = fetch_bootstrap(),
                                verbose = TRUE) {
  method <- match.arg(method)
  fx <- fetch_fixtures(gw)
  if (nrow(fx) == 0) {
    if (verbose) message("No fixtures found for GW", gw, ".")
    return(tibble::tibble(team = integer(), n_fix = integer(),
                          opponent = character(), att_mult = numeric(),
                          def_mult = numeric()))
  }
  ts <- team_strengths(boot)
  use_strength <- (method == "strength") || (method == "auto" && !is.null(ts))
  if (method == "strength" && is.null(ts))
    stop("Strength ratings not available; use method = 'fdr'.")

  home <- fx %>% transmute(team = team_h, opp = team_a, venue = "H", fdr = fdr_h)
  away <- fx %>% transmute(team = team_a, opp = team_h, venue = "A", fdr = fdr_a)
  long <- bind_rows(home, away)

  if (use_strength) {
    avg_att <- mean(c(ts$att_h, ts$att_a), na.rm = TRUE)
    avg_def <- mean(c(ts$def_h, ts$def_a), na.rm = TRUE)
    long <- long %>%
      left_join(ts %>% transmute(opp = team, opp_short = short,
                                 opp_att_h = att_h, opp_att_a = att_a,
                                 opp_def_h = def_h, opp_def_a = def_a),
                by = "opp") %>%
      mutate(
        opp_att = ifelse(venue == "H", opp_att_a, opp_att_h),
        opp_def = ifelse(venue == "H", opp_def_a, opp_def_h),
        bump    = ifelse(venue == "H", home_bump, 1),
        # neutral (=bump, ~1) when opponent strength is missing
        att_raw = ifelse(is.na(opp_def) | opp_def <= 0, bump, (avg_def / opp_def) * bump),
        def_raw = ifelse(is.na(opp_att) | opp_att <= 0, bump, (avg_att / opp_att) * bump),
        att_mult = pmin(pmax(att_raw, clamp[1]), clamp[2]),
        def_mult = pmin(pmax(def_raw, clamp[1]), clamp[2])
      )
  } else {
    long <- long %>%
      mutate(
        opp_short = NA_character_,
        bump = ifelse(venue == "H", home_bump, 1),
        adj  = ifelse(is.na(fdr), 1, 1 + (3 - fdr) * fdr_sens) * bump,  # FDR 1 easy .. 5 hard
        att_mult = pmin(pmax(adj, clamp[1]), clamp[2]),
        def_mult = att_mult
      )
  }

  out <- long %>%
    group_by(team) %>%
    summarise(
      n_fix    = dplyr::n(),
      opponent = paste0(coalesce(opp_short, as.character(opp)),
                        "(", venue, ")", collapse = " + "),
      att_mult = sum(att_mult),   # DGW: sum over the two fixtures
      def_mult = sum(def_mult),
      .groups  = "drop"
    )
  if (verbose)
    message(sprintf("GW%d fixture weighting: method=%s, %d teams matched.",
                    gw, ifelse(use_strength, "strength", "fdr"), nrow(out)))
  out
}

# Apply fixture weighting -> adds an xp_fixture column ------------------------
# Optimise on it with: optimise_squad(players, xp_col = "xp_fixture")
apply_fixtures <- function(players, gw, method = "auto",
                           boot = fetch_bootstrap(), ...) {
  stopifnot(all(c("xp_appear", "xp_attack", "xp_defence") %in% names(players)))
  mult <- fixture_multipliers(gw, method = method, boot = boot, ...)
  players %>%
    # drop any fixture columns from a previous apply_fixtures() call so re-runs
    # don't create n_fix.x / n_fix.y collisions
    dplyr::select(-dplyr::any_of(c("n_fix", "opponent", "att_mult",
                                   "def_mult", "xp_fixture"))) %>%
    left_join(mult, by = "team") %>%
    mutate(
      n_fix    = coalesce(n_fix, 0L),                       # 0 => blank GW => xP 0
      # NA multiplier but the team DOES play => neutral (1 per fixture), never 0
      att_mult = ifelse(is.na(att_mult), n_fix, att_mult),
      def_mult = ifelse(is.na(def_mult), n_fix, def_mult),
      xp_fixture = round(xp_appear * n_fix +
                         xp_attack * att_mult +
                         xp_defence * def_mult, 3)
    )
}
