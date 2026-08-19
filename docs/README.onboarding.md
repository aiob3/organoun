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
readlink -f "$HOME/.local/bin/organ"
```

`--help` explica o contrato antes de qualquer alteração. A execução sem
`--apply` é o dry-run: não escreve nada e mostra os quatro destinos exatos. Somente
`--apply` autoriza o instalador a criar, após validação e staging:

- `~/.local/share/organoun`: runtime, probes, exemplo de configuração e pin do
  vendor;
- `~/.local/bin/organ`: link relativo para o CLI instalado;
- `~/.codex/skills/organoun`: skill instalada do Codex;
- `~/.codex/organoun.config.toml`: perfil persistente do Codex, restrito ao
  socket exato do tmux owner em que a instalação foi executada. O mesmo caminho
  é autorizado nas camadas de filesystem e de rede Unix socket; o diretório
  `/tmp` inteiro não é liberado.

O perfil é gerado automaticamente a partir de `TMUX`; o operador não cria nem
edita esse arquivo. Ele persiste entre projetos e sessões Codex. O comando
`codex --profile organoun` apenas seleciona o perfil já instalado — não refaz a
configuração.

Uma instalação idêntica é aceita; um destino diferente ou inseguro é recusado.
O comando não modifica o checkout clonado, não altera outro repositório e não
executa onboarding de projeto.

`readlink -f "$HOME/.local/bin/organ"` comprova o link canônico instalado. O
onboarding e a skill usam esse caminho absoluto: não dependem do `PATH`, não
alteram arquivos de inicialização do shell e continuam funcionando em novos
shells, sessões tmux, sessões Codex e projetos.

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
readlink -f "$HOME/.local/bin/organ"
```

`--reinstall` exige `--apply` e uma instalação anterior completa: runtime, link
CLI exato e skill. Ele sempre recria `~/.codex/organoun.config.toml` com acesso
de filesystem e de rede Unix socket limitado ao socket do tmux owner atual:
perfil ausente é criado e qualquer arquivo regular anterior nesse caminho
exclusivo do Organoun é substituído. Não faça limpeza manual. A nova fonte é
montada e verificada antes da troca; uma interrupção restaura a instalação
anterior. Nenhum outro perfil Codex, deployment de projeto, checkout ou
configuração SSH é removido.

Resultado esperado:

```text
/home/SEU_USUARIO/.local/share/organoun/bin/organ
```

Essa etapa instala o CLI, o runtime e a skill do Codex. Ela não solicita servidor,
CWD remoto ou projeto e não cria `.organoun/` no checkout de instalação.

> Não execute `"$HOME/.local/bin/organ" onboard` no checkout do Organoun, a menos que o próprio
> Organoun seja deliberadamente o projeto em que a ponte atuará.

## 2. Entre no projeto em que o Organoun atuará

Exemplo com um projeto chamado Calculadora:

```bash
cd /caminho/absoluto/para/calculadora
git rev-parse --show-toplevel
```

O segundo comando deve imprimir exatamente a raiz do projeto.

## 3. Primeiro uso do projeto: onboarding antes do Codex

Ainda no tmux visível e na raiz do projeto, o operador executa diretamente:

```bash
"$HOME/.local/bin/organ" onboard
```

O Codex nunca executa esse comando nem recebe os dados do deployment.

O Organoun detecta e exibe a **Local project root**. O operador informa somente:

1. **Remote SSH host/alias:** nome usado por `ssh`, sem `usuario@`;
2. **Remote CWD:** caminho absoluto em que o Claude trabalhará no endpoint.

O onboarding mostra os dois valores que serão registrados e valida localmente a
resolução da rota com `ssh -G`. Ele não conecta ao endpoint, não comprova outra
vez um acesso que o operador já realizou, não abre pane e não inicia Claude.

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

Depois de `state=connected`, esse projeto não pede os dados novamente.

## 4. Inicie o Codex e ative o projeto

Ainda no mesmo tmux visível e na raiz do projeto, inicie:

```bash
codex --profile organoun
```

O perfil persistente já foi criado pelo instalador; não há configuração local a
reconstruir. No Codex, envie exatamente:

```text
Codex, inicialize o $organoun neste repositório.
```

Com o deployment válido, a skill executará pelo caminho canônico:

```bash
"$HOME/.local/bin/organ" init --json
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

Se o projeto ainda não tiver deployment, o Codex orientará a saída e parará. O
operador então executa o passo 3 no shell visível; o Codex nunca abre o diálogo
de onboarding nem coleta os dados.

## Se a sessão tmux original foi fechada

A Sessão Proprietária do Organoun fica amarrada à sessão tmux exata em que
`organ init` rodou pela primeira vez. Se você fechar essa sessão tmux e abrir
outra — mesmo no mesmo projeto, mesma máquina —, o próximo `init` recusa com
`CONTROLLER_OWNERSHIP_MISMATCH`: a posse antiga ainda está registrada e não é
substituída automaticamente.

Isso é esperado, não é uma reinstalação necessária. Na nova sessão tmux
visível, execute:

```bash
"$HOME/.local/bin/organ" reset-owner --json
```

O comando só libera a posse depois de confirmar que a sessão tmux antiga já
não existe mais; se ela ainda estiver ativa em outro lugar, ele recusa e
nada é alterado. Depois do reset, retome normalmente com `codex --profile
organoun`. Não reinstale, não repita `onboard` — o deployment local
continua válido; só a posse da sessão foi resetada.

## 5. Próximas sessões e outros projetos

Para retomar um projeto já onboarded, não reinstale, não exporte `PATH` e não
execute onboarding novamente:

```bash
cd /caminho/absoluto/para/calculadora
codex --profile organoun
```

Então repita no Codex:

```text
Codex, inicialize o $organoun neste repositório.
```

Para outro projeto, faça uma única vez os passos 2 e 3; a instalação da máquina
e o perfil Codex são reutilizados.

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

- instalação local comprovada em `~/.local/bin/organ`;
- Codex executando no tmux visível;
- recibo `state=connected` no primeiro uso;
- recibo `state=initialized` na retomada;
- mensagem `Organoun ativo nesta sessão. O que vamos criar hoje?`;
- nenhum pane criado antes de uma nova autorização do operador.
