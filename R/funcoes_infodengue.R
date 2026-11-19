# =============================================================================
# Funções de coleta — InfoDengue (API pública, sem chave)
# =============================================================================

suppressPackageStartupMessages({
  library(httr2)
  library(dplyr)
})

UA <- "arboviroses-br-ride (github.com/iannanapoleao/arboviroses-br-ride)"

# Pega uma coluna se existir; senão devolve NA do tamanho certo
pegar <- function(df, ...) {
  nomes <- tolower(c(...))
  achou <- intersect(nomes, names(df))
  if (length(achou) == 0) return(rep(NA, nrow(df)))
  df[[achou[1]]]
}

num <- function(x) suppressWarnings(as.numeric(x))

# data_iniSE pode vir como "2026-01-04" ou como milissegundos desde 1970
para_data <- function(x) {
  x <- as.character(x)
  out <- suppressWarnings(as.Date(x))
  ms <- is.na(out) & grepl("^[0-9]{10,}$", x)
  out[ms] <- as.Date(as.POSIXct(as.numeric(x[ms]) / 1000, origin = "1970-01-01", tz = "UTC"))
  out
}

# Deixa as colunas do InfoDengue num formato único
padronizar_infodengue <- function(df, doenca, fonte) {
  names(df) <- tolower(names(df))
  se_cod <- as.character(pegar(df, "se", "ew"))
  tibble::tibble(
    doenca      = doenca,
    geocode     = as.integer(pegar(df, "municipio_geocodigo", "geocodigo", "geocode")),
    ano         = as.integer(substr(se_cod, 1, 4)),
    se          = as.integer(substr(se_cod, 5, 6)),
    data_ini_se = para_data(pegar(df, "data_inise", "data_ini_se")),
    casos       = num(pegar(df, "casos")),
    casos_est   = num(pegar(df, "casos_est")),
    casprov     = num(pegar(df, "casprov")),
    casconf     = num(pegar(df, "casconf")),
    p_inc100k   = num(pegar(df, "p_inc100k")),
    nivel       = as.integer(pegar(df, "nivel")),
    rt          = num(pegar(df, "rt")),
    pop         = num(pegar(df, "pop")),
    receptivo   = as.integer(pegar(df, "receptivo")),
    transmissao = as.integer(pegar(df, "transmissao")),
    fonte       = fonte
  )
}

# -----------------------------------------------------------------------------
# InfoDengue — um município, uma doença, um ano (sem chave)
# -----------------------------------------------------------------------------
buscar_alertcity <- function(geocode, doenca, ano, se_ini = 1, se_fim = 53) {
  resp <- request("https://info.dengue.mat.br/api/alertcity") |>
    req_url_query(
      geocode = geocode, disease = doenca, format = "csv",
      ew_start = se_ini, ew_end = se_fim, ey_start = ano, ey_end = ano
    ) |>
    req_user_agent(UA) |>
    req_timeout(120) |>
    req_retry(max_tries = 4, backoff = function(i) 5 * i) |>
    req_perform()

  txt <- resp_body_string(resp)
  if (!nzchar(trimws(txt))) return(NULL)

  df <- readr::read_csv(I(txt), show_col_types = FALSE,
                        col_types = readr::cols(.default = "c"))
  if (nrow(df) == 0) return(NULL)

  out <- padronizar_infodengue(df, doenca, fonte = "InfoDengue/alertcity")
  # a API por município nem sempre devolve o geocódigo na tabela
  out$geocode <- as.integer(geocode)
  out
}

# Soma os municípios para ter a série semanal da UF
agregar_uf <- function(mun, uf) {
  mun |>
    filter(!is.na(se)) |>
    group_by(doenca, ano, se) |>
    summarise(
      data_ini_se = min(data_ini_se, na.rm = TRUE),
      n_municipios = n_distinct(geocode),
      casos   = sum(casos, na.rm = TRUE),
      casprov = if (all(is.na(casprov))) NA_real_ else sum(casprov, na.rm = TRUE),
      casconf = if (all(is.na(casconf))) NA_real_ else sum(casconf, na.rm = TRUE),
      pop     = sum(pop, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(uf = uf, inc_100k = casos / pop * 1e5, .after = doenca)
}

# -----------------------------------------------------------------------------
# Lista de todos os municípios do Brasil (IBGE), guardada em data/ref
# -----------------------------------------------------------------------------
carregar_municipios_br <- function(arquivo = "data/ref/municipios_br.csv") {
  if (file.exists(arquivo)) {
    return(readr::read_csv(arquivo, show_col_types = FALSE,
                           col_types = readr::cols(geocode = "i", .default = "c")))
  }
  message("Buscando a lista de municípios no IBGE...")
  mun <- dplyr::bind_rows(lapply(unname(UFS), function(uf) {
    js <- jsonlite::fromJSON(sprintf(
      "https://servicodados.ibge.gov.br/api/v1/localidades/estados/%s/municipios", uf))
    data.frame(geocode = as.integer(js$id), municipio = js$nome, uf = uf)
  }))
  if (nrow(mun) < 5500) stop("Lista de municípios incompleta: ", nrow(mun))
  dir.create(dirname(arquivo), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(mun, arquivo)
  mun
}
