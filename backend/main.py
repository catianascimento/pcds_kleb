import io
import os
from datetime import date
from functools import lru_cache
from math import comb, exp, log

import geopandas as gpd
import numpy as np
import psycopg2
import rasterio
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from scipy.optimize import brentq
from scipy.special import gamma
from shapely import contains_xy
import base64
import struct
import zlib

from dotenv import load_dotenv
load_dotenv()

from kriging import interpolar, consistencia

app = FastAPI(title="PCDs CEMADEN")

# O frontend pode ser aberto por localhost ou pelo IP da máquina na rede.
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://172.16.20.233:3000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

REGIOES = {
    "CO": ["DF", "GO", "MT", "MS"],
    "N": ["AC", "AP", "AM", "PA", "RO", "RR", "TO"],
    "NE": ["AL", "BA", "CE", "MA", "PB", "PE", "PI", "RN", "SE"],
    "S": ["PR", "RS", "SC"],
    "SE": ["ES", "MG", "RJ", "SP"],
}

BREAKS_BASE = [0.1, 0.5, 1, 2, 3, 5, 7, 10, 15, 20, 25, 30, 40, 50,
               75, 100, 150, 200, 250, 300, 350, 400, 500]

# Mesmas cores do palette do app.R.
COLORS = [
    "#C8C8C8", "#D5FFFF", "#00D5FF", "#0080AA", "#0000B3",
    "#80FF55", "#00CC7F", "#558000", "#005500", "#FFFF00",
    "#FFCC00", "#FF9900", "#D55500", "#FFBBFF", "#FF59E2",
    "#FF2B80", "#8000AA", "#49008A", "#230042", "#FFFFFF",
    "#C8C8C8", "#8A8A8A",
]


def db():
    return psycopg2.connect(
        dbname=os.getenv("DB_NAME"),
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT", "5432"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )


def breaks_period(start, end):
    # Exatamente a lógica de intervalsBreaks() do R.
    days = (end - start).days
    fator = 1
    if days > 14:
        fator = 2
    if days >= 45:
        fator = 3
    if days >= 150:
        fator = 4
    return [x * fator for x in BREAKS_BASE]


@lru_cache(maxsize=1)
def load_shapes():
    base = os.path.join(os.path.dirname(__file__), "..", "data")
    estados = gpd.read_file(os.path.join(base, "BR_UF_2024.shp"))
    municipios = gpd.read_file(os.path.join(base, "municipios_monitorados.shp"))
    return estados, municipios


def ufs(region_option, state, region):
    if region_option == "Região":
        if region not in REGIOES:
            raise HTTPException(400, "Região inválida")
        return REGIOES[region]
    if state not in REGIOES["SE"] + REGIOES["S"] + REGIOES["CO"] + REGIOES["N"] + REGIOES["NE"]:
        raise HTTPException(400, "Estado inválido")
    return [state]


def carregar_pcds(uf_list, start, end):
    """Reproduz dadosUsed() do R, inclusive sum(..., na.rm=TRUE)."""
    con = db()
    try:
        with con.cursor() as cur:
            placeholders = ",".join(["%s"] * len(uf_list))
            cur.execute(
                "SELECT codestacao, nome, cidade, longitude, latitude, uf "
                f"FROM info_pcd WHERE uf IN ({placeholders})",
                uf_list,
            )
            info = cur.fetchall()

            cur.execute(
                "SELECT codestacao, datadia, valor, n_dados "
                "FROM estat_diaria WHERE datadia >= %s AND datadia <= %s",
                (start, end),
            )
            chuva = cur.fetchall()
    finally:
        con.close()

    postos = {
        str(r[0]): {
            "codigo": str(r[0]), "nome": r[1], "municipio": r[2],
            "longitude": float(r[3]), "latitude": float(r[4]), "uf": r[5],
        }
        for r in info
        if r[3] is not None and r[4] is not None
    }

    # No R, postosUsed vem dos códigos existentes em estat_diaria.
    # Sum(..., na.rm=TRUE) transforma linhas NA em contribuição zero.
    acumulado = {}
    for cod, _, valor, _ in chuva:
        cod = str(cod)
        if cod not in postos:
            continue
        if cod not in acumulado:
            acumulado[cod] = 0.0
        if valor is not None:
            acumulado[cod] += float(valor)

    return [{**postos[cod], "acumulado": valor} for cod, valor in acumulado.items()]


def area_selecionada(estados, uflist):
    return estados[estados["SIGLA_UF"].isin(uflist)].copy()


def pontos_grid(area, spatial_res):
    minx, miny, maxx, maxy = area.total_bounds
    # Mesma fórmula do R: 0.009803922 * spatial_res.
    res = 0.009803922 * float(spatial_res)
    # R usa seq(min, max, by=res): nunca adiciona uma célula extra apenas
    # porque o limite superior está a menos de meia resolução do próximo passo.
    nx = int(np.floor((maxx - minx) / res + 1e-10)) + 1
    ny = int(np.floor((maxy - miny) / res + 1e-10)) + 1
    xs = minx + np.arange(nx, dtype=float) * res
    ys = miny + np.arange(ny, dtype=float) * res
    xx, yy = np.meshgrid(xs, ys)
    return xs, ys, np.column_stack([xx.ravel(), yy.ravel()]), res


def mascara_area(area, grid):
    mask = np.zeros(len(grid), dtype=bool)
    for geom in area.geometry:
        mask |= contains_xy(geom, grid[:, 0], grid[:, 1])
    return mask


def geojson_frame(frame, simplify=None):
    if frame.empty:
        return {"type": "FeatureCollection", "features": []}
    work = frame.copy()
    if simplify:
        work["geometry"] = work.geometry.simplify(simplify, preserve_topology=True)
    return work.__geo_interface__


def selected_municipios(municipios, uflist):
    return municipios[municipios["uf"].isin(uflist)].copy()


class Request(BaseModel):
    start: date
    end: date
    region_option: str = "Estado"
    state: str = "SP"
    region: str = "SE"
    spatial_res: float = 2
    lambda_: float = 0.0
    threshold: float = 20.0


class StationRequest(Request):
    codigo: str


class DownloadRequest(Request):
    consistencia: bool = False


@app.get("/")
def root():
    return {"status": "ok", "app": "PCDs CEMADEN"}


def preparar_mapa(req):
    if req.start > req.end:
        raise HTTPException(400, "Data inicial maior que a data final.")
    if not 0.25 <= req.spatial_res <= 10:
        raise HTTPException(400, "Resolução espacial deve estar entre 0.25 e 10 km.")
    if not 0 <= req.threshold <= 100:
        raise HTTPException(400, "Threshold mínimo deve estar entre 0 e 100 (%).")

    uflist = ufs(req.region_option, req.state, req.region)
    dados = carregar_pcds(uflist, req.start, req.end)
    if len(dados) < 3:
        raise HTTPException(400, "Menos de 3 PCDs com dados disponíveis.")

    estados, municipios = load_shapes()
    area = area_selecionada(estados, uflist)
    xs, ys, grid, res = pontos_grid(area, req.spatial_res)

    xy = np.array([[p["longitude"], p["latitude"]] for p in dados])
    valores = np.array([p["acumulado"] for p in dados], dtype=float)
    return uflist, dados, area, municipios, xs, ys, grid, res, xy, valores


def resposta_mapa(req, raster, dados, area, municipios, uflist, xs, ys, res, suspeitos=None, previsto=None):
    mun = selected_municipios(municipios, uflist)
    # A simplificação é somente para transporte/renderização do contorno.
    # O raster e todos os cálculos permanecem sem simplificação.
    # JSON não aceita NaN/Infinity.
    # No R, essas células ficam como NA (principalmente fora da área).
    # Para o frontend, enviamos essas células como null, preservando o
    # significado de "sem valor" em vez de transformá-las em zero.
    values = np.asarray(raster, dtype=float).reshape(len(ys), len(xs))
    values_json = np.where(np.isfinite(values), values, np.nan).tolist()
    values_json = [
        [None if not np.isfinite(v) else float(v) for v in row]
        for row in values_json
    ]

    # Arrays NumPy podem conter NaN/Infinity (por exemplo, quando a célula
    # de uma PCD fica fora da área válida). Esses valores não são JSON válido.
    # Convertemos somente na serialização para null; os cálculos continuam
    # usando NaN para representar ausência de previsão.
    previsto_json = []
    if previsto is not None:
        previsto_arr = np.asarray(previsto, dtype=float).reshape(-1)
        previsto_json = [
            float(v) if np.isfinite(v) else None
            for v in previsto_arr
        ]

    def json_seguro(valor):
        """Converte NaN/Infinity e escalares NumPy em valores JSON válidos."""
        if isinstance(valor, dict):
            return {str(k): json_seguro(v) for k, v in valor.items()}
        if isinstance(valor, (list, tuple)):
            return [json_seguro(v) for v in valor]
        if isinstance(valor, np.ndarray):
            return json_seguro(valor.tolist())
        if isinstance(valor, (float, np.floating)):
            return float(valor) if np.isfinite(valor) else None
        if isinstance(valor, (int, np.integer)):
            return int(valor)
        return valor

    # Quando é o mapa de consistência, devolve o diagnóstico de TODAS as
    # estações. Isso permite conferir por que uma PCD foi aceita ou marcada
    # como suspeita, sem inferir pela cor do marcador.
    dados_saida = dados
    if previsto is not None:
        previsto_arr = np.asarray(previsto, dtype=float).reshape(-1)
        codigos_suspeitos = {str(p.get("codigo")) for p in (suspeitos or [])}
        dados_saida = []
        for i, p in enumerate(dados):
            item = dict(p)
            calculado = previsto_arr[i] if i < len(previsto_arr) else np.nan
            observado = float(p.get("acumulado", np.nan))
            item["calculado"] = float(calculado) if np.isfinite(calculado) else None
            item["percentual_observado_previsto"] = (
                float(100.0 * observado / calculado)
                if np.isfinite(observado) and np.isfinite(calculado) and calculado != 0
                else None
            )
            if str(p.get("codigo")) in codigos_suspeitos:
                item["status_consistencia"] = "Suspeita"
            elif not np.isfinite(calculado):
                item["status_consistencia"] = "Sem previsão válida"
            else:
                item["status_consistencia"] = "Aceita"
            dados_saida.append(item)

    # Protege os dados das estações e a lista de suspeitas também.
    points_json = json_seguro(dados_saida)
    suspeitos_json = json_seguro(suspeitos or [])

    return {
        "xs": xs.tolist(), "ys": ys.tolist(),
        "values": values_json,
        "points": points_json,
        "suspeitos": suspeitos_json,
        "previsto": previsto_json,
        "bounds": area.total_bounds.tolist(),
        "raster_resolution": res,
        "breaks": breaks_period(req.start, req.end),
        "colors": COLORS,
        "states": geojson_frame(area, simplify=0.001),
        "municipalities": geojson_frame(mun, simplify=0.001),
    }


@app.post("/estacoes")
def estacoes(req: Request):
    """Mapa de seleção de estações usado pela aba Históricos e Extremos."""
    if req.start > req.end:
        raise HTTPException(400, "Data inicial maior que a data final.")
    uflist = ufs(req.region_option, req.state, req.region)
    con = db()
    try:
        with con.cursor() as cur:
            placeholders = ",".join(["%s"] * len(uflist))
            cur.execute(
                "SELECT codestacao, nome, cidade, longitude, latitude, uf "
                f"FROM info_pcd WHERE uf IN ({placeholders})", uflist
            )
            rows = cur.fetchall()
    finally:
        con.close()
    estados, _ = load_shapes()
    area = area_selecionada(estados, uflist)
    points = [{"codigo":str(r[0]),"nome":r[1],"municipio":r[2],"longitude":float(r[3]),"latitude":float(r[4]),"uf":r[5]}
              for r in rows if r[3] is not None and r[4] is not None]
    return {"points":points,"bounds":area.total_bounds.tolist(),"states":geojson_frame(area, simplify=0.001)}


@app.post("/mapa")
def mapa(req: Request):
    uflist, dados, area, municipios, xs, ys, grid, res, xy, valores = preparar_mapa(req)
    raster = interpolar(xy, valores, grid, req.lambda_, a_range=1.0)
    raster[~mascara_area(area, grid)] = np.nan
    return resposta_mapa(req, raster, dados, area, municipios, uflist, xs, ys, res)


@app.post("/consistencia")
def consistencia_api(req: Request):
    uflist, dados, area, municipios, xs, ys, grid, res, xy, valores = preparar_mapa(req)
    mascara = mascara_area(area, grid)
    raster, suspeita, previsto = consistencia(
        xy, valores, grid, xs, ys, req.lambda_, req.threshold, mascara
    )
    raster[~mascara] = np.nan

    suspeitos = []
    for p, flag, prev in zip(dados, suspeita, previsto):
        if flag:
            suspeitos.append({**p, "calculado": float(prev)})

    return resposta_mapa(
        req, raster, dados, area, municipios, uflist, xs, ys, res,
        suspeitos, previsto
    )


@app.post("/municipios")
def municipios_stats(req: Request):
    """Média e máximo da interpolação dentro de cada município monitorado."""
    uflist, dados, area, municipios, xs, ys, grid, res, xy, valores = preparar_mapa(req)
    raster = interpolar(xy, valores, grid, req.lambda_, a_range=1.0)
    raster[~mascara_area(area, grid)] = np.nan
    arr = raster.reshape(len(ys), len(xs))
    mun = selected_municipios(municipios, uflist)

    rows = []
    for _, m in mun.iterrows():
        geom = m.geometry
        inside = contains_xy(geom, grid[:, 0], grid[:, 1]).reshape(len(ys), len(xs))
        vals = arr[inside]
        vals = vals[np.isfinite(vals)]
        if len(vals):
            rows.append({
                "municipio": m["cidade"],
                "medio": float(np.mean(vals)),
                "maximo": float(np.max(vals)),
            })
        else:
            rows.append({"municipio": m["cidade"], "medio": None, "maximo": None})

    rows.sort(key=lambda x: (x["maximo"] is None, -(x["maximo"] or 0)))
    return {"rows": rows}


@app.post("/download")
def download(req: DownloadRequest):
    """Gera o mesmo tipo de arquivo que writeRaster(..., format='GTiff')."""
    uflist, dados, area, _, xs, ys, grid, res, xy, valores = preparar_mapa(req)
    if req.consistencia:
        mascara = mascara_area(area, grid)
        raster, _, _ = consistencia(xy, valores, grid, xs, ys, req.lambda_, req.threshold, mascara)
        suffix_prefix = "corr"
    else:
        raster = interpolar(xy, valores, grid, req.lambda_, a_range=1.0)
        suffix_prefix = "uncorr"
    if req.region_option == "Região":
        suffix = "regiao-" + req.region
    else:
        suffix = req.state
    raster[~mascara_area(area, grid)] = np.nan

    arr = raster.reshape(len(ys), len(xs))
    arr = np.flipud(arr)
    transform = rasterio.transform.from_origin(
        float(xs.min() - res / 2), float(ys.max() + res / 2), res, res
    )

    mem = io.BytesIO()
    with rasterio.MemoryFile() as mf:
        with mf.open(
            driver="GTiff", height=arr.shape[0], width=arr.shape[1], count=1,
            dtype="float32", crs="EPSG:4326", transform=transform,
            nodata=-9999.0,
        ) as dst:
            dst.write(np.nan_to_num(arr, nan=-9999.0).astype("float32"), 1)
        mem.write(mf.read())
    mem.seek(0)
    name = f"krig_pcd_cemaden_{suffix_prefix}_{req.start:%Y%m%d}-{req.end:%Y%m%d}_{suffix}.tif"
    return StreamingResponse(mem, media_type="image/tiff", headers={
        "Content-Disposition": f'attachment; filename="{name}"'
    })


@app.post("/historico")
def historico(req: StationRequest):
    con = db()
    try:
        with con.cursor() as cur:
            cur.execute(
                "SELECT datadia, valor FROM estat_diaria "
                "WHERE codestacao = %s ORDER BY datadia",
                (req.codigo,),
            )
            rows = cur.fetchall()
    finally:
        con.close()

    dados = [{"data": r[0].isoformat(), "acumulado": float(r[1])}
             for r in rows if r[1] is not None]
    return {"codigo": req.codigo, "dados": dados}


def sample_lmoments(values):
    """Primeiros L-momentos amostrais, no estimador de PWMs usual."""
    x = np.sort(np.asarray(values, dtype=float))
    n = len(x)
    if n < 4:
        raise ValueError("Poucos dados para ajustar GEV.")

    b = []
    for r in range(3):
        den = comb(n - 1, r)
        total = 0.0
        for i, value in enumerate(x, start=1):
            if i >= r + 1:
                total += comb(i - 1, r) / den * value
        b.append(total / n)

    l1 = b[0]
    l2 = 2 * b[1] - b[0]
    l3 = 6 * b[2] - 6 * b[1] + b[0]
    return l1, l2, l3


def gev_lmom_quantiles(values):
    """Ajuste GEV por L-momentos e quantis 95%/99%."""
    l1, l2, l3 = sample_lmoments(values)
    if l2 <= 0:
        raise ValueError("L-momento de dispersão inválido.")
    tau3 = l3 / l2

    def theoretical_tau3(k):
        if abs(k) < 1e-7:
            return 2 * log(3) / log(2) - 3
        return 2 * (1 - 3 ** (-k)) / (1 - 2 ** (-k)) - 3

    try:
        k = brentq(lambda z: theoretical_tau3(z) - tau3, -0.5, 0.5)
    except ValueError:
        c = 2 / (3 + tau3) - log(2) / log(3)
        k = 7.8590 * c + 2.9554 * c * c

    if abs(k) < 1e-7:
        alpha = l2 / log(2)
        xi = l1 - alpha * 0.5772156649015329
        quant = lambda p: xi - alpha * log(-log(p))
    else:
        g = gamma(1 + k)
        alpha = l2 * k / ((1 - 2 ** (-k)) * g)
        xi = l1 - alpha * (1 - g) / k
        quant = lambda p: xi + alpha * (1 - (-log(p)) ** k) / k

    return {
        "q95": float(quant(0.95)), "q99": float(quant(0.99)),
        "shape": float(k), "location": float(xi), "scale": float(alpha),
    }


@app.post("/extremos")
def extremos(req: StationRequest):
    data = historico(req)["dados"]
    values = [x["acumulado"] for x in data if x["acumulado"] > 0.5]
    if len(values) < 4:
        raise HTTPException(400, "Poucos dados acima de 0.5 mm para estimar os extremos.")
    return gev_lmom_quantiles(values)
