# Organoun: instalar uma vez, ativar por projeto

O Organoun é instalado uma vez na máquina. Depois, cada repositório em que ele
deve atuar recebe seu próprio onboarding local.

## Antes de começar

Na máquina local, confirme:

```bash
gh auth status
command -v git jq tmux codex claude
```

O endpoint remoto precisa ter somente acesso SSH autorizado, Claude autenticado
e o diretório de trabalho escolhido. O Organoun e o tmux permanecem na máquina
local do operador.

## 1. Instale o Organoun uma vez

Abra um terminal no diretório em que você escolheu guardar o checkout. O clone
cria a pasta `organoun` no diretório atual; o Organoun não impõe uma localização:

```bash
gh repo clone aiob3/organoun
cd organoun
./scripts/install-organoun.sh --apply
export PATH="$HOME/.local/bin:$PATH"
command -v organ
```

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

## 3. Inicie o tmux antes do Codex

Se ainda não estiver dentro de uma sessão tmux:

```bash
tmux new -s calculadora
```

Já dentro do tmux e ainda na raiz do projeto, inicie o Codex:

```bash
codex
```

O pane em que o Codex foi iniciado será o owner visível do Organoun. Não crie
sessões paralelas fora da visão do operador.

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
4. executar `codex resume` ou iniciar uma nova sessão com `codex`;
5. repetir a chamada de inicialização do Organoun.

O Codex nunca cria uma sessão oculta como correção automática.

## Comprovação concluída

O onboarding prático está concluído quando o operador observou, nesta ordem:

- instalação local encontrada por `command -v organ`;
- Codex executando no tmux visível;
- recibo `state=connected` no primeiro uso;
- recibo `state=initialized` na retomada;
- mensagem `Organoun ativo nesta sessão. O que vamos criar hoje?`;
- nenhum pane criado antes de uma nova autorização do operador.
