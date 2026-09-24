# GW2 — results

- **My total: 107** (GW1 was 54). Formation 5-4-1.
- Captain **B.Fernandes 23 (→46)** — the call of the week, and he was also POTW-level top scorer.
- **Calafiori 11** and made TOTW — the benefit-of-the-doubt hold (with the £0.5m
  buffer) is vindicated so far; the durability discount didn't cost us here.
- **3 of my players in GW2 TOTW**: Calafiori, B.Fernandes, Haaland (vs 0 in GW1).
- Transfer made: **Sarr -> Elanga**. Good pick (Elanga returned 8) BUT he scored
  those **8 on the bench** — no auto-sub fired because every starter played. He
  out-scored three starting mids (Tavernier 1, Anderson 3, Ndiaye 4).
  Lesson: if the model likes Elanga, he should START over the weakest mid, not sit.

## Optimiser suggestion — `gw02_suggested_squad.csv`
Reconstructed from the GW2 `res2` output (fixture-weighted `xp_fixture`, NOT
blended). Wildcard-optimal (fresh 15, not transfer-constrained). Captain De Cuyper.
CAVEAT: the xP are small-sample mirages off one game — De Cuyper 14.55, Guéhi
10.86, etc. This is the exhibit for why early-season shrinkage is needed. To
compare its real return vs my 107, pull GW2 actuals in R (fetch_event_points(2))
for those players.

## To review
- Bench/lineup selection: we optimise the 15 and the XI, but the ACTUAL XI I
  fielded left 8 pts on the bench. Worth running print_squad()/bench_order() and
  actually fielding the suggested XI.
- Still pending: early-season shrinkage (per-90 off tiny samples), 1-FT/-4
  transfer optimiser, EDA predictor selection, set-piece bonus, chips.
