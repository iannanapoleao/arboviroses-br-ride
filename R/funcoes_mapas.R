# =============================================================================
# Funções de mapa — tema e escalas nas cores do NVEPI Leste
# =============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(ggplot2)
  library(dplyr)
})

theme_nvepi_mapa <- function(base_size = 13) {
  theme_void(base_size = base_size) +
    theme(
      plot.title    = element_text(face = "bold", colour = NVEPI[["azul"]],
                                   size = rel(1.35), hjust = 0.5,
                                   margin = margin(b = 4)),
      plot.subtitle = element_text(colour = NVEPI[["cinza_txt"]], hjust = 0.5,
                                   margin = margin(b = 10)),
      plot.caption  = element_text(colour = NVEPI[["cinza_txt"]], size = rel(0.72),
                                   hjust = 0, margin = margin(t = 10)),
      legend.title  = element_text(colour = NVEPI[["cinza_esc"]], face = "bold",
                                   size = rel(0.82)),
      legend.text   = element_text(colour = NVEPI[["cinza_txt"]], size = rel(0.78)),
      legend.position  = "bottom",
      legend.key.width = grid::unit(2.2, "cm"),
      legend.key.height = grid::unit(0.35, "cm"),
      legend.title.position = "top",
      plot.background  = element_rect(fill = "white", colour = NA),
      plot.margin      = margin(15, 15, 15, 15)
    )
}

escala_incidencia <- function(paleta = PAL_SEQ_AZUL) {
  scale_fill_gradientn(
    colours = paleta,
    name = "Incidência\n(por 100 mil hab.)",
    labels = scales::label_number(big.mark = ".", decimal.mark = ","),
    na.value = "grey90"
  )
}

# Malhas do IBGE (via geobr), guardadas em data/ref para não baixar sempre
malha_ufs <- function(arquivo = "data/ref/malha_ufs.gpkg") {
  if (file.exists(arquivo)) return(sf::st_read(arquivo, quiet = TRUE))
  m <- geobr::read_state(year = 2020, showProgress = FALSE) |>
    transmute(uf = abbrev_state) |>
    sf::st_simplify(dTolerance = 2000, preserveTopology = TRUE)
  sf::st_write(m, arquivo, quiet = TRUE, delete_dsn = TRUE)
  m
}

malha_ride <- function(ride, arquivo = "data/ref/malha_ride.gpkg") {
  if (file.exists(arquivo)) return(sf::st_read(arquivo, quiet = TRUE))
  m <- lapply(c("DF", "GO", "MG"), function(u) {
    geobr::read_municipality(code_muni = u, year = 2020, showProgress = FALSE)
  }) |>
    bind_rows() |>
    mutate(geocode = as.integer(code_muni)) |>
    filter(geocode %in% ride$geocode) |>
    select(geocode) |>
    sf::st_simplify(dTolerance = 200, preserveTopology = TRUE)
  sf::st_write(m, arquivo, quiet = TRUE, delete_dsn = TRUE)
  m
}

# GeoJSON leve para o painel web (data/ref/*.geojson)
exportar_geojson <- function(malha, arquivo) {
  if (file.exists(arquivo)) return(invisible(arquivo))
  malha <- sf::st_transform(malha, 4326)
  sf::st_write(malha, arquivo, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE,
               layer_options = "COORDINATE_PRECISION=4")
  message("GeoJSON: ", arquivo)
  invisible(arquivo)
}

# Acumulado do ano: soma dos casos / população da última semana
acumular <- function(dados, chave, ano_alvo) {
  dados |>
    filter(ano == ano_alvo) |>
    group_by(across(all_of(c("doenca", chave)))) |>
    arrange(se, .by_group = TRUE) |>
    summarise(
      casos  = sum(casprov, na.rm = TRUE),   # casos prováveis
      pop    = dplyr::last(pop),
      se_max = max(se, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(inc_100k = casos / pop * 1e5)
}

mapa_incidencia <- function(malha_sf, titulo, subtitulo, legenda_fonte,
                            paleta = PAL_SEQ_AZUL, rotulos = NULL) {
  p <- ggplot(malha_sf) +
    geom_sf(aes(fill = inc_100k), colour = "white", linewidth = 0.3) +
    escala_incidencia(paleta) +
    ggspatial::annotation_north_arrow(
      location = "tr", which_north = "true",
      height = grid::unit(1.3, "cm"), width = grid::unit(1.1, "cm"),
      style = ggspatial::north_arrow_fancy_orienteering(
        fill = c(NVEPI[["azul"]], "white"), line_col = NVEPI[["cinza_esc"]],
        text_col = NVEPI[["cinza_esc"]])
    ) +
    ggspatial::annotation_scale(location = "bl", width_hint = 0.25,
                                bar_cols = c(NVEPI[["cinza_esc"]], "white"),
                                text_col = NVEPI[["cinza_esc"]]) +
    labs(title = titulo, subtitle = subtitulo, caption = legenda_fonte) +
    theme_nvepi_mapa()

  if (!is.null(rotulos) && nrow(rotulos) > 0) {
    p <- p + geom_sf_label(
      data = rotulos, aes(label = rotulo),
      size = 2.8, colour = NVEPI[["cinza_esc"]],
      fill = scales::alpha("white", 0.85), label.size = 0, fontface = "bold"
    )
  }
  p
}

salvar_slide <- function(p, arquivo) {
  dir.create(dirname(arquivo), recursive = TRUE, showWarnings = FALSE)
  ggsave(arquivo, p, width = 11, height = 6.2, dpi = 300, bg = "white")
  message("Figura: ", arquivo)
}
