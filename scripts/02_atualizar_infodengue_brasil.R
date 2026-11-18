# =============================================================================
# 02 — InfoDengue via Mosqlimate: Brasil por UF, dengue/chik/Zika, por semana
# Precisa da chave do Mosqlimate na variável de ambiente MOSQLIMATE_API_KEY
# (no GitHub: Settings > Secrets and variables > Actions).
#
# Cada execução baixa só as últimas SEMANAS_JANELA semanas (padrão 8).
# Para a carga inicial, defina ANO_INICIAL (ex.: ANO_INICIAL=2025).
# Para rodar só algumas doenças: DOENCAS_BR=dengue,zika
# O arquivo é salvo ao fim de cada doença, então uma queda no meio não perde tudo.
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
doencas <- Sys.getenv("DOENCAS_BR", "")
doencas <- if (nzchar(doencas)) trimws(strsplit(doencas, ",")[[1]]) else names(DOENCAS)

fim <- Sys.Date()
inicio <- if (nzchar(ano_inicial)) {
  inicio_se(as.integer(ano_inicial), 1)
} else if (!file.exists(arquivo)) {
  inicio_se(ANO_ATUAL, 1)
} else {
  fim - 7 * SEMANAS_JANELA
}

message("Recorte Brasil: ", inicio, " a ", fim, " | doenças: ", paste(doencas, collapse = ", "))
intervalo <- intervalo_mosqlimate(api_key)
message("Intervalo entre chamadas: ", round(intervalo, 2), " s")

total_falhas <- 0
for (doenca in doencas) {
  resultados <- list()
  falhas_seguidas <- 0

  for (uf in unname(UFS)) {
    t0 <- Sys.time()
    mun <- tryCatch(
      buscar_mosqlimate_uf(uf, doenca, inicio, fim, api_key, intervalo = intervalo),
      error = function(e) {
        message("  ", doenca, " — ", uf, ": falhou (", conditionMessage(e), ")")
        NULL
      }
    )

    if (is.null(mun) || nrow(mun) == 0) {
      falhas_seguidas <- falhas_seguidas + 1
      total_falhas <- total_falhas + 1
      if (falhas_seguidas >= 3) {
        message("  3 falhas seguidas em ", doenca, "; salvando o que já veio e parando.")
        break
      }
      next
    }

    falhas_seguidas <- 0
    resultados[[length(resultados) + 1]] <- agregar_uf(mun, uf)
    message(sprintf("  %s — %s: %d linhas (%.0f s)", doenca, uf, nrow(mun),
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }

  novos <- bind_rows(resultados)
  if (nrow(novos) > 0) {
    novos$atualizado_em <- as.character(Sys.Date())
    atualizar_arquivo(novos, arquivo, chaves = c("doenca", "uf", "ano", "se"))
  }
  if (falhas_seguidas >= 3) break
}

if (total_falhas > 0) {
  stop(total_falhas, " UF(s) sem dados nesta execução; o que foi baixado já está salvo.")
}
