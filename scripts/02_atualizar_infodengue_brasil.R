# =============================================================================
# 02 — InfoDengue via Mosqlimate: Brasil por UF, dengue/chik/Zika, por semana
# Precisa da chave do Mosqlimate na variável de ambiente MOSQLIMATE_API_KEY
# (no GitHub: Settings > Secrets and variables > Actions).
#
# Cada execução baixa só as últimas SEMANAS_JANELA semanas (padrão 8).
# Para a carga inicial, defina ANO_INICIAL (ex.: ANO_INICIAL=2025).
# Saída: data/brasil/infodengue_uf_semanal.csv
# =============================================================================

source("R/00_config.R", encoding = "UTF-8")
source("R/funcoes_infodengue.R", encoding = "UTF-8")

api_key <- Sys.getenv("MOSQLIMATE_API_KEY", "")
if (!nzchar(api_key)) {
  message("MOSQLIMATE_API_KEY não definida — pulando o recorte Brasil.")
  quit(save = "no", status = 0)
}

arquivo <- "data/brasil/infodengue_uf_semanal.csv"
ano_inicial <- Sys.getenv("ANO_INICIAL", "")

fim <- Sys.Date()
inicio <- if (nzchar(ano_inicial)) {
  inicio_se(as.integer(ano_inicial), 1)
} else if (!file.exists(arquivo)) {
  inicio_se(ANO_ATUAL, 1)
} else {
  fim - 7 * SEMANAS_JANELA
}

message("Recorte Brasil: ", inicio, " a ", fim)

resultados <- list()
falhas <- character()
for (doenca in names(DOENCAS)) {
  for (uf in unname(UFS)) {
    message("  ", doenca, " — ", uf)
    mun <- tryCatch(
      buscar_mosqlimate_uf(uf, doenca, inicio, fim, api_key),
      error = function(e) {
        message("    falhou: ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(mun) || nrow(mun) == 0) {
      falhas <- c(falhas, paste(doenca, uf))
      next
    }
    resultados[[length(resultados) + 1]] <- agregar_uf(mun, uf)
  }
}

if (length(falhas) > 0) message("Sem dados/falhas: ", paste(falhas, collapse = ", "))

novos <- bind_rows(resultados) |>
  mutate(atualizado_em = as.character(Sys.Date()))

atualizar_arquivo(novos, arquivo, chaves = c("doenca", "uf", "ano", "se"))

if (length(falhas) > 0.2 * length(DOENCAS) * length(UFS)) {
  stop("Muitas UFs sem dados nesta execução; confira a API do Mosqlimate.")
}
