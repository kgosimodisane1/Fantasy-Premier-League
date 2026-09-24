# GW1 — pre-deadline snapshot

Saved for post-GW analysis. Two squads recorded:
- `gw01_suggested_squad.csv` — the optimiser's pick (durability on, no fixture weighting)
- `gw01_my_squad.csv` — the squad Kgosi is actually fielding

Both captain **B.Fernandes**. Kgosi's vice = **Haaland**.

## Optimiser (suggested) XI — objective 59.48 xP, spend £99.5m, bank £0.5m
Raya; Gabriel, Virgil, Guéhi, Tarkowski; B.Fernandes (C), Enzo, Rice, Semenyo,
Anderson; Thiago.  Bench: Forster, Thomas, Furo, Ferguson.

## Kgosi's XI (4-5-1)
Raya; Virgil, Davis, Gabriel, Calafiori; Tavernier, B.Fernandes (C), Anderson,
Sarr, Ndiaye; Haaland (VC).  Bench: Dovin, Thomas, Kusi-Asare, Furo.

## Key divergences to watch post-GW
- **Haaland**: Kgosi starts him (and vices him); the optimiser DROPS him entirely
  and spreads the £15.5m across Thiago + Rice/Semenyo. Big template call to judge.
- **DEF**: optimiser Guéhi + Tarkowski vs Kgosi's Davis + Calafiori.
- **MID**: optimiser Enzo + Rice + Semenyo vs Kgosi's Tavernier + Sarr + Ndiaye.
- **Shared**: Raya, Gabriel, Virgil, B.Fernandes (C), Anderson.
- Optimiser left **Ferguson (BHA, injured, 0%)** on its bench as free fodder —
  flagged by the availability check; harmless (bench) but could be excluded.

## Team of the Week (official) — `gw01_team_of_the_week.csv`
Total 148 pts. Player of the Week: **De Cuyper (BHA, 17)**.
XI (4-5-1): Tzolakis 10; De Cuyper 17, Mendy 15, Ajayi 14, Kayode 13;
Hinshelwood 16, M.Sangaré 14, Palmer 13, Stach 13, Gakpo 12; João Pedro 11.

Observation: **none of our players (mine or the optimiser's) made GW1 TOTW.**
It was a differential-heavy week — cheap/explosive picks (De Cuyper, Hinshelwood,
Stach, Kayode). Worth revisiting once we have actual points whether our
template-heavy builds still scored well despite missing the TOTW spikes.

## Post-GW to-do
After the matches, run in R to score suggested vs mine vs ex-post optimal:
    record_actuals(players, gw = 1)
    read_tracker()
(Requires having logged the prediction in R first — see chat for the
log_prediction() call that stamps player ids for the automated comparison.)
