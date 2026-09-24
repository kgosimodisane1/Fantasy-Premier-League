# FPL-Optimiser — Project Context (read me first)

This file is the durable memory for this project. If you are an assistant picking
this up in a new session: read this, then `ROADMAP.md` (current status & next
steps), then the code in `R/`. The chat history does NOT persist between
sessions — this folder is the single source of truth.

## Who & why

- Owner: **Kgosi**. Quantitatively strong —
  background in portfolio optimisation (built a mean-variance efficient-frontier
  model in R with `fPortfolio`). Prefers **concise, direct** answers, minimal
  fluff, honest push-back.
- Mission: build an R system that picks the **optimal Fantasy Premier League
  squad each gameweek** via integer programming — the discrete analogue of a
  mean-variance portfolio optimiser. Continuous asset weights → binary
  own/don't-own decisions; expected return → expected points; risk/weight limits
  → FPL budget, squad, club and formation rules.
- Horizon: this runs across the **whole PL season**, gameweek by gameweek.

## How we work together (important)

- Kgosi runs R locally in RStudio. The assistant **edits files in this connected
  folder**; Kgosi executes them.
- The assistant's sandbox **cannot run R** and **cannot reach the FPL API**
  (proxy blocks it). So: write/modify code here, then give Kgosi the exact lines
  to run. Do not claim to have produced live results you can't compute.
- After editing a function, remind Kgosi to `source()` the file — a saved change
  doesn't update an already-loaded function in memory.

## Architecture (files in R/)

- `FPL.R` — fetch `bootstrap-static`, coerce string metrics to numeric, join
  teams/positions. Keeps the FULL raw feed + engineered cols (`age`,
  `days_at_club`, numeric `value_form/season`). `get_players()` is the entry point.
  (This is the renamed `01_fetch_data.R`; `main.R` sources it as `FPL.R`.)
- `02_expected_points.R` — structural, forward-looking per-position xP.
  `expected_points(players, durability_weight = 1, shrinkage_k = 6)`; `blend_ep()`
  to lean on FPL's `ep_next`. Adds columns `xp`, `xp_appear/attack/defence`.
  `shrink_rates()` regresses per-90 rates toward minutes-weighted positional
  priors (w = n90/(n90+k)) to kill early-season one-game mirages.
- `03_optimise_squad.R` — the MILP (ompr + ROI + GLPK). `optimise_squad()` with
  `budget`, `exclude_ids`, `lock_ids`, `bench_weight`. Returns squad + XI +
  captain + `xi_xp` / `bench_xp`.
- `04_analysis.R` — `print_squad()` (with inline availability check),
  `plot_value()`, `top_by_position()`, `bench_options()`, `bench_order()`,
  `availability_report()`, `evaluate_squad()`, `compare_players()`.
- `05_eda_scatter.R` — `eda_scatter()` / `eda_scatter_by_position()`.
- `06_tracker.R` — season decision tracker (see below).
- `07_watchlist.R` — persistent watchlist (`watchlist.csv`) + `transfer_targets()`
  (replacements for underperformers) + `form_movers()` (over-performers to add).
- `08_fixtures.R` — fixture-difficulty weighting. `apply_fixtures(players, gw)`
  re-prices xP per opponent (strength-based, home/away, DGW/BGW aware) into an
  `xp_fixture` column; optimise with `optimise_squad(players, xp_col="xp_fixture")`.
- `00_install.R` — one-time package install (run from a fresh session).
- `main.R` — sources everything, runs the full pipeline into `players` and `res`.

Run: open `FPL-Optimiser.Rproj` (or `setwd()` here) → `source("main.R")`.
First time only: restart R, then `source("R/00_install.R")`.

## Modelling principles (don't regress these away)

- xP is **structural / forward-looking**: built from per-90 expected stats
  (`xg90`, `xa90`, `xgc90`, `saves90`, `dc90`) + a minutes/availability/
  durability model. It deliberately does NOT use point-derived variables
  (`bps`, `bonus`, `ict`, `form`, `total_points`) — those are tautological with
  points and would leak. Keep this discipline in any future fitted model:
  predict NEXT-GW points from LAGGED features, validate out-of-sample.
- **Durability**: expected minutes are scaled by appearance rate
  (`apps / season_games`) via `durability_weight` (default 1), so injury/
  rotation-prone high-xP players are discounted automatically.
- FPL rules encoded: £100m budget, 15 = 2/5/5/3, max 3 per club, XI = 11 with
  GK 1 / DEF 3–5 / MID 2–5 / FWD 1–3, captain doubled. `now_cost` is tenths of £m.

## Decisions & state log

- Engine chosen: ompr + ROI + GLPK (readable MILP; provably optimal, verified vs CBC).
- Scoring constants in `02` are the **2025/26 ruleset** — re-verify each August
  (goal/CS values and the defensive-contribution rule change).
- Open assumption: API `defensive_contribution` treated as ACTIONS (confirm).
- Transfers made pre-season: Davies→O'Nien, Thomas→Diop (better playing fodder),
  Enzo→Anderson (Enzo off-pitch risk; frees £0.5m).
- **Calafiori**: kept despite injury/availability risk; Kgosi is giving him the
  benefit of the doubt with a £0.5m buffer to replace him if he doesn't produce.
  The durability factor now discounts him in the model.

## Season cadence (per gameweek)

1. `source("main.R")` → fresh `players` (durability on) and optimiser `res`.
2. `print_squad(res)` → suggested XI; sanity-check `availability_report(res)`.
3. Decide your XI. Before the deadline: `log_prediction(players, res, gw,
   my_xi_ids, my_cap_id, my_squad_ids, my_bench_ids, my_vice_id)`. Pass
   `my_bench_ids` IN ORDER [backup GK, sub1, sub2, sub3] and `my_vice_id` so
   auto-subs score correctly (both optional; without them subs are still applied
   but bench order is only best-effort).
4. After matches: `record_actuals(players, gw)` → applies FPL auto-substitutions
   to your XI off actual minutes (0-min starters -> bench, armband -> vice if the
   captain blanks), then fills SUGGESTED vs MINE vs EX-POST optimal into
   `tracking/xi_tracker.csv`. `read_tracker()` to view. NOTE: the SUGGESTED XI is
   scored without auto-subs (its bench order isn't stored).

Tracker measures decision quality over the season: `my_vs_suggested_pts`
(did you beat the model?) and `regret_vs_expost` (points left on the bench/
captaincy; 0 = perfect). Consider a scheduled weekly reminder before each deadline.

## Roadmap pointer

Live checklist is `ROADMAP.md`. Next up: interpret per-position EDA & select
predictors (#10), set-piece taker bonus (#11), chips: Bench Boost / Triple
Captain / Free Hit / Wildcard (#12). Backlog: fitted xP model, multi-GW +
transfers (1 FT / -4, fixture difficulty), efficient frontier (xP vs risk).
