library(tidyverse)
library(FPLdata)

devtools::install_github("chrisbrownlie/fantasy")

library(fantasy)
library(ggrepel)

# Gathering relevant data

Fixtures <- get_fixture_list()

Fixtures_stats <- get_fixture_stats()

Team_stats <- get_teams()

Players_stats <- get_players()

Predicted_lineups <- get_predicted_lineups()

Team_colours <- c("#EF0107", "#670E36", "#DA291C", "#E30613", "#0057B8", "#6A1D2F",
                  "#034694", "#1B458F", "#003399", "#000000", "#C8102E", "#F36F21",
                  "#6CABDD", "#DA291C", "#241F20", "#DD0000", "#EE2737", "#132257",
                  "#7A263A", "#FDB913")

Team_stats01 <- cbind(Team_stats, Team_colours)

# Basic Stats and Visuals

ggplot(Team_stats, aes(x = strength_overall_home, y = strength_overall_away)) +
  geom_point(aes(color = Team_colours), size = 3) +
  geom_text_repel(aes(label = short_name), show.legend = FALSE) +
  scale_color_identity()
