# Aplicação de producao de campos interpolados de PCDs do Cemaden
# Tambem produz e exibe dados estatisticos e de extremos (Somente Pluviometros)

################################################################################
# Bibliotecas

#install.packages("spatial", dependencies = TRUE, repos='https://cran.rstudio.com/')

library(shiny)
library(shinydashboard)
library(leaflet)
library(leaflet.extras)
library(shinythemes)
library(DT)
library(fields)
library(sf)
library(raster)
library(extremeStat)

################################################################################
# Setor de carregamento de informacoes externas pre-geradas

# Carrega dados processados pelo avaliaPluRede
load("./data/Dados_2015-2025.rda")

# Carrega coords dos postos
load("./data/infoPosto.rda")

# Carrega Estado a processar
load("./data/estadoUse.rda")

# Carrega Estado a processar
load("./data/munCema.rda")


################################################################################
# Constantes e formatacoes iniciais

# Instrumentos (num-nome)
instrums <- data.frame(nInstrum = c(0), instrumName = c("Precipitação"))

# Formata datas dos dados de entrada (acumMatrix)
acumMatrix[, 1] <- as.Date(format(as.POSIXct(strptime(as.character((acumMatrix[, 1])), format="%Y%m%d%H%M"), tz = "GMT"), format = "%Y-%m-%d"))


###############################################################################
# IDs das PCDs
postosID <- infoPosto$Codigo

ui <- dashboardPage( 
  
  
  dashboardHeader(title = "PCDs - Cemaden (Prototipo - RS) ", titleWidth = 300),
  
  
  dashboardSidebar(
    sidebarMenu(id = "sidebarid",
                menuItem("Interpolação PCDs", tabName = "pData"),
                #menuItem("Gráfico por Estação", tabName = "pPosto"),
                menuItem("Históricos e Extremos", tabName = "pEstat"),
                
                conditionalPanel(
                  'input.sidebarid == "pData"',
                  
                  
                  
                  # dateInput('date',
                  #           label = 'Data de Entrada: AAAA-MM-DD',
                  #           value = (Sys.Date()), 
                  #           language = "pt-BR", 
                  #           min = as.Date("2006-11-01"), 
                  #           max = (Sys.Date()))
                  dateRangeInput(inputId = 'dateRange', 
                                 label = 'Intervalo: AAAA-MM-DD',
                                 start = as.Date("2025-11-30"), 
                                 end = as.Date("2025-12-01"), 
                                 language = "pt-BR", 
                                 min = as.Date("2015-01-01"), 
                                 max = as.Date("2025-12-01"))
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
                )
    )
  ),
  dashboardBody(
    
    tabItems(
      tabItem("pData",
              fluidRow( 
                column(width = 7,
                       box(width = NULL, solidHeader = TRUE,
                           leafletOutput("mapaSimples", height = 800)
                           #actionButton("update", "Gerar Interpolação")
                       )
                ),
                column(width = 5, 
                       box(width = NULL, solidHeader = TRUE, style = "overflow-x: scroll;", 
                           
                             tabsetPanel(type = "tabs",
                                         tabPanel("Por Municipio", 
                                                  dataTableOutput("AcumMunCema")), 
                                         tabPanel("Por PCD",  
                                                  dataTableOutput("meteoDiario"))
                                         )
                           ), 
                           
                        
                )
              ) # Row 
      ),  # TabItem diario
      
      # tabItem("pPosto",
      #         fluidRow( 
      #             titlePanel("Dados Históricos - Máximos e Mínimos Diários", windowTitle = 10),
      #             column(width = 12, 
      #                    plotlyOutput("grafStat"),
      #                    #dataTableOutput("dadosTeste"),
      #                    #verbatimTextOutput("dateRangeText")
      #             )
      #         ) # Row
      # ),  # TabItem porPosto
      
      tabItem("pEstat",
              fluidRow(
                titlePanel("Escolha a PCD", windowTitle = 2),
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
  
  # Monta grade de interpolação para krigagem 
  bounds <- extent(estadoUse)
  res <- 0.009803922 * 4 # 4 km em grau
  grid <- make.surface.grid(list(seq(bounds[1],bounds[2],by=res),seq(bounds[3],bounds[4],by=res)))
  
  
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
  group_interpol  <- paste("PCDs Krigagem")

  
  # Label dos postos para selecao do historico
  labsInfo <- lapply(seq(nrow(infoPosto)), function(i) {
    paste0('<b> Municipio: ', infoPosto[i, "Municipio"], '</b></br>', 
           '<b> Estação: ', infoPosto[i, "Codigo"], '</b></br>')
  })
  
  
  #############################################################################
  # Reactives
  
  # Determina intervalos de acumulados baseado no periodo de acumulados
  intervalsBreaks <- reactive({
    timeStep <- as.numeric(difftime(input$dateRange[2], input$dateRange[1], units = "days"))

    if(timeStep <= 3){
      breaks.intervals <- breaks.intervals
    }
    if(timeStep > 3 & timeStep < 60){
      breaks.intervals <- breaks.intervals * 2
    }
    if(timeStep >= 60){
      breaks.intervals <- breaks.intervals * 3
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
  
  # Dados por periodo
  dadosUsed <- reactive({
    
    dataUsed   <- acumMatrix[acumMatrix$datahora >= input$dateRange[1] & 
                               acumMatrix$datahora <= input$dateRange[2], ]
    
    postosUsed <- names(dataUsed[2:length(dataUsed[1, ])])
    
    for(i in 2:length(dataUsed[1, ])){
      
      idPCD[i] <- names(dataUsed)[i]
      
      latAux <- infoPosto$Latitude[infoPosto$Codigo == idPCD[i]]
      
      if(length(latAux) > 0){
        munPCD[i] <- infoPosto$Municipio[infoPosto$Codigo == idPCD[i]]
        latPCD[i] <- infoPosto$Latitude[infoPosto$Codigo == idPCD[i]]
        lonPCD[i] <- infoPosto$Longitude[infoPosto$Codigo == idPCD[i]]
        
        precPCD[i] <- sum(dataUsed[, i])
      }
    }
    
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
    
    dadosKrig <- dadosUsed()
    
    cnd   <- dadosKrig[, c(3, 4)]
    media <- dadosKrig[, 5]
    
    krig         <- Krig(cnd, media, lambda = 0.05)    
    interpolated <- predict(krig, grid) 
    result       <- raster(as.surface(grid, interpolated))
    result[result < 0] <- 0
    
    result <- raster::mask(result, estadoUse)

    return(result)
    
  })
  
  
  # Calcula precipitação media/maxima sobre o poligono de cada municipio
  acumMun <- reactive({
    
    precInterpol <- interpolPCD()
    
    munIBGE<- munCema$cdibge
    
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
  
    dadosExt <- data.frame(acumMatrix[, 1], acumMatrix[names(acumMatrix) == posto])
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
      fitBounds(bounds[1], bounds[3], bounds[2], bounds[4]) %>%
      #fitBounds(bounds[1,1], bounds[2,1], bounds[1, 2], bounds[2, 2]) %>%
      
      # Tiles (backgrounds)
      #addProviderTiles(providers$CartoDB.Positron, group = "PB") %>%
      addProviderTiles("OpenStreetMap.Mapnik", group = "OpenStreetMap")  %>%
      
      addRasterImage(interpolPCD(), colors = paletteDin(), opacity = 0.7, group = group_interpol, layerId = "S") %>%
      
      addPolylines(data = munCema, weight = 1.5, color = "black", group = "Mun. Monitorados") %>%
      
      addPolylines(data = estadoUse, weight = 1.5, color = "black", group = "Limites") %>%
      
      #addPolylines(data = hidro, weight = 2.0, color = "cornflowerblue", group = "Hidrografia") %>%
      # addPolylines(data = hidro, weight = 2.0, color = "cornflowerblue", group = "Hidrografia") %>%
      
      #addMarkers(data = pos, group = "Postos", popup = desc, label = ~nome) %>%
      addCircleMarkers(lat = dadosUsed()$Latitude, lng = dadosUsed()$Longitude ,radius = 2, fillColor = "black", 
                       stroke = TRUE, color = "black", fillOpacity = 1., group = group_telem, label = lapply(labsPCD(), htmltools::HTML), 
                       layerId = dadosUsed()$Codigo) %>%
      
      leaflet::addLegend(pal = paletteDin(), values = intervalsBreaks(), title = "[mm]", opacity = 1, group = group_interpol) %>%
      
      
    # Controle de layers - Radares e fundos
    addLayersControl(
      baseGroups = c("OpenStreetMaps"),
       overlayGroups = c("Mun. Monitorados", group_telem, group_interpol, "Limites"),
      options = layersControlOptions(collapsed = FALSE, position = c("bottomright"))
    ) %>%
    
    hideGroup(c(group_telem)) 
    
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
      fitBounds(bounds[1], bounds[3], bounds[2], bounds[4]) %>%
      #fitBounds(bounds[1,1], bounds[2,1], bounds[1, 2], bounds[2, 2]) %>%
      
      # Tiles (backgrounds)
      #addProviderTiles(providers$CartoDB.Positron, group = "PB") %>%
      addProviderTiles("OpenStreetMap.Mapnik", group = "OpenStreetMap")  %>%

      addPolylines(data = munCema, weight = 1.5, color = "black", group = "Mun. Monitorados") %>%
      
      #addMarkers(data = pos, group = "Postos", popup = desc, label = ~nome) %>%
      # addCircleMarkers(lat = dadosUsed()$Latitude, lng = dadosUsed()$Longitude, radius = 2, fillColor = "black", 
      #                  stroke = TRUE, color = "black", fillOpacity = 1., group = group_telem, label = lapply(labsPCD(), htmltools::HTML), 
      #                  layerId = dadosUsed()$Codigo) %>%
      
      addMarkers(data = infoPosto, group = "Postos", icon = leafIcon, label = lapply(labsInfo, htmltools::HTML),  
                 labelOptions = labelOptions(noHide = FALSE, direction = "bottom"), layerId = postosID)
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
  # Montagem das tabelas - DT
  
  # Acumulados por PCD
  output$meteoDiario <- renderDataTable({
    
    dadosEvento <- dadosUsed()
    datatable(dadosEvento[, c(1, 2, 5)],
              caption = htmltools::tags$caption(style = 'caption-side: top; text-align: center; color: black; font-size: 130%;', 
                                                htmltools::em(paste("Acumulado: ", input$dateRange[1], "-", input$dateRange[2]))),
              
              #caption = paste("Data: ", input$date), 
              extensions = list('Buttons'= NULL), 
              options = list(
                order = list(list(3, 'desc')), 
                dom = "ftip",
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
    
    datatable(dadosEvento,
              caption = htmltools::tags$caption(style = 'caption-side: top; text-align: center; color: black; font-size: 130%;', 
                                                htmltools::em(paste("Acumulado: ", input$dateRange[1], "-", input$dateRange[2]))),
              
              #caption = paste("Data: ", input$date), 
              extensions = list('Buttons'= NULL), 
              options = list(
                order = list(list(3, 'desc')), 
                dom = "ftip",
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
                dom = "tp",
                rownames = FALSE,
                pageLength = 17,
                columnDefs = list(list(className = 'dt-center', targets = c(1,2))))) %>%
      formatRound("Acumulado Diário [mm]", 1) %>%
      formatStyle(columns = c("Data"), fontWeight = 'bold', `text-align` = 'left')
    #formatStyle(columns = c(1, 2, 3), fontSize = '120%')
  })
  
  
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


              #caption = paste("Data: ", input$date),
              extensions = list('Buttons'= NULL),
              options = list(
                #drawCallback = JS(salimCap),
                dom = "t",
                rownames = TRUE,
                pageLength = length(extremos[, 1]),
                columnDefs = list(list(className = 'dt-center', targets = c(1))))) %>%
      formatRound("Valores Extremos", 2)

    #formatStyle(columns = c(1, 2, 3), fontSize = '120%')
  })
  # 
  # # Reactive para pegar o nome da seleção do mapa
  # postoSelect <- reactive({
  #   
  #   if(is.null(input$mapaEstacoes_marker_click$id)){
  #     nomeSelected <- as.character(estacoes$nome[estacoes$posto == 503])
  #   } else{
  #     nomeSelected <- as.character(estacoes$nome[estacoes$posto == input$mapaEstacoes_marker_click$id])  
  #   }
  #   
  #   
  #   return(nomeSelected)
  # })
  
  
  # # Testes de saida para debug dos inputs    
  # output$dateRangeText  <- renderText({
  #     paste("Posto:", input$posto,"Datas: ", input$dateRange[1], "-", input$dateRange[2], class(input$dateRange[2]),sep = " ")
  # })
  
  #output$oText <- renderText({paste("Posto:", input$mapaEstacoes_marker_click$id)})
  
}


# Run the application 
shinyApp(ui = ui, server = server)
