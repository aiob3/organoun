---
document_type: domain_glossary
governed_by: urn:organoun:rfc:0001
governance_version: 1.1.0
governance_digest: sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586
execution_authority: false
---

# Organoun

O Organoun é o contexto de coordenação visível entre um operador humano e pares de agentes executados em paralelo. Ele existe para retirar do operador o trabalho mecânico de preparar conexões e transportar mensagens sem retirar sua observabilidade ou autoridade.

## Language

**Operador**:
A pessoa que inicia a intenção, observa a inicialização e conserva autoridade sobre alvo, escopo e ações mutantes. Durante a preparação, é observador — não mensageiro nem executor de comandos repetitivos.
_Avoid_: Entregador, piloto automático, usuário passivo

**Inicialização assistida e visível**:
A fase em que o Codex reconhece o contexto atual, prepara os pares e inicia as conexões enquanto o operador acompanha o processo em tempo real. Ela termina quando os pares esperados estão visíveis e prontos para receber uma intenção separadamente autorizada.
_Avoid_: Inicialização headless, automação autônoma, setup oculto

**Onboarding inicial**:
A configuração write-once de uma raiz local: recebe junto o projeto local, o host remoto e o CWD remoto, comprova a rota local e publica o deployment ignorado antes de qualquer evento paralelo. Componentes do plano de controle não são instalados no endpoint.
_Avoid_: Reinstalação a cada uso, bootstrap cego, cópia de credenciais, controlador remoto

**Deployment local**:
O estado estrito e não versionado que vincula uma raiz local a um endpoint e CWD explícitos. Ele fornece os insumos para inicializações recorrentes sem reenvio ou regravação.
_Avoid_: Configuração global, default do laboratório, manifesto remoto

**Organoun conectado**:
O estado em que a rota local do deployment foi validada e sua configuração foi publicada, sem alegar conexão remota e sem que pane, sessão ou dispatch tenha começado.
_Avoid_: Sessão inicializada, pane aberto, worker pronto

**Inicialização assistida recorrente**:
A retomada em que `organ init` carrega o deployment local válido, registra a Sessão Proprietária visível e somente então habilita os eventos subordinados. Se o deployment estiver ausente ou inválido, retorna ao onboarding sem criar pane.
_Avoid_: Onboarding completo, sessão permanente, execução headless

**Plano de controle único**:
O único núcleo de autoridade, estado e orquestração do Organoun, contido na Sessão Proprietária local. Nenhum endpoint ou pane subordinado pode criar, hospedar ou delegar outro plano de controle.
_Avoid_: Organoun distribuído, controlador remoto, orquestração multinível

**Sessão Proprietária**:
O ponto local e visível em que o Organoun é iniciado pela primeira vez e ao qual pertence com exclusividade a autoridade de dispatch. Sua perda bloqueia novas operações até recuperação explicitamente autorizada pelo operador.
_Avoid_: Pane mestre, controlador intercambiável, eleição automática

**Pane subordinado**:
Um espaço local, visível e pertencente à Sessão Proprietária, dedicado a exibir a conexão e a execução de um agente. Ele não possui autoridade de dispatch nem pode originar outro Organoun.
_Avoid_: Pane par autônomo, worker invisível, controlador secundário

**Endpoint de execução**:
O ambiente local ou remoto allowlisted em que Claude executa dentro de um diretório explícito, sem possuir estado ou componentes do plano de controle. Um endpoint recebe trabalho somente por um pane subordinado da Sessão Proprietária.
_Avoid_: Destino remoto gerenciado, host controlador, helper orquestrador

**Manifesto Operacional**:
A representação canônica e legível por máquina de uma única operação proposta, vinculada ao proprietário, alvo, efeitos e prova de observabilidade. Texto livre e comandos arbitrários não constituem um Manifesto Operacional.
_Avoid_: Prompt operacional, instrução implícita, comando sugerido

**Gate de Política Executável**:
O conjunto versionado de predicados determinísticos que decide se um Manifesto Operacional pode ser apresentado e executado. Uma recusa não é substituível por interpretação, autoridade verbal ou escolha do operador.
_Avoid_: Revisão por IA, aprovação por prosa, recomendação consultiva

**Prova de observabilidade**:
O vínculo entre um cliente local anexado, a exposição simultânea da Sessão Proprietária e do pane subordinado e uma atestação estruturada do operador para aquele layout. Ela comprova disponibilidade visual, não atenção física do operador.
_Avoid_: Suposição de visibilidade, pane oculto, execução headless

**Cenário visual**:
A comprovação de que a Sessão Proprietária foi reconhecida e de que um pane subordinado foi aberto, exibido e inicializado com sucesso. Não é prova de entrega de mensagem nem de resposta ponta a ponta.
_Avoid_: Canary de entrega, smoke hermético

**Fila assistida**:
Uma sequência ordenada de demandas visíveis que o Codex submete aos panes subordinados enquanto o operador acompanha recebimento e andamento. Não implica persistência, fanout automático ou um broker autônomo.
_Avoid_: Fila durável, fanout automático, processamento invisível

**Ponte**:
O mecanismo de coordenação que reduz setup e transporte manual entre o operador, o Codex e os pares, mantendo o processo observável.
_Avoid_: Autopilot, memória compartilhada, hierarquia entre agentes
