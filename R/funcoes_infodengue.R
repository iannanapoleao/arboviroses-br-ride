# =============================================================================
# Funções de coleta — InfoDengue (API pública) e Mosqlimate (API com chave)
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

# Deixa as colunas do InfoDengue/Mosqlimate num formato único
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

# -----------------------------------------------------------------------------
# Mosqlimate — todos os municípios de uma UF, uma doença, um intervalo de datas
# Documentação: https://api.mosqlimate.org/docs/datastore/GET/infodengue/
# -----------------------------------------------------------------------------
achatar <- function(itens) {
  if (is.data.frame(itens)) {
    for (nm in names(itens)) {
      if (is.list(itens[[nm]])) {
        itens[[nm]] <- vapply(itens[[nm]],
                              function(v) if (length(v) == 0) NA_character_ else as.character(v[[1]]),
                              character(1))
      }
    }
    return(itens)
  }
  dplyr::bind_rows(lapply(itens, function(linha) {
    linha[vapply(linha, is.null, logical(1))] <- NA
    as.data.frame(lapply(linha, as.character), stringsAsFactors = FALSE)
  }))
}

buscar_mosqlimate_uf <- function(uf, doenca, inicio, fim, api_key, por_pagina = 100) {
  pagina <- 1
  partes <- list()

  repeat {
    resp <- request("https://api.mosqlimate.org/api/datastore/infodengue/") |>
      req_url_query(
        page = pagina, per_page = por_pagina, disease = doenca,
        start = format(as.Date(inicio)), end = format(as.Date(fim)), uf = uf
      ) |>
      req_headers(`X-UID-Key` = api_key, accept = "application/json") |>
      req_user_agent(UA) |>
      req_timeout(180) |>
      req_retry(
        max_tries = 5,
        is_transient = function(r) resp_status(r) %in% c(429, 500, 502, 503, 504),
        backoff = function(i) 10 * i
      ) |>
      req_perform()

    js <- resp_body_json(resp, simplifyVector = TRUE)
    itens <- js$items
    if (is.null(itens) || NROW(itens) == 0) break

    partes[[length(partes) + 1]] <- achatar(itens)

    total_pag <- js$pagination$total_pages
    if (!is.null(total_pag) && pagina >= total_pag) break
    if (NROW(itens) < por_pagina) break

    pagina <- pagina + 1
    Sys.sleep(0.2)
  }

  if (length(partes) == 0) return(NULL)
  dplyr::bind_rows(partes) |>
    padronizar_infodengue(doenca, fonte = "InfoDengue/Mosqlimate")
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
