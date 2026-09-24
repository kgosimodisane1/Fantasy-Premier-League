# 01_fetch_data.R ------------------------------------------------------------
# Pull the official Fantasy Premier League "bootstrap-static" feed and build a
# tidy, correctly-typed player table for modelling and optimisation.
#
# The FPL API is a public JSON API - no key or login required for reads.
# Field names below were confirmed against the live feed.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(tidyr)
  library(tidyverse)
})

# Generic GET wrapper for any FPL API path -----------------------------------
fpl_get <- function(path) {
  url <- paste0("https://fantasy.premierleague.com/api/", path)
  res <- httr::GET(url, httr::user_agent("fpl-optimiser/1.0 (R)"))
  httr::stop_for_status(res)
  jsonlite::fromJSON(httr::content(res, as = "text", encoding = "UTF-8"),
                     simplifyVector = TRUE)
}

fetch_bootstrap <- function() fpl_get("bootstrap-static/")

# Build the tidy player table. Many numeric columns arrive as strings, so we
# coerce them explicitly. `now_cost` is in tenths of a million (60 => GBP 6.0m).
build_player_table <- function(boot) {
  num <- function(x) suppressWarnings(as.numeric(x))

  positions <- boot$element_types %>%
    dplyr::transmute(element_type = id, pos = singular_name_short)  # GKP/DEF/MID/FWD

  teams <- boot$teams %>%
    dplyr::transmute(team = id, team_name = name, team_short = short_name,
                     team_strength = strength)

  players <- boot$elements %>%
    dplyr::mutate(
      price      = now_cost / 10,
      ppg        = num(points_per_game),
      form       = num(form),
      ep_next    = num(ep_next),
      ep_this    = num(ep_this),
      sel_pct    = num(selected_by_percent),
      xg         = num(expected_goals),
      xa         = num(expected_assists),
      xgi        = num(expected_goal_involvements),
      xgc        = num(expected_goals_conceded),
      xg90       = num(expected_goals_per_90),
      xa90       = num(expected_assists_per_90),
      xgi90      = num(expected_goal_involvements_per_90),
      xgc90      = num(expected_goals_conceded_per_90),
      gc90       = num(goals_conceded_per_90),
      saves90    = num(saves_per_90),
      cs90       = num(clean_sheets_per_90),
      dc90       = num(defensive_contribution_per_90),
      starts90   = num(starts_per_90),
      ict        = num(ict_index),
      threat     = num(threat),
      creativity = num(creativity),
      influence  = num(influence),
      cop_next   = num(chance_of_playing_next_round),  # NA when unknown
      value_form   = num(value_form),                  # points per GBP (recent)
      value_season = num(value_season),                # points per GBP (season)
      # --- engineered from the retained bio fields --------------------------
      # Age & club tenure, in case they carry signal (see README note).
      age = round(as.numeric(difftime(Sys.Date(),
                  suppressWarnings(as.Date(birth_date)), units = "days")) / 365.25, 1),
      days_at_club = as.numeric(Sys.Date() -
                  suppressWarnings(as.Date(team_join_date)))
    ) %>%
    dplyr::left_join(positions, by = "element_type") %>%
    dplyr::left_join(teams, by = "team") %>%
    # Keep the FULL raw feed (news, price-change/churn, rank columns, set-piece
    # & scout fields, bio, etc.) for downstream feature engineering. We only pull
    # the most-used columns to the front for readability - nothing is dropped.
    dplyr::relocate(
      id, web_name, first_name, second_name,
      team, team_name, team_short, team_strength,
      element_type, pos, price, now_cost, status, cop_next, news,
      age, days_at_club,
      total_points, ppg, form, ep_next, ep_this, event_points,
      minutes, starts, sel_pct,
      xg, xa, xgi, xgc, xg90, xa90, xgi90, xgc90, gc90, saves90, cs90, dc90, starts90,
      ict, threat, creativity, influence,
      clearances_blocks_interceptions, tackles, recoveries, defensive_contribution
    )

  players
}

# Convenience one-shot: fetch + build ---------------------------------------
get_players <- function() build_player_table(fetch_bootstrap())

# Modelling -----------------------------------------------------------------

## Goalkeepers



Team <- get_players()

