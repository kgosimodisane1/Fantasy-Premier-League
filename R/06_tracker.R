# 06_tracker.R ---------------------------------------------------------------
# Gameweek decision tracker. Each GW we record three starting XIs and compare
# them, so you can measure how good your picks are over time:
#
#   1. SUGGESTED  - the optimiser's best XI, chosen ex-ante from xP
#   2. MINE       - the XI you actually pick
#   3. EX-POST    - the best XI you COULD have fielded from your 15, using the
#                   points that actually happened (a hindsight benchmark)
#
# Workflow each week:
#   BEFORE the deadline:  log_prediction(players, res, gw, my_xi_ids, my_cap_id)
#   AFTER the matches:    record_actuals(players, gw)
#
# Everything lands in tracking/ :
#   xi_tracker.csv                     <- master log (open in Excel)
#   gwNN_prediction.rds                <- machine state for record_actuals()
#   gwNN_<timestamp>_prediction.csv    <- human-readable pre-GW snapshot
#   gwNN_<timestamp>_actuals.csv       <- per-player actual points after the GW
#
# Requires FPL.R (fpl_get) and 03/04 (optimise_squad / evaluate_squad) sourced.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

TRACK_DIR <- "tracking"

.stamp <- function() format(Sys.time(), "%Y%m%d_%H%M%S")

# Actual points scored in a given gameweek: id -> gw_points --------------------
fetch_event_points <- function(gw) {
  live <- fpl_get(sprintf("event/%d/live/", gw))
  tibble(id = live$elements$id,
         gw_points = live$elements$stats$total_points,
         minutes   = live$elements$stats$minutes)
}

# XI + captain ids out of an optimise_squad() result -------------------------
.xi_from_res <- function(res) {
  list(xi_ids = res$squad$id[res$squad$in_xi],
       cap_id = res$squad$id[res$squad$captain])
}

# Score an XI on a points column, with the captain counted twice -------------
.score_xi <- function(df, xi_ids, cap_id, col) {
  base <- sum(df[[col]][df$id %in% xi_ids], na.rm = TRUE)
  capp <- df[[col]][df$id == cap_id]
  base + ifelse(length(capp) && !is.na(capp[1]), capp[1], 0)   # +1x => doubled
}

# Apply FPL auto-substitutions given who actually played (minutes) -------------
# pl needs id / pos / minutes. bench_ids should be ordered [backup GK, sub1..3].
# Returns the effective scoring XI and captain (armband moves to vice if the
# captain played 0 minutes). Outfield subs come on in bench order only if the
# resulting formation stays legal (1 GK, >=3 DEF, >=2 MID, >=1 FWD).
.apply_autosubs <- function(pl, xi_ids, bench_ids, cap_id, vice_id = NA) {
  pos_of <- setNames(pl$pos, as.character(pl$id))
  min_of <- setNames(pl$minutes, as.character(pl$id))
  P      <- function(id) unname(pos_of[as.character(id)])
  played <- function(id) { m <- min_of[as.character(id)]; length(m) && !is.na(m) && m > 0 }

  xi <- as.character(xi_ids); bench <- as.character(bench_ids)
  bench_gk  <- bench[vapply(bench, function(i) identical(P(i), "GKP"), logical(1))]
  bench_out <- bench[vapply(bench, function(i) !identical(P(i), "GKP"), logical(1))]

  # Goalkeeper: only a GK can replace a GK
  gk <- xi[vapply(xi, function(i) identical(P(i), "GKP"), logical(1))]
  if (length(gk) && !played(gk[1]) && length(bench_gk) && played(bench_gk[1]))
    xi <- c(setdiff(xi, gk[1]), bench_gk[1])

  cnt   <- function(ids, p) sum(vapply(ids, function(i) identical(P(i), p), logical(1)))
  valid <- function(ids) length(ids) == 11 && cnt(ids, "GKP") == 1 &&
    cnt(ids, "DEF") >= 3 && cnt(ids, "MID") >= 2 && cnt(ids, "FWD") >= 1

  used <- character(0)
  for (s in xi[vapply(xi, function(i) !identical(P(i), "GKP"), logical(1))]) {
    if (played(s)) next
    for (b in bench_out) {
      if (b %in% used || b %in% xi || !played(b)) next
      cand <- c(setdiff(xi, s), b)
      if (valid(cand)) { xi <- cand; used <- c(used, b); break }
    }
  }

  eff_cap <- as.character(cap_id)
  if (!played(cap_id) && !is.na(vice_id) && played(vice_id))
    eff_cap <- as.character(vice_id)

  list(xi = as.numeric(xi), cap = as.numeric(eff_cap),
       n_subs = length(setdiff(as.numeric(xi), as.numeric(xi_ids))))
}

# Insert-or-update one row (by gw) in the master CSV -------------------------
.upsert_tracker <- function(dir, row) {
  path <- file.path(dir, "xi_tracker.csv")
  cols <- c("gw", "logged_at", "suggested_xi_xp", "my_xi_xp",
            "suggested_xi_pts", "my_xi_pts", "expost_best_pts")
  master <- if (file.exists(path))
    suppressMessages(read_csv(path, show_col_types = FALSE)) else NULL
  # Normalise types so re-writes never clash (readr may infer logged_at as a
  # datetime and all-NA numeric columns as logical).
  if (!is.null(master)) {
    if ("logged_at" %in% names(master)) master$logged_at <- as.character(master$logged_at)
    for (nc in intersect(c("suggested_xi_xp", "my_xi_xp", "suggested_xi_pts",
                           "my_xi_pts", "expost_best_pts"), names(master)))
      master[[nc]] <- suppressWarnings(as.numeric(master[[nc]]))
  }
  if (is.null(master)) {
    master <- row
  } else if (row$gw %in% master$gw) {
    i <- which(master$gw == row$gw)
    for (c in names(row)) {
      v <- row[[c]][1]
      if (!is.na(v)) master[[c]][i] <- v
    }
  } else {
    master <- bind_rows(master, row)
  }
  for (c in cols) if (!c %in% names(master)) master[[c]] <- NA
  master <- master %>%
    arrange(gw) %>%
    mutate(my_vs_suggested_pts = my_xi_pts - suggested_xi_pts,  # + = you beat model
           regret_vs_expost    = my_xi_pts - expost_best_pts)   # <=0; 0 = perfect
  write_csv(master, path)
  invisible(master)
}

# BEFORE the deadline: log the suggested XI and your XI -----------------------
# my_xi_ids   : 11 player ids you are starting
# my_cap_id   : your captain's id
# my_squad_ids: your full 15 (defaults to the optimiser's squad; pass your own)
# my_bench_ids: your 4 bench ids IN ORDER [backup GK, sub1, sub2, sub3] for
#               correct auto-subs; if NULL, derived (unordered) from the squad.
# my_vice_id  : your vice-captain (armband moves here if the captain plays 0 min)
log_prediction <- function(players, res, gw, my_xi_ids, my_cap_id,
                           my_squad_ids = res$squad$id,
                           my_bench_ids = NULL, my_vice_id = NA,
                           dir = TRACK_DIR) {
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  sug <- .xi_from_res(res)

  suggested_xp <- .score_xi(players, sug$xi_ids, sug$cap_id, "xp")
  my_xp        <- .score_xi(players, my_xi_ids,  my_cap_id,  "xp")

  my_bench <- if (!is.null(my_bench_ids)) my_bench_ids else setdiff(my_squad_ids, my_xi_ids)
  saveRDS(list(gw = gw, logged_at = Sys.time(),
               suggested_xi = sug$xi_ids, suggested_cap = sug$cap_id,
               my_xi = my_xi_ids, my_cap = my_cap_id, my_squad = my_squad_ids,
               my_bench = my_bench, my_vice = my_vice_id),
          file.path(dir, sprintf("gw%02d_prediction.rds", gw)))

  players %>%
    filter(id %in% union(sug$xi_ids, my_squad_ids)) %>%
    transmute(gw, id, web_name, pos, team_short, price, xp,
              suggested_xi  = id %in% sug$xi_ids,
              suggested_cap = id == sug$cap_id,
              my_xi         = id %in% my_xi_ids,
              my_cap        = id == my_cap_id) %>%
    write_csv(file.path(dir, sprintf("gw%02d_%s_prediction.csv", gw, .stamp())))

  .upsert_tracker(dir, tibble(
    gw = gw, logged_at = format(Sys.time()),
    suggested_xi_xp = round(suggested_xp, 2), my_xi_xp = round(my_xp, 2),
    suggested_xi_pts = NA_real_, my_xi_pts = NA_real_, expost_best_pts = NA_real_))

  message(sprintf("Logged GW%d: suggested xP %.2f | your xP %.2f",
                  gw, suggested_xp, my_xp))
  invisible(read_tracker(dir))
}

# AFTER the matches: pull actual points and score all three XIs ---------------
record_actuals <- function(players, gw, dir = TRACK_DIR) {
  f <- file.path(dir, sprintf("gw%02d_prediction.rds", gw))
  if (!file.exists(f)) stop("No prediction logged for GW", gw, " - run log_prediction() first.")
  state  <- readRDS(f)
  actual <- fetch_event_points(gw)

  pl <- players %>%
    select(id, web_name, pos, team_short) %>%
    left_join(actual, by = "id") %>%
    mutate(gw_points = coalesce(gw_points, 0),
           minutes   = coalesce(minutes, 0))

  # MINE: apply FPL auto-subs off actual minutes (0-min starters -> bench)
  my_bench <- if (!is.null(state$my_bench)) state$my_bench else setdiff(state$my_squad, state$my_xi)
  my_vice  <- if (!is.null(state$my_vice)) state$my_vice else NA
  sub <- .apply_autosubs(pl, state$my_xi, my_bench, state$my_cap, my_vice)
  my_pts <- .score_xi(pl, sub$xi, sub$cap, "gw_points")

  # SUGGESTED: scored as logged (its bench order isn't stored, so no auto-sub)
  suggested_pts <- .score_xi(pl, state$suggested_xi, state$suggested_cap, "gw_points")

  # Ex-post best XI from your 15 on ACTUAL points (reuse the MILP)
  sel <- players %>%
    filter(id %in% state$my_squad) %>%
    left_join(actual, by = "id") %>%
    mutate(gw_points = coalesce(gw_points, 0))
  expost <- evaluate_squad(sel, state$my_squad, xp_col = "gw_points")
  expost_pts <- .score_xi(sel,
                          expost$squad$id[expost$squad$in_xi],
                          expost$squad$id[expost$squad$captain],
                          "gw_points")

  pl %>% filter(id %in% state$my_squad) %>% arrange(desc(gw_points)) %>%
    write_csv(file.path(dir, sprintf("gw%02d_%s_actuals.csv", gw, .stamp())))

  out <- .upsert_tracker(dir, tibble(
    gw = gw, logged_at = format(state$logged_at),
    suggested_xi_xp = NA_real_, my_xi_xp = NA_real_,
    suggested_xi_pts = round(suggested_pts, 1),
    my_xi_pts = round(my_pts, 1),
    expost_best_pts = round(expost_pts, 1)))

  message(sprintf("GW%d actuals -> suggested %.1f | you %.1f%s | ex-post best %.1f",
                  gw, suggested_pts, my_pts,
                  if (sub$n_subs > 0) sprintf(" (%d auto-sub)", sub$n_subs) else "",
                  expost_pts))
  invisible(out)
}

# Read the master log --------------------------------------------------------
read_tracker <- function(dir = TRACK_DIR) {
  path <- file.path(dir, "xi_tracker.csv")
  if (!file.exists(path)) { message("No tracker yet."); return(invisible(NULL)) }
  suppressMessages(read_csv(path, show_col_types = FALSE))
}
