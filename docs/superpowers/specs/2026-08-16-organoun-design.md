---
document_type: historical_design
status: invalid-as-operational-baseline
historical_operator_approved: true
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
policy_baseline: false
---

# Organoun — design da ponte Codex ↔ Claude

**Data:** 2026-08-16

**Status:** desenho historicamente aprovado, hoje inválido como baseline operacional; a única autoridade é a [Constituição Organoun/RFC-0001](../../../.spec/constituicao.md)

**Escopo de uso:** pessoal, experimental e não comercial

## 1. Decisão

Construiremos o **Organoun**, uma ponte pequena para que Codex e Claude possam trocar observações, perguntas curtas e resultados sem transformar o usuário em mensageiro entre janelas.

O usuário continua sendo o piloto dos dois trabalhos. A ponte não cria uma hierarquia Codex → Claude nem permite conversas autônomas ilimitadas entre agentes.

O [Outsourcerer](https://github.com/alexgreensh/outsourcerer) será usado como barramento substituível para descoberta, leitura, despacho e condução de sessões. Uma camada nossa, fina e independente, uniformizará o acesso local e remoto. Nenhum código do projeto da autora será modificado ou copiado para dentro desta ponte.

```text
Você ⇄ Codex        Você ⇄ Claude
          \         /
            Organoun
      (ponte de coordenação)
     Outsourcerer por baixo
```

## 2. Problema

O fluxo atual é produtivo porque o usuário trabalha com Codex e Claude em paralelo. O atrito aparece quando um agente precisa conhecer a conclusão, a dúvida ou o artefato produzido pelo outro: o usuário precisa copiar, resumir e entregar o conteúdo manualmente.

A ponte deve retirar esse trabalho de entrega sem retirar do usuário o controle sobre prioridade, escopo, permissões e decisões.

## 3. Objetivos

1. Permitir que Codex localize e leia a saída recente da sessão Claude correta.
2. Permitir uma pergunta técnica curta à sessão Claude, dentro de um trabalho já autorizado.
3. Permitir que o usuário despache daqui uma nova tarefa Claude e acompanhe seu andamento.
4. Transportar resultados por resumo, caminho, artefato ou commit, evitando cópias extensas de conversa.
5. Oferecer a mesma experiência para uma sessão local e para uma sessão na VPS `$ORGANOUN_REMOTE_HOST`.
6. Falhar de forma fechada quando sessão, destino, entrega ou autorização não puderem ser comprovados.
7. Manter o Outsourcerer substituível por um adaptador direto `Claude + tmux`.

## 4. Fora de escopo

- Autopilot ou decisão autônoma de quem deve executar uma tarefa.
- Conversas recursivas ou ilimitadas agente ↔ agente.
- Sincronização completa de históricos, skills, MCPs ou configurações.
- Painel web, banco de dados, daemon próprio ou novo servidor MCP.
- Fanout, loops, troca automática de modelos ou roteamento por custo.
- Manutenção, fork ou revisão geral do repositório Outsourcerer.
- Uso em produção, para clientes ou com finalidade comercial.
- Alteração simultânea do mesmo working tree por Codex e Claude.
- Motor completo de anti-evasão com fila autônoma de desafios, varredura AST por linguagem, mutation testing obrigatório ou CI próprio.

## 5. Princípios operacionais

### 5.1 O usuário é o piloto

O usuário pode conversar diretamente com os dois agentes. Codex pode ler ou fazer uma pergunta curta quando isso servir ao trabalho já autorizado. Nova tarefa, mudança de escopo, custo, permissão sensível ou decisão de produto volta ao usuário.

### 5.2 Inicialização assistida e visível

Um fluxo live é normalmente demandado pelo operador em conjunto com o Codex. O Codex reconhece o pane controlador, abre os panes pares e inicia as conexões em paralelo enquanto o operador observa a tela e conserva autoridade. O objetivo é retirar do operador o trabalho mecânico de setup e delivery, não retirar sua visibilidade.

O primeiro cenário de aceitação termina quando o pane controlador e o pane Claude estão visíveis, identificados e prontos. Ele é uma prova de inicialização da ponte, não uma alegação de entrega ponta a ponta. Testes herméticos apoiam esse contrato, mas não substituem a comprovação acompanhada.

### 5.3 Observação antes de intervenção

`status` e `read` são operações padrão. Escrever em uma sessão existente exige vínculo explícito ao painel correto, `claim` válido e confirmação de que o compositor está disponível.

### 5.4 Uma ponte, não uma memória compartilhada

Somente a saída recente e necessária cruza a ponte. Transcrições não são copiadas integralmente. O resultado do outro agente é tratado como dado não confiável, nunca como autorização automática para executar comandos.

### 5.5 Sem entrega presumida

Se a conexão cair durante um envio e não houver comprovante, o estado será `delivery-unknown`. A ponte não repetirá a mensagem automaticamente.

## 6. Arquitetura

```text
Linguagem natural no Codex
           │
       skill Organoun
           │
        CLI `organ`
      ┌────┴─────┐
      │          │
 transporte   transporte
   local      SSH/Tailscale
      │          │
 adaptador    helper remoto
 Outsourcerer    │
      │       adaptador Outsourcerer
 Claude/tmux     │
              Claude/tmux
```

### 6.1 Skill Organoun do Codex

Traduz intenções como “veja o Claude”, “pergunte ao Claude” e “despache isso” para chamadas explícitas da CLI. Aplica as regras de autoridade e pede seleção quando houver ambiguidade. A skill `organoun` só será criada depois que o fluxo manual da CLI passar no smoke test.

### 6.2 CLI `organ`

É um roteador, não um orquestrador. Valida ação, alias e host; recebe mensagens por `stdin`; seleciona transporte; chama o adaptador; normaliza estado, saída e erros em JSON.

Não usará `eval`, shell montado a partir de texto do usuário ou host arbitrário.

### 6.3 Registro de destinos

O arquivo do usuário ficará em `~/.config/organoun/targets.json`. Um exemplo sem dados privados ficará versionado no repositório Organoun.

Cada destino contém somente:

- alias;
- transporte `local` ou `ssh`;
- host permitido (`local` ou `$ORGANOUN_REMOTE_HOST`);
- diretório de trabalho;
- modo `managed` ou `adopted`;
- provider `cc` para sessões Claude gerenciadas;
- modelo opcional; ausente significa usar o default configurado do Claude;
- nome da sessão gerenciada ou painel `tmux` adotado;
- identificador da sessão Claude, quando ele puder ser comprovado.

Tokens de `claim`, credenciais e transcrições não entram nesse arquivo.

O MVP rejeita provider diferente de `cc`. Um modelo só é passado ao Outsourcerer quando estiver explicitamente presente no target; Organoun nunca troca o modelo por inferência.

Claims ativos ficam em `~/.local/state/organoun/claims/<alias>.json`, com diretório `0700` e arquivo `0600`. O registro contém somente o identificador externo, a identidade do controlador, o endpoint e o token necessário para autorizar `ask/release`; ele nunca é emitido no JSON público da CLI. A geração do claim continua sob autoridade do próprio Outsourcerer e não é duplicada pela ponte.

Sessões gerenciadas possuem ainda um recibo privado em `~/.local/state/organoun/sessions/<alias>.json`. Depois de criar a sessão, Organoun registra nome, cwd, painel, PID e identidade de início do processo. Antes de enviar ou encerrar, revalida essa identidade. Uma sessão `tmux` preexistente com o mesmo nome, mas sem recibo válido de posse, causa colisão e nunca é adotada implicitamente.

Jobs ficam em `~/.local/state/organoun/jobs/<job-id>.json`, sob as mesmas permissões privadas. O identificador é qualificado pelo host no formato `<host>.job-<timestamp>-<nonce>`, por exemplo `local.job-20260816T120000Z-a1b2c3d4` ou `$ORGANOUN_REMOTE_HOST.job-20260816T120000Z-a1b2c3d4`. `verify` aceita somente os hosts registrados `local` e `$ORGANOUN_REMOTE_HOST` e usa esse prefixo para rotear a chamada, sem criar um segundo cadastro local de jobs remotos. Para modo `edit`, o recibo registra target, commit-base, worktree, caminhos permitidos, comando de verificação, estado e artefatos; o prompt integral não é persistido.

### 6.4 Adaptador Outsourcerer

Usará somente o subconjunto necessário:

- `fleet ls/show --json` para descoberta e inspeção;
- `session start/read/send` para sessões gerenciadas;
- `session claim/reply/release` para sessões existentes;
- `status/result` para jobs destacados.

Recursos incompletos ou fora do objetivo, como `fleet tell/adopt`, autopilot, fanout e completion events, não serão usados.

Para uma sessão adotada, `read` usará `fleet show` quando o identificador Claude estiver comprovado. Se a descoberta não conseguir fazer esse vínculo, a ponte poderá capturar uma janela limitada do painel `tmux` explicitamente registrado. Esse fallback é somente-leitura e nunca escolhe painel por aproximação.

A escrita experimental em sessões externas requer `OSRC_EXTERNAL_SEND=1`. Essa variável será definida somente no processo do comando `claim/reply`; não será exportada globalmente no shell do usuário. Organoun fornecerá um probe mínimo e conservador para comprovar que o compositor Claude registrado está vazio. Sem um receipt probe independente, uma mensagem digitada continua sendo reportada como `delivery=unknown`; a ponte faz somente uma chamada e usa `read` para observação, nunca replay automático. Um receipt probe opcional só será aceito por caminho executável configurado pelo operador.

O mesmo princípio vale para sessões gerenciadas: a confirmação criptograficamente ou semanticamente forte não será inventada a partir de `tmux send-keys`. Quando o backend informar envio sem recibo independente, Organoun preservará `delivery=unknown` e seguirá apenas com leitura.

### 6.5 Transporte remoto

O destino `$ORGANOUN_REMOTE_HOST` executará um helper fixo por Tailscale SSH. A solicitação será enviada por `stdin`; o helper aceitará apenas verbos conhecidos e responderá com JSON. Credenciais, estado do Outsourcerer e tokens de `claim` permanecem na VPS.

Não haverá porta pública, serviço residente ou sincronização automática de diretórios.

## 7. Interface

```text
organ list [--json]
organ status <alias> [--json]
organ read <alias> [--json]
organ claim <alias> [--json]
organ ask <alias> --stdin [--json]
organ dispatch <alias> --mode read --stdin [--json]
organ dispatch <alias> --mode edit --worktree <absolute-path> --allow <relative-path>... --verify <command> --stdin [--json]
organ verify <job-id> [--json]
organ fetch <job-id> <artifact-id> [--stdout] [--json]
organ release <alias> [--json]
organ stop <alias> [--json]
```

O usuário não precisará memorizar esses comandos; eles são o contrato entre a skill e a ponte.

`dispatch` aceita somente destino `managed`; para continuar uma sessão já adotada usa-se `claim` uma vez e depois `ask`. `claim/release` aceitam somente destino `adopted`, e `stop` aceita somente sessão `managed` criada pela ponte. Em `--mode edit`, `--worktree`, ao menos um `--allow` e `--verify` são obrigatórios; caminhos permitidos são relativos ao worktree e não podem conter `..`. `status` nunca executa verificações; a aceitação de um job de edição ocorre somente por `verify` explícito. Depois da aceitação, arquivos regulares realmente alterados sob o escopo permitido recebem IDs opacos no manifesto do job; `fetch` não aceita caminho cru.

### 7.1 Resposta normalizada

Toda ação em modo JSON retornará um objeto com:

- `schema_version`;
- `ok`;
- `action`;
- `target`;
- `host`;
- `state` (`unknown`, `idle`, `working`, `waiting`, `done`, `stopped`, `unreachable`, `delivery-unknown`, `accepted`, `blocked-scope` ou `blocked-verification`);
- `delivery` (`not-applicable`, `confirmed`, `blocked` ou `unknown`);
- `data`, objeto com o conteúdo específico da ação, incluindo `excerpt`, `job_id` e `artifacts` quando existirem;
- `error.code` e `error.message`, em falha.

O JSON nunca conterá token de `claim`, credencial ou comando secreto.

Cada artefato será identificado por `host`, caminho restrito ao diretório autorizado, tamanho e, quando aplicável, commit Git. Em destino remoto, `fetch` fará leitura controlada por SSH; o usuário não precisará copiar o arquivo entre janelas. Payloads de pergunta serão limitados a 16 KiB e trechos de leitura a 64 KiB.

## 8. Modos e estados de sessão

### 8.1 Sessão existente (`adopted`)

```text
unbound → observed → claimed → idle/working/waiting → released
```

- `observed` permite leitura limitada.
- `claimed` permite resposta autenticada.
- Reinício do painel ou mudança de PID invalida o `claim`.
- `stop` é proibido para sessão adotada; a ponte somente a libera.

### 8.2 Sessão criada pela ponte (`managed`)

```text
absent → started → idle/working/waiting → done/stopped
```

- A ponte pode ler, enviar e encerrar a sessão que criou.
- Sessões diferentes usam nomes `tmux` diferentes.
- Trabalho de edição exige repositório e worktree explícitos.

## 9. Fluxos

### 9.1 Acompanhar o Claude que o usuário já está conduzindo

1. O usuário diz “veja o retorno do Claude do ONP”.
2. Codex resolve o alias; se houver mais de um candidato, pede seleção.
3. `organ read` retorna somente a saída recente.
4. Se a informação for suficiente, Codex continua o trabalho.
5. Se faltar um detalhe objetivo dentro do escopo atual, `organ ask` envia uma pergunta curta.
6. Codex lê a resposta e apresenta ao usuário a síntese e o impacto.

### 9.2 Despachar uma tarefa a partir do Codex

1. O usuário fornece a intenção.
2. Codex define destino, modo, repositório, escopo e critério de conclusão.
3. Organoun inicia uma sessão gerenciada e envia o trabalho.
4. Codex acompanha por leitura/polling enquanto estiver no turno ativo.
5. Uma dúvida dentro do escopo pode ser respondida; ampliação volta ao usuário.
6. Claude devolve resumo, verificações e referências aos artefatos.
7. Codex verifica o resultado proporcionalmente ao risco e entrega o desfecho.

Sem completion events, um job destacado preserva seu estado no host, mas não acorda sozinho uma conversa Codex ociosa. Durante um turno ativo, Codex acompanha por polling; entre turnos, o próximo `status/read` retoma o acompanhamento.

### 9.3 Executar na `$ORGANOUN_REMOTE_HOST`

O mesmo fluxo é usado, mas a CLI seleciona o transporte SSH. Falha de rede não muda de destino, não cai silenciosamente para local e não repete envios incertos.

## 10. Autoridade por ação

| Ação | Regra |
|---|---|
| `list`, `status`, `read` | Permitida para acompanhar trabalho colocado em escopo |
| `fetch` | Leitura de artefato declarado, restrita ao diretório autorizado |
| `claim` | Exige uma sessão adotada e intenção explícita de permitir respostas pela ponte |
| `ask` | Uma pergunta técnica curta dentro do escopo autorizado |
| `dispatch` | Exige intenção do usuário para abrir novo trabalho |
| `edit` | Exige repositório e escopo de escrita explícitos |
| `verify` | Audita o recibo de um job de edição e executa a verificação definida pelo controlador |
| `release` | Permitida para devolver uma sessão adotada ao controle exclusivamente manual |
| `stop` | Somente sessão criada pela ponte; nunca uma sessão adotada |
| mudança de modelo/permissão | Sempre explícita ou previamente autorizada |

## 11. Segurança e confiança

- Alias e hosts vêm de uma allowlist; não há SSH para host fornecido no prompt.
- Mensagens são transportadas por `stdin`, não interpoladas em comandos de shell.
- Saída de transcrição é delimitada e tratada como dado não confiável.
- `claim` requer identidade durável do controlador e token protegido no host da sessão.
- Compositor ocupado ou estado desconhecido bloqueia escrita.
- Entrega incerta nunca é repetida automaticamente.
- Logs registram metadados e resultado, não credenciais nem histórico integral.
- Codex e Claude não editam o mesmo working tree simultaneamente.
- A ponte não concede permissões além das já autorizadas pelo usuário.

### 11.1 Guard rail mínimo contra autoatestação

A `SPEC-002-organoun-anti-cheat-model-guard-rail.md` informa este recorte, mas não faz parte do runtime inicial. Organoun aplicará quatro invariantes no MVP:

1. `done`, `success` ou testes relatados pelo agente são alegações, não prova de conclusão.
2. Antes de `dispatch --mode edit`, o controlador valida `--worktree`, registra o commit-base e normaliza cada `--allow`. Mudança fora desse escopo invalida a entrega.
3. Depois que o agente devolve o controle, Codex chama `organ verify <job-id>`, que inspeciona o diff e executa o comando `--verify` no worktree. Arquivos de teste ou harness são protegidos, salvo quando o escopo autorizado exigir explicitamente modificá-los.
4. Organoun não inicia retries automáticos. Cada correção é uma nova ação explícita do controlador, ainda limitada pelo escopo original; ampliação volta ao usuário.

Esse guard rail separa quem produz de quem aceita sem transformar a ponte em um juiz autônomo de código.

## 12. Tratamento de falhas

| Situação | Comportamento |
|---|---|
| Alias ausente ou ambíguo | Falha fechada; nenhuma sessão é escolhida por aproximação |
| Sessão não comprovada | Somente observação, sem escrita |
| Compositor ocupado | `delivery=blocked`; mensagem não é digitada |
| Painel reiniciado | `claim` inválido; exige nova adoção |
| SSH indisponível em operação somente-leitura | `state=unreachable`; sem fallback local |
| Operação mutante sem resposta final válida do helper | `delivery=unknown`; sem presumir que falhou cedo e sem retry automático |
| Pedido de permissão fora do escopo | Volta ao usuário |
| Artefato não encontrado | Resultado incompleto; não é declarado concluído |
| Working tree compartilhado | Edição recusada até fornecer worktree isolado |

## 13. Licença e suporte

O experimento é pessoal, de pesquisa e teste, sem finalidade comercial prevista. Esse uso se enquadra na seção “Personal Uses” da PolyForm Noncommercial 1.0.0 usada pelo Outsourcerer.

A licença regula permissão de uso; ela não cria obrigação de suporte. O software é fornecido “as is”, sem garantia. A ponte, portanto:

- não pressupõe suporte da autora;
- não modifica nem redistribui o repositório dela;
- fixa uma versão ou commit validado;
- mantém o backend substituível;
- interrompe a adoção e reavalia a licença se o uso se tornar comercial.

O pin inicial do experimento será `v0.8.2` no commit `3a788b8e072b915622fd80c6f8ecec64de659bd5`, que é exatamente o código sobre o qual os testes focados foram executados. O pin não representa uma declaração de saúde geral do projeto; cada atualização exige repetir o nosso conjunto de testes.

## 14. Implantação gradual

1. Fixar a versão/commit do Outsourcerer e executar os testes focados do subconjunto adotado.
2. Instalar localmente sem alterar instruções globais do Codex.
3. Fazer smoke test somente-leitura e vincular explicitamente a sessão local correta.
4. Com o usuário presente, executar mensagem-canário única e liberar o `claim`.
5. Testar uma sessão local gerenciada de ponta a ponta.
6. Criar a skill do Codex somente após o fluxo manual funcionar.
7. Instalar e autenticar Claude na `$ORGANOUN_REMOTE_HOST`, com o usuário concluindo a autenticação interativa; instalar o mesmo backend e helper remoto.
8. Executar smoke test remoto somente-leitura e depois uma sessão gerenciada.
9. Validar o fluxo com uma tarefa real pequena e sem escrita.

O painel `tmux:1.3` observado durante o desenho é apenas um candidato transitório. A implantação deve confirmar novamente a identidade da sessão; esse valor não será gravado cegamente.

Como linha de base, 24 testes focados passaram no pin escolhido: descoberta externa, claims, autorização entre invocações, bloqueio de compositor desconhecido, comprovante contra replay e classificação/leitura de painel. Um ensaio real somente-leitura encontrou 27 registros externos, todos com estado `unknown`; isso comprova a necessidade do vínculo explícito e não será reinterpretado como descoberta confiável de atividade.

## 15. Testes de aceite

1. `status/read` identifica e lê a sessão local correta sem carregar o histórico completo.
2. Uma mensagem-canário chega exatamente uma vez à sessão adotada.
3. Envio com compositor ocupado é bloqueado sem digitar conteúdo.
4. Replay da mesma obrigação é recusado.
5. Reinício do painel invalida o vínculo anterior.
6. `claim` cria estado privado com permissões `0700/0600`, sem expor o token na saída pública.
7. Depois de `release`, a ponte não escreve na sessão adotada e o estado privado é removido.
8. Uma sessão gerenciada pode ser iniciada, conduzida e encerrada sem afetar a sessão manual.
9. Uma sessão adotada nunca é encerrada por `stop`.
10. O mesmo ciclo gerenciado funciona na `$ORGANOUN_REMOTE_HOST` por Tailscale SSH.
11. Perda de rede durante envio não gera duplicação.
12. Uma tarefa pequena retorna resumo, verificações e artefato sem cópia manual do usuário.
13. Um artefato remoto pertencente a um job aceito pode ser lido pela ponte por ID opaco, sem aceitar caminho cru ou fora do diretório autorizado.
14. A skill escolhe o alias correto ou pede seleção quando houver ambiguidade.
15. Uma tarefa de edição é recusada sem repositório e worktree explícitos.
16. Nenhum token, credencial ou transcrição integral aparece no JSON ou nos logs.
17. Um agente que apenas declara `done` não é aceito sem inspeção do diff e verificação do controlador.
18. Alteração em caminho protegido fora do escopo invalida a entrega, mesmo que os testes relatados passem.
19. Falha de verificação não dispara nova tentativa automaticamente.
20. `status` de um job de edição nunca executa o comando de verificação; somente `verify` pode mudar seu estado para aceito ou bloqueado.
21. Um `job-id` qualificado como `$ORGANOUN_REMOTE_HOST` é verificado somente na VPS, enquanto host ausente ou não permitido é recusado antes de qualquer execução.
22. Uma sessão `tmux` preexistente com o mesmo nome de um target gerenciado não é enviada nem encerrada sem um recibo Organoun cuja identidade de processo ainda seja válida.

## 16. Rollback

1. Liberar todos os `claims` ativos.
2. Encerrar somente sessões criadas pela ponte.
3. Desabilitar/remover a skill e a CLI próprias.
4. Remover a configuração do usuário e o helper remoto.
5. Desinstalar o Outsourcerer, se desejado, sem tocar nas instalações independentes de Claude ou Codex.

Nenhuma etapa de rollback depende de alterar o repositório da autora.

## 17. Estudo relacionado de anti-evasão

O estudo preliminar `$ORGANOUN_PROJECT_ROOT/spec/SPEC-002-organoun-anti-cheat-model-guard-rail.md` permanece não normativo para o MVP.

Foram incorporados o princípio de autoridade de verificação separada, o gate de diff/escopo e o limite contra loops automáticos. Foram adiados:

- `chmod 444` como suposta imutabilidade, pois permissão de arquivo isolada não protege contra um agente com o mesmo proprietário;
- detecção AST de variáveis de CI, que é específica por linguagem, sujeita a falsos positivos e contornável;
- mutation testing obrigatório e threshold fixo de `0.85`, cujo custo e valor dependem de cada repositório;
- fila autônoma de desafios, circuit breaker e protocolo `C → EOF`, que constituem um executor/verificador separado.

Se Organoun evoluir de ponte para harness autônomo, esse conjunto deve receber uma SPEC e um ciclo de implementação próprios.

## 18. Alternativas consideradas

### Outsourcerer puro

É o caminho mais curto localmente, mas não uniformiza `local` e `$ORGANOUN_REMOTE_HOST`, expõe diferenças de saída e acopla a interface do Codex diretamente ao backend.

### Ponte própria completa

Ofereceria controle total, mas recriaria descoberta, supervisão e condução `tmux` já desenvolvidas. Foi rejeitada por complexidade desnecessária.

### Roteador fino com backend substituível — escolhido

Reutiliza a interface madura do Outsourcerer, acrescenta apenas seleção de host, contrato estável e limites de segurança. Se o backend deixar de servir, o adaptador direto `Claude + tmux` pode substituí-lo sem mudar a experiência do usuário ou a skill.

## 19. Definição de pronto do experimento

O experimento Organoun estará pronto quando todos os testes de aceite aplicáveis ao local e à `$ORGANOUN_REMOTE_HOST` passarem e o usuário puder dizer “olhe”, “pergunte” ou “despache” sem copiar conteúdo entre janelas, recebendo de volta estado, resposta e referência aos artefatos, enquanto mantém o controle sobre ambos os agentes.
