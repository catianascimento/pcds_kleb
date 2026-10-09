"""Krigagem usada pelo aplicativo.

Este arquivo implementa, em Python, o caso específico de ``fields::Krig``
utilizado pelo aplicativo original:

    Krig(cnd, media, lambda=lambda)

com as configurações padrão relevantes:
    - covariância exponencial;
    - aRange = 1 para a interpolação normal;
    - m = 2, portanto tendência 1 + longitude + latitude;
    - pesos unitários;
    - scale.type = "user", x.center = 0 e x.scale = 1.

Para a consistência espacial o aplicativo original usa:

    Krig(cnd, media, theta = 15)

No ``fields``, theta é o antigo nome do parâmetro aRange. Portanto,
nessa etapa usamos aRange=15.

A álgebra abaixo segue o ``Krig.engine.fixed``: K + lambda/weights na
diagonal, decomposição de Cholesky, GLS para os coeficientes da tendência
e solução dos coeficientes espaciais.
"""

import numpy as np
from scipy.linalg import cholesky, solve_triangular, qr, cho_factor, cho_solve
from scipy.optimize import minimize_scalar
from scipy.spatial.distance import cdist


# ---------------------------------------------------------------------------
# Covariância
# ---------------------------------------------------------------------------

def cov_exponencial(x1, x2=None, a_range=1.0):
    """Retorna exp(-distância/aRange), como fields::Exponential."""
    x1 = np.asarray(x1, dtype=float)
    x2 = x1 if x2 is None else np.asarray(x2, dtype=float)
    d = cdist(x1, x2, metric="euclidean")
    return np.exp(-d / float(a_range))


# ---------------------------------------------------------------------------
# Parte fixa do modelo: m=2 -> polinômio de grau 1
# ---------------------------------------------------------------------------

def matriz_tendencia(x):
    """Matriz T usada pelo Krig.null.function com m=2."""
    x = np.asarray(x, dtype=float)
    return np.column_stack((
        np.ones(len(x)),
        x[:, 0],
        x[:, 1],
    ))


# ---------------------------------------------------------------------------
# Réplicas espaciais
# ---------------------------------------------------------------------------

def colapsar_replicatas(xy, valores, digits=8):
    """Reproduz o comportamento de fields::Krig.replicates.

    ``fields`` identifica locais repetidos depois de arredondar as
    coordenadas com ``digits=8``. Para cada grupo ele calcula a média e
    usa como peso o número de observações daquele local.
    """
    xy = np.asarray(xy, dtype=float)
    valores = np.asarray(valores, dtype=float)

    # É importante usar 8 casas decimais: np.unique sobre as coordenadas
    # originais não reproduz Krig.replicates.
    xy_8 = np.round(xy, digits)
    _, primeira, inverso, contagens = np.unique(
        xy_8, axis=0, return_index=True, return_inverse=True,
        return_counts=True,
    )

    # np.unique ordena as linhas. O conjunto de coordenadas usado para o
    # ajuste não depende da ordem original das PCDs.
    locais = xy_8[np.sort(primeira)]

    # O mapeamento acima precisa ser reconstruído na ordem de ``locais``.
    # Usamos uma chave arredondada para preservar a associação correta.
    grupos = {}
    for i, ponto in enumerate(xy_8):
        chave = tuple(ponto)
        grupos.setdefault(chave, []).append(i)

    locais = np.array(list(grupos.keys()), dtype=float)
    medias = np.array([np.mean(valores[idx]) for idx in grupos.values()])
    pesos = np.array([len(idx) for idx in grupos.values()], dtype=float)

    return locais, medias, pesos


# ---------------------------------------------------------------------------
# Ajuste equivalente ao Krig.engine.fixed
# ---------------------------------------------------------------------------

def ajustar_krig(xy, valores, lambda_, a_range):
    """Calcula os coeficientes ``d`` e ``c`` do modelo de Krigagem."""
    xy, valores, pesos = colapsar_replicatas(xy, valores, digits=8)

    if len(xy) < 3:
        raise ValueError("São necessárias pelo menos 3 PCDs para m=2.")

    # T = 1 + x + y
    T = matriz_tendencia(xy)

    # K é a matriz da covariância exponencial.
    K = cov_exponencial(xy, a_range=a_range)

    # Exatamente a matriz M formada em Krig.engine.fixed:
    #     diag(lambda / weightsM) + K
    M = K.copy()
    M[np.diag_indices_from(M)] += float(lambda_) / pesos

    # fields usa chol(M), que devolve uma matriz triangular superior R:
    #     M = t(R) %*% R
    R = cholesky(M, lower=False, check_finite=False)

    # VT = backsolve(Mc, Tmatrix, transpose=TRUE)
    #     equivale a resolver R' VT = T.
    VT = solve_triangular(
        R.T, T, lower=True, check_finite=False
    )

    # rhs = backsolve(Mc, yM, transpose=TRUE)
    rhs = solve_triangular(
        R.T, valores, lower=True, check_finite=False
    )

    # fields faz qr.solve(VT, rhs). Usamos QR sem pivotamento para manter
    # a mesma solução GLS sem formar uma inversa explícita.
    Q, Rq = qr(VT, mode="economic", pivoting=False, check_finite=False)
    d = solve_triangular(
        Rq, Q.T @ rhs, lower=False, check_finite=False
    )

    # c = backsolve(Mc, y - T d, transpose=TRUE)
    # c = backsolve(Mc, c)
    residuo = valores - T @ d
    c = solve_triangular(
        R.T, residuo, lower=True, check_finite=False
    )
    c = solve_triangular(
        R, c, lower=False, check_finite=False
    )

    return xy, d, c


# ---------------------------------------------------------------------------
# Estimativa automática de lambda para a primeira etapa
# ---------------------------------------------------------------------------

def estimar_lambda_gcv(xy, valores, a_range=15.0):
    """Estima lambda por GCV quando o R omite lambda em Krig(...).

    A estimativa é uma aproximação numérica ao procedimento de fields::Krig.
    Mantém o mesmo kernel exponencial, tendência linear e tratamento de
    coordenadas repetidas usado pelo ajuste principal.
    """
    xy, y, pesos = colapsar_replicatas(xy, valores, digits=8)
    if len(xy) < 3:
        raise ValueError("São necessárias pelo menos 3 PCDs para estimar lambda.")

    T = matriz_tendencia(xy)
    K = cov_exponencial(xy, a_range=a_range)
    n = len(y)
    I = np.eye(n)

    def score(log_lambda):
        lam = float(10.0 ** log_lambda)
        M = K.copy()
        M[np.diag_indices_from(M)] += lam / pesos
        try:
            cf = cho_factor(M, lower=True, check_finite=False)
            Minv = cho_solve(cf, I, check_finite=False)
            MinvT = Minv @ T
            A = T.T @ MinvT
            beta_operator = np.linalg.solve(A, T.T @ Minv)
            # Matriz de suavização: valores ajustados nos locais observados.
            S = T @ beta_operator + K @ Minv @ (I - T @ beta_operator)
            residual = y - S @ y
            denom = 1.0 - np.trace(S) / n
            if not np.isfinite(denom) or abs(denom) < 1e-10:
                return np.inf
            value = np.mean(residual ** 2) / (denom ** 2)
            return float(value) if np.isfinite(value) else np.inf
        except (np.linalg.LinAlgError, ValueError):
            return np.inf

    # Busca em escala logarítmica. O intervalo cobre suavização muito baixa
    # até alta; o mínimo é refinado pelo otimizador escalar.
    grid = np.linspace(-8.0, 4.0, 25)
    scores = np.array([score(v) for v in grid])
    finite = np.isfinite(scores)
    if not finite.any():
        return 0.0
    best = int(np.nanargmin(np.where(finite, scores, np.inf)))
    lo = grid[max(0, best - 1)]
    hi = grid[min(len(grid) - 1, best + 1)]
    if lo == hi:
        return float(10.0 ** grid[best])
    result = minimize_scalar(
        score, bounds=(float(lo), float(hi)), method="bounded",
        options={"xatol": 0.05, "maxiter": 20},
    )
    if not result.success or not np.isfinite(result.fun):
        return float(10.0 ** grid[best])
    return float(10.0 ** result.x)


# ---------------------------------------------------------------------------
# Predição: equivalente a predict(Krig(...), grid)
# ---------------------------------------------------------------------------

def interpolar(xy, valores, grid_xy, lambda_=0.0, a_range=1.0):
    """Prediz nos pontos de ``grid_xy`` usando a Krigagem equivalente ao R."""
    xy = np.asarray(xy, dtype=float)
    valores = np.asarray(valores, dtype=float)
    grid_xy = np.asarray(grid_xy, dtype=float)

    xy_fit, d, c = ajustar_krig(xy, valores, lambda_, a_range)

    # Parte polinomial + parte espacial.
    pred = matriz_tendencia(grid_xy) @ d
    pred += cov_exponencial(grid_xy, xy_fit, a_range=a_range) @ c

    # O app.R faz result[result < 0] <- 0 imediatamente após predict().
    return np.maximum(pred, 0.0)


# ---------------------------------------------------------------------------
# Conversão de ponto para a célula do raster
# ---------------------------------------------------------------------------

def indice_celula(x, y, xs, ys):
    """Encontra a célula da grade correspondente ao ponto.

    A grade é composta pelos mesmos centros produzidos por
    make.surface.grid(). Para a consistência, o importante é usar a célula,
    e não simplesmente predict() exatamente no ponto da PCD.
    """
    xs = np.asarray(xs)
    ys = np.asarray(ys)
    ix = int(np.argmin(np.abs(xs - x)))
    iy = int(np.argmin(np.abs(ys - y)))
    return iy, ix


def valores_nas_celulas(xy, raster, xs, ys):
    """Obtém para cada PCD o valor da célula equivalente ao cellFromXY()."""
    arr = np.asarray(raster, dtype=float).reshape(len(ys), len(xs))
    saida = np.full(len(xy), np.nan, dtype=float)

    for i, (x, y) in enumerate(np.asarray(xy, dtype=float)):
        iy, ix = indice_celula(x, y, xs, ys)
        valor = arr[iy, ix]
        if np.isfinite(valor):
            saida[i] = valor

    return saida


# ---------------------------------------------------------------------------
# Consistência espacial
# ---------------------------------------------------------------------------

def consistencia(xy, valores, grid_xy, xs, ys, lambda_, threshold, mascara=None):
    """Executa a consistência espacial conforme a sequência do app.R.

    A primeira Krigagem usa theta=15 e lambda automático, pois o R omite
    lambda nessa chamada. O threshold é informado em porcentagem (20 = 20%).
    A máscara geográfica NÃO é aplicada ao raster auxiliar: no app.R a máscara
    só é aplicada depois da segunda interpolação.
    """
    xy = np.asarray(xy, dtype=float)
    valores = np.asarray(valores, dtype=float)

    if not 0.0 <= float(threshold) <= 100.0:
        raise ValueError("O threshold deve estar entre 0 e 100 (%).")

    # 1. Equivale a Krig(cnd, media, theta=15): lambda é estimado
    # automaticamente pelo critério GCV, em vez de ser fixado em zero.
    lambda_aux = estimar_lambda_gcv(xy, valores, a_range=15.0)
    previsto_grid = interpolar(
        xy, valores, grid_xy,
        lambda_=lambda_aux,
        a_range=15.0,
    )

    # 2. O R consulta o raster auxiliar na célula que contém cada estação.
    #    Não se mascara este raster antes da consulta (app.R não faz isso).
    previsto_pcd = valores_nas_celulas(xy, previsto_grid, xs, ys)

    # 3. Regra de consistência sem o corte adicional de 15 mm:
    #    uma PCD é suspeita quando o acumulado observado é menor que a
    #    porcentagem configurada do valor previsto, para qualquer previsto
    #    finito (inclusive valores previstos de 15 mm ou menos).
    threshold_fraction = float(threshold) / 100.0
    suspeita = (
        np.isfinite(previsto_pcd)
        & np.isfinite(valores)
        & (valores < threshold_fraction * previsto_pcd)
        & (previsto_pcd > 15.0)
    )

    # No R, dataAccep fica NA quando não há previsão válida. Esses postos
    # não entram nem em unusedPCDS (dataAccep == 0) nem na interpolação
    # corrigida (dataAccep == 1). Não devemos aceitá-los por padrão.
    valido = np.isfinite(previsto_pcd) & np.isfinite(valores)
    aceito = valido & ~suspeita
    if int(aceito.sum()) < 3:
        raise ValueError(
            "Menos de 3 PCDs com previsão válida permaneceram após a consistência."
        )

    # 4. Equivale a Krig(cndCor, mediaCor, lambda=input$lambda), usando
    #    theta/range padrão (=1), somente com dataAccep == 1.
    corrigido = interpolar(
        xy[aceito],
        valores[aceito],
        grid_xy,
        lambda_=lambda_,
        a_range=1.0,
    )

    return corrigido, suspeita, previsto_pcd
