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
  { nome: "Epidêmica", cor: "#F8C46A" }
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
const dados = { ride: [], brasil: [], geoRide: null, geoUf: null, municipios: new Map() };

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
    pop: num(d.pop),
    atualizado: d.atualizado_em || ""
  };
}

async function csvOuVazio(url) {
  try { return (await d3.csv(url)).map(parseLinha); } catch (e) { return []; }
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
  const [ride, brasil, geoRide, geoUf] = await Promise.all([
    csvOuVazio("dados/infodengue_ride_semanal.csv"),
    csvOuVazio("dados/infodengue_uf_semanal.csv"),
    jsonOuNulo("dados/ride.geojson"),
    jsonOuNulo("dados/ufs.geojson")
  ]);
  Object.assign(dados, { ride, brasil, geoRide, geoUf });
  for (const r of ride) if (r.geocode) dados.municipios.set(r.geocode, { municipio: r.municipio, uf: r.uf });

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
    pop: d3.sum(v, d => d.pop || 0),
    data: d3.min(v, d => d.data)
  }), d => d.ano, d => d.se);
  const out = [];
  for (const [ano, semanas] of g) for (const [se, v] of semanas) {
    out.push({ ano, se, data: v.data, casos: v.casos, pop: v.pop, inc: v.pop > 0 ? v.casos / v.pop * 1e5 : NaN });
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

function mapa(id, geo, valores, chave, nomeDe, idSelecionado, aoClicar) {
  const w = largura(id);
  const feats = geo.features.map(f => ({ ...f, v: valores.get(f.properties[chave]) }));
  const incs = feats.map(f => f.v?.inc).filter(Number.isFinite);
  if (!incs.length) return vazio(id, "Sem casos registrados para este filtro.");

  const plot = Plot.plot({
    width: w,
    height: Math.round(w * 0.78),
    projection: { type: "mercator", domain: geo },
    color: {
      type: "quantile", n: Math.min(5, new Set(incs).size), range: PAL_MAPA, legend: true,
      label: "Incidência (por 100 mil hab.)", tickFormat: d => fmtInt.format(d),
      unknown: "#EEF1F5"
    },
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
    return vazio("mapa-brasil", "Os dados do Brasil por UF ainda estão em carga (a API do Mosqlimate limita as chamadas). Eles aparecem aqui assim que a primeira carga terminar.");
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
  document.getElementById("titulo-curva").textContent = `Casos por semana epidemiológica — ${terr}`;
  const pts = serie.filter(d => d.ano === ano || d.ano === ano - 1)
    .map(d => ({ ...d, serie: String(d.ano) }));
  if (!pts.length || d3.sum(pts, d => d.casos) === 0) {
    document.getElementById("nota-curva").textContent = "";
    return vazio("curva", "Sem casos registrados para este filtro.");
  }
  document.getElementById("nota-curva").textContent =
    `${NOME_DOENCA[estado.doenca]}: ${ano} comparado a ${ano - 1}. As últimas semanas são preliminares.`;
  const w = largura("curva");
  const plot = Plot.plot({
    width: w, height: Math.round(Math.min(380, w * 0.62)),
    marginLeft: 56,
    x: { label: "Semana epidemiológica", domain: [1, 53], ticks: d3.range(1, 54, 4) },
    y: { label: "Casos notificados", grid: true, tickFormat: d => fmtInt.format(d) },
    color: { domain: [String(ano - 1), String(ano)], range: [COR.amareloArc, COR.azul], legend: true },
    marks: [
      Plot.ruleY([0], { stroke: "#ccd3dd" }),
      Plot.areaY(pts.filter(d => d.ano === ano), { x: "se", y: "casos", fill: COR.azulGelo, fillOpacity: 0.7, curve: "monotone-x" }),
      Plot.lineY(pts, { x: "se", y: "casos", stroke: "serie", strokeWidth: 2.4, curve: "monotone-x" }),
      Plot.tip(pts, Plot.pointerX({
        x: "se", y: "casos",
        title: d => `SE ${d.se}/${d.ano}${d.data ? " (" + fmtData(d.data) + ")" : ""}\n${fmtInt.format(d.casos)} casos`
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

iniciar();
