# =============================================================================
# 03 — DATASUS/SINAN (microdatasus): dengue, chik e Zika
# Baixa o arquivo nacional de cada ano, resume e descarta os microdados.
# Os arquivos do DATASUS saem com atraso: se o ano ainda não estiver
# publicado, o script só avisa e segue.
#
# Anos: variável ANOS_DATASUS (ex.: "2025,2026"); padrão = ano anterior e atual
# Saídas:
#   data/datasus/sinan_uf_semana.csv     (Brasil, por UF de residência)
#   data/datasus/sinan_ride_perfil.csv   (RIDE-DF, por município de residência)
# =============================================================================

source("R/00_config.R", encoding = "UTF-8")
source("R/funcoes_datasus.R", encoding = "UTF-8")

anos <- Sys.getenv("ANOS_DATASUS", "")
anos <- if (nzchar(anos)) as.integer(strsplit(anos, ",")[[1]]) else c(ANO_ATUAL - 1, ANO_ATUAL)

ride <- carregar_ride()

arq_uf   <- "data/datasus/sinan_uf_semana.csv"
arq_ride <- "data/datasus/sinan_ride_perfil.csv"

# Troca o bloco inteiro (doença + ano) para não sobrar combinação antiga
substituir_bloco <- function(novos, arquivo, doenca_alvo, ano_alvo) {
  if (file.exists(arquivo)) {
    antigos <- readr::read_csv(arquivo, show_col_types = FALSE,
                               col_types = readr::cols(.default = "c")) |>
      filter(!(doenca == doenca_alvo & ano_arquivo == as.character(ano_alvo)))
    novos <- bind_rows(antigos, mutate(novos, across(everything(), as.character)))
  }
  dir.create(dirname(arquivo), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(novos, arquivo, na = "")
  message("Salvo: ", arquivo, " (", nrow(novos), " linhas)")
}

for (doenca in names(DOENCAS)) {
  for (ano in anos) {
    bruto <- baixar_sinan(doenca, ano)
    if (is.null(bruto) || nrow(bruto) == 0) next

    prep <- preparar_sinan(bruto, doenca, ano)
    rm(bruto); invisible(gc())

    substituir_bloco(resumo_uf(prep), arq_uf, doenca, ano)
    substituir_bloco(resumo_ride(prep, ride), arq_ride, doenca, ano)

    rm(prep); invisible(gc())
  }
}
