# 07_watchlist.R -------------------------------------------------------------
# Transfer planning:
#   * a PERSISTENT watchlist you curate (saved in watchlist.csv, survives
#     sessions) that tracks each player's price/xP movement since you added them
#   * transfer_targets(): for each of your players, the best affordable
#     same-position replacements - "who do I bring in if X underperforms?"
#   * form_movers(): highest-xP (or in-season, highest-form) players you don't
#     own - over-performers worth adding to the watchlist.
#
# Requires FPL.R + a scored table: players <- expected_points(get_players()).
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

WATCHLIST_FILE <- "watchlist.csv"

# Resolve a vector of ids OR web_names to ids --------------------------------
.resolve_ids <- function(players, x) {
  if (is.numeric(x)) return(unique(x))
  ids <- players$id[match(x, players$web_name)]
  if (anyNA(ids))
    warning("No exact web_name match for: ",
            paste(x[is.na(ids)], collapse = ", "),
            " - use ids or the exact web_name.")
  unique(ids[!is.na(ids)])
}

# Add player(s) to the watchlist (records price & xP at time of adding) ------
watch_add <- function(players, x, note = "", file = WATCHLIST_FILE) {
  ids <- .resolve_ids(players, x)
  if (!length(ids)) return(invisible(NULL))
  new <- players %>% filter(id %in% ids) %>%
    transmute(id, web_name, pos, team_short,
              added = as.character(Sys.Date()),
              added_price = price, added_xp = xp, note = note)
  wl <- if (file.exists(file))
    suppressMessages(read_csv(file, show_col_types = FALSE)) else NULL
  wl <- bind_rows(wl, new) %>% distinct(id, .keep_all = TRUE)
  write_csv(wl, file)
  message(sprintf("Watchlist: +%d, %d total (%s).", nrow(new), nrow(wl), file))
  invisible(wl)
}

# Remove player(s) from the watchlist ----------------------------------------
watch_remove <- function(players, x, file = WATCHLIST_FILE) {
  if (!file.exists(file)) return(invisible(NULL))
  ids <- .resolve_ids(players, x)
  wl  <- suppressMessages(read_csv(file, show_col_types = FALSE)) %>%
    filter(!id %in% ids)
  write_csv(wl, file)
  invisible(wl)
}

# Show the watchlist with CURRENT stats and movement since you added them ----
watch_show <- function(players, file = WATCHLIST_FILE) {
  if (!file.exists(file)) { message("Watchlist empty."); return(invisible(NULL)) }
  wl <- suppressMessages(read_csv(file, show_col_types = FALSE))
  players %>%
    filter(id %in% wl$id) %>%
    left_join(dplyr::select(wl, id, added, added_price, added_xp, note),
              by = "id") %>%
    transmute(web_name, pos, team_short, price,
              d_price = round(price - added_price, 1),   # price change since added
              xp = round(xp, 2),
              d_xp = round(xp - added_xp, 2),            # xP change since added
              form, ep_next, status, sel_pct, note, added) %>%
    arrange(match(pos, c("GKP", "DEF", "MID", "FWD")), desc(xp))
}

# Replacement candidates for your squad --------------------------------------
# For each held player, the best same-position alternatives you could afford
# (price <= their price + bank), not already owned, currently available (opt),
# with higher xP. `bank` = money in the bank (e.g. 0.5 for a GBP0.5m buffer).
transfer_targets <- function(players, squad_ids, bank = 0, n = 3,
                             xp_col = "xp", only_available = TRUE) {
  squad_ids <- .resolve_ids(players, squad_ids)
  held <- players %>% filter(id %in% squad_ids)
  pool <- if (only_available) filter(players, status == "a") else players
  rows <- lapply(seq_len(nrow(held)), function(i) {
    p <- held[i, ]
    pool %>%
      filter(pos == p$pos, !id %in% squad_ids,
             price <= p$price + bank,
             .data[[xp_col]] > p[[xp_col]]) %>%
      slice_max(.data[[xp_col]], n = n, with_ties = FALSE) %>%
      transmute(out = p$web_name, out_price = p$price,
                out_xp = round(p[[xp_col]], 2),
                in_player = web_name, in_team = team_short, in_price = price,
                in_xp = round(.data[[xp_col]], 2),
                xp_gain = round(.data[[xp_col]] - p[[xp_col]], 2),
                status, sel_pct)
  })
  bind_rows(rows) %>% arrange(desc(xp_gain))
}

# Over-performers you don't own (candidates to add to the watchlist) ---------
# Default ranks by xP; in-season pass by = "form" to catch momentum.
form_movers <- function(players, squad_ids = integer(0), n = 5,
                        by = c("xp", "form"), xp_col = "xp") {
  by <- match.arg(by)
  squad_ids <- .resolve_ids(players, squad_ids)
  players %>%
    filter(status == "a", !id %in% squad_ids) %>%
    group_by(pos) %>%
    slice_max(.data[[by]], n = n, with_ties = FALSE) %>%
    ungroup() %>%
    transmute(pos, web_name, team_short, price,
              xp = round(.data[[xp_col]], 2), form, ep_next, sel_pct) %>%
    arrange(match(pos, c("GKP", "DEF", "MID", "FWD")), desc(xp))
}
