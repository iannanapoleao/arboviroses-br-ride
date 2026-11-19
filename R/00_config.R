# =============================================================================
# Configurações gerais do projeto arboviroses-br-ride
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

# -----------------------------------------------------------------------------
# Doenças
# -----------------------------------------------------------------------------
# Nome usado nas APIs do InfoDengue -> rótulo para tabelas e mapas
DOENCAS <- c(
  dengue      = "Dengue",
  chikungunya = "Chikungunya",
  zika        = "Zika"
)

# Sistemas do microdatasus (DATASUS/SINAN)
SISTEMAS_SINAN <- c(
  dengue      = "SINAN-DENGUE",
  chikungunya = "SINAN-CHIKUNGUNYA",
  zika        = "SINAN-ZIKA"
)

# -----------------------------------------------------------------------------
# Datas
# -----------------------------------------------------------------------------
ANO_ATUAL <- lubridate::epiyear(Sys.Date())
SE_ATUAL  <- lubridate::epiweek(Sys.Date())

# Quantas semanas para trás o recorte Brasil é baixado de novo a cada execução
# (o InfoDengue revisa as semanas recentes conforme as fichas entram)
SEMANAS_JANELA <- as.integer(Sys.getenv("SEMANAS_JANELA", "8"))

# Primeiro dia (domingo) de uma semana epidemiológica
inicio_se <- function(ano, se) {
  jan4 <- as.Date(sprintf("%d-01-04", as.integer(ano)))
  inicio_se1 <- jan4 - as.integer(format(jan4, "%w"))
  inicio_se1 + 7 * (as.integer(se) - 1)
}

# -----------------------------------------------------------------------------
# UFs
# -----------------------------------------------------------------------------
UFS <- c(
  "11" = "RO", "12" = "AC", "13" = "AM", "14" = "RR", "15" = "PA", "16" = "AP",
  "17" = "TO", "21" = "MA", "22" = "PI", "23" = "CE", "24" = "RN", "25" = "PB",
  "26" = "PE", "27" = "AL", "28" = "SE", "29" = "BA", "31" = "MG", "32" = "ES",
  "33" = "RJ", "35" = "SP", "41" = "PR", "42" = "SC", "43" = "RS", "50" = "MS",
  "51" = "MT", "52" = "GO", "53" = "DF"
)

# -----------------------------------------------------------------------------
# RIDE-DF (LC 94/1998, redação da LC 163/2018): DF + 29 municípios de GO + 4 de MG
# Os códigos IBGE são buscados uma vez na API do IBGE e guardados em
# data/ref/ride_municipios.csv
# -----------------------------------------------------------------------------
RIDE_NOMES <- list(
  GO = c(
    "Abadiânia", "Água Fria de Goiás", "Águas Lindas de Goiás", "Alexânia",
    "Alto Paraíso de Goiás", "Alvorada do Norte", "Barro Alto", "Cabeceiras",
    "Cavalcante", "Cidade Ocidental", "Cocalzinho de Goiás", "Corumbá de Goiás",
    "Cristalina", "Flores de Goiás", "Formosa", "Goianésia", "Luziânia",
    "Mimoso de Goiás", "Niquelândia", "Novo Gama", "Padre Bernardo",
    "Pirenópolis", "Planaltina", "Santo Antônio do Descoberto",
    "São João d'Aliança", "Simolândia", "Valparaíso de Goiás", "Vila Boa",
    "Vila Propício"
  ),
  MG = c("Arinos", "Buritis", "Cabeceira Grande", "Unaí")
)
GEOCODE_DF <- 5300108L

ARQ_RIDE_REF <- "data/ref/ride_municipios.csv"

normalizar_nome <- function(x) {
  x <- chartr("\u00e1\u00e0\u00e2\u00e3\u00e4\u00e9\u00e8\u00ea\u00eb\u00ed\u00ec\u00ee\u00ef\u00f3\u00f2\u00f4\u00f5\u00f6\u00fa\u00f9\u00fb\u00fc\u00e7\u00c1\u00c0\u00c2\u00c3\u00c4\u00c9\u00c8\u00ca\u00cb\u00cd\u00cc\u00ce\u00cf\u00d3\u00d2\u00d4\u00d5\u00d6\u00da\u00d9\u00db\u00dc\u00c7",
              "aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC", enc2utf8(x))
  x <- tolower(gsub("[^A-Za-z ]", "", x))
  gsub("\\s+", " ", trimws(x))
}

carregar_ride <- function(arquivo = ARQ_RIDE_REF) {
  if (file.exists(arquivo)) {
    return(readr::read_csv(arquivo, show_col_types = FALSE,
                           col_types = readr::cols(geocode = "i", .default = "c")))
  }

  message("Buscando códigos IBGE dos municípios da RIDE-DF...")
  partes <- lapply(names(RIDE_NOMES), function(uf) {
    url <- sprintf(
      "https://servicodados.ibge.gov.br/api/v1/localidades/estados/%s/municipios", uf
    )
    mun <- jsonlite::fromJSON(url)
    mun <- data.frame(geocode = as.integer(mun$id), municipio = mun$nome, uf = uf)
    alvo <- normalizar_nome(RIDE_NOMES[[uf]])
    achados <- mun[normalizar_nome(mun$municipio) %in% alvo, ]
    faltando <- RIDE_NOMES[[uf]][!alvo %in% normalizar_nome(achados$municipio)]
    if (length(faltando) > 0) {
      stop("Não encontrei no IBGE: ", paste(faltando, collapse = ", "))
    }
    achados
  })

  ride <- dplyr::bind_rows(
    data.frame(geocode = GEOCODE_DF, municipio = "Brasília", uf = "DF"),
    partes
  )
  if (nrow(ride) != 34) stop("A RIDE-DF deveria ter 34 entes; achei ", nrow(ride))

  dir.create(dirname(arquivo), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(ride, arquivo)
  ride
}

# -----------------------------------------------------------------------------
# Paleta NVEPI Leste (cores do template dos slides)
# -----------------------------------------------------------------------------
NVEPI <- c(
  azul_escuro = "#004AAD",
  azul        = "#245EB6",
  azul_medio  = "#2762CC",
  azul_claro  = "#4A7FF7",
  azul_ceu    = "#9CCEFF",
  azul_gelo   = "#DCEBFF",
  amarelo     = "#FFDE59",
  amarelo_arc = "#FBD230",
  laranja     = "#F3AE08",
  cinza_txt   = "#6B6B6B",
  cinza_esc   = "#34495E"
)

PAL_SEQ_AZUL    <- c("#DCEBFF", "#9CCEFF", "#4A7FF7", "#245EB6", "#004AAD")
PAL_SEQ_AMARELO <- c("#FFF3C4", "#FFDE59", "#FBD230", "#F3AE08")

# -----------------------------------------------------------------------------
# Utilitário: junta dados novos aos antigos, trocando as linhas que se repetem
# -----------------------------------------------------------------------------
atualizar_arquivo <- function(novos, arquivo, chaves) {
  if (is.null(novos) || nrow(novos) == 0) {
    message("Nada novo para ", arquivo)
    return(invisible(NULL))
  }
  if (file.exists(arquivo)) {
    antigos <- readr::read_csv(arquivo, show_col_types = FALSE,
                               col_types = readr::cols(.default = "c"))
    novos_chr <- dplyr::mutate(novos, dplyr::across(dplyr::everything(), as.character))
    antigos <- dplyr::anti_join(antigos, novos_chr, by = chaves)
    final <- dplyr::bind_rows(antigos, novos_chr)
  } else {
    final <- dplyr::mutate(novos, dplyr::across(dplyr::everything(), as.character))
  }
  final <- dplyr::arrange(final, dplyr::across(dplyr::all_of(chaves)))
  dir.create(dirname(arquivo), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(final, arquivo, na = "")
  message("Salvo: ", arquivo, " (", nrow(final), " linhas)")
  invisible(final)
}
