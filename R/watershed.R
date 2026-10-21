# Delimitação de bacias hidrográficas e rede de rios usando somente R.
# A API Global Watersheds fornece GeoJSON baseado em MERIT-Hydro.
# As respostas ficam em cache local para evitar repetir consultas para o mesmo ponto.

.global_watersheds_request_state <- new.env(parent = emptyenv())
.global_watersheds_request_state$last_request <- NULL

normalizar_wgs84 <- function(x) {
  if (is.null(x) || nrow(x) == 0L) return(x)

  crs_atual <- sf::st_crs(x)
  if (is.na(crs_atual)) {
    sf::st_crs(x) <- 4326
  } else if (is.na(crs_atual$epsg) || crs_atual$epsg != 4326) {
    x <- sf::st_transform(x, 4326)
  }
  x
}

ler_geojson <- function(caminho) {
  if (!file.exists(caminho) || is.na(file.info(caminho)$size) ||
      file.info(caminho)$size < 2L) {
    stop("A resposta da delimitação está vazia ou não é um GeoJSON válido.", call. = FALSE)
  }

  resultado <- tryCatch(
    sf::st_read(caminho, quiet = TRUE),
    error = function(e) {
      stop(
        "Não foi possível interpretar o GeoJSON recebido: ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )
  normalizar_wgs84(resultado)
}

obter_cache_bacias <- function() {
  pasta <- Sys.getenv(
    "WATERSHED_CACHE_DIR",
    unset = file.path(getwd(), ".cache", "watersheds")
  )
  if (!nzchar(pasta)) pasta <- file.path(getwd(), ".cache", "watersheds")

  if (!dir.exists(pasta)) {
    dir.create(pasta, recursive = TRUE, showWarnings = FALSE)
  }
  if (!dir.exists(pasta)) {
    stop(
      "Não foi possível criar a pasta de cache da delimitação: ", pasta,
      call. = FALSE
    )
  }
  normalizePath(pasta, winslash = "/", mustWork = TRUE)
}

chave_ponto_bacia <- function(lat, lng) {
  # A API trabalha com coordenadas em graus decimais; seis casas são suficientes
  # para reutilizar uma resposta quando o usuário clica novamente no mesmo local.
  lat_txt <- formatC(round(lat, 6), format = "f", digits = 6, decimal.mark = ".")
  lng_txt <- formatC(round(lng, 6), format = "f", digits = 6, decimal.mark = ".")
  chave <- paste0("lat_", lat_txt, "_lng_", lng_txt)
  gsub("-", "m", chave, fixed = TRUE)
}

aguardar_intervalo_api <- function() {
  # O mantenedor pede que as solicitações sejam espaçadas em pelo menos 5 s.
  # O controle é compartilhado entre sessões no mesmo processo R.
  ultima <- .global_watersheds_request_state$last_request
  if (!is.null(ultima)) {
    decorrido <- as.numeric(difftime(Sys.time(), ultima, units = "secs"))
    if (is.finite(decorrido) && decorrido < 5) {
      Sys.sleep(5 - decorrido)
    }
  }
  .global_watersheds_request_state$last_request <- Sys.time()
  invisible(NULL)
}

baixar_geojson_global_watersheds <- function(endpoint, lat, lng, arquivo_cache) {
  consulta_rios <- grepl("upstream_rivers_api", endpoint, fixed = TRUE)
  # Usa cache local sempre que já existe uma resposta válida para o ponto.
  if (file.exists(arquivo_cache) && file.info(arquivo_cache)$size > 0L) {
    em_cache <- tryCatch(ler_geojson(arquivo_cache), error = function(e) NULL)
    if (!is.null(em_cache)) return(em_cache)
    unlink(arquivo_cache, force = TRUE)
  }

  if (!requireNamespace("httr", quietly = TRUE)) {
    stop(
      "Falta o pacote R 'httr'. Instale-o com install.packages('httr').",
      call. = FALSE
    )
  }

  url <- httr::modify_url(
    endpoint,
    query = list(
      lat = formatC(lat, format = "f", digits = 6, decimal.mark = "."),
      lng = formatC(lng, format = "f", digits = 6, decimal.mark = "."),
      precision = "high",
      simplify = "true",
      beautify = "false"
    )
  )

  aguardar_intervalo_api()
  resposta <- tryCatch(
    httr::GET(
      url,
      httr::timeout(120),
      httr::user_agent("PCDsCemaden R Shiny")
    ),
    error = function(e) {
      stop(
        "Não foi possível acessar a API Global Watersheds: ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )

  status <- httr::status_code(resposta)
  if (status != 200L) {
    if (status == 404L) {
      if (consulta_rios) {
        stop(
          paste0(
            "A API não conseguiu gerar a rede de rios para esse ponto (HTTP 404). ",
            "A bacia pode ser válida; tente clicar mais perto de um rio."
          ),
          call. = FALSE
        )
      }
      stop(
        paste0(
          "A API Global Watersheds não conseguiu delimitar uma bacia nesse ponto (HTTP 404). ",
          "Isso pode ocorrer em áreas sem drenagem definida, sobre água/oceano, ou em locais ",
          "em que os dados hidrológicos não permitem gerar o resultado. Tente clicar sobre ou bem próximo de um rio."
        ),
        call. = FALSE
      )
    }
    if (status == 400L) {
      stop("A API Global Watersheds rejeitou as coordenadas selecionadas (HTTP 400).", call. = FALSE)
    }
    stop(
      "A API Global Watersheds retornou HTTP ", status,
      ". Tente novamente mais tarde.",
      call. = FALSE
    )
  }

  conteudo <- httr::content(resposta, as = "raw")
  arquivo_temporario <- tempfile(
    pattern = "watershed_",
    tmpdir = dirname(arquivo_cache),
    fileext = ".geojson"
  )
  on.exit(unlink(arquivo_temporario, force = TRUE), add = TRUE)
  writeBin(conteudo, arquivo_temporario)

  # Valida o GeoJSON antes de gravá-lo no cache permanente.
  resultado <- ler_geojson(arquivo_temporario)
  if (nrow(resultado) < 1L) {
    stop("A API retornou uma camada geográfica vazia para esse ponto.", call. = FALSE)
  }

  if (!file.copy(arquivo_temporario, arquivo_cache, overwrite = TRUE)) {
    warning("Não foi possível gravar o cache local; a delimitação continuará disponível nesta sessão.")
  }
  resultado
}

#' Delimita uma bacia e a rede de rios a montante de um ponto
#' @return Lista com objetos sf: bacia, rios, e fonte.
delinear_bacia <- function(lat, lng) {
  lat <- suppressWarnings(as.numeric(lat))
  lng <- suppressWarnings(as.numeric(lng))

  if (length(lat) != 1L || length(lng) != 1L ||
      !is.finite(lat) || !is.finite(lng) ||
      lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    stop("As coordenadas do clique não são válidas.", call. = FALSE)
  }

  # Normaliza a precisão utilizada na requisição e na chave de cache.
  lat <- round(lat, 6)
  lng <- round(lng, 6)
  pasta_cache <- obter_cache_bacias()
  chave <- chave_ponto_bacia(lat, lng)
  arquivo_bacia <- file.path(pasta_cache, paste0(chave, "_bacia.geojson"))
  arquivo_rios <- file.path(pasta_cache, paste0(chave, "_rios.geojson"))

  bacia <- baixar_geojson_global_watersheds(
    "https://mghydro.com/app/watershed_api",
    lat, lng, arquivo_bacia
  )
  # A bacia e a rede de rios são geradas por endpoints separados. A falha do
  # endpoint de rios não deve apagar uma bacia que já foi delimitada com sucesso.
  aviso_rios <- NULL
  rios <- tryCatch(
    baixar_geojson_global_watersheds(
      "https://mghydro.com/app/upstream_rivers_api",
      lat, lng, arquivo_rios
    ),
    error = function(e) {
      aviso_rios <<- conditionMessage(e)
      NULL
    }
  )

  list(bacia = bacia, rios = rios, fonte = "api", aviso = aviso_rios)
}
