# =============================================================================
# 01 — InfoDengue: RIDE-DF (DF + 33 municípios), dengue/chik/Zika, por semana
# Não precisa de chave. Baixa o ano anterior e o atual inteiros a cada execução.
# Saída: data/ride/infodengue_ride_semanal.csv
# =============================================================================

source("R/00_config.R", encoding = "UTF-8")
source("R/funcoes_infodengue.R", encoding = "UTF-8")

anos <- Sys.getenv("ANOS_RIDE", "")
anos <- if (nzchar(anos)) as.integer(strsplit(anos, ",")[[1]]) else c(ANO_ATUAL - 1, ANO_ATUAL)

ride <- carregar_ride()
combinacoes <- expand.grid(geocode = ride$geocode, doenca = names(DOENCAS),
                           ano = anos, stringsAsFactors = FALSE)

message("Baixando ", nrow(combinacoes), " séries do InfoDengue (RIDE-DF)...")

resultados <- vector("list", nrow(combinacoes))
falhas <- 0
for (i in seq_len(nrow(combinacoes))) {
  cb <- combinacoes[i, ]
  resultados[[i]] <- tryCatch(
    buscar_alertcity(cb$geocode, cb$doenca, cb$ano),
    error = function(e) {
      falhas <<- falhas + 1
      message("  falhou: ", cb$geocode, " ", cb$doenca, " ", cb$ano, " — ", conditionMessage(e))
      NULL
    }
  )
  Sys.sleep(0.3)
}

novos <- bind_rows(resultados) |>
  left_join(ride, by = "geocode") |>
  relocate(municipio, uf, .after = geocode) |>
  mutate(atualizado_em = as.character(Sys.Date()))

message("Linhas baixadas: ", nrow(novos), " | falhas: ", falhas)

if (falhas > 0.2 * nrow(combinacoes)) {
  stop("Mais de 20% das chamadas falharam; os dados antigos foram mantidos.")
}

atualizar_arquivo(
  novos,
  "data/ride/infodengue_ride_semanal.csv",
  chaves = c("doenca", "geocode", "ano", "se")
)
