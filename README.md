# arboviroses-br-ride

Coleta automática, em R, dos dados de **dengue, chikungunya e Zika** para o **Brasil (por UF)** e a **RIDE-DF** (Distrito Federal + 33 municípios de GO e MG), com um painel publicado no GitHub Pages.

**Painel:** <https://iannanapoleao.github.io/arboviroses-br-ride/>

## Fontes

- **InfoDengue** (Fiocruz/FGV), API pública, sem chave: casos **notificados** por semana, nowcasting, população, nível de alerta e Rt. Usado para a RIDE-DF (por município) e para o Brasil (soma dos 5.570 municípios por UF).
- **DATASUS/SINAN** (pacote `microdatasus`): casos **prováveis** (notificados menos descartados) com perfil sociodemográfico e de gravidade. Publicado com atraso.

## Rotinas (GitHub Actions)

| Rotina | Script | Recorte | Quando | Saída |
|---|---|---|---|---|
| InfoDengue semanal (RIDE-DF) | `scripts/01_atualizar_infodengue_ride.R` + `04_gerar_mapas.R` | RIDE-DF por município e semana, desde 2016 | Terça, 08:17 | `data/ride/infodengue_ride_semanal.csv`, `figuras/` |
| InfoDengue Brasil por UF (semanal) | `scripts/02_atualizar_infodengue_brasil.R` | Brasil por UF e semana (uma execução por doença, em paralelo) | Terça, 09:37 | `data/brasil/infodengue_uf_<doenca>.csv` |
| DATASUS/SINAN mensal | `scripts/03_atualizar_datasus.R` | Perfil dos casos prováveis por UF e por município da RIDE-DF | Dia 5, 09:23 | `data/datasus/sinan_perfil.csv` |
| Publicar painel | `site/` | — | Ao fim de qualquer rotina acima | GitHub Pages |

Todas podem ser rodadas na mão em **Actions → (rotina) → Run workflow**.

## Usar os dados numa análise avulsa

```r
library(readr)
base <- "https://raw.githubusercontent.com/iannanapoleao/arboviroses-br-ride/main/data"

ride   <- read_csv(file.path(base, "ride/infodengue_ride_semanal.csv"))
dengue_uf <- read_csv(file.path(base, "brasil/infodengue_uf_dengue.csv"))
perfil <- read_csv(file.path(base, "datasus/sinan_perfil.csv"))

# paleta e lista da RIDE
source("https://raw.githubusercontent.com/iannanapoleao/arboviroses-br-ride/main/R/00_config.R")
```

## Colunas

**InfoDengue** (`data/ride`, `data/brasil`): `doenca`, `ano`, `se`, `data_ini_se`, `casos` (notificados), `casos_est` (nowcasting), `casprov`, `casconf`, `pop`, `p_inc100k`/`inc_100k`, `nivel` (alerta, 1 a 4), `rt`.

**DATASUS** (`data/datasus/sinan_perfil.csv`, formato longo): `doenca`, `ano_arquivo`, `ano` (da semana de início dos sintomas), `nivel` (`uf` ou `mun`), `territorio` (sigla da UF ou geocódigo IBGE), `variavel` (`semana`, `sexo_faixa`, `raca`, `escolaridade`, `classificacao`, `hospitalizacao`, `evolucao`), `categoria`, `n`.

## Observações

- Nas fontes públicas, o **DF é um município só** (Brasília, 5300108), sem quebra por Região Administrativa.
- O InfoDengue tem **Zika** da RIDE-DF só até o início de 2024; depois disso, o painel usa os casos prováveis do SINAN.
- As semanas mais recentes do InfoDengue são preliminares e sobem nas atualizações seguintes.
- O FTP do DATASUS cai com frequência; a rotina tenta cada arquivo até 4 vezes.
- Canal endêmico: mediana, Q1 e Q3 da incidência semanal desde 2016, excluindo os dois anos de maior incidência.
- RIDE-DF conforme a LC 94/1998, com redação da LC 163/2018.
