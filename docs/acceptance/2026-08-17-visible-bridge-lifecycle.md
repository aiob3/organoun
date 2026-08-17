---
document_type: historical_acceptance_evidence
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
---

# Aceite live — lifecycle visual e fila assistida

**Data:** 2026-08-17
**Branch:** `feat/organoun-bridge`
**Base observada:** `ac762402a53f`
**Evidência:** metadados `tmux`, marcador sintético e atestação visual do operador na sessão interativa

## Resultado

O operador e o Codex comprovaram juntos o lifecycle visual da ponte. O Codex executou as ações mecânicas; o operador permaneceu com visão simultânea dos panes e atestou cada transição.

### Provisionamento simples

1. O pane controlador foi reconhecido como `tmux:1.1` (`%2`).
2. Um pane Claude lateral foi provisionado e exibido.
3. O trust inicial da worktree, já autorizado e persistido, permitiu abrir o compositor.
4. O operador confirmou visualmente a divisão.
5. O pane Claude foi desprovisionado.
6. O operador confirmou o retorno ao pane controlador único.

**Veredito:** PASS para provisionamento e desprovisionamento visual assistido.

### Dois pares e fila assistida

1. O Codex preservou o controlador à esquerda e provisionou Claude A (`%6`) e Claude B (`%7`) à direita.
2. Ambos abriram no compositor e o operador confirmou visualmente os dois panes.
3. A mesma demanda sintética, sem ferramentas nem edição, foi registrada numa fila assistida `A → B`.
4. O Codex tornou cada mensagem visível no compositor antes de submetê-la, primeiro em A e depois em B.
5. Cada pane recebeu uma única submissão e exibiu a resposta exata `ORGANOUN_DUAL_CANARY_OK`.
6. A verificação sanitizada encontrou o marcador na pergunta e na resposta de cada pane; o operador confirmou recebimento e andamento em sequência.
7. B e A foram desprovisionados em sequência.
8. O servidor `tmux` voltou a conter somente o controlador `%2`, e o operador confirmou o encerramento.

**Veredito:** PASS para distribuição sequencial, observável e assistida da mesma demanda a dois pares.

## O que este aceite comprova

- reconhecimento compartilhado do contexto atual;
- provisionamento e desprovisionamento dinâmicos de panes pares;
- inicialização simultaneamente visível ao operador;
- distribuição determinística `A → B` da mesma demanda;
- observabilidade do recebimento, processamento, resposta e encerramento;
- redução do trabalho manual do operador sem retirar sua autoridade.

## Limites honestos

Este aceite não comprova ainda:

- `organ claim/ask/release` contra o Claude real;
- recibo durável de entrega;
- fila persistente, retry ou fanout automático;
- isolamento e roteamento remoto na VPS `$ORGANOUN_REMOTE_HOST`.

A fila observada foi assistida pelo Codex e atestada pelo operador. Chamá-la de fila durável ou fanout automático seria ampliar a evidência além do que ocorreu.

## Próximos gates

1. Preservar este lifecycle visual como fluxo canônico de inicialização da skill Organoun.
2. Encapsular provisionamento e desprovisionamento sem esconder os panes do operador.
3. Corrigir os contratos reais do probe de compositor e do `release` pinado antes de repetir `organ ask`.
4. Definir uma fila explícita e auditável somente se persistência, concorrência ou retries se tornarem necessários.
5. Repetir a entrega ponta a ponta via CLI local com o operador presente.
6. Não reutilizar o onboarding remoto distribuído registrado nos documentos históricos inválidos. Um novo cenário remoto só poderá nascer da Constituição, usando pane subordinado local visível e `$ORGANOUN_REMOTE_HOST` exclusivamente como endpoint de execução.
