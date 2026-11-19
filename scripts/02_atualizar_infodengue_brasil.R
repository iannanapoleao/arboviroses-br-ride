# =============================================================================
# 02 — InfoDengue: Brasil por UF, uma doença por execução
# Mesma API pública da RIDE-DF (sem chave): baixa os 5.570 municípios um a um
# e soma por UF. Só a soma por UF vai para o repositório.
#
# Variáveis:
#   DOENCA_BR     dengue | chikungunya | zika (obrigatória)
#   ANOS_BR       anos separados por vírgula; padrão = ano atual, mais o
#                 anterior se ainda não estiver no arquivo ou se estivermos
#                 nas 8 primeiras semanas do ano
#   PAUSA_SEG     pausa entre chamadas (padrão 0.3)
# Saída: data/brasil/infodengue_uf_<doenca>.csv
# O arquivo é salvo a cada UF; uma UF com mais de 5% de municípios sem
# resposta não é gravada (fica a versão anterior), para não subestimar casos.
# =============================================================================

source("R/00_config.R", encoding = "UTF-8")
source("R/funcoes_infodengue.R", encoding = "UTF-8")

doenca <- Sys.getenv("DOENCA_BR", "dengue")
if (!doenca %in% names(DOENCAS)) stop("DOENCA_BR inválida: ", doenca)
pausa <- as.numeric(Sys.getenv("PAUSA_SEG", "0.3"))
arquivo <- sprintf("data/brasil/infodengue_uf_%s.csv", doenca)

anos <- Sys.getenv("ANOS_BR", "")
if (nzchar(anos)) {
  anos <- as.integer(strsplit(anos, ",")[[1]])
} else {
  ja_tem <- if (file.exists(arquivo)) {
    unique(as.integer(readr::read_csv(arquivo, col_select = "ano", show_col_types = FALSE)$ano))
  } else integer()
  anos <- ANO_ATUAL
  if (!(ANO_ATUAL - 1) %in% ja_tem || SE_ATUAL <= 8) anos <- c(ANO_ATUAL - 1, anos)
}

municipios <- carregar_municipios_br()
message(doenca, " | anos: ", paste(anos, collapse = ", "), " | ",
        nrow(municipios), " municípios")

t0 <- Sys.time()
for (uf in unname(UFS)) {
  mun_uf <- municipios[municipios$uf == uf, ]
  partes <- list(); falhas <- 0
  for (g in mun_uf$geocode) {
    for (ano in anos) {
      r <- tryCatch(buscar_alertcity(g, doenca, ano), error = function(e) {
        falhas <<- falhas + 1
        NULL
      })
      if (!is.null(r)) partes[[length(partes) + 1]] <- r
      Sys.sleep(pausa)
    }
  }
  total <- nrow(mun_uf) * length(anos)
  if (falhas > 0.05 * total) {
    message(sprintf("  %s: %d de %d chamadas falharam — UF não gravada nesta execução", uf, falhas, total))
    next
  }
  mun <- bind_rows(partes)
  if (nrow(mun) == 0) {
    message("  ", uf, ": sem dados")
    next
  }
  novos <- agregar_uf(mun, uf)
  novos$atualizado_em <- as.character(Sys.Date())
  atualizar_arquivo(novos, arquivo, chaves = c("doenca", "uf", "ano", "se"))
  message(sprintf("  %s: %d municípios, %d falhas (%.0f min decorridos)", uf, nrow(mun_uf), falhas,
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}
