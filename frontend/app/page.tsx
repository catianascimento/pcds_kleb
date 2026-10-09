"use client";

import dynamic from "next/dynamic";
import { useState } from "react";

const Map = dynamic(() => import("../components/Map"), { ssr: false });

const estados = ["AC","AL","AM","AP","BA","CE","DF","ES","GO","MA","MG","MS","MT","PA","PB","PE","PI","PR","RJ","RN","RO","RR","RS","SE","SC","SP","TO"];
const regioes = ["CO","N","NE","S","SE"];
const API = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

function hoje() { return new Date().toISOString().slice(0, 10); }

export default function Home() {
  const [tab, setTab] = useState("interpolacao");
  const [start, setStart] = useState(hoje());
  const [end, setEnd] = useState(hoje());
  const [state, setState] = useState("SP");
  const [regionOption, setRegionOption] = useState("Estado");
  const [region, setRegion] = useState("SE");
  const [res, setRes] = useState(2);
  const [lambda, setLambda] = useState(0);
  const [threshold, setThreshold] = useState(20);
  const [map, setMap] = useState<any>(null);
  const [municipios, setMunicipios] = useState<any[]>([]);
  const [historico, setHistorico] = useState<any[]>([]);
  const [extremos, setExtremos] = useState<any>(null);
  const [station, setStation] = useState<any>(null);
  const [historyTab, setHistoryTab] = useState("historico");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const body = () => ({ start, end, region_option: regionOption, state, region, spatial_res: Number(res), lambda_: Number(lambda), threshold: Number(threshold) });

  async function abrirHistoricos() {
    setTab("historicos"); setError("");
    try {
      const r = await fetch(`${API}/estacoes`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body()) });
      const d = await r.json();
      if (!r.ok) throw new Error(d.detail || "Erro ao carregar estações");
      setMap({ ...d, municipalities: { type:"FeatureCollection", features:[] }, values: [], xs:[], ys:[], breaks:[], colors:[] });
      // O R usa 431490201A como estação padrão quando nenhuma PCD foi clicada.
      const padrao = d.points?.find((p:any) => p.codigo === "431490201A") || d.points?.[0];
      if (padrao) await selecionarEstacao(padrao);
    } catch(e:any) { setError(e.message); }
  }

  async function executar(endpoint: string) {
    setLoading(true); setError("");
    try {
      const r = await fetch(`${API}/${endpoint}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body()) });
      const data = await r.json();
      if (!r.ok) throw new Error(data.detail || "Erro na consulta");
      setMap(data);
      if (endpoint === "mapa") {
        const m = await fetch(`${API}/municipios`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body()) });
        if (m.ok) setMunicipios((await m.json()).rows || []);
      }
    } catch (e: any) { setError(e.message); }
    finally { setLoading(false); }
  }

  async function selecionarEstacao(p: any) {
    setStation(p); setHistorico([]); setExtremos(null);
    try {
      const payload = { ...body(), codigo: p.codigo };
      const [h, e] = await Promise.all([
        fetch(`${API}/historico`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) }),
        fetch(`${API}/extremos`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) }),
      ]);
      if (h.ok) setHistorico((await h.json()).dados || []);
      if (e.ok) setExtremos(await e.json());
    } catch { /* A estação continua selecionável mesmo se a série histórica falhar. */ }
  }

  // function diaAtual() { const d = hoje(); setStart(d); setEnd(d); }

  async function download() {
    const r = await fetch(`${API}/download`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...body(), consistencia: tab === "consistencia" }) });
    if (!r.ok) { setError("Não foi possível gerar o raster."); return; }
    const blob = await r.blob();
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = "krig_pcd_cemaden.tif"; a.click(); URL.revokeObjectURL(a.href);
  }

  return <main className="app">
    <aside className="sidebar">
      <div className="brand"><div className="brand-mark">☁</div><div><strong>PCDs</strong><span>CEMADEN</span></div></div>

      <nav className="nav">
        <button className={tab === "interpolacao" ? "active" : ""} onClick={() => setTab("interpolacao")}>☔ <span>Interpolação PCDs</span></button>
        <button className={tab === "consistencia" ? "active" : ""} onClick={() => setTab("consistencia")}>✓ <span>Consistência Espacial</span></button>
        <button className={tab === "historicos" ? "active" : ""} onClick={abrirHistoricos}>▥ <span>Históricos e Extremos</span></button>
      </nav>

      <div className="controls">
        <h3>Configuração</h3>
        <label>Intervalo
          <div className="dates"><input type="date" value={start} onChange={e => setStart(e.target.value)}/><span>até</span><input type="date" value={end} onChange={e => setEnd(e.target.value)}/></div>
        </label>
        {/* <button className="secondary" onClick={diaAtual}>Dia Atual</button> */}
        
        {/* <label>Seleção por<select value={regionOption} onChange={e => setRegionOption(e.target.value)}><option>Estado</option><option>Região</option></select></label>
        {regionOption === "Estado" ? <label>Estado<select value={state} onChange={e => setState(e.target.value)}>{estados.map(x => <option key={x}>{x}</option>)}</select></label> : <label>Região<select value={region} onChange={e => setRegion(e.target.value)}>{regioes.map(x => <option key={x}>{x}</option>)}</select></label>} */}

        <div className="region-row">
          <label>
            Seleção por
            <select
              value={regionOption}
              onChange={e => setRegionOption(e.target.value)}
            >
              <option>Estado</option>
              <option>Região</option>
            </select>
          </label>

          {regionOption === "Estado" ? (
            <label>
              Estado
              <select value={state} onChange={e => setState(e.target.value)}>
                {estados.map(x => <option key={x}>{x}</option>)}
              </select>
            </label>
          ) : (
            <label>
              Região
              <select value={region} onChange={e => setRegion(e.target.value)}>
                {regioes.map(x => <option key={x}>{x}</option>)}
              </select>
            </label>
          )}
        </div>  

        <div className="region-row">
        <label>
          Resolução espacial [km]
          <input
            type="number"
            min=".25"
            max="10"
            step=".25"
            value={res}
            onChange={e => setRes(Number(e.target.value))}
          />
        </label>

        <label>
          Parâmetro de Smooth
          <input
            type="number"
            min="0"
            max="20"
            step=".01"
            value={lambda}
            onChange={e => setLambda(Number(e.target.value))}
          />
        </label>
      </div>    

        {/* <label>Resolução espacial [km]<input type="number" min=".25" max="10" step=".25" value={res} onChange={e => setRes(Number(e.target.value))}/></label>
        <label>Parâmetro de Smooth<input type="number" min="0" max="20" step=".01" value={lambda} onChange={e => setLambda(Number(e.target.value))}/></label> */}
        {tab === "consistencia" && <label>Threshold mínimo (% do previsto para descarte)<input type="number" min="0" max="100" step="1" value={threshold} onChange={e => setThreshold(Number(e.target.value))}/><small style={{display:"block", marginTop:4, opacity:.8}}>Ex.: 20 significa que a PCD é suspeita quando o acumulado é menor que 20% do previsto, sem limite mínimo para o valor previsto.</small></label>}

        {tab !== "historicos" && <button className="primary" onClick={() => executar(tab === "consistencia" ? "consistencia" : "mapa")} disabled={loading}>{loading ? "Processando..." : "Gerar Mapa"}</button>}
        {error && <div className="error">{error}</div>}
      </div>

      <div className="sidebar-footer">Produção de campos interpolados<br/>de PCDs do CEMADEN</div>
    </aside>

    <section className="content">
      <header className="topbar"><div><h1>{tab === "interpolacao" ? "Interpolação PCDs" : tab === "consistencia" ? "Consistência Espacial" : "Históricos e Extremos"}</h1><p>Precipitação acumulada e monitoramento espacial</p></div>{map && <span className="badge">{map.points?.length || 0} PCDs</span>}</header>

      {tab === "historicos" ? <div className="history-layout"><div className="map-card"><Map data={map} onStation={selecionarEstacao} historyMode/></div><div className="panel-card history-panel"><h2>{station ? `${station.municipio} — ${station.codigo}` : "Selecione uma PCD"}</h2><div className="tabs"><button className={historyTab === "historico" ? "selected" : ""} onClick={() => setHistoryTab("historico")}>Histórico</button><button className={historyTab === "extremos" ? "selected" : ""} onClick={() => setHistoryTab("extremos")}>Extremos</button></div>{station && historyTab === "historico" && <><div className="stats"><div><small>Registros</small><b>{historico.length}</b></div><div><small>Máximo</small><b>{historico.length ? Math.max(...historico.map(x => x.acumulado)).toFixed(1) : "—"} mm</b></div></div><div className="table-wrap"><table><thead><tr><th>Data</th><th>Acumulado [mm]</th></tr></thead><tbody>{historico.slice(-100).reverse().map(x => <tr key={x.data}><td>{x.data}</td><td>{x.acumulado.toFixed(1)}</td></tr>)}</tbody></table></div></>}{station && historyTab === "extremos" && <ExtremePanel data={historico} extremos={extremos}/>}</div></div> :
      <div className="dashboard"><div className="map-card"><Map data={map} onStation={selecionarEstacao}/>{map && <div className="map-actions"><button onClick={download}>Download Raster</button></div>}</div><div className="panel-card"><div className="panel-title"><h2>{tab === "interpolacao" ? "Resultados" : "PCDs Suspeitas"}</h2><span>{map ? `${map.points?.length || 0} estações` : "Aguardando"}</span></div>{tab === "interpolacao" ? <div className="subtabs"><div><h3>Por Município</h3><TableMunicipios rows={municipios}/></div><div><h3>Por PCD</h3><TablePCD rows={map?.points || []}/></div></div> : <TableSuspeitos rows={map?.suspeitos || []}/>}</div></div>}
    </section>
  </main>;
}

function TableMunicipios({rows}:{rows:any[]}) { return <div className="table-wrap"><table><thead><tr><th>Município</th><th>Médio [mm]</th><th>Máximo [mm]</th></tr></thead><tbody>{rows.map(r=><tr key={r.municipio}><td>{r.municipio}</td><td>{r.medio == null ? "—" : r.medio.toFixed(1)}</td><td>{r.maximo == null ? "—" : r.maximo.toFixed(1)}</td></tr>)}</tbody></table></div>; }
function TablePCD({rows}:{rows:any[]}) { return <div className="table-wrap"><table><thead><tr><th>Município</th><th>Código</th><th>Acumulado [mm]</th></tr></thead><tbody>{[...rows].sort((a,b)=>b.acumulado-a.acumulado).map(r=><tr key={r.codigo}><td>{r.municipio}</td><td><b>{r.codigo}</b></td><td>{r.acumulado.toFixed(1)}</td></tr>)}</tbody></table></div>; }
function TableSuspeitos({rows}:{rows:any[]}) { return <div className="table-wrap"><table><thead><tr><th>Código</th><th>Município</th><th>Acumulado [mm]</th><th>Calculado [mm]</th></tr></thead><tbody>{rows.map(r=><tr key={r.codigo}><td><b>{r.codigo}</b></td><td>{r.municipio}</td><td>{r.acumulado.toFixed(1)}</td><td>{r.calculado.toFixed(1)}</td></tr>)}</tbody></table></div>; }

function ExtremePanel({data, extremos}:{data:any[],extremos:any}) {
  const vals=data.map(x=>x.acumulado).filter((x:number)=>x>0.5);
  if(!vals.length) return <p className="muted">Não há dados suficientes.</p>;
  const max=Math.max(...vals, extremos?.q99 || 0, 1); const bins=18; const counts=Array(bins).fill(0);
  vals.forEach(v=>counts[Math.min(bins-1,Math.floor(v/max*bins))]++); const maxC=Math.max(...counts,1);
  return <div className="extreme-content"><div className="extreme-chart">{counts.map((c,i)=><div key={i} style={{height:`${c/maxC*85}%`}} title={`${c} registros`}/>)}</div><div className="extreme-lines">{extremos ? <><div><span>Prob. 95%</span><b>{extremos.q95.toFixed(2)} mm</b></div><div><span>Prob. 99%</span><b>{extremos.q99.toFixed(2)} mm</b></div></> : <p>Não foi possível ajustar a GEV.</p>}</div></div>;
}
