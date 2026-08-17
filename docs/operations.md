---
document_schema_version: 1
document_type: operational_runbook
status: approved
operator_approved: true
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
---

# Operação do Organoun

Leia primeiro a [Constituição Organoun/RFC-0001](../.spec/constituicao.md). Este runbook
descreve o rito; somente os gates mecânicos e a autorização aplicável permitem efeitos.

## Instalação única na máquina e dentro do tmux owner

“Máquina local” significa a controladora em que o operador observa e conduz o
tmux e o Codex; ela pode ser uma estação ou um servidor de teste. O endpoint
remoto recebe somente a conexão SSH e o trabalho do Claude, sem outra instalação
Organoun ou tmux criada por esta ponte.

Abra o terminal no diretório escolhido pelo operador para guardar o checkout.
O clone cria a pasta `organoun` no diretório atual; o Organoun não escolhe nem
cria um diretório-pai para o código-fonte:

```bash
gh repo clone aiob3/organoun
cd organoun
tmux new -s organoun
```

Se já estiver no tmux owner visível, não crie outro. Dentro dele:

```bash
./scripts/install-organoun.sh --help
./scripts/install-organoun.sh
./scripts/install-organoun.sh --apply
export PATH="$HOME/.local/bin:$PATH"
command -v organ
```

`--help` descreve os efeitos; sem `--apply`, o comando comprova o tmux e imprime os quatro
destinos e não escreve. Com `--apply`, ele valida, monta um staging e cria apenas
o runtime em `~/.local/share/organoun`, o link CLI `~/.local/bin/organ` e a skill
`~/.codex/skills/organoun`, além do perfil persistente e privado
`~/.codex/organoun.config.toml`, gerado com acesso de filesystem e de rede Unix
socket limitado ao socket exato do tmux owner, sem liberar `/tmp` inteiro.
Instalação idêntica é idempotente; colisão diferente ou insegura é recusada. O
clone e os projetos não são modificados. O operador nunca cria ou edita o perfil
manualmente.

O `export` altera somente o `PATH` do shell corrente e seus filhos, sem escrever
arquivos. `command -v organ` deve então comprovar o executável efetivamente
resolvido; resultado ausente ou diferente interrompe o rito.

Para atualizar a partir do clone escolhido pelo operador, entre primeiro no
tmux owner visível e execute somente:

```bash
cd /caminho/escolhido/organoun
git pull --ff-only
./scripts/install-organoun.sh --help
./scripts/install-organoun.sh
./scripts/install-organoun.sh --apply --reinstall
export PATH="$HOME/.local/bin:$PATH"
command -v organ
```

`--reinstall` exige `--apply` e comprova a topologia Organoun antes de substituir
runtime e skill a partir de um staging validado. Ele sempre recria somente
`~/.codex/organoun.config.toml`: ausência é aceita e qualquer arquivo regular
anterior nesse caminho dedicado é substituído. O link CLI e todos os demais
perfis Codex são preservados. Falha durante a publicação restaura a instalação
anterior; deployments de projeto, clone e configuração SSH não são tocados.

O instalador publica o runtime, a skill e somente o perfil dedicado do Codex,
mas não solicita raiz de projeto, alias SSH ou CWD remoto e não altera a
configuração geral do Codex. Não execute
`organ onboard` dentro desse checkout, exceto se o próprio Organoun for
deliberadamente o projeto-alvo.

## Protocolo por projeto

Execute sempre na raiz Git canônica e no pane local visível do operador.

O instalador já derivou o socket do tmux owner e publicou o perfil persistente
`~/.codex/organoun.config.toml`, autorizando o mesmo caminho exato nas camadas
de filesystem e de rede Unix socket. Inicie com `codex --profile organoun`;
esse comando apenas seleciona o perfil existente e não recria configuração por
sessão ou projeto. Não combine o perfil com `sandbox_mode` ou
`[sandbox_workspace_write]`, não permita `/tmp` inteiro e não substitua esse gate
por `danger-full-access`. Se uma política administrada impedir o socket, pare,
saia do Codex e reinstale pelo checkout dentro do tmux owner. Persistindo o
bloqueio, devolva a política administrada ao operador.

```text
organ ausente                    -> reinstalar a partir do checkout Organoun
Codex fora do tmux owner visível -> sair, entrar no tmux e retomar o Codex
socket tmux sem permissão         -> sair; reinstalar no tmux owner; parar
deployment ausente ou inválido -> sair do Codex; operador executa organ onboard
deployment válido             -> organ init --json
init válido                    -> reserve/enter/observe/send/close/release
```

Nenhum pane, SSH, Claude, claim, dispatch ou evento paralelo começa antes de `init` para
o digest atual.

Ao receber “inicialize o `$organoun` aqui”, o Codex verifica primeiro
`command -v organ` e o contexto `TMUX`/`TMUX_PANE`. Se o Codex não tiver sido
iniciado dentro da sessão tmux owner, ele orienta o operador a sair, iniciar ou
entrar no tmux, executar `codex --profile organoun resume` ou iniciar uma nova
sessão com `codex --profile organoun` e repetir o pedido. O perfil e o deployment
são reutilizados; nenhuma configuração é refeita. Nenhuma sessão é criada por
trás do operador. Se o deployment estiver ausente, o Codex manda o operador sair
e para: somente o operador executa `organ onboard` no shell humano visível.

### Primeira execução na raiz

Antes de abrir o Codex, na raiz canônica do projeto e no shell humano visível:

```bash
organ onboard
```

O comando detecta e exibe a raiz local. O operador informa somente o host/alias
SSH sem `usuario@` e o CWD remoto. Os valores são exibidos e a rota é resolvida
localmente com `ssh -G` antes da gravação. Nenhuma conexão SSH é aberta: o
onboarding registra no projeto um acesso que o operador já comprovou.

O frontend detecta a raiz e solicita uma vez:

1. host/alias SSH remoto sem `usuario@`;
2. CWD remoto absoluto.

A raiz detectada e os dois valores informados formam uma única submissão. O
comando valida localmente a rota SSH sem abrir conexão, protege o estado no
`.gitignore` e publica uma vez:

```text
.organoun/deployment.json  mode 0600
.organoun/state/           mode 0700
```

Sucesso produz um único envelope com `state=connected`, mensagem
`Organoun Connected`, `submission_count=1` e `write_count=1`. O recibo não reproduz
host nem caminhos absolutos. O operador recebe o recibo no shell e somente então
inicia ou retoma o Codex.

Se o deployment já existir, `onboard` recusa sobrescrita. Se a gravação ficar ambígua,
não repita: inspecione o estado e obtenha nova intenção explícita.

### Próxima janela e retomadas

```bash
organ init --json
```

`init` carrega automaticamente o deployment da raiz corrente, associa seu digest ao
owner e comprova o pane/controlador visível. Deployment ausente, inválido, alterado ou
pertencente a outra raiz retorna `ONBOARD_REQUIRED` antes de qualquer efeito.

Depois de um recibo `state=initialized`, o Codex responde exatamente:

```text
Organoun ativo nesta sessão. O que vamos criar hoje?
```

Então devolve o controle ao operador.

Uma raiz já onboarded nunca solicita nem grava novamente os valores. Uma raiz
nova recomeça obrigatoriamente por `organ onboard`, fora do Codex.

Não existe fallback para `XDG_CONFIG_HOME` ou `XDG_STATE_HOME`.

## Targets derivados

O runtime deriva em memória, sem gravar outro registry:

- `local-managed`: endpoint local no `local_project_root`;
- `remote-managed`: endpoint SSH no `remote_host` e `remote_cwd`.

O host real vem somente do deployment estrito. Prompt, worker e pane não selecionam
host. O endpoint remoto não recebe tmux, Organoun, Outsourcerer, helper, claims, jobs,
receipts, targets ou qualquer plano de controle.

## Operação visível após init

O operador permanece no owner local. Cada endpoint usa um pane subordinado local
simultaneamente visível. A ordem mecânica é:

```text
organ reserve ALIAS --json
operator attestation
organ enter ALIAS --attest NONCE --json
organ status/read ALIAS --json
uma ação autorizada
organ close ALIAS --json
```

Sessões adotadas mantêm claim obrigatório, `release` em vez de `stop` e proibição de
replay após entrega desconhecida. Sessões gerenciadas só podem ser encerradas quando um
recibo Organoun válido comprova posse.

## Falhas fechadas

| Código/estado | Ação |
|---|---|
| `ONBOARD_REQUIRED` | Execute `organ onboard` somente após nova autorização; nenhum pane foi criado. |
| `DEPLOYMENT_ALREADY_EXISTS` | Preserve o arquivo. Não sobrescreva nem reenvie os dados. |
| `ROUTE_INVALID` | Corrija o alias localmente e reinicie o onboarding mediante nova intenção. |
| `VISIBLE_PANE_REQUIRED` | Pare; não crie transporte oculto nem contorne pelo tmux. |
| `delivery=unknown` | Use somente `read`; nunca repita a obrigação. |
| `blocked-verification` | Esse job é terminal; não reexecute `organ verify` nem redespache/reapresente esse job. Somente uma nova intenção explícita e separadamente escopada pode criar trabalho novo. |

Qualquer erro de permissão associado a uma tentativa de sessão paralela sem visibilidade
encerra imediatamente o procedimento. Não há fallback oculto.

## Preservação e rollback

O deployment pertence ao operador e não é removido automaticamente. Um rollback de
runtime pode remover somente paths comprovadamente instalados pelo Organoun; nunca
remove `.organoun/deployment.json`, credenciais, Claude, tmux ou checkouts independentes.

Depois de comprovar que cada destino ainda pertence à instalação Organoun, o escopo
máximo de remoção é exatamente:

```text
$HOME/.local/bin/organ
$HOME/.local/share/organoun
$HOME/.codex/skills/organoun
```
