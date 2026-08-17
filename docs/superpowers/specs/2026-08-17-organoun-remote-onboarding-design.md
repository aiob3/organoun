---
document_schema_version: 1
document_type: invalid_historical_record
status: invalid
operator_approved: false
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
policy_baseline: false
---

# Organoun em endpoint remoto — onboarding e primeiro cenário remoto

**Data:** 2026-08-17

**Status:** inválido e não autorizado pelo operador; não executar nem usar como baseline

**Escopo:** primeiro uso remoto, assistido e visível, sem edição

> **Bloqueado:** este documento atribuiu incorretamente aprovação a uma hipótese distribuída formulada durante o experimento. Autorizações pontuais para comandos visíveis não aprovaram seus requisitos de `tmux`, Organoun, Outsourcerer, helper ou estado no host remoto. O documento é registro histórico inválido, não especificação e não instrução operacional.

## 1. Hipótese inválida registrada

O primeiro cenário remoto usará a opção 2: o operador acompanhará uma conexão SSH visível com `$ORGANOUN_REMOTE_HOST`, enquanto uma única demanda sintética será enviada pela interface real `organ` no host local, atravessará o helper remoto fixo e será processada por uma sessão Claude gerenciada na VPS.

O diretório remoto aprovado é exatamente `$ORGANOUN_REMOTE_CWD`. O cenário não tentará descobrir outro projeto, alterar arquivos ou escolher um fallback.

O fluxo separa duas responsabilidades:

1. **Onboarding inicial:** comprovar e preparar o que falta no host, uma única vez.
2. **Inicialização assistida recorrente:** repetir somente conexão, provisionamento, transporte, observação e encerramento nos usos seguintes.

### 1.1 Alternativas rejeitadas

- **SSH direto seguido de comandos `tmux`:** seria útil como diagnóstico, mas contornaria a CLI, o helper, os recibos e o roteamento que este cenário precisa comprovar.
- **Canário inteiramente headless:** testaria transporte, porém removeria a observabilidade que constitui o benefício operacional da ponte.
- **Instalar tudo novamente antes do inventário:** aumentaria risco e tempo, poderia sobrescrever estado válido e confundiria onboarding com inicialização recorrente.

Por isso, a conexão visual e o transporte real pela ponte são complementares no mesmo cenário; nenhum deles substitui o outro.

## 2. Contrato do destino

O alvo canônico desta comprovação é:

```json
{
  "alias": "remote-managed",
  "transport": "ssh",
  "host": "$ORGANOUN_REMOTE_HOST",
  "cwd": "$ORGANOUN_REMOTE_CWD",
  "mode": "managed",
  "provider": "cc",
  "session_name": "organoun-remote",
  "model": null
}
```

- `$ORGANOUN_REMOTE_HOST` é o único alias SSH autorizado para o cenário.
- `$ORGANOUN_REMOTE_CWD` é o diretório remoto exato; ausência, falta de leitura ou resolução diferente bloqueia o fluxo.
- `managed` permite encerrar somente a sessão cujo recibo Organoun comprova que foi criada pela ponte.
- `model: null` preserva o modelo padrão configurado no Claude; o Organoun não escolhe outro modelo por inferência.
- A mesma definição precisa existir na configuração usada pelo controlador e na configuração resolvida pelo helper remoto.

## 3. Experiência visual

O pane controlador local permanece visível. Ao lado dele, o Codex abre um pane par e inicia uma conexão SSH interativa com `$ORGANOUN_REMOTE_HOST`. Toda pré-etapa que afeta o host é apresentada nesse pane para que o operador veja onde está e o que está acontecendo.

O Codex executa o trabalho mecânico. O operador:

- confirma visualmente a conexão e o diretório;
- conclui autenticação ou trust quando uma interface de terceiros exigir decisão pessoal;
- observa o provisionamento e o processamento;
- conserva autoridade sobre qualquer ampliação ou mutação.

O aceite não é um teste headless. Checagens herméticas continuam úteis contra regressões, mas não substituem a atestação do operador nesta sessão.

## 4. Onboarding inicial

As etapas são discovery-first. Uma etapa já pronta pode ser marcada como satisfeita somente por evidência observada no host; não é reinstalada por rotina.

### 4.1 Autoridade e conexão

1. Confirmar localmente que o alias SSH resolve exatamente para `$ORGANOUN_REMOTE_HOST` e que existe identidade configurada.
2. Abrir o pane remoto visível.
3. Conectar sem imprimir IP, chave, token ou configuração sensível.
4. Exibir `hostname` sanitizado, `pwd -P` e comprovar que o diretório é exatamente `$ORGANOUN_REMOTE_CWD`.

### 4.2 Inventário remoto somente-leitura

Comprovar presença e versão suficiente de:

- `tmux`;
- `claude`;
- `organ`;
- `jq`, `git` e utilitários exigidos pelos scripts;
- helper executável em `~/.local/libexec/organoun/organ-remote`;
- checkout/install Organoun correspondente a um commit aprovado;
- Outsourcerer no commit pinado `3a788b8e072b915622fd80c6f8ecec64de659bd5`.

Nenhuma ausência autoriza instalação automática. O fluxo pausa, mostra o delta e segue somente com a autorização já aplicável ou uma nova decisão do operador.

### 4.3 Claude e trust

Se Claude não estiver autenticado, o operador conclui o login no terminal remoto. Tokens locais nunca são copiados, exportados ou exibidos. Se `$ORGANOUN_REMOTE_CWD` apresentar uma confirmação inicial de trust, a escolha é feita visivelmente; uma autorização persistida e observável não é refeita.

### 4.4 Instalação ausente

Quando Organoun ou Outsourcerer realmente estiver ausente:

1. empacotar somente um commit Organoun aprovado com `git archive`;
2. calcular e conferir SHA-256 nos dois lados;
3. extrair num diretório novo e qualificado pelo commit sob `~/.local/src/organoun/`;
4. executar os instaladores em dry-run visível;
5. aplicar somente após conferir destinos;
6. verificar os links instalados, o helper fixo e o pin do Outsourcerer;
7. configurar o target exato da seção 2 sem sobrescrever configuração divergente.

Não há sincronização do HOME, working tree, credenciais ou histórico local.

## 5. Primeiro cenário de funcionamento

Depois do onboarding satisfeito:

1. manter visíveis o pane controlador e o pane SSH remoto;
2. executar observações `status`/preflight sem criar sessão;
3. enviar uma única demanda sintética e somente-leitura por `organ dispatch remote-managed --mode read --stdin --json`;
4. no pane remoto, tornar visível a sessão `organoun-remote` criada pela ponte e o processamento Claude em `$ORGANOUN_REMOTE_CWD`;
5. acompanhar somente com `organ status` e `organ read`;
6. exigir uma resposta-canário exata, sem interpretar texto aproximado como sucesso;
7. se a entrega ficar `unknown`, não reenviar; usar somente `read`;
8. encerrar com `organ stop remote-managed --json`, após validar o recibo de posse da sessão gerenciada;
9. fechar o pane SSH e restaurar o layout local original.

A mensagem final será curta, inerte e sem ferramentas ou edição. Seu texto exato será fixado no plano de execução para permitir comparação byte a byte.

## 6. Critérios de aceite

O primeiro cenário remoto passa somente se o operador atestar, em sequência:

1. conexão visível com `$ORGANOUN_REMOTE_HOST`;
2. diretório remoto canônico exatamente `$ORGANOUN_REMOTE_CWD`;
3. dependências, helper e configuração comprovados ou preparados com onboarding visível;
4. uma única chamada de envio pelo caminho local `organ` → SSH → helper remoto;
5. nenhuma chamada para host diferente e nenhum fallback local;
6. sessão `organoun-remote` visível e possuída pela ponte;
7. uma única ocorrência da demanda e uma resposta-canário exata observável por `organ read`;
8. nenhum replay após estado ambíguo;
9. `stop` aplicado somente à sessão gerenciada;
10. pane remoto desprovisionado e layout original restaurado.

A evidência registra comandos, estados e marcadores sanitizados. Não registra IP, credenciais, tokens, transcrição integral ou conteúdo de outros projetos em `$ORGANOUN_REMOTE_CWD`.

## 7. Falhas fechadas e recuperação

- **SSH/Tailscale indisponível:** preservar `$ORGANOUN_REMOTE_HOST`, corrigir conexão e repetir apenas observações; nunca cair para local.
- **`$ORGANOUN_REMOTE_CWD` ausente ou divergente:** parar antes de configuração, criação de sessão ou envio.
- **Dependência ausente:** apresentar o delta e entrar no trecho de onboarding correspondente.
- **Login/trust necessário:** devolver o controle interativo ao operador.
- **Configuração divergente:** preservar o arquivo existente e mostrar a diferença; não mesclar nem sobrescrever silenciosamente.
- **Sessão com mesmo nome sem recibo válido:** tratar como colisão; não adotar nem parar.
- **Entrega incerta:** não repetir a obrigação; consultar apenas `read`.
- **Falha depois da criação:** tentar um único `stop` limitado somente quando o recibo prova posse; manter evidência do estado se a limpeza não puder ser comprovada.

## 8. Fora de escopo desta comprovação

- edição de arquivos em `$ORGANOUN_REMOTE_CWD`;
- `verify` ou `fetch` de artefatos;
- sessão adotada remota, `claim` ou `ask`;
- fanout, retry, fila durável ou operação sem operador;
- serviço público, daemon novo ou porta aberta;
- instalação automática recorrente;
- validação de todos os projetos contidos em `$ORGANOUN_REMOTE_CWD`.

Esses recursos permanecem evoluções posteriores. O objetivo agora é comprovar o caminho mínimo real e observável, sem transformar o primeiro teste num gate de produção completo.

## 9. Encerramento e registro

Ao final, será criado um registro de aceite remoto equivalente ao aceite local. Ele distinguirá:

- evidência do onboarding;
- evidência da inicialização recorrente;
- resultado do transporte ponta a ponta;
- limpeza comprovada;
- limitações honestamente pendentes.

O sucesso deste cenário autoriza usar a ponte remota de forma assistida dentro do mesmo contrato. Não autoriza edição, execução autônoma ou ampliação de host/diretório.
