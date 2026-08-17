# Organoun: instalar uma vez, ativar por projeto

O Organoun é instalado uma vez na máquina. Depois, cada repositório em que ele
deve atuar recebe seu próprio onboarding local.

## Antes de começar

Na máquina controladora — o host em que o operador vê e conduz tmux e Codex —
confirme:

```bash
gh auth status
command -v git jq tmux codex claude
```

Essa controladora pode ser uma estação ou um servidor de teste; “local” significa
o lado owner da ponte, não proximidade física. O endpoint remoto precisa ter
somente acesso SSH autorizado, Claude autenticado e o diretório de trabalho
escolhido. Organoun, Codex e o tmux owner permanecem na controladora.

## 1. Clone, entre no tmux e instale uma vez

Abra um terminal no diretório em que você escolheu guardar o checkout. O clone
cria a pasta `organoun` no diretório atual; o Organoun não impõe uma localização:

```bash
gh repo clone aiob3/organoun
cd organoun
tmux new -s organoun
```

Se já estiver dentro do tmux que será o owner visível, não crie outro. Dentro
dessa sessão, execute:

```bash
./scripts/install-organoun.sh --help
./scripts/install-organoun.sh
./scripts/install-organoun.sh --apply
export PATH="$HOME/.local/bin:$PATH"
command -v organ
```

`--help` explica o contrato antes de qualquer alteração. A execução sem
`--apply` é o dry-run: não escreve nada e mostra os quatro destinos exatos. Somente
`--apply` autoriza o instalador a criar, após validação e staging:

- `~/.local/share/organoun`: runtime, probes, exemplo de configuração e pin do
  vendor;
- `~/.local/bin/organ`: link relativo para o CLI instalado;
- `~/.codex/skills/organoun`: skill instalada do Codex;
- `~/.codex/organoun.config.toml`: perfil persistente do Codex, restrito ao
  socket exato do tmux owner em que a instalação foi executada.

O perfil é gerado automaticamente a partir de `TMUX`; o operador não cria nem
edita esse arquivo. Ele persiste entre projetos e sessões Codex. O comando
`codex --profile organoun` apenas seleciona o perfil já instalado — não refaz a
configuração.

Uma instalação idêntica é aceita; um destino diferente ou inseguro é recusado.
O comando não modifica o checkout clonado, não altera outro repositório e não
executa onboarding de projeto.

`export PATH="$HOME/.local/bin:$PATH"` apenas antepõe o diretório do CLI ao
`PATH` do shell atual e de seus processos filhos. Ele não escreve arquivo e deixa
de valer quando esse shell termina. Torná-lo permanente é uma decisão do
operador no arquivo de inicialização do seu próprio shell; o Organoun não o
altera automaticamente.

`command -v organ` é a comprovação final: deve imprimir o executável que esse
shell realmente resolverá. Se não imprimir `~/.local/bin/organ` (com `~`
expandido para o home real), pare.

### Atualize uma instalação existente a partir do checkout escolhido

Entre no clone que você decidiu manter; o Organoun não presume onde ele está.
Inicie ou entre no tmux owner visível antes de atualizar. Já dentro dele,
atualize somente por avanço linear, releia a ajuda e observe o dry-run antes de
autorizar a reinstalação:

```bash
cd /caminho/escolhido/organoun
git pull --ff-only
./scripts/install-organoun.sh --help
./scripts/install-organoun.sh
./scripts/install-organoun.sh --apply --reinstall
export PATH="$HOME/.local/bin:$PATH"
command -v organ
```

`--reinstall` exige `--apply` e uma instalação anterior completa: runtime, link
CLI exato e skill. Ele sempre recria `~/.codex/organoun.config.toml` com o socket
do tmux owner atual: perfil ausente é criado e qualquer arquivo regular anterior
nesse caminho exclusivo do Organoun é substituído. Não faça limpeza manual. A
nova fonte é montada e verificada antes da troca; uma interrupção restaura a
instalação anterior. Nenhum outro perfil Codex, deployment de projeto, checkout
ou configuração SSH é removido.

Resultado esperado:

```text
/home/SEU_USUARIO/.local/bin/organ
```

O `export` torna o CLI visível na sessão atual e no tmux iniciado a partir dela.
Depois, inclua `~/.local/bin` no `PATH` permanente do seu shell conforme a
configuração da sua máquina.

Essa etapa instala o CLI, o runtime e a skill do Codex. Ela não solicita servidor,
CWD remoto ou projeto e não cria `.organoun/` no checkout de instalação.

> Não execute `organ onboard` no checkout do Organoun, a menos que o próprio
> Organoun seja deliberadamente o projeto em que a ponte atuará.

## 2. Entre no projeto em que o Organoun atuará

Exemplo com um projeto chamado Calculadora:

```bash
cd /caminho/absoluto/para/calculadora
git rev-parse --show-toplevel
```

O segundo comando deve imprimir exatamente a raiz do projeto.

## 3. Inicie o Codex com o perfil já instalado

Ainda no mesmo tmux visível e na raiz do projeto, inicie:

```bash
codex --profile organoun
```

O pane em que o Codex foi iniciado será o owner visível do Organoun. O perfil
persistente já foi criado pelo instalador; não há arquivo local a reconstruir.
Não crie sessões paralelas fora da visão do operador. Se a consulta ao tmux
ainda retornar `Operation not permitted`, pare: saia do Codex e, nesse mesmo
tmux visível, atualize/reinstale a partir do checkout escolhido. Se uma política
administrada continuar prevalecendo, devolva o bloqueio ao operador; não use
`danger-full-access` como atalho.

## 4. Faça a chamada no Codex

Envie exatamente:

```text
Codex, inicialize o $organoun neste repositório.
```

O Codex seguirá esta decisão:

| Condição observada | Resultado obrigatório |
|---|---|
| `organ` ou a skill não estão instalados | Informar a ausência e parar. |
| Codex não está dentro do tmux visível | Orientar a saída e a retomada dentro do tmux; parar. |
| Socket tmux retorna `Operation not permitted` | Sair do Codex e reinstalar pelo checkout dentro do tmux owner; nunca editar o perfil manualmente nem recomendar acesso total. |
| Projeto ainda não possui deployment | Executar somente `organ onboard`; apresentar o recibo e parar. |
| Projeto já possui deployment válido | Executar `organ init --json`. |

## 5. Primeiro uso do projeto: onboarding

Quando solicitado pelo `organ onboard`, o operador informa diretamente no
terminal:

1. **Local project root:** resultado exato de `pwd -P` na raiz do projeto;
2. **Remote SSH alias:** alias já autorizado no `~/.ssh/config` local;
3. **Remote CWD:** caminho absoluto em que o Claude trabalhará no endpoint.

O onboarding apenas valida localmente a rota com `ssh -G`. Ele não abre conexão,
não abre pane e não inicia Claude.

Resultado esperado:

```text
state=connected
Organoun Connected
```

O projeto passa a conter somente dados locais ignorados pelo Git:

```text
.organoun/deployment.json
.organoun/state/
```

O Codex apresenta o recibo e para. Não executa `init` na mesma interação.

## 6. Ative o projeto

Na interação seguinte, ainda no mesmo projeto e dentro do tmux visível, repita:

```text
Codex, inicialize o $organoun neste repositório.
```

Agora o Codex executará:

```bash
organ init --json
```

Resultado esperado:

```text
state=initialized
```

Depois do recibo, o Codex responderá:

```text
Organoun ativo nesta sessão. O que vamos criar hoje?
```

O controle retorna ao operador. Nenhum pane subordinado é aberto até que o
operador apresente uma nova intenção e autorize o próximo passo visível.

## Se o Codex foi iniciado fora do tmux

O Codex deve parar e orientar este procedimento:

1. sair do Codex;
2. executar `tmux new -s NOME` ou entrar em uma sessão tmux existente;
3. voltar à raiz do projeto;
4. executar `codex --profile organoun resume` ou iniciar uma nova sessão com
   `codex --profile organoun`;
5. repetir a chamada de inicialização do Organoun.

O perfil e o deployment existente são reutilizados; nenhuma configuração é
refeita. O Codex nunca cria uma sessão oculta como correção automática.

## Comprovação concluída

O onboarding prático está concluído quando o operador observou, nesta ordem:

- instalação local encontrada por `command -v organ`;
- Codex executando no tmux visível;
- recibo `state=connected` no primeiro uso;
- recibo `state=initialized` na retomada;
- mensagem `Organoun ativo nesta sessão. O que vamos criar hoje?`;
- nenhum pane criado antes de uma nova autorização do operador.
