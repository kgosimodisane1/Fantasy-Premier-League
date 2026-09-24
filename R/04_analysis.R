# 04_analysis.R --------------------------------------------------------------
# Reporting helpers: pretty-print the optimal squad and draw a value scatter
# (expected points vs price) with the selected 15 highlighted -- the visual
# analogue of plotting the chosen portfolio against the investable universe.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(scales)
})

# Console summary of a result from optimise_squad() --------------------------
print_squad <- function(res) {
  cat("\n================  OPTIMAL FPL SQUAD  ================\n")
  cat(sprintf("Solver status     : %s\n", res$status))
  cat(sprintf("Objective (XI+cap): %.2f expected pts\n", res$objective))
  cat(sprintf("Starting XI xP    : %.2f  (captain doubled)\n", res$xi_xp))
  if (!is.null(res$bench_xp))
    cat(sprintf("Bench xP (4 subs) : %.2f\n", res$bench_xp))
  cat(sprintf("Spend / bank      : GBP %.1fm / GBP %.1fm\n", res$spend, res$bank))
  cat(sprintf("Formation (XI)    : %s\n",
              paste(names(res$formation), unlist(res$formation),
                    sep = "=", collapse = "  ")))
  cat("----------------------------------------------------\n")
  print(res$squad %>%
          mutate(price = sprintf("%.1f", price),
                 xp    = sprintf("%.2f", xp)) %>%
          select(pos, web_name, team_short, price, xp, role),
        row.names = FALSE)
  cat("----------------------------------------------------\n")
  av <- availability_report(res)
  if (nrow(av)) {
    cat("!! AVAILABILITY CHECK - not fully available:\n")
    print(av %>% select(pos, web_name, team_short, flag, chance, role),
          row.names = FALSE)
  } else {
    cat("Availability      : all 15 fully available (status = a)\n")
  }
  cat("====================================================\n")
  invisible(res)
}

# Availability check ---------------------------------------------------------
# Returns the chosen players whose FPL availability is NOT fully clear, so you
# get an automatic "check these" list. Accepts an optimise_squad() result or any
# squad / players data frame with status/cop_next columns.
# status codes: a=available, d=doubtful, i=injured, s=suspended,
#               u=unavailable, n=not in squad / on loan.
availability_report <- function(x, ids = NULL) {
  sq <- if (is.data.frame(x)) x
        else if (is.list(x) && !is.null(x[["squad"]])) x[["squad"]]
        else x
  sq <- tibble::as_tibble(sq)
  if (!is.null(ids)) sq <- sq[sq$id %in% ids, , drop = FALSE]   # filter to a squad
  if (!"cop_next" %in% names(sq)) sq$cop_next <- NA_real_
  if (!"news"     %in% names(sq)) sq$news     <- ""
  if (!"role"     %in% names(sq)) sq$role     <- NA_character_
  labels <- c(a = "Available", d = "Doubtful", i = "Injured",
              s = "Suspended", u = "Unavailable", n = "Not in squad")
  sq %>%
    filter(status != "a" | (!is.na(cop_next) & cop_next < 100)) %>%
    mutate(flag   = ifelse(status %in% names(labels), labels[status], status),
           chance = ifelse(is.na(cop_next), "-", paste0(cop_next, "%"))) %>%
    select(any_of(c("pos", "web_name", "team_short", "price", "role",
                    "flag", "chance", "news", "xp")))
}

# Score a hand-picked 15 --------------------------------------------------
# Evaluate any manual squad: pass 15 player ids (preferred) or web_names.
# Reuses the MILP to (a) validate FPL legality - composition, budget, 3-per-club
# - and (b) pick the best XI + captain, returning the same object as
# optimise_squad(). Infeasible => your 15 break a rule (message says which is
# most likely). Great for A/B-testing a transfer before you make it.
evaluate_squad <- function(players, ids, xp_col = "xp", bench_weight = 0) {
  sel <- if (is.numeric(ids)) dplyr::filter(players, id %in% ids)
         else                 dplyr::filter(players, web_name %in% ids)
  n_found <- dplyr::n_distinct(sel$id)
  if (n_found != length(unique(ids)))
    warning(sprintf("Matched %d of %d players - check for typos or duplicate web_names (use ids to be safe).",
                    n_found, length(unique(ids))))
  if (nrow(sel) != 15)
    warning(sprintf("Squad has %d players after matching, not 15.", nrow(sel)))
  optimise_squad(sel, xp_col = xp_col, bench_weight = bench_weight)
}

# Head-to-head compare of specific players -----------------------------------
compare_players <- function(players, names, xp_col = "xp") {
  players %>%
    filter(web_name %in% names) %>%
    select(any_of(c("web_name", "pos", "team_short", "price")),
           xp = all_of(xp_col),
           any_of(c("ep_next", "minutes", "starts", "status",
                    "cop_next", "sel_pct", "news"))) %>%
    arrange(pos, desc(xp))
}

# Value scatter: xP vs price, chosen squad highlighted -----------------------
plot_value <- function(players, res, xp_col = "xp") {
  chosen <- res$squad$id
  d <- players %>%
    filter(!is.na(.data[[xp_col]]), minutes > 0) %>%
    mutate(xp_plot  = .data[[xp_col]],
           selected = ifelse(id %in% chosen, "In squad", "Universe"),
           starter  = id %in% res$squad$id[res$squad$in_xi])

  ggplot(d, aes(price, xp_plot)) +
    geom_point(aes(colour = selected, size = selected, alpha = selected)) +
    ggrepel::geom_text_repel(
      data = filter(d, id %in% chosen),
      aes(label = web_name), size = 3, max.overlaps = 20, seed = 1) +
    facet_wrap(~ pos, scales = "free") +
    scale_colour_manual(values = c("In squad" = "#1f77b4", "Universe" = "grey75")) +
    scale_size_manual(values = c("In squad" = 2.6, "Universe" = 1.2)) +
    scale_alpha_manual(values = c("In squad" = 1, "Universe" = 0.5)) +
    labs(title = "FPL value map: expected points vs price",
         subtitle = "Highlighted = players chosen by the optimiser",
         x = "Price (GBP m)", y = "Expected points (next GW)",
         colour = NULL, size = NULL, alpha = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "top")
}

# Top N by expected points within each position -----------------------------
top_by_position <- function(players, n = 10, xp_col = "xp") {
  players %>%
    filter(!is.na(.data[[xp_col]])) %>%
    group_by(pos) %>%
    slice_max(order_by = .data[[xp_col]], n = n, with_ties = FALSE) %>%
    ungroup() %>%
    select(pos, web_name, team_short, price, xp = all_of(xp_col),
           ep_next, form, sel_pct) %>%
    arrange(match(pos, c("GKP", "DEF", "MID", "FWD")), desc(xp))
}

# Recommended bench order for auto-subs --------------------------------------
# Outfield subs ranked by xP (slot 1 = first to be brought on if a starter plays
# 0 mins). The backup GK sits in the separate GK bench slot and is not ordered.
# Pass an optimise_squad() result (or a squad data frame with an in_xi column).
bench_order <- function(x) {
  sq <- if (is.list(x) && !is.null(x$squad)) x$squad else x
  stopifnot("in_xi" %in% names(sq))
  bench <- sq %>% filter(!in_xi)
  gk  <- bench %>% filter(pos == "GKP") %>% mutate(slot = "GK (backup)")
  out <- bench %>% filter(pos != "GKP") %>% arrange(desc(xp)) %>%
    mutate(slot = paste0("Sub ", row_number(),
                         ifelse(row_number() == 1L, " (first on)", "")))
  bind_rows(gk, out) %>%
    select(slot, web_name, pos, team_short, price, xp, ep_next, status)
}

# Best-value CHEAP options for bench slots -----------------------------------
# For each position, the highest-xP players at/under a price cap -- i.e. the
# best "bench fodder upgrades": cheap players who might actually score.
# A bench player only scores if they PLAY (auto-subs / Bench Boost), so we also
# surface minutes/starts/status to judge how nailed-on each one is. Tighten with
# min_minutes or status == "a" to keep only genuine starters.
bench_options <- function(players, n = 8,
                          price_cap   = c(GKP = 4.5, DEF = 4.5, MID = 5.0, FWD = 4.5),
                          min_minutes = 0,
                          xp_col      = "xp") {
  players %>%
    filter(!is.na(.data[[xp_col]]),
           minutes >= min_minutes,
           price <= price_cap[pos]) %>%
    group_by(pos) %>%
    slice_max(order_by = .data[[xp_col]], n = n, with_ties = FALSE) %>%
    ungroup() %>%
    select(pos, web_name, team_short, price, xp = all_of(xp_col),
           minutes, starts, status, ep_next, sel_pct) %>%
    arrange(match(pos, c("GKP", "DEF", "MID", "FWD")), desc(xp))
}
