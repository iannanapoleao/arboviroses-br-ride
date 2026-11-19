# =============================================================================
# 03 — DATASUS/SINAN (microdatasus): dengue, chik e Zika — casos prováveis
# Baixa o arquivo nacional de cada ano, resume e descarta os microdados.
# Os arquivos do DATASUS saem com atraso: se o ano ainda não estiver
# publicado, o script só avisa e segue.
#
# Anos: variável ANOS_DATASUS (ex.: "2025,2026"); padrão = ano anterior e atual
# Saída: data/datasus/sinan_perfil.csv (tabela longa)
#   doenca, ano_arquivo, ano (da SE de início dos sintomas), nivel (uf | mun),
#   territorio (sigla da UF ou geocódigo IBGE), variavel, categoria, n
#   variavel: semana, sexo_faixa, raca, escolaridade, classificacao,
#             hospitalizacao, evolucao
# =============================================================================

source("R/00_config.R", encoding = "UTF-8")
source("R/funcoes_datasus.R", encoding = "UTF-8")

anos <- Sys.getenv("ANOS_DATASUS", "")
anos <- if (nzchar(anos)) as.integer(strsplit(anos, ",")[[1]]) else c(ANO_ATUAL - 1, ANO_ATUAL)
doencas <- Sys.getenv("DOENCAS_DATASUS", "")
doencas <- if (nzchar(doencas)) trimws(strsplit(doencas, ",")[[1]]) else c("zika", "chikungunya", "dengue")  # menores primeiro

ride <- carregar_ride()
arquivo <- "data/datasus/sinan_perfil.csv"

# Troca o bloco inteiro (doença + ano do arquivo) para não sobrar combinação antiga
substituir_bloco <- function(novos, doenca_alvo, ano_alvo) {
  novos <- mutate(novos, across(everything(), as.character))
  if (file.exists(arquivo)) {
    antigos <- readr::read_csv(arquivo, show_col_types = FALSE,
                               col_types = readr::cols(.default = "c")) |>
      filter(!(doenca == doenca_alvo & ano_arquivo == as.character(ano_alvo)))
    novos <- bind_rows(antigos, novos)
  }
  dir.create(dirname(arquivo), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(novos, arquivo, na = "")
  message("Salvo: ", arquivo, " (", nrow(novos), " linhas)")
}

for (doenca in doencas) {
  for (ano in anos) {
    bruto <- baixar_sinan(doenca, ano)
    if (is.null(bruto) || nrow(bruto) == 0) next
    message("  ", nrow(bruto), " notificações")

    prep <- preparar_sinan(bruto, doenca, ano)
    rm(bruto); invisible(gc())
    message("  ", nrow(prep), " casos prováveis")

    substituir_bloco(resumir_perfil(prep, ride), doenca, ano)
    rm(prep); invisible(gc())
  }
}

# Arquivos do formato antigo não são mais usados
unlink(c("data/datasus/sinan_uf_semana.csv", "data/datasus/sinan_ride_perfil.csv"))
