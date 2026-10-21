# PCDs Cemaden — configuração segura e delimitação de bacias (R)

## 1. Somente R

A aplicação, as funções de delimitação e a integração com os mapas estão implementadas em R. Não é necessário instalar Python nem criar um ambiente Python.

## 2. Proteger as credenciais do PostgreSQL

As credenciais não devem ser gravadas no `app.R` nem em comentários. A aplicação lê as variáveis `DB_NAME`, `DB_HOST`, `DB_PORT`, `DB_USER` e `DB_PASSWORD` do ambiente ou de um arquivo `.env` local.

1. Copie `.env.example` para `.env`.
2. Preencha os valores do seu ambiente, sem enviar o arquivo `.env` ao GitHub.
3. O `.gitignore` ignora `.env`, `.Renviron`, a pasta `.secrets/` e os arquivos de cache.
4. Reinicie a sessão do R e execute a aplicação a partir da pasta do projeto.

Exemplo no PowerShell, se preferir definir as variáveis no ambiente:

```powershell
$env:DB_NAME = "cemaden"
$env:DB_HOST = "127.0.0.1"
$env:DB_PORT = "5432"
$env:DB_USER = "seu_usuario"
$env:DB_PASSWORD = "sua_senha"
```

**Importante:** o código original continha credenciais no código-fonte. Se ele já foi enviado ao GitHub, troque as senhas/tokens expostos e avalie removê-los do histórico Git. Adicionar `.gitignore` ou alterar o arquivo atual não elimina segredos de commits antigos.

## 3. Delimitar bacias e rios clicando no mapa

Nos mapas **Interpolação PCDs** e **Consistência Espacial**, clique com o botão esquerdo em um ponto do mapa. A aplicação consulta a API do Global Watersheds, que utiliza dados MERIT-Hydro, e desenha:

- contorno da bacia hidrográfica a montante em vermelho;
- rede de rios a montante em azul.

Um novo clique substitui as camadas da delimitação anterior e ajusta o enquadramento para mostrar a bacia.

### Dependências R

A aplicação utiliza `sf`, que já é usado pelo projeto, e o pacote `httr` para consumir a API. Caso `httr` não esteja instalado, execute no R:

```r
install.packages("httr")
```

### Cache local e limite da abordagem

Os GeoJSONs são guardados em `.cache/watersheds/` (ou no diretório definido por `WATERSHED_CACHE_DIR` no `.env`). Se o usuário clicar novamente no mesmo ponto, os dados são lidos do disco e não é necessário consultar novamente a API para aquela bacia e seus rios.

**Limitação importante:** o cache não é um motor hidrológico local. Para cada novo ponto, a aplicação precisa consultar a API remota. O código público que reproduz localmente o método exato do Global Watersheds é implementado em Python; para manter este projeto exclusivamente em R, optei por consumir a API oficial diretamente do R, sem subprocessos nem dependência de Python. Uma solução inteiramente local em R exigiria implementar e validar outro fluxo hidrológico com dados raster MERIT-Hydro locais, que não seria automaticamente idêntico aos resultados da API.

A API é um serviço compartilhado. O código espera pelo menos 5 segundos entre solicitações no mesmo processo R, conforme orientação do mantenedor. Um ponto fora de uma área de drenagem válida (por exemplo, no oceano) pode não gerar uma bacia.

## 4. Validação dos resultados

A delimitação global é uma ferramenta de apoio, e o mantenedor não garante que os resultados sejam adequados para qualquer finalidade. Verifique visualmente as bacias, em especial em áreas costeiras, perto de divisores e em regiões com rede de drenagem pouco definida.
