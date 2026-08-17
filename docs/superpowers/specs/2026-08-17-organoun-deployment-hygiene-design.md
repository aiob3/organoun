---
document_schema_version: 1
document_type: design_specification
status: approved
operator_approved: true
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
---

# Higienização do deployment local do Organoun

**Data:** 2026-08-17

**Objetivo:** retirar identidade de servidor e caminhos concretos do motor Organoun e
transformá-los em estado local de deployment, informado uma única vez durante o
onboarding e gravado dentro do projeto inicializado.

Este documento é derivado da Constituição Organoun/RFC-0001. Ele não autoriza uma
operação, não substitui a Constituição e não transforma o endpoint remoto em plano de
controle.

## 1. Decisões do operador

1. O nome ou alias do servidor remoto, o CWD remoto e a raiz local do projeto são
   variáveis de deployment; não são constantes do produto.
2. Os três valores são apresentados e coletados durante o onboarding.
3. Os três valores são submetidos juntos, uma única vez.
4. A configuração é gravada uma única vez dentro da raiz local informada.
5. A configuração real é automaticamente protegida pelo `.gitignore` dessa raiz.
6. A configuração real nunca é versionada.
7. Não serão criados novos testes automatizados para o procedimento de escrita.
8. A prova do procedimento será um único recibo mecânico produzido após a gravação,
   sem repetir a escrita e sem executar uma suíte de testes.

Essas decisões implementam `ssot:term:harness-state`: o que varia por deployment fica
fora do `ssot:term:harness-service`, que permanece genérico.

## 2. Interface de onboarding

O comando novo é `organ onboard`. `organ init` permanece reservado ao registro da
Sessão Proprietária local e visível.

O frontend assistido `scripts/onboard-organoun.sh` coleta exatamente, a partir do
terminal da Sessão Proprietária:

- `local_project_root`: caminho local absoluto, canônico e já existente;
- `remote_host`: alias SSH explícito escolhido pelo operador;
- `remote_cwd`: caminho remoto absoluto escolhido pelo operador.

O frontend monta um único objeto JSON e o entrega uma única vez por stdin:

```bash
printf '%s' "$deployment_json" | organ onboard --stdin --json
```

Os valores não são repetidos em argv, não são enviados ao endpoint e não são
reapresentados automaticamente após uma falha ambígua.

O frontend não grava a configuração. Sua única saída de autoridade é o JSON enviado ao
backend `organ onboard`; somente o backend valida, protege e publica o arquivo.

### 2.1 Máquina de estados única

Toda inicialização Organoun segue exatamente esta sequência:

```text
UNCONFIGURED
  -> ONBOARD_INPUT_RECEIVED
  -> DEPLOYMENT_VALIDATED
  -> CONNECTIVITY_OK
  -> DEPLOYMENT_PUBLISHED
  -> CONNECTED
  -> INITIALIZED
```

- `UNCONFIGURED`: a raiz corrente não contém deployment válido;
- `ONBOARD_INPUT_RECEIVED`: os três valores ingressaram juntos uma vez;
- `DEPLOYMENT_VALIDATED`: schema, raiz, host e CWD passaram pelas validações locais;
- `CONNECTIVITY_OK`: uma única checagem local somente-leitura comprovou que a rota SSH
  explícita pode ser resolvida; ela não abre conexão com o endpoint;
- `DEPLOYMENT_PUBLISHED`: o arquivo ignorado foi gravado uma vez;
- `CONNECTED`: o recibo sanitizado `Organoun Connected` foi emitido;
- `INITIALIZED`: `organ init` carregou aquele deployment e registrou a Sessão
  Proprietária visível.

Não existe transição que comece por reserve, pane, SSH interativo, session enter,
dispatch ou outro evento paralelo. Todas dependem de `INITIALIZED` para o mesmo digest
de deployment.

### 2.2 Primeira execução e retomada

Na primeira execução de uma raiz, `organ onboard` recebe os dados, verifica localmente a
configuração de transporte, publica `deployment.json` e emite `CONNECTED`. O comando não
cria pane, não abre SSH e não executa dispatch.

Na próxima janela de interação, `organ init --json` resolve e valida automaticamente o
deployment local antes de registrar o owner. Se o arquivo estiver ausente, inválido ou
pertencer a outra raiz, retorna `ONBOARD_REQUIRED` sem qualquer efeito paralelo. O
operador pode então autorizar novamente `organ onboard`, reiniciando a ponte desde
`UNCONFIGURED`.

Em uma raiz já onboarded, a retomada começa diretamente por `organ init`; os três dados
não são solicitados, enviados ou gravados novamente.

O payload aceito possui exatamente esta forma:

```json
{
  "schema_version": "1",
  "local_project_root": "/absolute/local/project/root",
  "remote_host": "operator-selected-ssh-alias",
  "remote_cwd": "/absolute/remote/project/root"
}
```

O JSON precisa ser um único documento, UTF-8 válido, sem NUL, sem chaves duplicadas e
sem campos extras. O host aceita somente caracteres de um alias SSH seguro. Os dois
caminhos precisam ser absolutos e não podem conter caracteres de controle.

## 3. Autoridade e topologia

O onboarding ocorre somente num pane local visível com cliente do operador anexado. Esse
pane ainda é candidato a owner: somente `organ init`, na janela seguinte, registra a
Sessão Proprietária. O arquivo de deployment não contém owner, pane, PID, layout ou
credencial; esses dados continuam sendo descobertos e atestados dinamicamente.

O endpoint remoto recebe somente comandos de execução originados no controlador local.
O onboarding não instala nem configura Organoun, tmux, Outsourcerer, helper, claims,
jobs, receipts ou targets no endpoint remoto.

O `remote_host` vem exclusivamente do arquivo local estrito. Texto de prompt, pane ou
resposta do worker nunca pode selecionar ou substituir o host.

## 4. Persistência local write-once

O destino canônico é:

```text
<local_project_root>/.organoun/deployment.json
```

Regras de publicação:

1. validar integralmente o payload antes de criar qualquer arquivo;
2. comprovar que a raiz informada é exatamente o resultado de `pwd -P` e a raiz do
   worktree retornada por `git rev-parse --show-toplevel`;
3. recusar ancestrais simbólicos e destinos simbólicos;
4. criar `.organoun/` com modo `0700`, caso esteja ausente;
5. inserir no `.gitignore` da raiz, de forma idempotente, a linha exata
   `/.organoun/deployment.json`;
6. inserir também `/.organoun/state/`, isolando o estado operacional por projeto;
7. somente depois de comprovar a proteção Git, gravar um estágio privado no mesmo
   filesystem;
8. validar o estágio e publicá-lo por rename atômico com modo `0600`;
9. nunca sobrescrever um `deployment.json` existente, mesmo se seu conteúdo parecer
   equivalente.

Se o `.gitignore` não existir, ele é criado. Se existir como arquivo regular, seu
conteúdo e modo são preservados e apenas a linha ausente é adicionada. A atualização é
montada num estágio regular no mesmo diretório e publicada por rename atômico. Symlink,
tipo inesperado ou falha de escrita encerram o onboarding antes da publicação da
configuração.

Uma entrada de `.gitignore` criada sem que a configuração seja publicada pode
permanecer: ela é segura e idempotente. A configuração nunca deve existir num intervalo
em que ainda não esteja ignorada.

## 5. Descoberta e consumo

Por padrão, o runtime resolve a raiz Git canônica do diretório corrente e procura
`.organoun/deployment.json` exatamente nessa raiz. Não há fallback silencioso para o antigo arquivo global em
`XDG_CONFIG_HOME`, nem para valores embutidos no repositório.

O estado operacional padrão fica em `.organoun/state/` na mesma raiz. Não há fallback
silencioso para estado global em `XDG_STATE_HOME`; owner, panes, claims, jobs e receipts
de um projeto não podem satisfazer outro deployment.

O runtime deriva em memória dois destinos gerenciados com nomes neutros:

- `local-managed`: `transport=local`, `host=local` e `cwd=local_project_root`;
- `remote-managed`: `transport=ssh`, `host=remote_host` e `cwd=remote_cwd`.

Provider e política de modelo continuam explícitos no motor. Targets adotados não são
fabricados pelo onboarding; uma sessão adotada continua exigindo identificação e claim
próprios.

O CLI público ignora `ORGAN_CONFIG`, `ORGAN_STATE_HOME`, `XDG_CONFIG_HOME` e
`XDG_STATE_HOME` para roteamento e estado Organoun. O deployment e o estado são sempre
resolvidos da raiz Git corrente.

`organ init` calcula o digest do deployment carregado e o associa ao registro do owner.
Reserve, enter, observe, send, close e release recusam execução se o deployment estiver
ausente, tiver mudado ou não corresponder ao digest inicializado.

## 6. Higienização do repositório

Os artefatos executáveis, templates instaláveis, exemplos atuais e documentos
normativos não podem conter identidade real de host, raiz local ou CWD remoto.

O exemplo versionado usa somente valores neutros e não é instalado como configuração
real. Registros históricos inválidos podem preservar contexto histórico, mas não podem
ser lidos como configuração, baseline ou autoridade operacional.

A referência concreta de worktree hoje presente na política de promoção da Constituição
deve passar a referenciar semanticamente `deployment.local_project_root`. Essa mudança
exige nova versão e novo digest constitucional; documentos governados recebem o binding
atualizado como migração mecânica, sem ampliar sua autoridade.

Não há reescrita de histórico Git e nenhum valor real é apagado do ambiente do operador.
Os valores reais passam a existir somente no arquivo local ignorado.

## 7. Falhas fechadas e não repetição

O onboarding retorna erro sem segunda tentativa automática quando ocorrer:

- payload ausente, múltiplo, malformado ou fora do schema;
- caminho local divergente, não canônico ou inseguro;
- host ou CWD remoto inválido;
- `.gitignore` inseguro ou não gravável;
- configuração já existente;
- falha, interrupção ou ambiguidade durante a publicação;
- falha na leitura mecânica posterior.

Depois de uma falha ambígua, o operador recebe o caminho esperado e o estado observado.
Uma nova execução só pode ocorrer mediante nova intenção explícita. O processo nunca
reenvia os dados nem tenta sobrescrever o arquivo existente.

## 8. Recibo mecânico único

Sem criar uma suíte nova, a mesma execução faz uma única verificação somente-leitura
após o rename:

1. arquivo regular, sem symlink, modo `0600`;
2. conteúdo estrito e digest igual ao payload normalizado recebido;
3. raiz declarada igual à raiz de inicialização;
4. entrada exata presente no `.gitignore`;
5. `git check-ignore` identifica o deployment e o estado local como ignorados.

Antes da publicação, o onboarding executa exatamente uma checagem local somente-leitura
da rota `remote_host`, equivalente à resolução estrita por `ssh -G`. `remote_cwd` é
validado lexicalmente nessa fase; sua existência remota só pode ser comprovada depois de
`init`, no pane subordinado visível. A checagem não abre pane, conexão de rede, Claude ou
processo remoto e não possui retry. Falha ou resultado ambíguo encerra o fluxo antes de
`DEPLOYMENT_PUBLISHED`.

Se as cinco condições forem satisfeitas, a saída JSON contém:

```json
{
  "schema_version": "1",
  "ok": true,
  "action": "onboard",
  "target": "",
  "host": "",
  "state": "connected",
  "delivery": "not-applicable",
  "data": {
    "message": "Organoun Connected",
    "write_count": 1,
    "submission_count": 1,
    "config_path": ".organoun/deployment.json",
    "gitignored": true
  }
}
```

O recibo não reproduz host nem caminhos absolutos. `Organoun Connected` significa que o
deployment foi associado ao Organoun; não alega que uma sessão SSH esteja aberta. Ele
prova a publicação sem vazar os valores e sem repetir a operação.

## 9. Fora de escopo

- reconfiguração ou sobrescrita do deployment;
- sincronização do arquivo entre máquinas;
- armazenamento remoto de configuração;
- instalação de plano de controle no endpoint;
- descoberta automática de host ou caminho;
- migração automática de configurações divergentes;
- criação de novos testes automatizados para a escrita do onboarding;
- reescrita do histórico Git.

## 10. Critério de aceite

A implementação está apta a ser apresentada ao operador quando uma única execução
assistida:

1. coleta os três valores uma vez;
2. cria o arquivo local uma vez;
3. prova que o arquivo está ignorado e protegido;
4. produz o recibo sanitizado uma vez;
5. não envia dados ao endpoint remoto;
6. não contém valores do deployment no motor ou em defaults instaláveis;
7. preserva o único owner local e todas as invariantes da RFC-0001;
8. impede qualquer evento paralelo antes de `INITIALIZED` para o mesmo deployment.
