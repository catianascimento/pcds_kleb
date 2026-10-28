# PCDsCemaden

Aplicação R Shiny para análise e visualização de dados de precipitação das Plataformas de Coleta de Dados (PCDs) do Cemaden.

## Funcionalidades

- Interpolação espacial da precipitação por estado ou região.
- Análise de consistência espacial e identificação de PCDs suspeitas.
- Estatísticas municipais, históricos e análise de extremos.
- Exportação de rasters em formato GeoTIFF.
- Delimitação de bacias hidrográficas e visualização dos rios a montante.

## Requisitos

- R instalado no computador.
- Acesso ao banco de dados PostgreSQL utilizado pela aplicação.
- Conexão com a internet.

## Instalação

Clone o repositório e acesse a pasta do projeto:

```bash
git clone <URL_DO_REPOSITORIO>
cd <PASTA_DO_REPOSITORIO>
```

No console do R, instale o `renv` e restaure as dependências registradas em `renv.lock`:

```r
if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv")
}

renv::restore()
```

## Configuração

Crie um arquivo `.env` na raiz do projeto com as credenciais do PostgreSQL:

```text
DB_NAME=nome_do_banco
DB_HOST=servidor
DB_PORT=5432
DB_USER=usuario
DB_PASSWORD=senha
```

Substitua os valores pelos fornecidos pelo administrador do banco. Caso necessário, configure também a variável `PED_TOKEN_FILE` para indicar o caminho local do token PED.

**Não envie credenciais, tokens ou arquivos `.env` para o GitHub.**

## Execução

Na raiz do projeto, execute:

```r
shiny::runApp(".", launch.browser = TRUE)
```

## Delimitação de bacias

Nos mapas de Interpolação PCDs e Consistência Espacial, clique com o botão direito no ponto desejado e selecione **Desenhar bacia**.

A funcionalidade depende do módulo `R/watershed.R`, da conexão com a internet e da disponibilidade do serviço Global Watersheds.

## Dados necessários

Os arquivos espaciais e demais recursos utilizados pela aplicação devem estar disponíveis nas pastas esperadas pelo código, especialmente `data/`, `R/` e `www/`.

Consulte o responsável pelo projeto caso os dados necessários não estejam disponíveis no repositório.