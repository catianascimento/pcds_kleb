################################################################################
# Funcao que utiliza API do Cemaden para baixar dados cadastrais das PCDs
# Manual de uso da API: https://sws.cemaden.gov.br/PED/api/ui/#/
#
#
# Author: Kleber Lopes da Rocha Filho - Tecnologista CGPD - JAN-2026
################################################################################

getLocationPCDCemaden <- function(uf = NULL, token){
  
  # uf      : Unidade federal (indicar Ex: SP) ou default para todo pais
  # token   : Arquivo contendo o token     : https://ped.cemaden.gov.br/acesso/pedToken

  library(tidyr)
  library(RCurl)
  library(stringr)
  
  # https://sws.cemaden.gov.br/PED/rest/pcds-cadastro/dados-cadastrais?formato=CSV&uf=RS
  urlBase <- "https://sws.cemaden.gov.br/PED/rest/pcds-cadastro/dados-cadastrais?formato=CSV"
  
  tokenString <- readLines(token)
  auth_header <- paste0("token: ", tokenString)
  
  if(is.null(uf)){
      # Todo pais
      urlQuery <- urlBase
  } else{
    # Somente ufs desejadas (1 por vez)
    urlQuery <- paste0(urlBase, "&uf=", uf)
    
  }
 
  dataPCD <- try(getURL(urlQuery, httpheader = c(auth_header)))
  
  if(class(dataPCD) != "try-error" & length(dataPCD) > 0){
    
    dataParse <- data.frame(dataPCD) %>% 
      separate_rows(dataPCD, sep = "\n")
    
    dataParse <- dataParse[[1]]
    #dataParse <- dataParse[-1]
    
    nCols     <- length(strsplit(dataParse[1], ",")[[1]])
    dataParse <- str_split_fixed(dataParse, ",", n  = nCols)
    
    namesData <- dataParse[1, ]
    dataParse <- as.data.frame(dataParse[-1, ])
    
    names(dataParse) <- namesData
    
    return(dataParse)
  } else{
    cat("No data available \n")
  }
}
