# Aplicação de producao de campos interpolados de PCDs do Cemaden
# Tambem produz e exibe dados estatisticos e de extremos (Somente Pluviometros)
# A configuração do banco é lida de um arquivo local .env (não versionado).
#
# Kleber Lopes da Rocha Filho - Tecnologista CGPD - Cemaden
# FEB-2026

################################################################################
# Bibliotecas

library(shiny)
library(shinydashboard)
library(leaflet)
library(leafem)
library(leaflet.extras)
library(shinythemes)
library(DT)
library(fields)
library(sf)
library(raster)
library(extremeStat)
library(DBI)
library(RPostgres)
library(shinycssloaders)

# Carrega configurações locais, quando o arquivo existir. O .env fica fora do Git.
if (file.exists(file.path(getwd(), ".env"))) {
  readRenviron(file.path(getwd(), ".env"))
} else if (file.exists(file.path(getwd(), ".Renviron"))) {
  readRenviron(file.path(getwd(), ".Renviron"))
}

# Funções R para delimitação via API Global Watersheds com cache local.
source(file.path("R", "watershed.R"))

################################################################################
# Setor de carregamento de informacoes externas pre-geradas

# Carrega dados processados pelo avaliaPluRede
# Removido com o uso da versão com postgres - 20260128
# load("./data/Dados_2015-2025.rda")

# # Carrega coords dos postos
# load("./data/infoPosto.rda")
# 
# # Carrega Estado a processar
# load("./data/estadoUse.rda")
# 
# # Carrega Estado a processar
# load("./data/munCema_2026.rda")

################################################################################
# Constantes e formatacoes iniciais

# Instrumentos (num-nome)
instrums <- data.frame(nInstrum = c(0), instrumName = c("Precipitação"))

# Estados disponiveis
estados_available <- sort(c("AC","AL" ,"AM" ,"AP" ,"BA" ,"CE", "DF", "ES", "GO","MA" , "MG" ,"MS" ,"MT" ,"PA" ,"PB" ,"PE" ,
                            "PI" ,"PR" ,"RJ", "RN","RO" ,"RR" ,"RS", "SE", "SC", "SP", "TO"))

# regioes disponiveis
regions_available <- c("CO", "N", "NE", "S", "SE")

# opcoes de escolha
regions_opt <- c("Estado", "Região")


# Formata datas dos dados de entrada (acumMatrix)
# acumMatrix[, 1] <- as.Date(format(as.POSIXct(strptime(as.character((acumMatrix[, 1])), format="%Y%m%d%H%M"), tz = "GMT"), format = "%Y-%m-%d"))

# Logo do Cemaden
logoCema <- "Logo_Comemorativo_15_Anos_Cemaden_2026_transparente_inv.png"

token_ped <- Sys.getenv("PED_TOKEN_FILE", unset = file.path(".secrets", "tokenPed.txt"))


source("./R/getLocationPCDCemaden.R")
source("./R/renewTokenPED.R")

###############################################################################
ui <- dashboardPage( 
  
  
  dashboardHeader(title = "PCDs - Cemaden ", titleWidth = 300),
  
  
  dashboardSidebar(
    sidebarMenu(id = "sidebarid",
                menuItem("Interpolação PCDs", tabName = "pData", icon = icon("cloud-rain")),
                menuItem("Consistência Espacial", tabName = "pCons", icon = icon("list-check")),
                menuItem("Históricos e Extremos", tabName = "pEstat", icon = icon("chart-line")),
                
                dateRangeInput(inputId = 'dateRange', 
                               label = 'Intervalo: AAAA-MM-DD',
                               start = as.Date(Sys.Date()), 
                               end = as.Date(Sys.Date()), 
                               language = "pt-BR", 
                               min = as.Date("2015-01-01"), 
                               max = as.Date(Sys.Date())),
                selectInput("region_option",
                            "Seleção por :",
                            choices = regions_opt,
                            selected = "Estado"),
                
                conditionalPanel(
                  condition = 'input.region_option == "Estado"',
                  
                  selectInput("state_select",
                              "Estado :",
                              choices = estados_available,
                              selected = "SP"), 
                  numericInput(inputId = "spatial_res", 
                               label = HTML("Resolução Espacial [km]:"), 
                               value = 2,
                               min = 0.25, 
                               max = 10, 
                               updateOn = "blur") 
                  
                ),
                
                conditionalPanel(
                  condition = 'input.region_option == "Região"',
                  
                  selectInput("region_select",
                              "Região :",
                              choices = regions_available,
                              selected = "SE"), 
                  numericInput(inputId = "spatial_res", 
                               label = HTML("Resolução Espacial [km]:"), 
                               value = 5,
                               min = 0.25, 
                               max = 10, 
                               updateOn = "blur"), 
                  
                ),
                
                # selectInput("state_select",
                #             "Estado :",
                #             choices = estados_available,
                #             selected = "SP"),
                # radioButtons("checkSmoothCor",
                #              label = "Opção de Smooth",
                #              choices = list("Automático", "Manual"),
                #              selected = "Manual"),
                
                numericInput(inputId = "lambda", 
                             label = HTML("Parâmetro de Smooth: <br/> (p = 0 - Baixo | p > 1 - Alto)"), 
                             value = 0.0,
                             min = 0, 
                             max = 20, 
                             updateOn = "blur"),

                conditionalPanel(
                  'input.sidebarid == "pData"',


                ),
                
                conditionalPanel(
                  'input.sidebarid == "pCons"',
                  # dateRangeInput(inputId = 'dateRange', 
                  #                label = 'Intervalo: AAAA-MM-DD',
                  #                start = as.Date(Sys.Date()), 
                  #                end = as.Date(Sys.Date()), 
                  #                language = "pt-BR", 
                  #                min = as.Date("2015-01-01"), 
                  #                max = as.Date(Sys.Date())), 
                  # selectInput("state_select",
                  #             "Estado :",
                  #             choices = estados_available, 
                  #             selected = "SC"),
                  numericInput(inputId = "percBotton", 
                               label = HTML("Threshold Mínimo: <br/> (% do previsto para descarte)"), 
                               value = 0.2,
                               min = 0, 
                               max = 1, 
                               updateOn = "blur"), 
                  # radioButtons("checkSmoothCor", 
                  #              label = "Opção de Smooth", 
                  #              choices = list("Automático", "Manual"),
                  #              selected = "Manual"),
                  # conditionalPanel(
                  #   condition = "input.checkSmoothCor == 'Manual'",
                  #   numericInput(inputId = "lambdaCor", 
                  #                label = HTML("Parâmetro de Smooth: <br/> (p = 0 - Baixo | p > 1 - Alto)"), 
                  #                value = 0.05,
                  #                min = 0, 
                  #                max = 20, 
                  #                updateOn = "blur"))
                ),
                
                # conditionalPanel(
                #     'input.sidebarid == "pEstat"',
                #     selectInput("posto", "Selecione a Estação:", choices = unique(as.character(estacoes$nome))), 
                #     dateRangeInput(inputId = 'dateRange', label = 'Datas: AAAA-MM-DD',
                #                    start = Sys.Date() - 10, end = Sys.Date())
                # ), 
                
                conditionalPanel(
                  'input.sidebarid == "pEstat"',
                  #selectInput("postoEstat", "Selecione a Estação:", choices = unique(as.character(estacoes$nome))),
                  #selectInput("exInstrum", "Selecione a Variável:", choices = unique(as.character(instrums$instrumName)))
                ),
                
                actionButton("update_interpol", "Gerar Mapa")
    ), 
    
    # Logo at bottom
    tags$div(style = "position: absolute; bottom: 0; width: 100%; text-align: center; padding: 0px;",
             img(src = logoCema, height = "150px", width = "180px"))
             
  ),
  dashboardBody(
    
    tabItems(
      tabItem("pData",
              fluidRow( 
                column(width = 7,
                       box(width = NULL, solidHeader = TRUE,
                           tags$p(
                             "Clique com o botão esquerdo no mapa para desenhar a bacia hidrográfica e os rios a montante.",
                             style = "color: #555; margin: 4px 0 8px 0;"
                           ),
                           leafletOutput("mapaSimples", height = 800) %>% withSpinner(type = 1, color = "#2596be"),
                           downloadButton("downloadData", "Download Raster")
                           #actionButton("update", "Gerar Interpolação")
                       )
                ),
                column(width = 5, 
                       box(width = NULL, solidHeader = TRUE, style = "overflow-x: scroll;", 
                           
                             tabsetPanel(type = "tabs",
                                         tabPanel("Por Municipio", 
                                                  dataTableOutput("AcumMunCema") %>% withSpinner(type = 1, color = "#2596be")), 
                                         tabPanel("Por PCD",  
                                                  dataTableOutput("meteoDiario"))
                                         )
                           ), 
                           
                        
                )
              ) # Row 
      ),  # TabItem diario
      
      tabItem("pCons",
              fluidRow( 
                column(width = 7,
                       box(width = NULL, solidHeader = TRUE,
                           tags$p(
                             "Clique com o botão esquerdo no mapa para desenhar a bacia hidrográfica e os rios a montante.",
                             style = "color: #555; margin: 4px 0 8px 0;"
                           ),
                           leafletOutput("mapaCons", height = 800) %>% withSpinner(type = 1, color = "#2596be"),
                           downloadButton("downloadDataCons", "Download Raster")
                           #actionButton("update", "Gerar Interpolação")
                       )
                ),
                column(width = 5, 
                       box(width = NULL, solidHeader = TRUE, style = "overflow-x: scroll;", 
                           
                           tabsetPanel(type = "tabs",
                                       tabPanel("Postos Suspeitos", 
                                                dataTableOutput("PCDsuspeitas") %>% withSpinner(type = 1, color = "#2596be"))  
                           )
                       ), 
                       
                       
                )
              ) # Row 
      ),  # TabItem diario
      
      tabItem("pEstat",
              fluidRow(
                column(width = 6,
                       #plotlyOutput("grafStat"),
                       #dataTableOutput("dadosTeste"),
                       #verbatimTextOutput("p_postoEstat")
                       box(width = NULL, solidHeader = TRUE,
                           leafletOutput("mapaEstacoes", height = 800)
                       )
                ),
                column(width = 6,
                              # Output: Tabset w/ plot, summary, and table ----
                             tabsetPanel(type = "tabs",
                                         tabPanel("Histórico",
                                                  dataTableOutput("HistPosto")),
                                         tabPanel("Extremos", align="center",
                                                  plotOutput("grafExtreme", height = "550px", width = "700px"),
                                                  dataTableOutput("Quantiles")),
                                         # tabPanel("Médias Climatológicas",
                                         #          plotlyOutput("grafMedia",  height = "550px", width = "800px")
                                         #          #ploacumMatrix[, 1]tOutput("grafMedia", height = "550px", width = "800px")
                                         # )
                             )
                ) # column

              ) # Row
      )  # TabItem porPosto
    ) # Todos itens
  ) # Body do dashboard
) # UI
################################################################################
################################## SERVER ######################################

# Define server logic required to draw a histogram
server <- function(input, output, session) {
  
  # Declaracoes de vetores
  precPCD     <- vector()
  latPCD      <- vector()
  lonPCD      <- vector()
  idPCD       <- vector()
  precMedMun  <- vector()
  precMaxMun  <- vector()
  nameMun     <- vector()
  munPCD      <- vector()

  # Leitura dos shapes dos estados e municipios montorados
  # mun monitorados
  munCemaAll   <- st_read("./data/municipios_monitorados.shp")
  estadoUseAll <- st_read("./data/BR_UF_2024.shp")


  # Produz os icones usados nos mapas
  leafIcon <- makeIcon(
    iconUrl = "./data/P.png",
    iconWidth = 24, iconHeight = 24, # Set size in pixels
    iconAnchorX = 12, iconAnchorY = 12
  )
  
  ## Paleta de cores e intervalos - Precipitacao
  palette <- c(rgb(200,200,200,maxColorValue=255),
               rgb(213,255,255,maxColorValue=255), rgb(0,213,255,maxColorValue=255),
               rgb(0,128,170,maxColorValue=255),   rgb(0,0,179,maxColorValue=255) ,
               rgb(128,255,85,maxColorValue=255),  rgb(0,204,127,maxColorValue=255),
               rgb(85,128,0,maxColorValue=255),    rgb(0,85,0,maxColorValue=255),
               rgb(255,255,0,maxColorValue=255),   rgb(255,204,0,maxColorValue=255),
               rgb(255,153,0,maxColorValue=255),   rgb(213,85,0,maxColorValue=255),
               rgb(255,187,255,maxColorValue=255), rgb(255,89,226,maxColorValue=255), 
               rgb(255,43,128,maxColorValue=255),  rgb(128,0,170,maxColorValue=255), 
               rgb(73,0,138,maxColorValue=255), rgb(35,0,66,maxColorValue=255), rgb(255,255,255,maxColorValue=255), 
               rgb(200,200,200,maxColorValue=255),rgb(138,138,138,maxColorValue=255))
  

  # Intervalos de exibição das cores
  breaks.intervals <- c(0.1,0.5,1,2,3,5,7,10,15,20,25,30,40,50,75,100,150,200,250,300,350,400,500)
  
  # Constroi paleta
  pal      <- colorBin(palette, bins = breaks.intervals, na.color = "transparent")
  
  # Grpo para legenda do leaflet
  group_telem     <- paste("PCDs Cemaden")
  group_telem_cor <- paste("PCDs Suspeitas")
  group_interpol  <- paste("PCDs Krigagem")


  # Conexão PostgreSQL: todas as credenciais vêm do .env/ambiente.
  required_db_vars <- c("DB_NAME", "DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD")
  env_db_values <- vapply(required_db_vars, Sys.getenv, character(1), unset = "")
  missing_db_vars <- names(env_db_values)[!nzchar(env_db_values)]
  if (length(missing_db_vars) > 0) {
    stop(
      paste0(
        "Configure as variáveis ", paste(missing_db_vars, collapse = ", "),
        " no arquivo local .env. Use .env.example como modelo; não envie .env ao GitHub."
      ),
      call. = FALSE
    )
  }

  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    dbname = Sys.getenv("DB_NAME"),
    host = Sys.getenv("DB_HOST"),
    port = as.integer(Sys.getenv("DB_PORT")),
    user = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASSWORD")
  )

  session$onSessionEnded(function() {
    if (DBI::dbIsValid(con)) DBI::dbDisconnect(con)
  })
  
  #############################################################################
  # Reactives

  
  # # Atualiza datas para dia atual  
  # observeEvent(input$state_select, {
   mun_monitorados <- reactive({
     
     if(input$region_option == "Estado"){
       munCema   <- munCemaAll[munCemaAll$uf == input$state_select, ] 
     }
     
     if(input$region_option == "Região"){
       
       region_selected <- estadoUseAll$SIGLA_UF[estadoUseAll$SIGLA_RG == input$region_select]
       munCema   <- munCemaAll[munCemaAll$uf %in% region_selected, ] 
     }
     return(munCema)
   })
  
  estado_utilizado <- reactive({
    
    if(input$region_option == "Estado"){
      estadoUse <- estadoUseAll[estadoUseAll$SIGLA_UF == input$state_select, ] 
    }
    
    if(input$region_option == "Região"){
      
      region_selected <- estadoUseAll$SIGLA_UF[estadoUseAll$SIGLA_RG == input$region_select]
      estadoUse <- estadoUseAll[estadoUseAll$SIGLA_UF %in% region_selected, ] 
    }

    return(estadoUse)
  })  
  
  bounds <- reactive({
    bounds <- extent(estado_utilizado())
    return(bounds)
  })  
    
  grid_krig <- reactive({
    
    estadoUse <- estado_utilizado()
    
    # Monta grade de interpolação para krigagem 
    bounds <- extent(estadoUse)
    res <- 0.009803922 * input$spatial_res
    grid <- make.surface.grid(list(seq(bounds[1],bounds[2],by=res),seq(bounds[3],bounds[4],by=res)))
    
    return(grid)
  })
    
  # Coordenadas e metadados das PCDs vêm diretamente do PostgreSQL.
  make_infoposto <- reactive({
    
    estadoUse <- estado_utilizado()
    
    if(input$region_option == "Região"){
      region_query <- paste0("'", paste(estadoUse$SIGLA_UF, collapse = "','"), "'")
    } 
    
    if(input$region_option == "Estado"){
      region_query <- paste0("'",estadoUse$SIGLA_UF, "'")
    } 

    # Monta query para select no postgres
    query_info_postgres <- paste0("SELECT codestacao, nome, cidade, longitude, latitude, uf",
                                   " from info_pcd", 
                                   " where",  
                                   " uf in (", region_query, ")")
    
    # Roda a query de select
    select_info <- try(dbSendQuery(conn = con, statement = query_info_postgres))
    infoPosto   <- dbFetch(select_info)
    
    # infoPosto <- infoPosto[, c(2, 3, 16, 15)]
    # infoPosto[, 3] <- as.numeric(infoPosto[, 3])
    # infoPosto[, 4] <- as.numeric(infoPosto[, 4])
    
    infoPosto <- infoPosto[!is.na(infoPosto[, 4]), ]
    
    names(infoPosto) <- c("Codigo", "Nome", "Municipio", "Longitude", "Latitude", "UF")
    return(infoPosto)
  })
    

  postosID <- reactive({
    postosID  <- make_infoposto()$Codigo 
    return(postosID)
  })
  

 
  lab_info_hist <- reactive({
    
    infoPosto <- make_infoposto()
    
    # Label dos postos para selecao do historico
    labsInfo <- lapply(seq(nrow(infoPosto)), function(i) {
      paste0('<b> Municipio: ', infoPosto[i, "Municipio"], '</b></br>',
             '<b> Estação: ', infoPosto[i, "Codigo"], '</b></br>')
    })
    
    return(labsInfo)
  })

    
  # })
  

    
  button_data <- eventReactive(input$update_interpol, {
    as.character(input$dateRange)
  })
  
  # Determina intervalos de acumulados baseado no periodo de acumulados
  intervalsBreaks <- reactive({
    
    dates <- button_data()
    
    timeStep <- as.numeric(difftime(dates[2], dates[1], units = "days"))

    if(timeStep <= 14){
      breaks.intervals <- breaks.intervals
    }
    if(timeStep > 14 & timeStep < 45){
      breaks.intervals <- breaks.intervals * 2
    }
    if(timeStep >= 45){
      breaks.intervals <- breaks.intervals * 3
    }
    if(timeStep >= 150){
      breaks.intervals <- breaks.intervals * 4
    }
    
    return(breaks.intervals)
    
  })
  
  # Constroi a paleta dinamicamente a cada requisicao
  paletteDin <- reactive({
    
    # Constroi paleta
    pal      <- colorBin(palette, bins = intervalsBreaks(), na.color = "transparent")
    return(pal)
  })
  
  ############################################################################
  # Selecao dos dados usados de acordo com a data do inputRange. Se mais de 1 data
  # eh gerado acumulado. 
  # Nova versao usando postgres 
  
  # Dados por periodo
  dadosUsed <- reactive({

    # Declaracoes de vetores
    precPCD     <- vector()
    latPCD      <- vector()
    lonPCD      <- vector()
    idPCD       <- vector()
    munPCD      <- vector()
    nomPCD      <- vector()
    
    infoPosto <- make_infoposto()
    dates     <- button_data()
    
    # Monta query para select no postgres
    query_dados_postgres <- paste0("SELECT codestacao, datadia, valor, n_dados",
                                   " from estat_diaria", 
                                  " where",  
                                  " datadia >= '", dates[1], "' and",
                                  " datadia <= '", dates[2], "'")
    
    # Roda a query de select
    select_query <- try(dbSendQuery(conn = con, statement = query_dados_postgres))
    dataUsed     <- dbFetch(select_query)
    

    postosUsed <- unique(dataUsed$codestacao)
    
    for(i in 1:length(postosUsed)){
      
      idPCD[i] <- postosUsed[i]
      
      latAux <- infoPosto$Latitude[infoPosto$Codigo == idPCD[i]]
      
      if(length(latAux) > 0){
        munPCD[i] <- infoPosto$Municipio[infoPosto$Codigo == idPCD[i]]
        latPCD[i] <- infoPosto$Latitude[infoPosto$Codigo == idPCD[i]]
        lonPCD[i] <- infoPosto$Longitude[infoPosto$Codigo == idPCD[i]]
        nomPCD[i] <- infoPosto$Nome[infoPosto$Codigo == idPCD[i]]
        
        precPCD[i] <- sum(dataUsed$valor[dataUsed$codestacao == idPCD[i]], na.rm = TRUE)
      } else{
        munPCD[i]  <- NA
        latPCD[i]  <- NA
        lonPCD[i]  <- NA
        precPCD[i] <- NA
        nomPCD[i]  <- NA
        
      }
    }
    
    lonPCD <- as.numeric(lonPCD)
    latPCD <- as.numeric(latPCD)
    
    dadosPCD <- data.frame(munPCD, idPCD, lonPCD, latPCD, precPCD)
    dadosPCD <- dadosPCD[!is.na(dadosPCD[, 5]) , ]
    names(dadosPCD) <- c("Municipio", "Codigo", "Longitude", "Latitude", "Acumulado [mm]")

    return(dadosPCD)
    
  })
  
  # Monta as labels das PCDs para leaflet
  labsPCD <- reactive({
    
    dadosLab <- dadosUsed()
    dadosLab <- dadosLab[!is.na(dadosLab[, 5]), ]
    
    labsMeteo <- lapply(seq(nrow(dadosLab)), function(i) {
      paste0('<b> Municipio: ', dadosLab[i, "Municipio"], '</b></br>', 
             '<b> Estação: ', dadosLab[i, "Codigo"], '</b></br>',
              '<b> Acumulado: </b>', dadosLab[i, "Acumulado [mm]"], " mm")
    })
    return(labsMeteo)
  })
  
  
  
  # Produz o campo interpolado para o periodo selecionado
  interpolPCD <- reactive({
    
    cat("Interpolando - INICIO \n")
    
    dadosKrig <- dadosUsed()
    estadoUse <- estado_utilizado()
    grid      <- grid_krig()
    
    cat("Interpolando  2 \n")
    
    cnd   <- dadosKrig[, c(3, 4)]
    media <- dadosKrig[, 5]
    
    krig         <- Krig(cnd, media, lambda = input$lambda)      

    # if(input$checkSmooth == "Manual"){
    #   krig         <- Krig(cnd, media, lambda = input$lambda)      
    # }
    # 
    # if(input$checkSmooth == "Automático"){
    #   krig         <- Krig(cnd, media)      
    # }

    interpolated <- predict(krig, grid) 
    result       <- raster(as.surface(grid, interpolated))
    result[result < 0] <- 0
    
    result <- raster::mask(result, estadoUse)

    return(result)
    
  })
  

  # Aplica consistencia spacial usando krigagem
  consistenciaPCD <- reactive({
  
    cat("Iniciando Consistencia \n")
      
    latKrig   <- vector()
    lonKrig   <- vector()
    valorKrig <- vector()
    prevKrig  <- vector()
    dataAccep <- vector()

    dadosKrig <- dadosUsed()
    cnd   <- dadosKrig[, c(3, 4)]
    media <- dadosKrig[, 5]
    
    grid      <- grid_krig()
    estadoUse <- estado_utilizado()
    
    # Faz krigagem com smoot elevado para predicao do acumulado nas vizinhancas
    krig <- Krig(cnd, media, theta = 15)      
    
    interpolated <- predict(krig, grid) 
    result       <- raster(as.surface(grid, interpolated))
    result[result < 0] <- 0
    
    # Loop nos pontos para checagem do previsto na krigagem e medido pela estacao
    for(j in 1:length(dadosKrig[, 1])){
      cellKrig <- cellFromXY(result, c(dadosKrig[j, 3], dadosKrig[j, 4]))
      
      if(length(cellKrig) != 0 & !is.na(cellKrig)){
        prevKrig[j] <- result[cellKrig]
        
        if(!is.na(prevKrig[j]) & !is.na(dadosKrig[j, 4])){
          if(dadosKrig[j, 5] < (input$percBotton * prevKrig[j]) & prevKrig[j] > 15){
            dataAccep[j] <- 0
          } else {
            dataAccep[j] <- 1
          }
          
          # Aplica consistencia para valores altos tambem
          # if(dadosKrig[j, 5] > (percUp * prevKrig[j]) & dadosKrig[j, 4] > 100){
          #   dataAccep[j] <- 0
          # } else {
          #   if(is.na(dataAccep[j])){
          #     dataAccep[j] <- 1  
          #   }
          # }
        } else{
          dataAccep[j] <- NA
        }
        
      } else{
        dataAccep[j] <- NA
      }
    } # postos
    
    ############################### Fazendo a interpolacao com dados corrigidos
    dadosKrigCorr <- cbind(dadosKrig, dataAccep, prevKrig)
    names(dadosKrigCorr) <- c("Municipio", "Codigo", "Longitude", "Latitude", "Acumulado [mm]", "dataAccep", "Calculado [mm]")
    
    # PCDs descartadas/cairam no filtro
    unusedPCDS    <- dadosKrigCorr[dadosKrigCorr$dataAccep == 0, ]
    
    # Dados para interpolacao corrigida
    dadosKrigCorr <- dadosKrigCorr[dadosKrigCorr$dataAccep == 1, ]
    
    cndCor   <- dadosKrigCorr[, c(3, 4)]
    mediaCor <- dadosKrigCorr[, 5]
    
    # Faz krigagem com smoot elevado para predicao do acumulado nas vizinhancas
    krigCor <- Krig(cndCor, mediaCor, lambda = input$lambda)      
    
    interpolatedCor <- predict(krigCor, grid) 
    resultCor       <- raster(as.surface(grid, interpolatedCor))
    resultCor[resultCor < 0] <- 0
    
    resultCor <- raster::mask(resultCor, estadoUse)
    
    return(list(resultCor, unusedPCDS))
    
  })
  
  
  # Inserindo botão para download do raster produzido
  output$downloadData <- downloadHandler(
    filename = function() {
      dates     <- button_data()
      dti_name <- gsub("-", "", dates[1])
      dtf_name <- gsub("-", "", dates[2])
      paste("krig_pcd_cemaden_uncorr_", dti_name, "-", dtf_name, "_", input$state_select, ".tif", sep = "")
#      paste("krig_pcd_cemaden_uncorr.tif", sep = "")
      
    },
    content = function(file) {
      raster::writeRaster(interpolPCD(),
                          file      = file,
                          format    = "GTiff", 
                          overwrite = TRUE)
      
      #write.csv(datasetInput(), file, row.names = FALSE)
    }
  )
  
  # Inserindo botão para download do raster produzido do consistido
  output$downloadDataCons <- downloadHandler(
    filename = function() {
      dates     <- button_data()
      dti_name <- gsub("-", "", dates[1])
      dtf_name <- gsub("-", "", dates[2])
      paste("krig_pcd_cemaden_corr_", dti_name, "-", dtf_name, "_", input$state_select, ".tif", sep = "")
    },
    content = function(file) {
      raster::writeRaster(consistenciaPCD()[[1]],
                          file      = file,
                          format    = "GTiff", 
                          overwrite = TRUE)
      
      #write.csv(datasetInput(), file, row.names = FALSE)
    }
  )
  
  
  # Monta as labels das PCDs para leaflet
  labsErrPCD <- reactive({
    
    dadosLab <- consistenciaPCD()[[2]]
    dadosLab <- dadosLab[!is.na(dadosLab[, 5]), ]
    dadosLab[, 7] <- as.numeric(formatC(dadosLab[, 7], digits = 1, format = "f"))
    
    labsMeteo <- lapply(seq(nrow(dadosLab)), function(i) {
      paste0('<b> Municipio: ', dadosLab[i, "Municipio"], '</b></br>', 
             '<b> Estação: ', dadosLab[i, "Codigo"], '</b></br>',
             '<b> Acumulado: </b>', dadosLab[i, "Acumulado [mm]"], " mm", '</br>', 
             '<b> Calculado: </b>', dadosLab[i, "Calculado [mm]"], " mm")
    })
    return(labsMeteo)
  })
  
  
  
  # output$downloadRaster <- downloadHandler(
  #   filename = function() {
  #     paste("Krig_Cemaden_", input$dateRange[1], "_", input$dateRange[2], ".tif", sep = "")
  #   },
  #   content = function(file) {
  #     # Salva o raster reativo no arquivo temporário
  #     writeRaster(interpolPCD, file, format="GTiff")
  #   }
  # )
  
  
  # Calcula precipitação media/maxima sobre o poligono de cada municipio
  acumMun <- reactive({
    
    
    munCema      <- mun_monitorados()
    precInterpol <- interpolPCD()
    
    munIBGE     <- munCema$cdibge
    
    for(i in 1:length(munIBGE)){
    
        
      munUsed <- munCema[munCema$cdibge == munIBGE[i], ]
      precMun <- mask(crop(precInterpol, munUsed), munUsed)
      
      nameMun[i] <- munCema$cidade[munCema$cdibge == munIBGE[i]]
      
      precMedMun[i] <- mean(values(precMun), na.rm = TRUE)
      precMaxMun[i] <- max(values(precMun), na.rm = TRUE)
      
    }
    
    
    
    precMunCema <- data.frame("Municipio" = nameMun, 
                              "Acumulado Médio" = precMedMun, 
                              "Célula Máxima" = precMaxMun)
    
    
    return(precMunCema)
    
  })
  
  
  # Dados Historicos por posto/instrum 
  dadosHist <- reactive({
    
    #posto <- input$mapaEstacoes_marker_click$id
    
    if(is.null(input$mapaEstacoes_marker_click$id)){
      # Estação Default será do Porto Alegue no Guaiba
      posto <- "431490201A"
    } else{
      posto <- input$mapaEstacoes_marker_click$id  
    }
  
    
    # Select em uma unica estacao, todo historico
    select_hist <- paste0("SELECT datadia, valor from estat_diaria where ", 
                         "codestacao = '", posto, "' order by datadia")
    
    # Roda a query de select
    select_hist <- try(dbSendQuery(conn = con, statement = select_hist))
    
    dadosExt <- dbFetch(select_hist)
    dadosExt <- dadosExt[!is.na(dadosExt), ]

    names(dadosExt) <- c("Data", "Acumulado")      
    return(dadosExt)
  })
  
  ## Monta a distribuição de probabilidade dos extremos
  ## Utiliza os quantils de 1% para extremo minimo e 99% de extremo máximo
  extremeValue <- reactive({
    
    dataExtreme <- dadosHist()
    dataExtreme <- dataExtreme[dataExtreme[, 2] > 0.5, ]
    
    dlq <- distLquantile(dataExtreme[, 2], weighted=FALSE, quiet=TRUE, probs = c(0.95, 0.99),
                         list=TRUE, selection = c("gev"))
    
    extrV <- c(dlq$quant[1,1], dlq$quant[1,2])
    
    outDLQ <- list(extrV, dlq)
    
  })
  
  
  ############################################################################
  # Montagem do mapa leaflet com a interpolação dos postos para exibicao 
  
  output$mapaSimples <- renderLeaflet(
    leaflet() %>%
      fitBounds(bounds()[1], bounds()[3], bounds()[2], bounds()[4]) %>%
      #fitBounds(bounds[1,1], bounds[2,1], bounds[1, 2], bounds[2, 2]) %>%
      
      # Tiles (backgrounds)
      #addProviderTiles(providers$CartoDB.Positron, group = "PB") %>%
      addProviderTiles("OpenStreetMap.Mapnik", group = "OpenStreetMap")  %>%
      
      addRasterImage(interpolPCD(), colors = paletteDin(), opacity = 0.7, group = group_interpol, layerId = "S") %>%
      
      addPolylines(data = mun_monitorados(), weight = 1.5, color = "black", group = "Mun. Monitorados") %>%
      
      addPolylines(data = estado_utilizado(), weight = 1.5, color = "black", group = "Limites") %>%
      
      #addPolylines(data = hidro, weight = 2.0, color = "cornflowerblue", group = "Hidrografia") %>%
      # addPolylines(data = hidro, weight = 2.0, color = "cornflowerblue", group = "Hidrografia") %>%
      
      #addMarkers(data = pos, group = "Postos", popup = desc, label = ~nome) %>%
      addCircleMarkers(lat = dadosUsed()$Latitude, lng = dadosUsed()$Longitude ,radius = 1, fillColor = "black", 
                       stroke = TRUE, color = "black", fillOpacity = 1., group = group_telem, label = lapply(labsPCD(), htmltools::HTML), 
                       layerId = dadosUsed()$Codigo) %>%
      
      leaflet::addLegend(pal = paletteDin(), values = intervalsBreaks(), title = "[mm]", opacity = 1, group = group_interpol) %>%
      
      
    # Controle de layers - Radares e fundos
    addLayersControl(
      baseGroups = c("OpenStreetMaps"),
       overlayGroups = c("Mun. Monitorados", group_telem, group_interpol, "Limites"),
      options = layersControlOptions(collapsed = FALSE, position = c("bottomright"))
    ) %>%
    
    # addLogo(
    #   img = logoCema,
    #   position = "bottomleft", 
    #   height = 130,
    #   width = 150, 
    #   alpha = 1) %>%
    
    addScaleBar(position = c("bottomleft"), options = scaleBarOptions(metric = TRUE)) %>%
    
    # Botão para medir distancias/Areas
    addMeasure(
      position = "topleft",
      primaryLengthUnit = "kilometers",
      primaryAreaUnit = "sqmeters",
      activeColor = "#3D535D",
      completedColor = "#7D4479")

    #hideGroup(c(group_telem)) 
    
  )
  
  
  output$mapaCons <- renderLeaflet(
    leaflet() %>%
      fitBounds(bounds()[1], bounds()[3], bounds()[2], bounds()[4]) %>%
      #fitBounds(bounds[1,1], bounds[2,1], bounds[1, 2], bounds[2, 2]) %>%
      
      # Tiles (backgrounds)
      #addProviderTiles(providers$CartoDB.Positron, group = "PB") %>%
      addProviderTiles("OpenStreetMap.Mapnik", group = "OpenStreetMap")  %>%
      
      addRasterImage(consistenciaPCD()[[1]], colors = paletteDin(), opacity = 0.7, group = group_interpol, layerId = "S") %>%
      
      addPolylines(data = mun_monitorados(), weight = 1.5, color = "black", group = "Mun. Monitorados") %>%
      
      addPolylines(data = estado_utilizado(), weight = 1.5, color = "black", group = "Limites") %>%
      
      #addPolylines(data = hidro, weight = 2.0, color = "cornflowerblue", group = "Hidrografia") %>%
      # addPolylines(data = hidro, weight = 2.0, color = "cornflowerblue", group = "Hidrografia") %>%
      
      #addMarkers(data = pos, group = "Postos", popup = desc, label = ~nome) %>%
      addCircleMarkers(lat = dadosUsed()$Latitude, lng = dadosUsed()$Longitude ,radius = 1, fillColor = "black", 
                       stroke = TRUE, color = "black", fillOpacity = 1., group = group_telem, label = lapply(labsPCD(), htmltools::HTML), 
                       layerId = dadosUsed()$Codigo) %>%
      
      addCircleMarkers(lat = consistenciaPCD()[[2]]$Latitude, lng = consistenciaPCD()[[2]]$Longitude ,radius = 3, fillColor = "red", 
                       stroke = TRUE, color = "red", fillOpacity = 1., group = group_telem_cor, label = lapply(labsErrPCD(), htmltools::HTML), 
                       layerId = consistenciaPCD()[[2]]$Codigo) %>%
      
      
      leaflet::addLegend(pal = paletteDin(), values = intervalsBreaks(), title = "[mm]", opacity = 1, group = group_interpol) %>%
      
      
      # Controle de layers - Radares e fundos
      addLayersControl(
        baseGroups = c("OpenStreetMaps"),
        overlayGroups = c("Mun. Monitorados", group_telem, group_telem_cor, group_interpol, "Limites"),
        options = layersControlOptions(collapsed = FALSE, position = c("bottomright"))
      ) %>%
      
      # addLogo(
      #   img = logoCema,
      #   position = "bottomleft", 
      #   height = 130,
      #   width = 150, 
      #   alpha = 1) %>%
      
      addScaleBar(position = c("bottomleft"), options = scaleBarOptions(metric = TRUE)) %>%
      
      # Botão para medir distancias/Areas
      addMeasure(
        position = "topleft",
        primaryLengthUnit = "kilometers",
        primaryAreaUnit = "sqmeters",
        activeColor = "#3D535D",
        completedColor = "#7D4479")
      
      
      #hideGroup(c(group_telem)) 
    
  )
  
  
  # observeEvent(input$update, {
  #   leafletProxy("mapaSimples", session) %>%
  #     addRasterImage(interpolPCD(), colors = pal, opacity = 0.7, group = group_interpol, layerId = "S")
  # 
  # })
  
  
  
  ############################################################################
  # Montagem do mapa leaflet com os postos para selecao do posto para extremos
  
  output$mapaEstacoes <- renderLeaflet(
    leaflet() %>%
      fitBounds(bounds()[1], bounds()[3], bounds()[2], bounds()[4]) %>%
      #fitBounds(bounds[1,1], bounds[2,1], bounds[1, 2], bounds[2, 2]) %>%
      
      # Tiles (backgrounds)
      #addProviderTiles(providers$CartoDB.Positron, group = "PB") %>%
      addProviderTiles("OpenStreetMap.Mapnik", group = "OpenStreetMap")  %>%

      addPolylines(data = estado_utilizado(), weight = 1.5, color = "black", group = "Estado") %>%
      
      #addMarkers(data = pos, group = "Postos", popup = desc, label = ~nome) %>%
      # addCircleMarkers(lat = dadosUsed()$Latitude, lng = dadosUsed()$Longitude, radius = 2, fillColor = "black", 
      #                  stroke = TRUE, color = "black", fillOpacity = 1., group = group_telem, label = lapply(labsPCD(), htmltools::HTML), 
      #                  layerId = dadosUsed()$Codigo) %>%
      
      # addLogo(
      #   img = logoCema,
      #   position = "bottomleft", 
      #   height = 130,
      #   width = 150, 
      #   alpha = 1) %>%
      
      addScaleBar(position = c("bottomleft"), options = scaleBarOptions(metric = TRUE)) %>%
      
      # Botão para medir distancias/Areas
      addMeasure(
        position = "topleft",
        primaryLengthUnit = "kilometers",
        primaryAreaUnit = "sqmeters",
        activeColor = "#3D535D",
        completedColor = "#7D4479") %>%
      
      
      addMarkers(lat = make_infoposto()$Latitude, lng = make_infoposto()$Longitude, group = "Postos", icon = leafIcon, label = lapply(lab_info_hist(), htmltools::HTML),  
                 labelOptions = labelOptions(noHide = FALSE, direction = "bottom"), layerId = postosID())
  )
  
  observeEvent(input$mapaEstacoes_marker_click, {
    click <- input$mapaEstacoes_marker_click
    
    #text<-paste("Lattitude ", click$lat, "Longtitude ", click$lng, "TESTE")
    
    if(is.null(click)){
      return()
    }
    
    # nomeSelected <- as.character(estacoes$nome[estacoes$posto == click$id])
    # text2 <- paste("Posto Selecionado: ", nomeSelected)
    
    # proxy <- leafletProxy("mapaEstacoes")
    # proxy %>% clearPopups() %>%
    #   addPopups(click$lng, click$lat, text2)
  })
  
  
  
 
  ############################################################################
  # Delimitação de bacias no clique esquerdo dos mapas.
  # A função R consulta a API Global Watersheds e reutiliza GeoJSONs em cache local.
  desenhar_bacia <- function(map_id, click) {
    if (is.null(click) || is.null(click$lat) || is.null(click$lng) ||
        !is.finite(as.numeric(click$lat)) || !is.finite(as.numeric(click$lng))) {
      return(invisible(NULL))
    }

    lat <- as.numeric(click$lat)
    lng <- as.numeric(click$lng)
    progress_id <- paste0("watershed-progress-", map_id)

    showNotification(
      "Consultando a delimitação da bacia e dos rios. Se este ponto já tiver sido consultado, os dados serão lidos do cache local.",
      id = progress_id, duration = NULL, type = "message"
    )
    on.exit(removeNotification(progress_id), add = TRUE)

    resultado <- tryCatch(
      withProgress(message = "Delimitando bacia hidrográfica...", value = 0, {
        incProgress(0.1, detail = "Preparando dados")
        ans <- delinear_bacia(lat = lat, lng = lng)
        incProgress(0.9, detail = "Preparando camadas do mapa")
        ans
      }),
      error = function(e) e
    )

    if (inherits(resultado, "error")) {
      showNotification(
        paste0(
          "Não foi possível delimitar a bacia. ",
          conditionMessage(resultado),
          " Verifique a conexão com a API Global Watersheds e tente novamente."
        ),
        type = "error", duration = 12
      )
      return(invisible(NULL))
    }

    proxy <- leafletProxy(map_id, session = session) %>%
      clearGroup("Bacia hidrográfica") %>%
      clearGroup("Rios a montante")

    if (!is.null(resultado$bacia) && nrow(resultado$bacia) > 0) {
      proxy <- proxy %>%
        addPolygons(
          data = resultado$bacia,
          group = "Bacia hidrográfica",
          color = "#d73027",
          weight = 2.5,
          opacity = 0.95,
          fill = FALSE,
          options = pathOptions(clickable = FALSE)
        )
    }

    if (!is.null(resultado$rios) && nrow(resultado$rios) > 0) {
      proxy <- proxy %>%
        addPolylines(
          data = resultado$rios,
          group = "Rios a montante",
          color = "#1677c8",
          weight = 1.2,
          opacity = 0.9,
          options = pathOptions(clickable = FALSE)
        )
    }

    # Ajusta o enquadramento para mostrar toda a bacia delimitada.
    if (!is.null(resultado$bacia) && nrow(resultado$bacia) > 0) {
      bb <- sf::st_bbox(resultado$bacia)
      proxy <- proxy %>%
        fitBounds(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]])
    }

    if (!is.null(resultado$aviso) && nzchar(resultado$aviso)) {
      showNotification(
        paste0(
          "A bacia foi delimitada e desenhada, mas a rede de rios não ficou disponível. ",
          resultado$aviso
        ),
        type = "warning", duration = 12
      )
    } else {
      showNotification(
        "Bacia e rede de rios adicionadas ao mapa (API Global Watersheds).",
        type = "message", duration = 5
      )
    }
    invisible(NULL)
  }

  observeEvent(input$mapaSimples_click, {
    desenhar_bacia("mapaSimples", input$mapaSimples_click)
  }, ignoreInit = TRUE)

  observeEvent(input$mapaCons_click, {
    desenhar_bacia("mapaCons", input$mapaCons_click)
  }, ignoreInit = TRUE)


  ############################################################################
  # Montagem das tabelas - DT
  
  # Acumulados por PCD
  output$meteoDiario <- renderDataTable({
    
    dates <- button_data()
    
    dadosEvento <- dadosUsed()
    datatable(dadosEvento[, c(1, 2, 5)],
              caption = htmltools::tags$caption(style = 'caption-side: top; text-align: center; color: black; font-size: 130%;', 
                                                htmltools::em(paste("Acumulado: ", dates[1], "-", dates[2]))),
              
              #caption = paste("Data: ", input$date), 
              extensions = list('Buttons'= NULL), 
              options = list(
                order = list(list(3, 'desc')), 
                dom = "Bftip",
                buttons = c('excel', 'csv'),
                rownames = FALSE,
                pageLength = 15,
                columnDefs = list(list(className = 'dt-center', targets = c(2,3))))) %>% 
      formatRound("Acumulado [mm]", 1) %>%
      formatStyle(columns = c("Municipio"), fontWeight = 'bold', `text-align` = 'left') %>%
      formatStyle(columns = c("Codigo"), fontWeight = 'bold', `text-align` = 'left')
    #formatStyle(columns = c(1, 2, 3), fontSize = '120%')
  })    
  

  # Acumulados por Municipios
  output$AcumMunCema <- renderDataTable({
    
    dadosEvento <- acumMun()
    names(dadosEvento) <- c("Município", "Acumulado Médio [mm]", "Célula Máxima [mm]")
    
    dates <- button_data()
    
    datatable(dadosEvento,
              caption = htmltools::tags$caption(style = 'caption-side: top; text-align: center; color: black; font-size: 130%;', 
                                                htmltools::em(paste("Acumulado: ", dates[1], "-", dates[2]))),
              
              #caption = paste("Data: ", input$date), 
              extensions = list('Buttons'= NULL), 
              options = list(
                order = list(list(3, 'desc')), 
                dom = "Bftip",
                buttons = c('excel', 'csv'),
                rownames = FALSE,
                pageLength = 15,
                columnDefs = list(list(className = 'dt-center', targets = c(2,3))))) %>% 
      formatRound("Acumulado Médio [mm]", 1) %>%
      formatRound("Célula Máxima [mm]", 1) %>%
      formatStyle(columns = c("Município"), fontWeight = 'bold', `text-align` = 'left')
    #formatStyle(columns = c(1, 2, 3), fontSize = '120%')
  })    
  
    
  # Tabela dos historicos de maximos/minimos diarios de cada posto ordenados
  output$HistPosto <- renderDataTable({
    
    infoPosto <- make_infoposto()
    
    dadosHistoricos <- dadosHist()
    names(dadosHistoricos) <- c("Data", "Acumulado Diário [mm]")
    dadosHistoricos <- dadosHistoricos[!is.na(dadosHistoricos[, 2]), ]
    
    minDatePCD <- min(dadosHistoricos$Data, na.rm = TRUE)
    maxDatePCD <- max(dadosHistoricos$Data, na.rm = TRUE)
    
    nomePCD <- infoPosto$Municipio[infoPosto$Codigo == input$mapaEstacoes_marker_click$id]
    
    if(length(nomePCD) > 0){
      titleTabHist <- paste(nomePCD, "-", input$mapaEstacoes_marker_click$id, 
                            " | ", minDatePCD, "-", maxDatePCD)
    } else{
      titleTabHist <- paste("Porto Alegre - 431490201A", 
                            " | ", minDatePCD, "-", maxDatePCD)
    }
    
    datatable(dadosHistoricos,

              caption = htmltools::tags$caption(style = 'caption-side: top; text-align: center; color: black; font-size: 130%;',
                                                htmltools::em(titleTabHist)),


              #caption = paste("Data: ", input$date),
              extensions = list('Buttons'= NULL),
              options = list(
                order = list(list(2, 'desc')),
                dom = "Bftp",
                buttons = c('excel', 'csv'),
                rownames = FALSE,
                pageLength = 15,
                columnDefs = list(list(className = 'dt-center', targets = c(1,2))))) %>%
      formatRound("Acumulado Diário [mm]", 1) %>%
      formatStyle(columns = c("Data"), fontWeight = 'bold', `text-align` = 'left')
    #formatStyle(columns = c(1, 2, 3), fontSize = '120%')
  }, server = FALSE)
  
  
  ######## # Tabela das PCDs suspeitas para o periodo
  output$PCDsuspeitas <- renderDataTable({
    
    PCDserr <- consistenciaPCD()[[2]]
    PCDserr <- PCDserr[, c(2, 1, 5, 7)]
    
    names(PCDserr) <- c("Código", "Município", "Acumulado [mm]", "Calculado [mm]")
    
    dates <- button_data()
    
    datatable(PCDserr,
              caption = htmltools::tags$caption(style = 'caption-side: top; text-align: center; color: black; font-size: 130%;', 
                                                htmltools::em(paste("Período Acumulado: ", dates[1], "-", dates[2]))),
              
              #caption = paste("Data: ", input$date), 
              extensions = list('Buttons'= NULL), 
              options = list(
                order = list(list(3, 'desc')), 
                dom = "Bftip",
                buttons = c('excel', 'csv'),
                rownames = FALSE,
                pageLength = 15,
                columnDefs = list(list(className = 'dt-center', targets = c(1,3, 4))))) %>% 
      formatRound("Acumulado [mm]", 1) %>%
      formatRound("Calculado [mm]", 1) %>%
      formatStyle(columns = c("Código"), fontWeight = 'bold', `text-align` = 'left')
    #formatStyle(columns = c(1, 2, 3), fontSize = '120%')
  }, server = FALSE)    
  
  
  
  # ############################################################################
  # # Montagem do gráfico das estacoes
  # output$grafStat <- renderPlotly({
  #   
  #   dadosGraph <- dadosEstacao()
  #   dadosGraph[, 1] <- ymd(dadosGraph[, 1])
  #   
  #   plot_ly(dadosGraph,
  #           x = ~dadosGraph[, 1],
  #           y = ~as.numeric(dadosGraph[, 3]),
  #           type = "scatter", mode = 'lines', name = "Temperatura Máxima [ºC]",
  #           line = list(width = 2.5, color = 'rgb(205, 12, 24)')) %>%
  #     
  #     add_trace(x = ~dadosGraph[, 1],
  #               y = ~as.numeric(dadosGraph[, 4]),
  #               name = 'Temperatura Mínima [ºC]', mode = 'lines',
  #               line = list(width = 2.5, color = 'rgb(22, 96, 167)')) %>%
  #     add_trace(x = ~dadosGraph[, 1],
  #               y = ~as.numeric(dadosGraph[, 5]),
  #               name = 'Umidade Relativa Mínima[%]', mode = 'lines', yaxis = "y2", 
  #               line = list(width = 2.5, color = 'rgb(64, 212, 19)')) %>%
  #     layout(title = paste("Posto: ", input$posto),
  #            yaxis = list(title = "Temperatura", range = c(-5, 45), tick0 = 0, dtick = 5),
  #            xaxis = list(title = "Data"),
  #            yaxis2 = list(title = "Umidade Relativa [%]", overlaying = "y", side = "right", range = c(10, 110), tick0 = 0, dtick = 10))
  #   
  # })
  
  
  ##### Montagem do grafico de distribuição de probabilidade com os valores extremos
  output$grafExtreme <- renderPlot({


    extremos  <- extremeValue()[[1]]
    dataGraph <- extremeValue()[[2]]
    #dataGraph <- dataGraph[dataGraph[, 2] > 0, ]

    mainTitle <- paste("Acumulados Diarios de Precipitação[mm] ", sep = "")
    yLim      <- c(0, 0.09)
    xlabText  <- "Precipitação Diária [mm]"
    breaksX   <- 30
 
    par(mar=c(4.2, 4.2, 3.1, 1.1))
    plotLquantile(dataGraph, xlab = list(xlabText, cex = 1.3), ylab = list("Densidade de Probabilidade", cex = 1.3), main = list(input$mapaEstacoes_marker_click$id, cex = 1.3),
                  breaks = breaksX, lwd = 2, ylim = yLim, legargs=list(x="right", y="top", cex = 1.3, bg = "grey90", lwd = 2))

    abline(v = extremos, col = "blue", lwd = 2, lty = 2)
    grid(lwd = 0.5)
    graphics::box(lwd = 1.5)
  })
  
  # ########Grafico das Medias Climatologicas
  # output$grafMedia <- renderPlotly({
  #   
  #   dadosGraph <- dadosMedias()
  #   
  #   instrumUsed <- instrums$nInstrum[instrums$instrumName == input$exInstrum]
  #   
  #   if(instrumUsed == 51){
  #     instrumUsed <- 5
  #   }
  #   
  #   if(instrumUsed == 0){
  #     yRange      <- c(0, 300)
  #     yLab  <- "Precipitação [mm]"
  #     step  <- 50
  #   }
  #   
  #   if(instrumUsed == 5){
  #     yRange      <- c(5, 40)
  #     yLab  <- "Temperatura Máxima [ºC]"
  #     step  <- 5
  #   } 
  #   
  #   if(instrumUsed == 51){
  #     yRange      <- c(0, 25)
  #     yLab  <- "Temperatura Mínima [ºC]"
  #     step  <- 5
  #   } 
  #   
  #   if(instrumUsed == 6){
  #     yRange      <- c(30, 70)
  #     yLab  <- "Umidade Relativa Mínima [%]"
  #     step  <- 10
  #   }
  #   
  #   
  #   plot_ly(dadosGraph,
  #           x = ~dadosGraph[, 1],
  #           y = ~as.numeric(dadosGraph[, 2]),
  #           type = "bar", name = ,
  #           marker = list(color = 'rgb(158,202,225)',
  #                         line = list(color = 'rgb(8,48,107)',
  #                                     width = 1.5))) %>%
  #     layout(title = paste("Médias Mensais", postoSelect()),
  #            yaxis = list(title = yLab, range = yRange, tick0 = 0, dtick = step),
  #            xaxis = list(title = "Mês"))
  #   
  # })
  
  
  
  
  ############################################################################
  # Tabelas
  
  # renderiza a tabela com os valores dos 2 quantils (1 e 99%)
  output$Quantiles <- renderDataTable({

    extremos <- as.data.frame(extremeValue()[[1]])
    row.names(extremos) <- c("Prob. 95%", "Prob. 99%")
    names(extremos)     <- "Valores Extremos"

    datatable(extremos,

              # caption = htmltools::tags$caption(style = 'caption-side: top; text-align: center; color: black; font-size: 130%;',
              #                                   htmltools::em(paste(postoSelect(), " - ", input$exInstrum))),


              extensions = list('Buttons'= NULL),
              options = list(
                #drawCallback = JS(salimCap),
                dom = "t",
                rownames = TRUE,
                pageLength = length(extremos[, 1]),
                columnDefs = list(list(className = 'dt-center', targets = c(1))))) %>%
      formatRound("Valores Extremos", 2)

  })
}

# Run the application 
shinyApp(ui = ui, server = server)
