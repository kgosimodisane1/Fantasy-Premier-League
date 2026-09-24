# FPL-Optimiser — Roadmap & Working Notes

Living checklist for the project. At the start of a new chat, point me here
("read ROADMAP.md") and I'll pick up exactly where we left off.

Project root: `C:\Users\modikgo\Claude\Projects\FPL-Optimiser`
Run order: `source("main.R")` (first time: restart R, then `source("R/00_install.R")`)

---

## Done

- [x] **Data pipeline** — `R/FPL.R`: pulls `bootstrap-static`, coerces string
      metrics to numeric, joins teams/positions. Keeps the FULL raw feed plus
      engineered columns (`age`, `days_at_club`, numeric `value_form/season`).
- [x] **Expected-points model** — `R/02_expected_points.R`: transparent,
      bottom-up per-position xP from per-90 expected stats + a minutes/
      availability model. `blend_ep()` anchors toward FPL's own `ep_next`.
- [x] **MILP optimiser** — `R/03_optimise_squad.R`: single optimal 15 + XI +
      captain via ompr/ROI/GLPK. Budget, 2-5-5-3, max-3-per-club, formation,
      one-captain rules. `lock_ids` / `exclude_ids` / `budget` overrides.
      `bench_weight` (0=fodder … 1=Bench-Boost) values the bench.
      Formulation independently verified (CBC) — provably optimal.
- [x] **Analysis** — `R/04_analysis.R`: `print_squad()` (now with an inline
      availability check), `plot_value()` (xP vs price), `top_by_position()`,
      `bench_options()` (best cheap subs), `availability_report()` (flags any
      chosen player whose FPL status != available / chance-of-playing < 100%).
- [x] **EDA** — `R/05_eda_scatter.R`: scatter grid + correlation ranking of
      every numeric variable vs a target; `position=` and
      `eda_scatter_by_position()` for per-position views.
- [x] **Scaffolding** — `R/00_install.R`, `main.R`, `README.md`.
- [x] Connected project folder (this folder) so `source()` and paths are stable.
- [x] **Durability factor** — `02_expected_points.R`: expected minutes scaled by
      appearance rate (apps / season_games) via `durability_weight` (default 1),
      so injury/rotation-prone high-xP players (Calafiori, low-minute fringe
      players) are discounted automatically instead of caught by eye.
- [x] **Gameweek tracker** — `R/06_tracker.R`: each GW logs SUGGESTED (optimiser)
      vs MINE vs EX-POST optimal XI. `log_prediction()` before the deadline
      (now takes `my_bench_ids` ordered + `my_vice_id`), `record_actuals()` after
      (pulls `event/{gw}/live/`; **applies FPL auto-subs** off actual minutes so
      your true post-sub score is recorded — added GW4 where Davis auto-subbed
      in for a 0-min Elanga). Accumulates in `tracking/xi_tracker.csv` with
      per-GW snapshots. `read_tracker()` to view.
- [x] **Watchlist & transfer targets** — `R/07_watchlist.R`: persistent
      `watchlist.csv` (`watch_add/remove/show`, tracks price/xP movement since
      added), `transfer_targets()` (affordable same-position upgrades for
      underperformers), `form_movers()` (over-performers to add).
- [x] **Early-season shrinkage** — `02_expected_points.R` `shrink_rates()`:
      per-90 rates regressed toward minutes-weighted positional priors,
      w = n90/(n90+k), `shrinkage_k` default 6. Added after GW2 where the
      unshrunk optimiser suggestion scored 51 vs Kgosi's 107 (De Cuyper captain
      mirage off one game). Lower k as the season matures.
- [x] **Fixture-difficulty weighting** — `R/08_fixtures.R`: `apply_fixtures(
      players, gw)` re-prices xP per opponent (team-strength based, home/away,
      blank/double GW aware) into `xp_fixture`. Optimise with
      `xp_col = "xp_fixture"`. VERIFY bootstrap has strength_attack/defence_*
      fields (else it auto-falls back to FPL's FDR).

## Next up (proposed order)

- [ ] **Interpret the EDA** — run per-position scatter/correlations, decide
      which within-position variables are real signal (xg90, xa90, xgc90, dc90,
      minutes) vs point-derived artefacts (bps, bonus, ict), and promote the
      keepers into the xP model.
- [ ] **Set-piece taker bonus** — fold `penalties_order` /
      `direct_freekicks_order` into xP (designated penalty taker => xG premium).
- [ ] **Chips** — Bench Boost (add bench xP), Triple Captain (3x), Free Hit /
      Wildcard (one-GW / permanent re-optimise ignoring transfer cost).

## Backlog

- [ ] **Fitted xP model** — train regression/GBM on per-player GW history
      (`element-summary/{id}/`), validate out-of-sample; keep the
      `expected_points()` interface so the optimiser is unchanged.
      LEAKAGE GUARD: predict NEXT-GW points from LAGGED forward-looking features
      only; exclude same-period point-derived vars (bps, bonus, ict,
      total_points, form). The current structural model already avoids these by
      construction — this discipline is specifically for the fitted model.
- [ ] **Multi-gameweek + transfers** — optimise over a horizon with the
      1 free transfer / -4 rule and fixture difficulty (`fixtures/`).
- [ ] **Efficient frontier** — trace max xP against a risk measure (variance of
      points, or ownership) for a true risk/return frontier like fPortfolio.

## Squad admin — near-term FPL moves (Kgosi's team)

- [ ] **GW6+: replace backup GK Dovin** — he's on a season loan (status `u`),
      so there's no auto-sub cover if Raya is rested. Swap for a playing £4.0–4.5m
      keeper (e.g. Petrović / Verbruggen). Bank is ~£1.0m after the GW5
      Elanga→Groß move, so it's a free, budget-neutral fix.
- [ ] **GW6+: clear Furo** — bench FWD, injured (0%), dead fodder slot. Swap for
      a playing cheap forward (e.g. Thomas-Asante ~£5.0) in a free week.
- One at a time on free transfers — do NOT take a -4 to fix bench/GK fodder
  (a dead slot costs ~0 pts; a hit costs 4).
- GW5 move done: Elanga (injured) → Groß (£5.7, freed £0.5m). Bank ~£1.0m.

## Notes / gotchas

- `SCORING` constants in `02_expected_points.R` are the 2025/26 ruleset — verify
  each August (goal/CS values and the defensive-contribution rule change).
- Confirm whether the API `defensive_contribution` field is ACTIONS (assumed)
  or POINTS, and adjust the DC term if needed.
- Pre-season: the feed shows last season's totals and `form`/`ep_next` may be 0;
  the structural model still works off expected stats.
- The data fetch script is `FPL.R` (renamed from `01_fetch_data.R`); `main.R`
  sources it under that name.
