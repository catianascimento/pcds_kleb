"use client";

import { useEffect, useMemo, useState } from "react";
import {
  GeoJSON,
  FeatureGroup,
  ImageOverlay,
  LayersControl,
  MapContainer,
  Marker,
  Popup,
  TileLayer,
  useMap,
  useMapEvents,
  CircleMarker,
  Polyline,
  Tooltip,
} from "react-leaflet";

import L from "leaflet";
import "leaflet/dist/leaflet.css";

const icon = L.divIcon({
  className: "pcd-marker",
  html: "<span></span>",
  iconSize: [12, 12],
  iconAnchor: [6, 6],
});

const suspectIcon = L.divIcon({
  className: "suspect-marker",
  html: "<span></span>",
  iconSize: [16, 16],
  iconAnchor: [8, 8],
});

function Fit({ bounds }: { bounds: number[] }) {
  const map = useMap();

  useEffect(() => {
    if (bounds?.length === 4) {
      map.fitBounds(
        [
          [bounds[1], bounds[0]],
          [bounds[3], bounds[2]],
        ],
        { padding: [10, 10] }
      );
    }
  }, [map, bounds]);

  return null;
}

// Versão anterior: desenha a krigagem no navegador usando canvas
function rasterData(data: any) {
  if (!data?.values?.length || !data?.xs?.length || !data?.ys?.length) {
    return null;
  }

  const values = data.values as (number | null)[][];
  const width = data.xs.length;
  const height = data.ys.length;

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;

  const ctx = canvas.getContext("2d");
  if (!ctx) return null;

  const image = ctx.createImageData(width, height);
  const breaks = data.breaks as number[];
  const colors = data.colors as string[];

  const rgb = colors.map((c: string) => {
    const n = parseInt(c.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  });

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const v = values[y][x];
      const dst = ((height - 1 - y) * width + x) * 4;

      if (v == null || !Number.isFinite(v)) {
        image.data[dst + 3] = 0;
        continue;
      }

      // Equivalente ao colorBin() do leaflet no R:
      // intervalos fechados à esquerda e abertos à direita (right = FALSE).
      // Valores fora dos limites e valores ausentes ficam transparentes.
      if (v < breaks[0] || v > breaks[breaks.length - 1]) {
        image.data[dst + 3] = 0;
        continue;
      }

      let i = 0;
      while (i < breaks.length - 2 && v >= breaks[i + 1]) {
        i++;
      }

      const c = rgb[i];

      image.data[dst] = c[0];
      image.data[dst + 1] = c[1];
      image.data[dst + 2] = c[2];
      // A transparência é aplicada pela própria camada Leaflet (opacity=0.7),
      // como no addRasterImage(..., opacity = 0.7) do R.
      image.data[dst + 3] = 255;
    }
  }

  ctx.putImageData(image, 0, 0);

  const dx =
    data.xs.length > 1
      ? data.xs[1] - data.xs[0]
      : 0.02;

  const dy =
    data.ys.length > 1
      ? data.ys[1] - data.ys[0]
      : 0.02;

  return {
    url: canvas.toDataURL("image/png"),
    bounds: [
      [data.ys[0] - dy / 2, data.xs[0] - dx / 2],
      [
        data.ys[height - 1] + dy / 2,
        data.xs[width - 1] + dx / 2,
      ],
    ] as [[number, number], [number, number]],
  };
}

function formatBreak(value: number) {
  return Number(value).toLocaleString("pt-BR", {
    maximumFractionDigits: 2,
  });
}

function Legend({ data }: { data: any }) {
  if (!Array.isArray(data?.breaks) || !Array.isArray(data?.colors)) return null;

  // Cada cor representa um intervalo do colorBin() do R.
  // Os intervalos são [limite inferior, limite superior), exceto o último,
  // que inclui o limite máximo. Valores abaixo do primeiro ou acima do último
  // limite ficam transparentes.
  const breaks = data.breaks as number[];
  const colors = data.colors as string[];
  const intervals = colors.map((color: string, i: number) => {
    const lower = breaks[i];
    const upper = breaks[i + 1];
    return {
      color,
      label: i === colors.length - 1
        ? `${formatBreak(lower)} – ${formatBreak(upper)}`
        : `${formatBreak(lower)} – < ${formatBreak(upper)}`,
    };
  });

  return (
    <div className="legend">
      <b>Precipitação [mm]</b>
      {intervals.map((item, i) => (
        <div key={`${item.label}-${i}`}>
          <i style={{ background: item.color }} />
          <span>{item.label}</span>
        </div>
      ))}
      <small style={{ display: "block", marginTop: 5, color: "#667085" }}>
        Fora da faixa (menor que {formatBreak(breaks[0])} ou maior que {formatBreak(breaks[breaks.length - 1])} mm): transparente.
      </small>
    </div>
  );
}

function Measure() {
  const [on, setOn] = useState(false);
  const [pts, setPts] = useState<[number, number][]>([]);
  const map = useMap();

  useMapEvents({
    click(e) {
      if (on) {
        setPts((p) => [...p, [e.latlng.lat, e.latlng.lng]]);
      }
    },
  });

  const total =
    pts.length > 1
      ? pts.slice(1).reduce(
          (sum, p, i) => sum + map.distance(pts[i], p),
          0
        )
      : 0;

  return (
    <>
      <button
        className="measure-button"
        onClick={() => {
          setOn(!on);
          setPts([]);
        }}
      >
        {on ? "×" : "⌖"} Medir
      </button>

      {pts.length > 1 && (
        <div className="measure-readout">
          {(total / 1000).toFixed(2)} km
        </div>
      )}

      <Polyline
        positions={pts}
        pathOptions={{ color: "#394b59", weight: 3 }}
      />
    </>
  );
}

export default function Map({
  data,
  onStation,
  historyMode = false,
}: {
  data: any;
  onStation?: (p: any) => void;
  historyMode?: boolean;
}) {
  const [raster, setRaster] = useState<any>(null);

  useEffect(() => {
    if (typeof window !== "undefined") {
      setRaster(rasterData(data));
    }
  }, [data]);

  const center = useMemo<[number, number]>(
    () =>
      data?.bounds?.length === 4
        ? [
            (data.bounds[1] + data.bounds[3]) / 2,
            (data.bounds[0] + data.bounds[2]) / 2,
          ]
        : [-15, -50],
    [data]
  );

  if (!data) {
    return (
      <div className="map-empty">
        <div>
          <div className="empty-icon">☔</div>
          <h2>Mapa ainda não gerado</h2>
          <p>Escolha o período e os parâmetros ao lado.</p>
        </div>
      </div>
    );
  }

  return (
    <MapContainer
      center={center}
      zoom={5}
      className="mapa"
      preferCanvas
    >
      <LayersControl position="topright">
        <LayersControl.BaseLayer
          checked
          name="OpenStreetMap"
        >
          <TileLayer
            attribution="&copy; OpenStreetMap"
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
        </LayersControl.BaseLayer>

        {/* Krigagem desenhada a partir de xs, ys e values */}
        <LayersControl.Overlay checked name="Krigagem">
          {raster && (
            <ImageOverlay
              url={raster.url}
              bounds={raster.bounds}
              opacity={0.7}
            />
          )}
        </LayersControl.Overlay>

        <LayersControl.Overlay checked name="Municípios — limites municipais">
          <GeoJSON
            key={`municipios-${data.municipalities?.features?.length ?? 0}`}
            data={data.municipalities ?? { type: "FeatureCollection", features: [] }}
            style={{ color: "#f0a020", weight: 1.15, opacity: 0.95, fillColor: "#f0a020", fillOpacity: 0.025 }}
          />
        </LayersControl.Overlay>

        <LayersControl.Overlay checked name="Limites estaduais">
          <GeoJSON
            key={`estados-${data.states?.features?.length ?? 0}`}
            data={data.states ?? { type: "FeatureCollection", features: [] }}
            style={{ color: "#243b53", weight: 2.4, opacity: 1, fillOpacity: 0 }}
          />
        </LayersControl.Overlay>

        {/* Uma única camada para todos os PCDs */}
        <LayersControl.Overlay checked name="PCDs">
          <FeatureGroup>
            {historyMode
              ? (data.points || []).map((p: any, i: number) => (
                  <Marker
                    key={p.codigo ?? i}
                    position={[p.latitude, p.longitude]}
                    icon={icon}
                    eventHandlers={{
                      click: () => onStation?.(p),
                    }}
                  >
                    <Popup>
                      <b>{p.municipio}</b>
                      <br />
                      Estação: {p.codigo}
                    </Popup>
                  </Marker>
                ))
              : (data.points || []).map((p: any, i: number) => (
                  <CircleMarker
                    key={p.codigo ?? i}
                    center={[p.latitude, p.longitude]}
                    radius={5}
                    pathOptions={{
                      color: "#111",
                      fillColor: "#fff",
                      fillOpacity: 1,
                      weight: 2,
                    }}
                    eventHandlers={{
                      click: () => onStation?.(p),
                    }}
                  >
                    <Popup>
                      <b>{p.municipio}</b>
                      <br />
                      Estação: {p.codigo}
                      <br />
                      Acumulado:{" "}
                      {Number.isFinite(p.acumulado)
                        ? p.acumulado.toFixed(1)
                        : "—"}{" "}
                      mm
                      {p.status_consistencia && (
                        <>
                          <br />
                          Previsto na primeira krigagem: {Number.isFinite(p.calculado) ? p.calculado.toFixed(1) : "—"} mm
                          <br />
                          Observado / previsto: {Number.isFinite(p.percentual_observado_previsto) ? `${p.percentual_observado_previsto.toFixed(1)}%` : "—"}
                          <br />
                          Classificação: {p.status_consistencia}
                        </>
                      )}
                    </Popup>
                  </CircleMarker>
                ))}
          </FeatureGroup>
        </LayersControl.Overlay>

        {!historyMode && (
          <LayersControl.Overlay
            checked
            name="PCDs Suspeitas"
          >
            <FeatureGroup key={`suspeitas-${(data.suspeitos || []).length}`}>
              {(data.suspeitos || []).map(
                (p: any, i: number) => (
                  <Marker
                    key={p.codigo ?? i}
                    position={[p.latitude, p.longitude]}
                    icon={suspectIcon}
                  >
                    <Popup>
                      <b>{p.municipio}</b>
                      <br />
                      Estação: {p.codigo}
                      <br />
                      Acumulado:{" "}
                      {Number.isFinite(p.acumulado)
                        ? p.acumulado.toFixed(1)
                        : "—"}{" "}
                      mm
                      <br />
                      Calculado:{" "}
                      {Number.isFinite(p.calculado)
                        ? p.calculado.toFixed(1)
                        : "—"}{" "}
                      mm
                    </Popup>
                  </Marker>
                )
              )}
            </FeatureGroup>
          </LayersControl.Overlay>
        )}
      </LayersControl>

      <Fit bounds={data.bounds || []} />
      <Legend data={data} />
      <Measure />
    </MapContainer>
  );
}