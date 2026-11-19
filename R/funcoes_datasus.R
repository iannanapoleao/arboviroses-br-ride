# =============================================================================
# Funções — microdados do SINAN (DATASUS) via microdatasus
# Os microdados não são salvos no repositório: só tabelas agregadas
# (contagens de casos PROVÁVEIS, isto é, notificados menos descartados).
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

VARS_SINAN <- c("SG_UF", "ID_MN_RESI", "SEM_PRI", "CLASSI_FIN", "CRITERIO",
                "CS_SEXO", "NU_IDADE_N", "CS_RACA", "CS_ESCOL_N",
                "HOSPITALIZ", "EVOLUCAO")

# Código de "descartado" em CLASSI_FIN
DESCARTADO <- c(dengue = "5", chikungunya = "5", zika = "2")

baixar_sinan <- function(doenca, ano, tentativas = 4) {
  sistema <- SISTEMAS_SINAN[[doenca]]
  vars_doenca <- if (doenca == "zika") setdiff(VARS_SINAN, "HOSPITALIZ") else VARS_SINAN
  baixar <- function(vars) microdatasus::fetch_datasus(
    year_start = ano, year_end = ano, information_system = sistema, vars = vars,
    timeout = 900
  )
  # o FTP do DATASUS cai com frequência: tenta de novo algumas vezes
  for (i in seq_len(tentativas)) {
    message("Baixando ", sistema, " ", ano, " (tentativa ", i, " de ", tentativas, ")...")
    df <- tryCatch(
      baixar(vars_doenca),
      error = function(e) {
        message("  erro: ", conditionMessage(e))
        if (grepl("Unknown variable|variable", conditionMessage(e), ignore.case = TRUE)) {
          tryCatch(baixar(NULL), error = function(e2) NULL)
        } else NULL
      }
    )
    if (!is.null(df) && nrow(df) > 0) return(df)
    if (i < tentativas) Sys.sleep(60 * i)
  }
  message("  não foi possível baixar ", sistema, " ", ano, " desta vez")
  NULL
}

col <- function(df, nome) {
  if (nome %in% names(df)) trimws(as.character(df[[nome]])) else rep(NA_character_, nrow(df))
}

faixa_etaria <- function(nu_idade_n) {
  x <- as.character(nu_idade_n)
  unidade <- substr(x, 1, 1)
  valor <- suppressWarnings(as.integer(substr(x, 2, 4)))
  anos <- dplyr::case_when(
    unidade == "4" ~ valor,
    unidade %in% c("1", "2", "3") ~ 0L,
    TRUE ~ NA_integer_
  )
  as.character(cut(anos,
    breaks = c(-Inf, 0, 4, 9, 14, 19, 29, 39, 49, 59, 69, 79, Inf),
    labels = c("<1", "1-4", "5-9", "10-14", "15-19", "20-29", "30-39",
               "40-49", "50-59", "60-69", "70-79", "80+")))
}

rotular <- function(x, mapa, outro = "Ignorado/em branco") {
  out <- unname(mapa[x])
  out[is.na(out)] <- outro
  out
}

ROT_SEXO  <- c(M = "Masculino", F = "Feminino")
ROT_RACA  <- c("1" = "Branca", "2" = "Preta", "3" = "Amarela", "4" = "Parda", "5" = "Indígena")
ROT_ESCOL <- c("0" = "Analfabeto", "1" = "Fund. I incompleto", "2" = "Fund. I completo",
               "3" = "Fund. II incompleto", "4" = "Fund. completo", "5" = "Médio incompleto",
               "6" = "Médio completo", "7" = "Superior incompleto", "8" = "Superior completo",
               "10" = "Não se aplica")
ROT_HOSP  <- c("1" = "Sim", "2" = "Não")
ROT_EVOL  <- c("1" = "Cura", "2" = "Óbito pelo agravo", "3" = "Óbito por outras causas",
               "4" = "Óbito em investigação")
ROT_CLASS <- list(
  dengue = c("10" = "Dengue", "11" = "Dengue com sinais de alarme", "12" = "Dengue grave",
             "13" = "Chikungunya", "8" = "Inconclusivo"),
  chikungunya = c("13" = "Chikungunya", "10" = "Dengue", "11" = "Dengue com sinais de alarme",
                  "12" = "Dengue grave", "8" = "Inconclusivo"),
  zika = c("1" = "Confirmado")
)

# Casos prováveis com as variáveis já rotuladas
preparar_sinan <- function(df, doenca, ano) {
  classi <- col(df, "CLASSI_FIN")
  provavel <- is.na(classi) | classi != DESCARTADO[[doenca]]
  df <- df[provavel, , drop = FALSE]
  classi <- classi[provavel]
  sem <- col(df, "SEM_PRI")
  # rotula antes do tibble(): lá dentro, "doenca" passaria a ser a coluna
  classificacao <- rotular(classi, ROT_CLASS[[doenca]], outro = "Em investigação")
  nome_doenca <- doenca

  tibble::tibble(
    doenca        = nome_doenca,
    ano_arquivo   = as.integer(ano),
    ano           = suppressWarnings(as.integer(substr(sem, 1, 4))),
    se            = suppressWarnings(as.integer(substr(sem, 5, 6))),
    uf            = unname(UFS[col(df, "SG_UF")]),
    cod_mun6      = substr(col(df, "ID_MN_RESI"), 1, 6),
    sexo          = rotular(col(df, "CS_SEXO"), ROT_SEXO),
    faixa         = dplyr::coalesce(faixa_etaria(col(df, "NU_IDADE_N")), "Ignorada"),
    raca          = rotular(col(df, "CS_RACA"), ROT_RACA),
    escolaridade  = rotular(col(df, "CS_ESCOL_N"), ROT_ESCOL),
    classificacao = classificacao,
    hospitalizacao = rotular(col(df, "HOSPITALIZ"), ROT_HOSP),
    evolucao      = rotular(col(df, "EVOLUCAO"), ROT_EVOL)
  ) |>
    filter(!is.na(ano))
}

# Tabela longa: uma linha por território x variável x categoria
# nivel = "uf" (Brasil, por UF de residência) ou "mun" (município da RIDE-DF)
resumir_perfil <- function(prep, ride) {
  ride6 <- ride |>
    mutate(cod_mun6 = substr(as.character(geocode), 1, 6)) |>
    select(cod_mun6, geocode)

  base_uf  <- prep |> filter(!is.na(uf)) |> mutate(nivel = "uf", territorio = uf)
  base_mun <- prep |> inner_join(ride6, by = "cod_mun6") |>
    mutate(nivel = "mun", territorio = as.character(geocode))
  base <- bind_rows(base_uf, base_mun)

  contar <- function(variavel, categoria) {
    base |>
      mutate(variavel = variavel, categoria = categoria) |>
      count(doenca, ano_arquivo, ano, nivel, territorio, variavel, categoria, name = "n")
  }

  bind_rows(
    contar("semana", sprintf("%02d", base$se)),
    contar("sexo_faixa", paste(base$sexo, base$faixa, sep = "|")),
    contar("raca", base$raca),
    contar("escolaridade", base$escolaridade),
    contar("classificacao", base$classificacao),
    contar("hospitalizacao", base$hospitalizacao),
    contar("evolucao", base$evolucao)
  )
}
