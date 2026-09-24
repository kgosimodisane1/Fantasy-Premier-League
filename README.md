# Fantasy Premier League — Optimiser

An R system that picks an optimal Fantasy Premier League squad each gameweek by
**integer programming** — the discrete analogue of a mean-variance portfolio
optimiser. Continuous asset weights become binary own/don't-own decisions,
expected return becomes expected points, and the risk budget becomes FPL's
budget, squad, club and formation rules.

## What it does

- **Expected points (xP):** a transparent, forward-looking per-position model
  built from per-90 expected stats (xG/xA/xGC, saves, defensive contribution)
  plus a minutes/availability model. It deliberately avoids point-derived
  variables (bonus, bps, ict, total points) to prevent leakage. Includes
  **durability** discounting for rotation/injury-prone players and
  **early-season shrinkage** toward positional priors so one big game can't
  distort a rate.
- **Optimiser:** an exact mixed-integer program (`ompr` + `ROI` + `GLPK`) that
  selects the best 15 + starting XI + captain under every FPL rule (£100m
  budget, 2-5-5-3 squad, max 3 per club, valid formation, captain doubled).
  Supports player locks, exclusions, a bench-value weight (for Bench Boost),
  and optional fixture-difficulty weighting.
- **Management tools:** availability checks, bench ordering, a persistent
  watchlist, transfer-target suggestions, and a **season decision tracker**
  that scores your XI against the model's suggestion and the ex-post best XI
  each week (with FPL auto-substitutions applied).

## Quick start

```r
# first time only (from a fresh R session):
source("R/00_install.R")

# each run:
source("main.R")     # fetches data, scores xP, optimises, prints the squad
```

Open `FPL-Optimiser.Rproj` in RStudio so the working directory is set
automatically.

## Project layout

```
R/
  FPL.R               data fetch + cleaning (official FPL bootstrap-static)
  00_install.R        one-time package install
  02_expected_points.R  per-position xP model (durability + shrinkage)
  03_optimise_squad.R   the MILP optimiser
  04_analysis.R         squad report, value map, bench/availability tools
  05_eda_scatter.R      exploratory scatter / correlations
  06_tracker.R          season decision tracker (+ auto-subs)
  07_watchlist.R        watchlist + transfer targets
  08_fixtures.R         fixture-difficulty weighting
main.R                end-to-end pipeline
tracking/             weekly decision log + results (xi_tracker.csv, per-GW files)
archive/              original scripts, preserved
ROADMAP.md            live status & next steps
CLAUDE.md             project context / design notes
```

## Approach & modelling notes

xP is built bottom-up from the FPL scoring rules applied to *forward-looking*
inputs (expected goals/assists per 90, expected minutes) rather than points
already scored — the same discipline any future fitted model should keep
(predict next-GW points from lagged features, validate out-of-sample). The
optimiser treats each player's xP as a scalar and enforces the squad structure,
so the model prices positions and the optimiser counts them. See `ROADMAP.md`
for current status and the backlog (fitted xP model, multi-gameweek transfer
planning, an efficient frontier of xP vs risk).

## Data

Uses the public, unofficial Fantasy Premier League JSON API
(`fantasy.premierleague.com/api/`). No key required; please cache and avoid
hammering it. Scoring constants reflect the 2025/26 ruleset and should be
re-verified each season.
