/* Painel de Arboviroses — Brasil e RIDE-DF (NVEPI Leste)
 * Lê os CSVs gerados pelo GitHub Actions e desenha tudo no navegador. */

const COR = {
  azulEscuro: "#004AAD", azul: "#245EB6", azulClaro: "#4A7FF7", azulCeu: "#9CCEFF",
  azulGelo: "#DCEBFF", amarelo: "#FFDE59", amareloArc: "#FBD230", laranja: "#F3AE08",
  cinzaTxt: "#6B6B6B", cinzaEsc: "#34495E"
};
const PAL_MAPA = ["#DCEBFF", "#9CCEFF", "#4A7FF7", "#245EB6", "#004AAD"];
const ZONAS = [
  { nome: "Êxito", cor: "#E8F1FF" },
  { nome: "Segurança", cor: "#B9D9FF" },
  { nome: "Alerta", cor: "#FFE89A" },
  { nome: "Epidêmica", cor: "#FBD9A0" }
];
const NOME_DOENCA = { dengue: "Dengue", chikungunya: "Chikungunya", zika: "Zika" };
const ANO_BASE_MIN = 2016;
const NOME_UF = {
  AC: "Acre", AL: "Alagoas", AP: "Amapá", AM: "Amazonas", BA: "Bahia", CE: "Ceará",
  DF: "Distrito Federal", ES: "Espírito Santo", GO: "Goiás", MA: "Maranhão",
  MT: "Mato Grosso", MS: "Mato Grosso do Sul", MG: "Minas Gerais", PA: "Pará",
  PB: "Paraíba", PR: "Paraná", PE: "Pernambuco", PI: "Piauí", RJ: "Rio de Janeiro",
  RN: "Rio Grande do Norte", RS: "Rio Grande do Sul", RO: "Rondônia", RR: "Roraima",
  SC: "Santa Catarina", SP: "São Paulo", SE: "Sergipe", TO: "Tocantins"
};

const fmtInt = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 });
const fmt1 = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const fmtPct = new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0, signDisplay: "exceptZero" });
const fmtData = d => d ? d.toLocaleDateString("pt-BR", { timeZone: "UTC" }) : "";

const estado = { doenca: "dengue", territorio: "ride:total", ano: null };
const dados = { ride: [], brasil: [], perfil: [], geoRide: null, geoUf: null, municipios: new Map() };

// ---------------------------------------------------------------------------
// Carga
// ---------------------------------------------------------------------------
const num = v => (v === "" || v == null ? NaN : +v);
function parseLinha(d) {
  return {
    doenca: d.doenca,
    geocode: d.geocode ? +d.geocode : null,
    municipio: d.municipio || null,
    uf: d.uf,
    ano: +d.ano,
    se: +d.se,
    data: d.data_ini_se ? new Date(d.data_ini_se + "T00:00:00Z") : null,
    casos: num(d.casos),
    est: num(d.casos_est),
    pop: num(d.pop),
    atualizado: d.atualizado_em || "",
    fonte: "InfoDengue"
  };
}

function parsePerfil(d) {
  return { doenca: d.doenca, ano: +d.ano, nivel: d.nivel, territorio: d.territorio,
           variavel: d.variavel, categoria: d.categoria, n: +d.n };
}

async function csvOuVazio(url, parse = parseLinha) {
  try { return (await d3.csv(url)).map(parse); } catch (e) { return []; }
}

// Anos sem InfoDengue (ex.: Zika depois de 2024) recebem os casos prováveis
// semanais do SINAN/DATASUS, com a população do InfoDengue da mesma unidade
function completarComSinan(linhas, perfil, nivel) {
  const chave = nivel === "mun" ? "geocode" : "uf";
  const pop = new Map();
  for (const d of linhas) if (Number.isFinite(d.pop)) {
    const k = `${d[chave]}|${d.ano}`;
    pop.set(k, Math.max(pop.get(k) || 0, d.pop));
  }
  const comInfo = new Set(d3.rollups(linhas, v => d3.sum(v, d => d.casos || 0), d => d.doenca, d => d.ano)
    .flatMap(([doe, anos]) => anos.filter(([, t]) => t > 0).map(([ano]) => `${doe}|${ano}`)));
  const extra = perfil
    .filter(p => p.nivel === nivel && p.variavel === "semana" && !comInfo.has(`${p.doenca}|${p.ano}`))
    .map(p => {
      const id = nivel === "mun" ? +p.territorio : p.territorio;
      const m = nivel === "mun" ? dados.municipios.get(id) : null;
      return {
        doenca: p.doenca, geocode: nivel === "mun" ? id : null, municipio: m ? m.municipio : null,
        uf: nivel === "mun" ? (m ? m.uf : null) : id, ano: p.ano, se: +p.categoria,
        data: null, casos: p.n, est: NaN, pop: pop.get(`${id}|${p.ano}`) ?? pop.get(`${id}|${p.ano - 1}`) ?? NaN,
        atualizado: "", fonte: "SINAN"
      };
    });
  return linhas.concat(extra);
}
async function jsonOuNulo(url) {
  try { return rebobinar(await d3.json(url)); } catch (e) { return null; }
}

// d3-geo espera anéis no sentido horário; corrige malhas no padrão RFC 7946
function rebobinar(fc) {
  if (!fc) return fc;
  for (const f of fc.features) {
    if (d3.geoArea(f) > 2 * Math.PI) {
      const g = f.geometry;
      if (g.type === "Polygon") g.coordinates.forEach(r => r.reverse());
      if (g.type === "MultiPolygon") g.coordinates.forEach(p => p.forEach(r => r.reverse()));
    }
  }
  return fc;
}

async function iniciar() {
  const [ride, brasil, perfil, geoRide, geoUf] = await Promise.all([
    csvOuVazio("dados/infodengue_ride_semanal.csv"),
    Promise.all(["dengue", "chikungunya", "zika"].map(d => csvOuVazio(`dados/infodengue_uf_${d}.csv`))).then(x => x.flat()),
    csvOuVazio("dados/sinan_perfil.csv", parsePerfil),
    jsonOuNulo("dados/ride.geojson"),
    jsonOuNulo("dados/ufs.geojson")
  ]);
  for (const r of ride) if (r.geocode) dados.municipios.set(r.geocode, { municipio: r.municipio, uf: r.uf });
  Object.assign(dados, {
    ride: completarComSinan(ride, perfil, "mun"),
    brasil: completarComSinan(brasil, perfil, "uf"),
    perfil, geoRide, geoUf
  });
  prepararDownloads();

  if (!ride.length && !brasil.length) {
    document.getElementById("atualizacao").textContent = "Ainda não há dados publicados.";
    return;
  }

  const todos = ride.concat(brasil);
  const ultimaData = d3.max(todos, d => d.data);
  const ultimaAtualizacao = d3.max(todos, d => d.atualizado);
  const ultimo = todos.find(d => +d.data === +ultimaData);
  document.getElementById("atualizacao").textContent =
    `Dados até a SE ${String(ultimo.se).padStart(2, "0")}/${ultimo.ano} (semana iniciada em ${fmtData(ultimaData)})` +
    (ultimaAtualizacao ? ` · atualizado em ${fmtData(new Date(ultimaAtualizacao + "T00:00:00Z"))}` : "");

  montarFiltros();
  desenhar();
  let t;
  window.addEventListener("resize", () => { clearTimeout(t); t = setTimeout(desenhar, 200); });
}

// ---------------------------------------------------------------------------
// Filtros
// ---------------------------------------------------------------------------
function montarFiltros() {
  document.querySelectorAll("#filtro-doenca button").forEach(b => {
    b.addEventListener("click", () => {
      estado.doenca = b.dataset.valor;
      document.querySelectorAll("#filtro-doenca button").forEach(x => {
        x.classList.toggle("ativo", x === b);
        x.setAttribute("aria-checked", x === b);
      });
      atualizarAnos();
      desenhar();
    });
  });

  const sel = document.getElementById("filtro-territorio");
  const opt = (v, t) => `<option value="${v}">${t}</option>`;
  let html = "";
  if (dados.ride.length) {
    const muns = [...dados.municipios.entries()]
      .sort((a, b) => (a[0] === 5300108 ? -1 : b[0] === 5300108 ? 1 : a[1].municipio.localeCompare(b[1].municipio, "pt-BR")));
    html += `<optgroup label="RIDE-DF">${opt("ride:total", "RIDE-DF (total)")}` +
      muns.map(([g, m]) => opt(`mun:${g}`, `${m.municipio} (${m.uf})`)).join("") + "</optgroup>";
  }
  if (dados.brasil.length) {
    const ufs = [...new Set(dados.brasil.map(d => d.uf))].sort((a, b) => NOME_UF[a].localeCompare(NOME_UF[b], "pt-BR"));
    html += `<optgroup label="Brasil">${opt("br:total", "Brasil (total)")}` +
      ufs.map(u => opt(`uf:${u}`, NOME_UF[u] || u)).join("") + "</optgroup>";
  }
  sel.innerHTML = html;
  if (!dados.ride.length) estado.territorio = "br:total";
  sel.value = estado.territorio;
  sel.addEventListener("change", () => { estado.territorio = sel.value; desenhar(); });

  document.getElementById("filtro-ano").addEventListener("change", e => {
    estado.ano = +e.target.value; desenhar();
  });
  atualizarAnos();
}

function atualizarAnos() {
  const anos = [...new Set(dados.ride.concat(dados.brasil)
    .filter(d => d.doenca === estado.doenca && d.casos > 0).map(d => d.ano))].sort((a, b) => b - a);
  const sel = document.getElementById("filtro-ano");
  const lista = anos.length ? anos : [d3.max(dados.ride.concat(dados.brasil), d => d.ano)];
  sel.innerHTML = lista.map(a => `<option value="${a}">${a}</option>`).join("");
  if (!lista.includes(estado.ano)) estado.ano = lista[0];
  sel.value = estado.ano;
}

function selecionarTerritorio(valor) {
  const sel = document.getElementById("filtro-territorio");
  if (![...sel.options].some(o => o.value === valor)) return;
  estado.territorio = valor;
  sel.value = valor;
  desenhar();
}

// ---------------------------------------------------------------------------
// Séries
// ---------------------------------------------------------------------------
function linhasTerritorio(territorio, doenca) {
  const [tipo, id] = territorio.split(":");
  if (tipo === "ride") return dados.ride.filter(d => d.doenca === doenca);
  if (tipo === "mun") return dados.ride.filter(d => d.doenca === doenca && d.geocode === +id);
  if (tipo === "br") return dados.brasil.filter(d => d.doenca === doenca);
  if (tipo === "uf") return dados.brasil.filter(d => d.doenca === doenca && d.uf === id);
  return [];
}

function nomeTerritorio(territorio) {
  const [tipo, id] = territorio.split(":");
  if (tipo === "ride") return "RIDE-DF";
  if (tipo === "br") return "Brasil";
  if (tipo === "uf") return NOME_UF[id] || id;
  const m = dados.municipios.get(+id);
  return m ? `${m.municipio} (${m.uf})` : id;
}

// série semanal (soma das unidades) → [{ano, se, data, casos, pop, inc}]
function serieSemanal(linhas) {
  const g = d3.rollups(linhas, v => ({
    casos: d3.sum(v, d => d.casos || 0),
    est: v.some(d => Number.isFinite(d.est)) ? d3.sum(v, d => (Number.isFinite(d.est) ? d.est : d.casos || 0)) : NaN,
    pop: d3.sum(v, d => d.pop || 0),
    data: d3.min(v, d => d.data),
    sinan: v.some(d => d.fonte === "SINAN")
  }), d => d.ano, d => d.se);
  const out = [];
  for (const [ano, semanas] of g) for (const [se, v] of semanas) {
    out.push({ ano, se, data: v.data, casos: v.casos, est: v.est, pop: v.pop, sinan: v.sinan,
               inc: v.pop > 0 ? v.casos / v.pop * 1e5 : NaN });
  }
  return out.sort((a, b) => a.ano - b.ano || a.se - b.se);
}

// Canal endêmico: mediana, Q1 e Q3 da incidência semanal dos anos-base,
// excluindo os dois anos de maior incidência acumulada
function canalEndemico(serie, anoAlvo) {
  const porAno = d3.group(serie.filter(d => d.ano < anoAlvo && d.ano >= ANO_BASE_MIN && d.se <= 52), d => d.ano);
  let anos = [...porAno.entries()]
    .filter(([, v]) => v.length >= 40)
    .map(([ano, v]) => ({ ano, total: d3.sum(v, d => d.inc || 0), semanas: new Map(v.map(d => [d.se, d.inc])) }));
  const excluidos = anos.slice().sort((a, b) => b.total - a.total).slice(0, 2).map(a => a.ano);
  anos = anos.filter(a => !excluidos.includes(a.ano));
  if (anos.length < 3) return { pontos: [], anosBase: anos.map(a => a.ano), excluidos };
  const pontos = d3.range(1, 53).map(se => {
    const v = anos.map(a => a.semanas.get(se)).filter(x => Number.isFinite(x)).sort(d3.ascending);
    return { se, q1: d3.quantileSorted(v, 0.25), med: d3.quantileSorted(v, 0.5), q3: d3.quantileSorted(v, 0.75) };
  });
  return { pontos, anosBase: anos.map(a => a.ano).sort(), excluidos: excluidos.sort() };
}

function zonaDe(valor, p) {
  if (!p || !Number.isFinite(valor)) return null;
  if (valor <= p.q1) return ZONAS[0];
  if (valor <= p.med) return ZONAS[1];
  if (valor <= p.q3) return ZONAS[2];
  return ZONAS[3];
}

// ---------------------------------------------------------------------------
// Desenho
// ---------------------------------------------------------------------------
function largura(id) {
  return Math.max(320, document.getElementById(id).clientWidth);
}
function vazio(id, texto) {
  document.getElementById(id).innerHTML = `<div class="vazio">${texto}</div>`;
}
function colocar(id, no) {
  const el = document.getElementById(id);
  el.innerHTML = "";
  el.append(no);
}

function desenhar() {
  const linhas = linhasTerritorio(estado.territorio, estado.doenca);
  const serie = serieSemanal(linhas);
  desenharCards(serie);
  desenharMapaRide();
  desenharMapaBrasil();
  desenharCurva(serie);
  desenharCanal(serie);
  desenharPerfil();
}

function desenharCards(serie) {
  const ano = estado.ano;
  const atual = serie.filter(d => d.ano === ano);
  const el = document.getElementById("cards");
  const doenca = NOME_DOENCA[estado.doenca];
  const terr = nomeTerritorio(estado.territorio);

  if (!atual.length || d3.sum(atual, d => d.casos) === 0) {
    el.innerHTML = `<div class="card claro"><div class="titulo">${doenca} · ${terr} · ${ano}</div>
      <div class="valor">—</div><div class="detalhe">Sem casos registrados nesta fonte para o filtro escolhido.</div></div>`;
    return;
  }

  const seMax = d3.max(atual, d => d.se);
  const casos = d3.sum(atual, d => d.casos);
  const popFim = atual.find(d => d.se === seMax)?.pop || d3.max(atual, d => d.pop);
  const inc = popFim > 0 ? casos / popFim * 1e5 : NaN;

  const anterior = serie.filter(d => d.ano === ano - 1 && d.se <= seMax);
  const casosAnt = d3.sum(anterior, d => d.casos);
  const variacao = anterior.length && casosAnt > 0 ? (casos / casosAnt - 1) * 100 : null;

  const ult4 = atual.filter(d => d.se > seMax - 4);
  const casos4 = d3.sum(ult4, d => d.casos);
  const canal = canalEndemico(serie, ano);
  const pUlt = canal.pontos.find(p => p.se === Math.min(seMax, 52));
  const incUlt = atual.find(d => d.se === seMax)?.inc;
  const zona = zonaDe(incUlt, pUlt);

  const varTxt = variacao === null ? "sem dado do ano anterior"
    : `<span class="${variacao > 0 ? "sobe" : "desce"}">${variacao > 0 ? "aumento" : "redução"}</span> em relação às SE 01–${String(seMax).padStart(2, "0")} de ${ano - 1} (${fmtInt.format(casosAnt)} casos)`;

  el.innerHTML = `
    <div class="card"><div class="titulo">Casos notificados · ${doenca} · ${terr}</div>
      <div class="valor">${fmtInt.format(casos)}</div>
      <div class="detalhe">SE 01 a ${String(seMax).padStart(2, "0")}/${ano}</div></div>
    <div class="card claro"><div class="titulo">Incidência acumulada</div>
      <div class="valor">${Number.isFinite(inc) ? fmt1.format(inc) : "—"}</div>
      <div class="detalhe">casos por 100 mil habitantes</div></div>
    <div class="card amarelo"><div class="titulo">Comparação com ${ano - 1}</div>
      <div class="valor">${variacao === null ? "—" : fmtPct.format(variacao) + "%"}</div>
      <div class="detalhe">${varTxt}</div></div>
    <div class="card laranja"><div class="titulo">Últimas 4 semanas</div>
      <div class="valor">${fmtInt.format(casos4)}</div>
      <div class="detalhe">${zona ? `SE ${seMax} na zona <strong>${zona.nome.toLowerCase()}</strong> do canal endêmico` : "casos notificados (dados preliminares)"}</div></div>`;
}

function acumuladoPor(linhas, chave, ano) {
  const doAno = linhas.filter(d => d.ano === ano);
  return new Map(d3.rollups(doAno, v => {
    const seMax = d3.max(v, d => d.se);
    const casos = d3.sum(v, d => d.casos || 0);
    const pop = v.find(d => d.se === seMax)?.pop;
    return { casos, pop, inc: pop > 0 ? casos / pop * 1e5 : NaN };
  }, d => d[chave]));
}

// Faixas: zero na cor mais clara; positivos divididos pelos quartis
function escalaMapa(incs) {
  const pos = incs.filter(v => v > 0).sort(d3.ascending);
  const base = { legend: true, label: "Incidência (por 100 mil hab.)", unknown: "#EEF1F5" };
  if (!pos.length) return { ...base, type: "threshold", domain: [1e-9], range: [PAL_MAPA[0], PAL_MAPA[1]], tickFormat: () => "0" };
  const cortes = [...new Set([0.25, 0.5, 0.75].map(q => +d3.quantileSorted(pos, q).toPrecision(2)))]
    .filter(v => v > 0);
  const temZero = incs.some(v => v === 0);
  const domain = temZero ? [1e-9, ...cortes.filter(v => v > 1e-9)] : cortes;
  const range = temZero
    ? [PAL_MAPA[0], ...PAL_MAPA.slice(5 - domain.length)]
    : PAL_MAPA.slice(4 - domain.length);
  return { ...base, type: "threshold", domain, range,
    tickFormat: d => (d < 1e-6 ? "0" : fmtInt.format(d)) };
}

function mapa(id, geo, valores, chave, nomeDe, idSelecionado, aoClicar) {
  const w = largura(id);
  const feats = geo.features.map(f => ({ ...f, v: valores.get(f.properties[chave]) }));
  const incs = feats.map(f => f.v?.inc).filter(Number.isFinite);
  if (!incs.length) return vazio(id, "Sem casos registrados para este filtro.");

  const plot = Plot.plot({
    width: w,
    height: Math.round(w * 0.78),
    projection: { type: "mercator", domain: geo },
    color: escalaMapa(incs),
    marks: [
      Plot.geo(feats, { fill: f => f.v?.inc, stroke: "#fff", strokeWidth: 0.7 }),
      Plot.geo(feats.filter(f => f.properties[chave] == idSelecionado),
        { stroke: COR.laranja, strokeWidth: 2.5, fill: "none" }),
      Plot.tip(feats, Plot.pointer(Plot.geoCentroid({
        title: f => `${nomeDe(f)}\n` + (f.v
          ? `${fmtInt.format(f.v.casos)} casos\n${Number.isFinite(f.v.inc) ? fmt1.format(f.v.inc) : "—"} por 100 mil hab.`
          : "sem dados")
      })))
    ]
  });
  plot.style.cursor = "pointer";
  plot.addEventListener("click", () => { if (plot.value) aoClicar(plot.value); });
  colocar(id, plot);
}

function desenharMapaRide() {
  if (!dados.geoRide || !dados.ride.length) return vazio("mapa-ride", "Malha ou dados da RIDE-DF ainda não publicados.");
  const linhas = dados.ride.filter(d => d.doenca === estado.doenca);
  const valores = acumuladoPor(linhas, "geocode", estado.ano);
  const sel = estado.territorio.startsWith("mun:") ? +estado.territorio.split(":")[1] : null;
  mapa("mapa-ride", dados.geoRide, valores, "geocode",
    f => `${f.properties.municipio} (${f.properties.uf})`, sel,
    f => selecionarTerritorio(`mun:${f.properties.geocode}`));
}

function desenharMapaBrasil() {
  if (!dados.brasil.length) {
    return vazio("mapa-brasil", "Os dados do Brasil por UF ainda estão em carga. Eles aparecem aqui assim que a primeira carga terminar.");
  }
  if (!dados.geoUf) return vazio("mapa-brasil", "Malha das UFs ainda não publicada.");
  const linhas = dados.brasil.filter(d => d.doenca === estado.doenca);
  const valores = acumuladoPor(linhas, "uf", estado.ano);
  const sel = estado.territorio.startsWith("uf:") ? estado.territorio.split(":")[1] : null;
  mapa("mapa-brasil", dados.geoUf, valores, "uf",
    f => NOME_UF[f.properties.uf] || f.properties.uf, sel,
    f => selecionarTerritorio(`uf:${f.properties.uf}`));
}

function desenharCurva(serie) {
  const ano = estado.ano;
  const terr = nomeTerritorio(estado.territorio);
  document.getElementById("titulo-curva").textContent = `Curva epidêmica — ${terr}`;
  const nota = document.getElementById("nota-curva");
  const atual = serie.filter(d => d.ano === ano);
  if (!atual.length || d3.sum(atual, d => d.casos) === 0) {
    nota.textContent = "";
    return vazio("curva", "Sem casos registrados para este filtro.");
  }

  // semanas preliminares: as 3 últimas do ano mais recente da base
  const anoMaisRecente = d3.max(dados.ride.concat(dados.brasil).filter(d => d.doenca === estado.doenca && d.casos > 0), d => d.ano);
  const seMax = d3.max(atual, d => d.se);
  const pts = atual.map(d => ({
    ...d,
    prelim: ano === anoMaisRecente && d.se > seMax - 3,
    grupo: ano === anoMaisRecente && d.se > seMax - 3 ? "Preliminares" : "Notificados"
  }));
  const nowcast = pts.filter(d => d.prelim && Number.isFinite(d.est) && d.est > d.casos);
  const fimEixo = ano === anoMaisRecente ? seMax : Math.max(52, seMax);
  const usaSinan = pts.some(d => d.sinan);

  nota.innerHTML = `${NOME_DOENCA[estado.doenca]}, ${ano}: casos por semana epidemiológica de início dos sintomas` +
    (usaSinan ? " (casos prováveis do SINAN/DATASUS)." : " (casos notificados, InfoDengue).") +
    `<span class="legenda-curva"><span><i style="background:${COR.azul}"></i>Notificados</span>` +
    (pts.some(d => d.prelim) ? `<span><i style="background:${COR.azulCeu}"></i>Últimas semanas (preliminares)</span>` : "") +
    (nowcast.length ? `<span><i style="border:2px dashed ${COR.laranja};background:none"></i>Estimado pelo nowcasting do InfoDengue</span>` : "") +
    "</span>";

  const w = largura("curva");
  const plot = Plot.plot({
    width: w, height: Math.round(Math.min(380, w * 0.62)),
    marginLeft: 56,
    x: { type: "band", domain: d3.range(1, fimEixo + 1), label: "Semana epidemiológica", padding: 0.15,
         tickFormat: d => (d % 4 === 1 ? d : "") },
    y: { label: "Casos", grid: true, tickFormat: d => fmtInt.format(d) },
    color: { domain: ["Notificados", "Preliminares"], range: [COR.azul, COR.azulCeu] },
    marks: [
      Plot.barY(nowcast, { x: "se", y: "est", fill: "#FFF6E0", stroke: COR.laranja, strokeDasharray: "4,3", strokeWidth: 1.4 }),
      Plot.barY(pts, { x: "se", y: "casos", fill: "grupo" }),
      Plot.ruleY([0], { stroke: "#9aa5b4" }),
      Plot.tip(pts, Plot.pointerX({
        x: "se", y: d => Math.max(d.casos, Number.isFinite(d.est) ? d.est : 0),
        title: d => `SE ${d.se}/${d.ano}${d.data ? " (início " + fmtData(d.data) + ")" : ""}\n${fmtInt.format(d.casos)} casos` +
          (d.prelim ? " (preliminar)" : "") +
          (d.prelim && Number.isFinite(d.est) && d.est > d.casos ? `\nEstimado (nowcasting): ${fmtInt.format(Math.round(d.est))}` : "")
      }))
    ]
  });
  colocar("curva", plot);
}

function desenharCanal(serie) {
  const ano = estado.ano;
  const terr = nomeTerritorio(estado.territorio);
  document.getElementById("titulo-canal").textContent = `Canal endêmico — ${terr}`;
  const nota = document.getElementById("nota-canal");
  const canal = canalEndemico(serie, ano);
  const atual = serie.filter(d => d.ano === ano && d.se <= 52);

  if (!canal.pontos.length) {
    nota.textContent = "";
    const msg = estado.territorio.startsWith("br") || estado.territorio.startsWith("uf")
      ? "O canal endêmico precisa de anos anteriores. Por enquanto o Brasil por UF só tem o ano corrente; use um território da RIDE-DF."
      : "Não há anos anteriores suficientes com casos para montar o canal endêmico deste filtro (mínimo de 3 anos-base).";
    return vazio("canal", msg);
  }

  nota.textContent = `Incidência semanal por 100 mil hab. Base: ${canal.anosBase.join(", ")}` +
    (canal.excluidos.length ? ` (excluídos ${canal.excluidos.join(" e ")}, de maior incidência).` : ".");

  const ymax = Math.max(d3.max(canal.pontos, p => p.q3) || 0, d3.max(atual, d => d.inc) || 0) * 1.15 || 1;
  const bandas = canal.pontos.flatMap(p => [
    { se: p.se, y1: 0, y2: p.q1, zona: ZONAS[0].nome },
    { se: p.se, y1: p.q1, y2: p.med, zona: ZONAS[1].nome },
    { se: p.se, y1: p.med, y2: p.q3, zona: ZONAS[2].nome },
    { se: p.se, y1: p.q3, y2: ymax, zona: ZONAS[3].nome }
  ]);
  const w = largura("canal");
  const plot = Plot.plot({
    width: w, height: Math.round(Math.min(380, w * 0.62)),
    marginLeft: 56,
    x: { label: "Semana epidemiológica", domain: [1, 52], ticks: d3.range(1, 53, 4) },
    y: { label: "Incidência (por 100 mil hab.)", domain: [0, ymax], tickFormat: d => fmt1.format(d) },
    color: { domain: ZONAS.map(z => z.nome), range: ZONAS.map(z => z.cor), legend: true },
    marks: [
      Plot.areaY(bandas, { x: "se", y1: "y1", y2: "y2", fill: "zona", z: "zona", curve: "monotone-x" }),
      Plot.lineY(canal.pontos, { x: "se", y: "med", stroke: "#C9A21A", strokeDasharray: "3,3", strokeWidth: 1, curve: "monotone-x" }),
      Plot.lineY(atual, { x: "se", y: "inc", stroke: COR.azulEscuro, strokeWidth: 2.6, curve: "monotone-x" }),
      Plot.dot(atual, { x: "se", y: "inc", fill: COR.azulEscuro, r: 2.2 }),
      Plot.tip(atual, Plot.pointerX({
        x: "se", y: "inc",
        title: d => {
          const p = canal.pontos.find(q => q.se === d.se);
          const z = zonaDe(d.inc, p);
          return `SE ${d.se}/${d.ano}\n${fmt1.format(d.inc)} por 100 mil (${fmtInt.format(d.casos)} casos)` +
            (p ? `\nQ1 ${fmt1.format(p.q1)} · mediana ${fmt1.format(p.med)} · Q3 ${fmt1.format(p.q3)}` : "") +
            (z ? `\nZona: ${z.nome.toLowerCase()}` : "");
        }
      }))
    ]
  });
  colocar("canal", plot);
}

// ---------------------------------------------------------------------------
// Perfil dos casos prováveis (SINAN/DATASUS)
// ---------------------------------------------------------------------------
const ORDEM_FAIXA = ["<1", "1-4", "5-9", "10-14", "15-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70-79", "80+"];
const ORDEM_ESCOL = ["Analfabeto", "Fund. I incompleto", "Fund. I completo", "Fund. II incompleto", "Fund. completo",
  "Médio incompleto", "Médio completo", "Superior incompleto", "Superior completo", "Não se aplica", "Ignorado/em branco"];

function perfilFiltrado() {
  const [tipo, id] = estado.territorio.split(":");
  const nivel = tipo === "ride" || tipo === "mun" ? "mun" : "uf";
  return dados.perfil.filter(p => p.doenca === estado.doenca && p.ano === estado.ano && p.nivel === nivel &&
    (tipo === "mun" ? p.territorio === id : tipo === "uf" ? p.territorio === id : true));
}
function somar(linhas, variavel) {
  return d3.rollups(linhas.filter(p => p.variavel === variavel), v => d3.sum(v, p => p.n), p => p.categoria)
    .map(([categoria, n]) => ({ categoria, n }));
}

function barrasProporcao(id, itens, ordem, cor) {
  const total = d3.sum(itens, d => d.n);
  if (!total) return vazio(id, "Sem dados.");
  const dadosB = itens.map(d => ({ ...d, p: d.n / total }));
  const dominio = ordem ? ordem.filter(c => dadosB.some(d => d.categoria === c))
    .concat(dadosB.map(d => d.categoria).filter(c => !ordem.includes(c)))
    : dadosB.slice().sort((a, b) => b.n - a.n).map(d => d.categoria);
  const w = largura(id);
  colocar(id, Plot.plot({
    width: w, height: 34 + dominio.length * 28, marginLeft: 150, marginRight: 70,
    x: { axis: null, domain: [0, d3.max(dadosB, d => d.p) * 1.05] },
    y: { domain: dominio, label: null },
    marks: [
      Plot.barX(dadosB, { y: "categoria", x: "p", fill: d => (d.categoria.startsWith("Ignorado") ? "#C9D2DE" : cor) }),
      Plot.text(dadosB, { y: "categoria", x: "p", text: d => `${fmt1.format(d.p * 100)}% (${fmtInt.format(d.n)})`,
        dx: 6, textAnchor: "start", fill: COR.cinzaEsc, fontSize: 11 }),
      Plot.tip(dadosB, Plot.pointerY({ y: "categoria", x: "p",
        title: d => `${d.categoria}\n${fmtInt.format(d.n)} casos (${fmt1.format(d.p * 100)}%)` }))
    ]
  }));
}

function desenharPerfil() {
  const linhas = perfilFiltrado();
  const terr = nomeTerritorio(estado.territorio);
  document.getElementById("titulo-perfil").textContent =
    `Perfil dos casos prováveis — ${NOME_DOENCA[estado.doenca]}, ${terr}, ${estado.ano}`;
  const nota = document.getElementById("nota-perfil");
  const ids = ["piramide", "gravidade", "raca", "escolaridade"];

  if (!dados.perfil.length || !linhas.length) {
    nota.textContent = "";
    const anos = [...new Set(dados.perfil.filter(p => p.doenca === estado.doenca).map(p => p.ano))].sort();
    const msg = !dados.perfil.length
      ? "Os dados do SINAN/DATASUS ainda estão sendo processados. Eles aparecem aqui assim que a rotina terminar."
      : `Sem dados do SINAN/DATASUS para ${estado.ano} neste filtro` +
        (anos.length ? ` (disponível: ${anos.join(", ")}). O DATASUS publica os arquivos com atraso.` : ".");
    ids.forEach(id => vazio(id, msg));
    return;
  }

  const total = d3.sum(somar(linhas, "semana"), d => d.n);
  nota.textContent = `Fonte: SINAN/DATASUS. ${fmtInt.format(total)} casos prováveis (notificados menos descartados), por residência e ano de início dos sintomas.`;

  // pirâmide etária
  const sf = somar(linhas, "sexo_faixa").map(d => {
    const [sexo, faixa] = d.categoria.split("|");
    return { sexo, faixa, n: d.n };
  }).filter(d => (d.sexo === "Masculino" || d.sexo === "Feminino") && ORDEM_FAIXA.includes(d.faixa));
  if (sf.length) {
    const w = largura("piramide");
    const max = d3.max(sf, d => d.n);
    colocar("piramide", Plot.plot({
      width: w, height: 380, marginLeft: 50,
      x: { label: "Casos prováveis", domain: [-max * 1.1, max * 1.1], tickFormat: d => fmtInt.format(Math.abs(d)), grid: true },
      y: { domain: ORDEM_FAIXA.slice().reverse(), label: "Faixa etária (anos)" },
      color: { domain: ["Masculino", "Feminino"], range: [COR.azul, COR.amareloArc], legend: true },
      marks: [
        Plot.barX(sf, { y: "faixa", x: d => (d.sexo === "Masculino" ? -d.n : d.n), fill: "sexo" }),
        Plot.ruleX([0], { stroke: COR.cinzaEsc }),
        Plot.tip(sf, Plot.pointer({ y: "faixa", x: d => (d.sexo === "Masculino" ? -d.n : d.n),
          title: d => `${d.sexo}, ${d.faixa} anos\n${fmtInt.format(d.n)} casos` }))
      ]
    }));
  } else vazio("piramide", "Sem dados de sexo e idade.");

  // gravidade
  const classif = somar(linhas, "classificacao");
  const hosp = new Map(somar(linhas, "hospitalizacao").map(d => [d.categoria, d.n]));
  const evol = new Map(somar(linhas, "evolucao").map(d => [d.categoria, d.n]));
  const hospSim = hosp.get("Sim") || 0, hospNao = hosp.get("Não") || 0;
  const obitos = evol.get("Óbito pelo agravo") || 0;
  const emInvest = evol.get("Óbito em investigação") || 0;
  const el = document.getElementById("gravidade");
  el.innerHTML = `<div class="mini-stats">
      <div><strong>${hospSim + hospNao ? fmt1.format(hospSim / (hospSim + hospNao) * 100) + "%" : "—"}</strong>hospitalizados<br>(entre os com informação)</div>
      <div><strong>${fmtInt.format(obitos)}</strong>óbitos pelo agravo</div>
      <div><strong>${fmtInt.format(emInvest)}</strong>óbitos em investigação</div>
      <div><strong>${total ? fmt1.format(obitos / total * 100).replace(",0", "") + "%" : "—"}</strong>letalidade<br>(óbitos ÷ casos prováveis)</div>
    </div><div id="gravidade-barras"></div>`;
  const ordemClass = ["Dengue", "Dengue com sinais de alarme", "Dengue grave", "Chikungunya", "Confirmado", "Inconclusivo", "Em investigação"];
  barrasProporcao("gravidade-barras", classif, ordemClass, COR.laranja);

  barrasProporcao("raca", somar(linhas, "raca"), null, COR.azul);
  barrasProporcao("escolaridade", somar(linhas, "escolaridade"), ORDEM_ESCOL, COR.azulClaro);
}

// ---------------------------------------------------------------------------
// Baixar cada painel como PNG
// ---------------------------------------------------------------------------
function prepararDownloads() {
  document.querySelectorAll(".painel").forEach(painel => {
    if (painel.querySelector(".baixar")) return;
    const h2 = painel.querySelector("h2");
    const topo = document.createElement("div");
    topo.className = "painel-topo";
    h2.replaceWith(topo);
    topo.append(h2);
    const botao = document.createElement("button");
    botao.className = "baixar";
    botao.type = "button";
    botao.textContent = "Baixar PNG";
    botao.title = "Baixar este gráfico como imagem";
    botao.addEventListener("click", async () => {
      botao.disabled = true;
      try {
        const url = await htmlToImage.toPng(painel, {
          backgroundColor: "#ffffff", pixelRatio: 2,
          filter: n => !(n.classList && (n.classList.contains("baixar") || n.getAttribute?.("aria-label") === "tip"))
        });
        const a = document.createElement("a");
        const nome = h2.textContent.normalize("NFD").replace(/[̀-ͯ]/g, "")
          .replace(/[^\w]+/g, "_").replace(/^_|_$/g, "").toLowerCase();
        a.href = url;
        a.download = `${nome}_${estado.doenca}_${estado.ano}.png`;
        a.click();
      } catch (e) {
        alert("Não foi possível gerar a imagem neste navegador.");
      } finally {
        botao.disabled = false;
      }
    });
    topo.append(botao);
  });
}

iniciar();
