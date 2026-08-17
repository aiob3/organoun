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

## Instalação única na máquina

Abra o terminal no diretório escolhido pelo operador para guardar o checkout.
O clone cria a pasta `organoun` no diretório atual; o Organoun não escolhe nem
cria um diretório-pai para o código-fonte:

```bash
gh repo clone aiob3/organoun
cd organoun
./scripts/install-organoun.sh --apply
export PATH="$HOME/.local/bin:$PATH"
command -v organ
```

O instalador publica o runtime e a skill em `~/.local`, mas não solicita raiz de
projeto, alias SSH ou CWD remoto e não cria configuração global. Não execute
`organ onboard` dentro desse checkout, exceto se o próprio Organoun for
deliberadamente o projeto-alvo.

## Protocolo por projeto

Execute sempre na raiz Git canônica e no pane local visível do operador.

```text
organ ausente                    -> reinstalar a partir do checkout Organoun
Codex fora do tmux owner visível -> sair, entrar no tmux e retomar o Codex
deployment ausente ou inválido -> organ onboard
deployment válido             -> organ init --json
init válido                    -> reserve/enter/observe/send/close/release
```

Nenhum pane, SSH, Claude, claim, dispatch ou evento paralelo começa antes de `init` para
o digest atual.

Ao receber “inicialize o `$organoun` aqui”, o Codex verifica primeiro
`command -v organ` e o contexto `TMUX`/`TMUX_PANE`. Se o Codex não tiver sido
iniciado dentro da sessão tmux owner, ele orienta o operador a sair, iniciar ou
entrar no tmux, executar `codex resume` ou iniciar uma nova sessão e repetir o
pedido. Nenhuma sessão é criada por trás do operador.

### Primeira execução na raiz

```bash
organ onboard
```

O frontend solicita uma vez:

1. raiz local absoluta do projeto;
2. alias SSH remoto;
3. CWD remoto absoluto.

Os três valores formam uma única submissão. O comando valida localmente a rota SSH sem
abrir conexão, protege o estado no `.gitignore` e publica uma vez:

```text
.organoun/deployment.json  mode 0600
.organoun/state/           mode 0700
```

Sucesso produz um único envelope com `state=connected`, mensagem
`Organoun Connected`, `submission_count=1` e `write_count=1`. O recibo não reproduz
host nem caminhos absolutos. O Codex apresenta o recibo e para; não executa
`init` na mesma interação.

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

Uma raiz já onboarded nunca solicita nem grava novamente os três valores. Uma raiz nova
recomeça obrigatoriamente por `organ onboard`.

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
