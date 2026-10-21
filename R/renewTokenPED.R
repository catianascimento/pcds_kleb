################################################################################
# Funcao que renova tokepara API do Cemaden para baixar dados das PCDs
# Manual de uso da API: https://sws.cemaden.gov.br/PED/api/ui/#/
#
# Author: Kleber Lopes da Rocha Filho - Tecnologista CGPD - NOV-2025
################################################################################

renewTokenPED <- function(mail, password, fileOut){
  
  library(httr)
  library(jsonlite)
  
  token_url <- "https://sgaa.cemaden.gov.br/SGAA/rest/controle-token/tokens"
  login <- list(email = mail, password = password)
  
  response     <- POST(token_url, body = login, encode = "json")
  content      <- content(response, as = "text", encoding = "UTF-8")
  json_content <- fromJSON(content)
  
  token        <- json_content$token
  
  write(token, file = fileOut)  
  
}

