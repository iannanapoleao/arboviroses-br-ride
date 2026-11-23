# =============================================================================
# 04 — Mapas de incidência acumulada no ano (Brasil por UF e RIDE-DF)
# Usa os dados já baixados em data/. Ano: variável MAPA_ANO (padrão = ano atual)
# Saída: figuras/*.png (16:9, prontas para slide)
# =============================================================================

source("R/00_config.R", encoding = "UTF-8")
source("R/funcoes_mapas.R", encoding = "UTF-8")

ano_mapa <- as.integer(Sys.getenv("MAPA_ANO", ANO_ATUAL))
ler <- function(arq) {
  readr::read_csv(arq, show_col_types = FALSE) |>
    mutate(ano = as.integer(ano), se = as.integer(se),
           casos = as.numeric(casos), casprov = as.numeric(casprov), pop = as.numeric(pop))
}
fonte_txt <- function(se_max) {
  sprintf("Fonte: InfoDengue (casos prováveis, SINAN). SE 01 a %02d/%d. Dados sujeitos a revisão.",
          se_max, ano_mapa)
}

# Malhas em GeoJSON para o painel web (só cria se ainda não existirem)
tryCatch({
  ride_ref <- carregar_ride()
  exportar_geojson(malha_ride(ride_ref) |> left_join(ride_ref, by = "geocode"),
                   "data/ref/ride.geojson")
  exportar_geojson(malha_ufs(), "data/ref/ufs.geojson")
}, error = function(e) message("Falha ao exportar GeoJSON: ", conditionMessage(e)))

# -----------------------------------------------------------------------------
# RIDE-DF
# -----------------------------------------------------------------------------
arq_ride <- "data/ride/infodengue_ride_semanal.csv"
if (file.exists(arq_ride)) {
  ride <- carregar_ride()
  malha <- malha_ride(ride)
  acum <- acumular(ler(arq_ride), "geocode", ano_mapa)

  for (d in c("dengue", "chikungunya")) {  # Zika não tem prováveis no InfoDengue
    dd <- filter(acum, doenca == d)
    if (nrow(dd) == 0) next
    m <- malha |>
      left_join(dd, by = "geocode") |>
      left_join(ride, by = "geocode")

    # rótulo nos 5 municípios com maior incidência
    top <- m |>
      filter(!is.na(inc_100k), casos > 0) |>
      slice_max(inc_100k, n = 5, with_ties = FALSE) |>
      mutate(rotulo = paste0(municipio, "\n",
                             format(round(inc_100k, 1), decimal.mark = ",")))
    top <- suppressWarnings(sf::st_point_on_surface(top))

    p <- mapa_incidencia(
      m,
      titulo = paste("Incidência de", DOENCAS[[d]], "— RIDE-DF"),
      subtitulo = paste("Casos prováveis por 100 mil habitantes,", ano_mapa),
      legenda_fonte = fonte_txt(max(dd$se_max, na.rm = TRUE)),
      rotulos = top
    )
    salvar_slide(p, sprintf("figuras/ride_incidencia_%s_%d.png", d, ano_mapa))
  }
} else {
  message("Sem dados da RIDE ainda (rode scripts/01).")
}

# -----------------------------------------------------------------------------
# Brasil por UF
# -----------------------------------------------------------------------------
arqs_br <- Sys.glob("data/brasil/infodengue_uf_*.csv")
if (length(arqs_br) > 0) {
  malha <- malha_ufs()
  acum <- acumular(bind_rows(lapply(arqs_br, ler)), "uf", ano_mapa)

  for (d in c("dengue", "chikungunya")) {  # Zika não tem prováveis no InfoDengue
    dd <- filter(acum, doenca == d)
    if (nrow(dd) == 0) next
    m <- left_join(malha, dd, by = "uf")
    p <- mapa_incidencia(
      m,
      titulo = paste("Incidência de", DOENCAS[[d]], "por UF — Brasil"),
      subtitulo = paste("Casos prováveis por 100 mil habitantes,", ano_mapa),
      legenda_fonte = fonte_txt(max(dd$se_max, na.rm = TRUE))
    )
    salvar_slide(p, sprintf("figuras/brasil_incidencia_%s_%d.png", d, ano_mapa))
  }
} else {
  message("Sem dados do Brasil ainda (rode scripts/02).")
}
