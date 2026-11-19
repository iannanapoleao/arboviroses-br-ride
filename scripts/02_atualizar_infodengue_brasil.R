# =============================================================================
# 02 — InfoDengue via Mosqlimate: Brasil por UF, dengue/chik/Zika, por semana
# Precisa da chave do Mosqlimate na variável de ambiente MOSQLIMATE_API_KEY
# (no GitHub: Settings > Secrets and variables > Actions).
#
# O Mosqlimate limita bastante as chamadas, então este script é RETOMÁVEL:
#  - salva o arquivo a cada UF concluída;
#  - pula as UFs atualizadas nos últimos DIAS_VALIDADE dias (padrão 5);
#  - UF sem dado nenhum recebe a carga do ano inteiro (ou desde ANO_INICIAL);
#  - UF com dado antigo recebe só as últimas SEMANAS_JANELA semanas (padrão 8);
#  - para sozinho ao chegar em TEMPO_MAX_MIN minutos (padrão 200) e a próxima
#    execução continua de onde parou.
# Para rodar só algumas doenças: DOENCAS_BR=dengue,zika
# Saída: data/brasil/infodengue_uf_semanal.csv
# =============================================================================

source("R/00_config.R", encoding = "UTF-8")
source("R/funcoes_infodengue.R", encoding = "UTF-8")

api_key <- Sys.getenv("MOSQLIMATE_API_KEY", "")
if (!nzchar(api_key)) {
  message("MOSQLIMATE_API_KEY não definida — pulando o recorte Brasil.")
  quit(save = "no", status = 0)
}

arquivo       <- "data/brasil/infodengue_uf_semanal.csv"
ano_inicial   <- as.integer(Sys.getenv("ANO_INICIAL", ANO_ATUAL))
if (is.na(ano_inicial)) ano_inicial <- ANO_ATUAL
dias_validade <- as.numeric(Sys.getenv("DIAS_VALIDADE", "5"))
tempo_max     <- as.numeric(Sys.getenv("TEMPO_MAX_MIN", "200"))
doencas <- Sys.getenv("DOENCAS_BR", "")
doencas <- if (nzchar(doencas)) trimws(strsplit(doencas, ",")[[1]]) else names(DOENCAS)

hoje <- Sys.Date()
t_inicio <- Sys.time()

# Situação de cada doença x UF no arquivo atual
situacao <- if (file.exists(arquivo)) {
  readr::read_csv(arquivo, show_col_types = FALSE,
                  col_types = readr::cols(.default = "c")) |>
    mutate(ano = as.integer(ano), atualizado_em = as.Date(atualizado_em)) |>
    group_by(doenca, uf) |>
    summarise(ano_min = min(ano, na.rm = TRUE),
              ultima = max(atualizado_em, na.rm = TRUE), .groups = "drop")
} else {
  tibble::tibble(doenca = character(), uf = character(),
                 ano_min = integer(), ultima = as.Date(character()))
}

intervalo <- intervalo_mosqlimate(api_key)
message("Doenças: ", paste(doencas, collapse = ", "), " | ano inicial: ", ano_inicial,
        " | limite de tempo: ", tempo_max, " min")

feitas <- 0; puladas <- 0; falhas <- 0; parou_por_tempo <- FALSE

for (doenca in doencas) {
  for (uf in unname(UFS)) {
    min_passados <- as.numeric(difftime(Sys.time(), t_inicio, units = "mins"))
    if (min_passados > tempo_max) { parou_por_tempo <- TRUE; break }

    s <- situacao[situacao$doenca == doenca & situacao$uf == uf, ]
    precisa_carga <- nrow(s) == 0 || is.na(s$ano_min) || s$ano_min > ano_inicial
    recente <- nrow(s) == 1 && !is.na(s$ultima) && (hoje - s$ultima) < dias_validade

    if (!precisa_carga && recente) { puladas <- puladas + 1; next }

    inicio <- if (precisa_carga) inicio_se(ano_inicial, 1) else hoje - 7 * SEMANAS_JANELA
    t0 <- Sys.time()
    mun <- tryCatch(
      buscar_mosqlimate_uf(uf, doenca, inicio, hoje, api_key, intervalo = intervalo),
      error = function(e) {
        message("  ", doenca, " — ", uf, ": falhou (", conditionMessage(e), ")")
        NULL
      }
    )
    if (is.null(mun) || nrow(mun) == 0) { falhas <- falhas + 1; next }

    novos <- agregar_uf(mun, uf)
    novos$atualizado_em <- as.character(hoje)
    atualizar_arquivo(novos, arquivo, chaves = c("doenca", "uf", "ano", "se"))
    feitas <- feitas + 1
    message(sprintf("  %s — %s: desde %s, %d linhas municipais (%.0f s)",
                    doenca, uf, inicio, nrow(mun),
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
  if (parou_por_tempo) break
}

message(sprintf("Resumo: %d UFs atualizadas, %d já em dia, %d falhas%s",
                feitas, puladas, falhas,
                if (parou_por_tempo) " — parou pelo limite de tempo; a próxima execução continua" else ""))
