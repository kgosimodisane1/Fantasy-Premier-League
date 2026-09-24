# 02_expected_points.R -------------------------------------------------------
# Per-position expected-points (xP) model, built BOTTOM-UP from the FPL scoring
# rules and the per-90 expected stats already in the player table. Each player
# gets one number `xp` = expected points in the next single gameweek.
#
# Why structural (rules-based) rather than a black-box regression?
#   * It is transparent and uses the available parameters directly.
#   * It is forward-looking: attacking output is driven by xG90 / xA90, not by
#     points already scored (which would be circular / backward-looking).
#   * Every coefficient below maps to a real scoring rule, so it is easy to
#     tune and to explain.
# A fitted alternative (regression / GBM on historical per-GW data) is on the
# roadmap in the README; `expected_points()` is written so you can swap it.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(dplyr) })

# FPL scoring constants -- 2025/26 ruleset. VERIFY at the start of each season
# (goal / clean-sheet values and the defensive-contribution rule do change).
SCORING <- list(
  appear_short  = 1,                                   # 1-59 minutes
  appear_60     = 2,                                   # 60+ minutes
  goal          = c(GKP = 6, DEF = 6, MID = 5, FWD = 4),
  assist        = 3,
  clean_sheet   = c(GKP = 4, DEF = 4, MID = 1, FWD = 0),
  save_per      = 1/3,                                 # 1 pt per 3 saves (GKP)
  conceded_per2 = -0.5,                                # -1 per 2 conceded (GKP/DEF)
  dc_reward     = 2,                                   # defensive-contribution pts
  dc_threshold  = c(GKP = Inf, DEF = 10, MID = 12, FWD = 12),  # actions needed
  yellow        = -1,
  red           = -3,
  bonus_scale   = 0.0                                  # set >0 to add a bonus proxy
)

# --- Early-season shrinkage of per-90 rates ---------------------------------
# A per-90 rate off one match is noise (a GW1 haul -> a monstrous xg90). We pull
# each rate toward a minutes-weighted positional prior (the league average for
# that position), letting this season's data take over as minutes accumulate:
#   rate_shrunk = w * rate + (1 - w) * prior,   w = n90 / (n90 + k)
# where n90 = minutes/90 and k = pseudo-games. Small n90 (early season) -> mostly
# prior; by ~k nineties the split is even; late season -> mostly real data.
shrink_rates <- function(df, k = 6) {
  rate_cols <- intersect(c("xg90","xa90","xgi90","xgc90","gc90",
                           "saves90","cs90","dc90"), names(df))
  n90 <- pmax(df$minutes, 0) / 90
  w   <- n90 / (n90 + k)
  for (col in rate_cols) {
    s <- df[[col]]
    # minutes-weighted positional prior for this rate
    prior_by_pos <- tapply(seq_along(s), df$pos, function(ix) {
      ok <- is.finite(s[ix]) & df$minutes[ix] > 0
      if (!any(ok)) 0 else
        sum(s[ix][ok] * df$minutes[ix][ok]) / sum(df$minutes[ix][ok])
    })
    prior <- as.numeric(prior_by_pos[df$pos])
    df[[col]] <- ifelse(is.na(s), prior, w * s + (1 - w) * prior)
  }
  df
}

# --- Minutes / availability model -------------------------------------------
# Season totals let us infer appearances, start rate and minutes-per-appearance;
# `status` + chance-of-playing give an availability multiplier for next GW.
#
# DURABILITY: a player who misses whole games (injury/rotation) should be
# discounted even while currently "available". We estimate an appearance rate =
# apps / season_games and blend it in via durability_weight:
#   0 = ignore durability (assume they feature every GW - old behaviour)
#   1 = full discount (expected minutes = average minutes across ALL team games,
#       counting missed games as 0). This is what catches high-xP / low-minutes
#       players like Calafiori or a fringe player with a noisy per-90.
add_minutes_model <- function(df, durability_weight = 1) {
  season_games <- max(c(df$starts, 1L), na.rm = TRUE)     # ~38 over a full season
  df %>% mutate(
    apps         = ifelse(ppg > 0, pmax(round(total_points / ppg), 1L), 0L),
    mins_per_app = ifelse(apps > 0, pmin(minutes / apps, 90), 0),
    start_rate   = ifelse(apps > 0, pmin(starts / apps, 1), 0),
    appearance_rate = pmin(apps / season_games, 1),        # share of games featured
    durability   = (1 - durability_weight) + durability_weight * appearance_rate,
    avail = dplyr::case_when(
      status == "a"                    ~ 1,
      status == "d"                    ~ ifelse(!is.na(cop_next), cop_next / 100, 0.5),
      status %in% c("i", "s", "u", "n") ~ ifelse(!is.na(cop_next), cop_next / 100, 0),
      TRUE                             ~ ifelse(!is.na(cop_next), cop_next / 100, 1)
    ),
    exp_minutes  = avail * durability * mins_per_app,      # avg minutes per GW
    p_play       = pmin(avail * durability, 1),            # P(features this GW)
    p_60         = pmin(exp_minutes / 90, 1)               # ~ P(reach 60 mins)
  )
}

# --- The expected-points model ----------------------------------------------
# durability_weight -> minutes model (see add_minutes_model).
# shrinkage_k       -> early-season shrinkage of per-90 rates toward positional
#                      priors (0 disables; higher = more regression). Set lower
#                      as the season matures if you want to trust current data.
expected_points <- function(df, durability_weight = 1, shrinkage_k = 6) {
  if (shrinkage_k > 0) df <- shrink_rates(df, k = shrinkage_k)
  df  <- add_minutes_model(df, durability_weight = durability_weight)
  m   <- pmax(df$exp_minutes, 0) / 90                    # expected minutes fraction
  pos <- df$pos

  gp  <- SCORING$goal[pos]                               # goal value by position
  csp <- SCORING$clean_sheet[pos]                        # clean-sheet value
  thr <- SCORING$dc_threshold[pos]                       # DC action threshold

  # Appearance points
  appear <- SCORING$appear_short * df$p_play +
            (SCORING$appear_60 - SCORING$appear_short) * df$p_60

  # Attacking returns (per-90 rates scaled to expected minutes)
  goals   <- gp * df$xg90 * m
  assists <- SCORING$assist * df$xa90 * m

  # Clean sheets: needs 60+ mins AND team keeps a clean sheet.
  # P(0 conceded) ~ Poisson with mean = team expected goals conceded / 90.
  p_cs <- df$p_60 * exp(-pmax(df$xgc90, 0))
  cs   <- csp * p_cs

  # Goalkeeper saves and the goals-conceded penalty (GKP/DEF only)
  saves    <- ifelse(pos == "GKP", SCORING$save_per * df$saves90 * m, 0)
  conceded <- ifelse(pos %in% c("GKP", "DEF"),
                     SCORING$conceded_per2 * df$xgc90 * m, 0)

  # Defensive contribution: +2 when a player hits the per-match action threshold.
  # dc90 = defensive-contribution actions per 90; approximate the probability of
  # clearing the threshold as min(dc90 / threshold, 1). NOTE: confirm whether the
  # API's defensive_contribution field is ACTIONS (assumed here) or POINTS, and
  # adjust if needed.
  p_dc <- pmin(pmax(df$dc90, 0) / thr, 1) * as.integer(m > 0)
  dc   <- ifelse(pos == "GKP", 0, SCORING$dc_reward * p_dc)

  # Discipline drag (season card rate per appearance, scaled by playing chance)
  cards <- -((df$yellow_cards / pmax(df$apps, 1)) * abs(SCORING$yellow) +
             (df$red_cards    / pmax(df$apps, 1)) * abs(SCORING$red)) * df$p_play

  # Optional bonus proxy (off by default): small credit for high ICT per 90
  bonus <- SCORING$bonus_scale * (df$ict / pmax(df$apps, 1)) * m

  xp <- appear + goals + assists + cs + saves + conceded + dc + cards + bonus

  df$xp_appear   <- round(appear, 3)
  df$xp_attack   <- round(goals + assists, 3)
  df$xp_defence  <- round(cs + saves + conceded + dc, 3)
  df$xp_model    <- round(pmax(xp, 0), 3)
  df$xp          <- df$xp_model
  df
}

# Blend the structural model with FPL's own ep_next as a sanity anchor.
#   w = 0  -> pure structural model (default)
#   w = 1  -> pure FPL ep_next
blend_ep <- function(df, w = 0) {
  anchor <- ifelse(is.na(df$ep_next), df$xp_model, df$ep_next)
  df$xp  <- round((1 - w) * df$xp_model + w * anchor, 3)
  df
}
