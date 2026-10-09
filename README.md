# PCDs CEMADEN — Python + React

Aplicação web para interpolação espacial de precipitação de PCDs do CEMADEN.

## Tecnologias

- Backend: Python + FastAPI
- Banco: PostgreSQL
- Krigagem: implementação Python do caso de `fields::Krig` usado pela aplicação
- Geoprocessamento: GeoPandas, Shapely e Rasterio
- Frontend: Next.js + React + TypeScript + Leaflet

**Não há código R nem execução de R neste projeto.**

## 1. Banco de dados

Copie `backend/.env.example` para `backend/.env` e informe as credenciais do PostgreSQL. O arquivo `.env` com credenciais locais não é distribuído no ZIP.

O backend espera as tabelas usadas pela aplicação:

- `info_pcd`
- `estat_diaria`

Colunas usadas:

```text
info_pcd:
  codestacao, nome, cidade, longitude, latitude, uf

estat_diaria:
  codestacao, datadia, valor, n_dados
```

## 2. Backend

```bash
cd backend
python -m venv venv
venv\\Scripts\\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

No Linux/macOS, ative o ambiente com `source venv/bin/activate`.

## 3. Frontend

```bash
cd frontend
npm install
npm run dev
```

Por padrão o frontend usa `http://localhost:8000` para o backend.

Para outro endereço:

```text
NEXT_PUBLIC_API_URL=http://localhost:8000
```

## Krigagem

A implementação em `backend/kriging.py` segue a álgebra do caso de `fields::Krig` usado pelo aplicativo:

1. covariância exponencial `exp(-d/aRange)`;
2. `m=2`, com matriz `1 + x + y`;
3. colapso de réplicas em 8 casas decimais;
4. pesos iguais ao número de observações em cada local repetido;
5. matriz `K + lambda/weights` na diagonal;
6. Cholesky;
7. GLS da tendência por QR;
8. coeficientes espaciais;
9. predição na grade;
10. valores negativos zerados.

Para consistência espacial, `aRange=15`, e a PCD é comparada ao valor da célula da grade antes da filtragem.

## Funcionalidades

- Interpolação PCDs
- Consistência espacial
- PCDs suspeitas
- Seleção por estado ou região
- Resolução espacial
- Lambda de suavização
- Threshold de consistência
- Mapa Leaflet
- Raster interpolado
- Limites estaduais
- Municípios monitorados
- PCDs e PCDs suspeitas
- Medição de distância
- Tabela por município
- Tabela por PCD
- Histórico de estação
- Extremos GEV por L-momentos
- Quantis 95% e 99%
- Download GeoTIFF


## Revisão da consistência espacial em relação ao app.R

Alterações nesta revisão:
- A krigagem auxiliar `theta=15` não fixa mais `lambda=0`; estima `lambda` automaticamente por GCV, pois o `app.R` omite esse argumento. A estimativa Python é numérica e deve ser comparada com o `lambda` do objeto `Krig` da versão instalada de `fields`.
- A máscara geográfica não é aplicada ao raster auxiliar antes da leitura das células das PCDs, porque o `app.R` não mascara essa superfície intermediária.
- PCDs sem previsão válida não são consideradas aceitas automaticamente: no R, `dataAccep=NA` não entra nem em `dataAccep == 0` nem em `dataAccep == 1`.
- A grade usa os mesmos limites de `seq(min, max, by=res)` do R e evita adicionar pontos além do limite superior.
- A segunda krigagem continua usando somente PCDs aceitas e o `lambda` selecionado na interface, com o range padrão da função.

### Limitação da equivalência numérica

A equivalência exata depende da versão do pacote `fields` instalada no ambiente R, especialmente do método usado para estimar `lambda` quando ele é omitido. Para uma validação conclusiva, compare no R `packageVersion("fields")`, `fit$lambda` e `fit$method` para `fit <- Krig(cnd, media, theta=15)`, usando exatamente os mesmos dados e coordenadas da execução Python.


## Paleta de precipitação — equivalência visual com o R

A renderização do raster no navegador reproduz a paleta RGB e os limites de `breaks.intervals` definidos em `app.R`. Cada uma das 22 cores corresponde ao intervalo entre dois limites consecutivos (23 limites). Os intervalos são fechados à esquerda e abertos à direita, com o limite máximo incluído no último intervalo, conforme `colorBin()` do Leaflet no R. Valores fora da faixa e valores ausentes são transparentes. A opacidade do raster é `0.7`, como no `addRasterImage()` original.

Os intervalos são escalados de acordo com o número de dias selecionado, pela mesma regra usada em `intervalsBreaks()` no R. Como a API devolve `breaks` e `colors` tanto em `/mapa` quanto em `/consistencia`, a mesma classificação de cores é aplicada aos dois mapas.

## Revisão da comparação visual e diagnóstico da consistência

- O raster no navegador agora usa pixels opacos e aplica `opacity=0.7` uma única vez na camada, como `addRasterImage(..., opacity = 0.7)` no R. Antes a transparência era aplicada duas vezes (alpha do pixel e opacidade da camada), deixando as cores lavadas.
- A legenda usa uma cor para cada intervalo consecutivo de `breaks`, com 22 cores para 23 limites, e informa que valores fora da faixa ficam transparentes.
- No mapa de consistência, o popup de cada PCD informa o previsto na primeira krigagem, a razão observado/previsto e a classificação (Suspeita, Aceita ou Sem previsão válida). Isso permite verificar casos que parecem não ter sido descartados.
- A regra Python continua sem o corte de 15 mm, conforme solicitado anteriormente. O `app.R` original exige `prevKrig > 15`; portanto, as duas regras não serão idênticas para previsões de 15 mm ou menos.
- A primeira krigagem Python estima lambda por uma implementação GCV aproximada. A igualdade exata da classificação ainda deve ser validada contra os valores previstos e o lambda produzidos pela versão de `fields` usada no R. Sem essa comparação com os mesmos dados, não se deve afirmar equivalência numérica exata.
