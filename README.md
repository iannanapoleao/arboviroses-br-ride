# arboviroses-br-ride

Coleta automática, em R, dos dados de **dengue, chikungunya e Zika** para o **Brasil (por UF)** e a **RIDE-DF** (Distrito Federal + 33 municípios de GO e MG), com mapas nas cores do NVEPI Leste.

Os dados são atualizados sozinhos pelo GitHub Actions e ficam na pasta `data/`.

## O que roda e quando

| Rotina | Fonte | Recorte | Frequência | Arquivo gerado |
|---|---|---|---|---|
| `scripts/01_atualizar_infodengue_ride.R` | InfoDengue (API pública) | RIDE-DF por município e semana | Semanal (terça) | `data/ride/infodengue_ride_semanal.csv` |
| `scripts/02_atualizar_infodengue_brasil.R` | InfoDengue via Mosqlimate (precisa de chave) | Brasil por UF e semana | Semanal (terça) | `data/brasil/infodengue_uf_semanal.csv` |
| `scripts/03_atualizar_datasus.R` | DATASUS/SINAN (microdatasus) | Brasil por UF e RIDE-DF por perfil | Mensal (dia 5) | `data/datasus/sinan_uf_semana.csv` e `data/datasus/sinan_ride_perfil.csv` |
| `scripts/04_gerar_mapas.R` | Dados acima | Incidência acumulada no ano | Junto da semanal | `figuras/*.png` |

## Configuração (uma vez só)

1. **Chave do Mosqlimate** (para o recorte Brasil): crie uma conta gratuita em <https://api.mosqlimate.org>, copie sua chave (X-UID-Key) e cadastre no repositório em **Settings → Secrets and variables → Actions → New repository secret**, com o nome `MOSQLIMATE_API_KEY`. Sem a chave, a RIDE-DF continua atualizando normalmente; só o Brasil é pulado.
2. **Permissão de escrita das Actions**: em **Settings → Actions → General → Workflow permissions**, marque **Read and write permissions**.
3. **Primeira carga**: em **Actions → InfoDengue semanal → Run workflow**, preencha `ano_inicial` (ex.: `2025`) para baixar o Brasil desde aquele ano. Depois disso, cada execução baixa só as últimas 8 semanas (o InfoDengue revisa as semanas recentes).

## Usar no RStudio

Abra `arboviroses-br-ride.Rproj` e rode os scripts da pasta `scripts/` na ordem. Para o recorte Brasil localmente, crie um arquivo `.Renviron` na raiz do projeto (ele não vai para o GitHub) com:

```
MOSQLIMATE_API_KEY=sua_chave_aqui
```

Pacotes: `httr2`, `jsonlite`, `dplyr`, `readr`, `tibble`, `lubridate`, `sf`, `ggplot2`, `scales`, `geobr` e, para o DATASUS, `microdatasus` (`remotes::install_github("rfsaldanha/microdatasus")`).

## Colunas principais

**InfoDengue** (`data/ride` e `data/brasil`): `doenca`, `ano`, `se`, `data_ini_se`, `casos` (casos notificados), `casos_est` (estimados por nowcasting), `casprov` (prováveis), `casconf` (confirmados), `pop`, `inc_100k`/`p_inc100k`, `nivel` (alerta 1 verde a 4 vermelho), `rt`.

**DATASUS** (`data/datasus`): contagens (`n`) por UF ou município de residência, semana de primeiros sintomas (`sem_pri`), classificação final (`classi_fin`, código bruto do SINAN), critério, sexo, faixa etária, hospitalização e evolução. Os microdados não são salvos no repositório, só os resumos.

## Observações

- Nas fontes públicas, o **DF entra como um único município** (Brasília, 5300108): não há quebra por Região Administrativa.
- Os mapas usam **casos notificados** do InfoDengue. Para casos prováveis segundo a definição do Ministério da Saúde, use `casprov` ou o resumo do DATASUS excluindo os descartados.
- O DATASUS publica os arquivos do SINAN com atraso; se o ano atual ainda não estiver disponível, a rotina mensal só avisa e segue.
- Para Zika, confira no dicionário de dados do SINAN os códigos de `classi_fin` antes de calcular casos prováveis.
- Municípios da RIDE-DF conforme a LC 94/1998, com redação da LC 163/2018.
