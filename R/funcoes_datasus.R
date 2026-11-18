# =============================================================================
# Funções — microdados do SINAN (DATASUS) via microdatasus
# Os microdados não são salvos no repositório: só tabelas agregadas.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

baixar_sinan <- function(doenca, ano) {
  sistema <- SISTEMAS_SINAN[[doenca]]
  message("Baixando ", sistema, " ", ano, " (arquivo nacional, pode demorar)...")
  tryCatch(
    microdatasus::fetch_datasus(
      year_start = ano, year_end = ano, information_system = sistema
    ),
    error = function(e) {
      message("  não disponível/erro: ", conditionMessage(e))
      NULL
    }
  )
}

col <- function(df, nome) {
  if (nome %in% names(df)) as.character(df[[nome]]) else rep(NA_character_, nrow(df))
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
  cut(anos,
      breaks = c(-Inf, 0, 4, 9, 14, 19, 29, 39, 49, 59, 69, 79, Inf),
      labels = c("<1", "1-4", "5-9", "10-14", "15-19", "20-29", "30-39",
                 "40-49", "50-59", "60-69", "70-79", "80+"))
}

# Variáveis brutas do SINAN que entram nas tabelas agregadas
preparar_sinan <- function(df, doenca, ano) {
  tibble::tibble(
    doenca         = doenca,
    ano_arquivo    = as.integer(ano),
    uf_resid_cod   = col(df, "SG_UF"),
    cod_mun_resid  = col(df, "ID_MN_RESI"),
    sem_pri        = col(df, "SEM_PRI"),
    classi_fin     = col(df, "CLASSI_FIN"),
    criterio       = col(df, "CRITERIO"),
    sexo           = col(df, "CS_SEXO"),
    faixa_etaria   = as.character(faixa_etaria(col(df, "NU_IDADE_N"))),
    hospitalizado  = col(df, "HOSPITALIZ"),
    evolucao       = col(df, "EVOLUCAO")
  ) |>
    mutate(
      uf_resid = unname(UFS[uf_resid_cod]),
      across(c(classi_fin, criterio, sexo, hospitalizado, evolucao),
             ~ ifelse(is.na(.x) | trimws(.x) == "", "(em branco)", trimws(.x)))
    )
}

# Brasil: notificações por UF de residência, semana de início dos sintomas
# e classificação final
resumo_uf <- function(prep) {
  prep |>
    count(doenca, ano_arquivo, uf_resid, sem_pri, classi_fin, name = "n")
}

# RIDE-DF: perfil por município de residência (código IBGE de 6 dígitos)
resumo_ride <- function(prep, ride) {
  ride6 <- ride |> mutate(cod_mun_resid = substr(as.character(geocode), 1, 6))
  prep |>
    inner_join(ride6 |> select(cod_mun_resid, geocode, municipio, uf),
               by = "cod_mun_resid") |>
    count(doenca, ano_arquivo, geocode, municipio, uf, sem_pri, classi_fin,
          criterio, sexo, faixa_etaria, hospitalizado, evolucao, name = "n")
}
