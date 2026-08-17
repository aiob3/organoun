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

# Organoun Remote First Proof Implementation Plan

> **INVÁLIDO E NÃO AUTORIZADO — NÃO EXECUTAR.** Este plano inferiu aprovação arquitetural a partir de autorizações pontuais do experimento. O operador nunca aprovou seu plano de controle remoto. Ele permanece somente como registro do caminho interrompido e não é baseline, predecessor nem fonte de requisitos.

> O conteúdo imperativo abaixo é evidência histórica inerte. Nenhum agente deve tratá-lo como plano executável.

**Goal:** Comprovar, com o operador presente, uma demanda sintética enviada uma única vez pelo Organoun local para uma sessão Claude gerenciada e visível em `$ORGANOUN_REMOTE_HOST`, dentro de `$ORGANOUN_REMOTE_CWD`, seguida de leitura e desprovisionamento seguros.

**Architecture:** O pane controlador local permanece intacto; um pane lateral mantém a conexão SSH visível. O comando local `organ` resolve o target allowlisted, abre uma chamada SSH por ação e invoca o helper remoto fixo, enquanto sessão, receipt e job permanecem em `$ORGANOUN_REMOTE_HOST`. O onboarding é discovery-first: qualquer dependência ausente interrompe o canário antes de instalação ou envio.

**Tech Stack:** Bash, tmux local e remoto, OpenSSH/Tailscale, Claude Code, CLI `organ`, helper `organ-remote`, Outsourcerer `v0.8.2` no commit `3a788b8e072b915622fd80c6f8ecec64de659bd5`, jq.

## Global Constraints

- Operador e Codex permanecem juntos no pane controlador durante toda a execução live.
- Target exato: alias `remote-managed`, transporte `ssh`, host `$ORGANOUN_REMOTE_HOST`, cwd `$ORGANOUN_REMOTE_CWD`, modo `managed`, provider `cc`, sessão `organoun-remote`, modelo ausente/default.
- O primeiro cenário é somente-leitura; não editar arquivos em `$ORGANOUN_REMOTE_CWD` nem executar `verify`/`fetch`.
- Não copiar credenciais, tokens, configuração SSH integral, transcrição integral, IP ou conteúdo de outros projetos.
- Nunca escolher outro host, diretório, provider, modelo ou fallback local.
- Uma única tentativa de envio. `delivery=unknown` implica somente `read`, nunca replay.
- Encerrar apenas a sessão `managed` com receipt válido; nunca parar sessão preexistente ou sem posse comprovada.
- Se uma dependência ou configuração estiver ausente/divergente, pausar no checkpoint e apresentar o delta ao operador antes de escrever no host.
- Evidência de sucesso exige observação visual do operador e resposta exata `ORGANOUN_ASVERAS_CANARY_OK`.

---

### Task 1: Fixar controlador e preflight local

**Files:**
- Read: `docs/superpowers/specs/2026-08-17-organoun-remote-onboarding-design.md`
- Read: `config/deployment.example.json`
- Read: `~/.config/organoun/targets.json` somente por projeção sanitizada do alias `remote-managed`

**Interfaces:**
- Consumes: commit aprovado `a287dc9` e pane controlador já observado.
- Produces: identidade do pane controlador, disponibilidade local e target sanitizado ou um delta explícito.

- [ ] **Step 1: Confirmar commit e árvore limpa**

Run:

```bash
git -C $ORGANOUN_PROJECT_ROOT status --short --branch
git -C $ORGANOUN_PROJECT_ROOT merge-base --is-ancestor a287dc9 HEAD
```

Expected: branch `feat/organoun-bridge`, sem paths modificados e commit de desenho `a287dc9` ancestral do HEAD.

- [ ] **Step 2: Reconhecer o pane controlador sem capturar conteúdo**

Run:

```bash
tmux display-message -p '#{session_name}:#{window_index}.#{pane_index} #{pane_id} command=#{pane_current_command} cwd=#{pane_current_path}'
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_id} active=#{pane_active} command=#{pane_current_command} cwd=#{pane_current_path}'
```

Expected: um único pane controlador ativo antes do split; registrar seu `pane_id` sem ler a tela.

- [ ] **Step 3: Verificar somente presença local e resolução do alias**

Run:

```bash
command -v tmux
command -v ssh
command -v jq
command -v organ
ssh -G $ORGANOUN_REMOTE_HOST >/dev/null
```

Expected: todos os comandos retornam zero; `ssh -G` resolve a configuração sem abrir conexão.

- [ ] **Step 4: Projetar somente o target aprovado da configuração local**

Run:

```bash
jq -ce --arg alias remote-managed '
  first(.targets[] | select(.alias == $alias)) |
  {alias,transport,host,cwd,mode,provider,session_name,model}
' "${XDG_CONFIG_HOME:-$HOME/.config}/organoun/targets.json"
```

Expected:

```json
{"alias":"remote-managed","transport":"ssh","host":"$ORGANOUN_REMOTE_HOST","cwd":"$ORGANOUN_REMOTE_CWD","mode":"managed","provider":"cc","session_name":"organoun-remote","model":null}
```

Se o arquivo ou target estiver ausente/divergente, não corrigir ainda; registrar o delta para Task 3.

### Task 2: Abrir conexão visível e inventariar `$ORGANOUN_REMOTE_HOST`

**Files:**
- Read: metadados tmux locais
- Read: presença/versão de executáveis remotos
- Read: target remoto projetado sem outros aliases

**Interfaces:**
- Consumes: `PANE_CONTROLADOR` da Task 1 e alias SSH fixo `$ORGANOUN_REMOTE_HOST`.
- Produces: `PANE_ASVERAS` visível, cwd remoto comprovado e inventário `READY` ou `MISSING`.

- [ ] **Step 1: Criar um único pane lateral no cwd local neutro**

Run:

```bash
tmux split-window -h -t "$PANE_CONTROLADOR" -c $ORGANOUN_LOCAL_PARENT -P -F '#{pane_id}'
```

Expected: novo `PANE_ASVERAS`, controlador ainda visível, sem terceira divisão.

- [ ] **Step 2: Digitar e submeter a conexão no pane visível**

Run through `tmux send-keys` in two visible stages:

```text
ssh -t $ORGANOUN_REMOTE_HOST 'cd $ORGANOUN_REMOTE_CWD && exec "${SHELL:-/bin/bash}" -l'
```

Expected: operador vê o comando antes do Enter; shell remoto abre em `$ORGANOUN_REMOTE_CWD`.

- [ ] **Step 3: Comprovar host lógico e cwd sem dados sensíveis**

Run visibly in `PANE_ASVERAS`:

```bash
printf 'ORGANOUN_REMOTE_HOST=$ORGANOUN_REMOTE_HOST\nORGANOUN_REMOTE_CWD=%s\n' "$(pwd -P)"
test "$(pwd -P)" = $ORGANOUN_REMOTE_CWD
```

Expected: `ORGANOUN_REMOTE_HOST=$ORGANOUN_REMOTE_HOST`, `ORGANOUN_REMOTE_CWD=$ORGANOUN_REMOTE_CWD`, rc zero.

- [ ] **Step 4: Fazer inventário remoto somente-leitura**

Run visibly:

```bash
for name in tmux claude organ jq git; do
  if command -v "$name" >/dev/null 2>&1; then
    printf 'ORGANOUN_DEP_%s=READY\n' "$name"
  else
    printf 'ORGANOUN_DEP_%s=MISSING\n' "$name"
  fi
done
if test -x "$HOME/.local/libexec/organoun/organ-remote"; then
  printf 'ORGANOUN_REMOTE_HELPER=READY\n'
else
  printf 'ORGANOUN_REMOTE_HELPER=MISSING\n'
fi
tmux -V
claude --version
jq --version
git --version
```

Expected: todos os cinco executáveis e o helper imprimem `READY`; as quatro ferramentas versionadas respondem sem iniciar sessão nem revelar configuração sensível. O Outsourcerer possui pin exato na etapa seguinte; esta prova não inventa um piso de versão adicional para Claude, tmux, jq ou Git.

- [ ] **Step 5: Comprovar pin e target remoto por projeção**

Run visibly:

```bash
pin_dir="$HOME/.local/share/organoun/outsourcerer-3a788b8"
test "$(git -C "$pin_dir" rev-parse HEAD)" = 3a788b8e072b915622fd80c6f8ecec64de659bd5 &&
  printf 'ORGANOUN_OUTSOURCERER_PIN=READY\n'
jq -ce --arg alias remote-managed '
  first(.targets[] | select(.alias == $alias)) |
  {alias,transport,host,cwd,mode,provider,session_name,model}
' "${XDG_CONFIG_HOME:-$HOME/.config}/organoun/targets.json"
```

Expected: pin `READY` e o mesmo objeto exato da Task 1, Step 4.

### Task 3: Resolver somente lacunas comprovadas

**Files:**
- Modify only if absent and separately authorized: local and remote `~/.config/organoun/targets.json`
- Install only if absent and separately authorized: paths enumerated by `scripts/install-organoun.sh` and `scripts/install-outsourcerer.sh`

**Interfaces:**
- Consumes: deltas exatos das Tasks 1 e 2.
- Produces: ambos os targets idênticos e todas as dependências `READY`, ou encerramento limpo sem envio.

- [ ] **Step 1: Aplicar o gate de decisão**

Se tudo estiver `READY` e os targets forem byte-semanticamente iguais ao contrato, não escrever nada e avançar à Task 4.

Se houver qualquer ausência/divergência, mostrar o delta. A aprovação deste plano cobre somente a correção do target exato quando Organoun já estiver instalado; instalação de binário, autenticação ou substituição de arquivo divergente exige checkpoint visual e confirmação aplicável do operador:

```text
PAUSAR — listar apenas componente, estado esperado e estado observado; solicitar autorização específica antes de dry-run, instalação ou alteração de configuração.
```

Expected: nenhuma escrita implícita e nenhum canário antes de um novo `READY` comprovado.

- [ ] **Step 2: Revalidar depois de eventual correção autorizada**

Repetir exatamente Task 1 Step 4 e Task 2 Steps 4–5.

Expected: todos `READY`; targets local e remoto iguais ao contrato da spec.

### Task 4: Gate somente-leitura do transporte real

**Files:**
- Read: `scripts/smoke-remote.sh`
- Read: estado privado remoto somente através do helper

**Interfaces:**
- Consumes: onboarding `READY` e target idêntico nos dois lados.
- Produces: transporte real observável sem criar sessão ou enviar mensagem.

- [ ] **Step 1: Executar status pelo caminho real**

Run no host local:

```bash
organ status remote-managed --json
```

Expected: um único envelope JSON estrito para target `remote-managed`, host `$ORGANOUN_REMOTE_HOST`; `ok:true` ou erro fechado `state:unknown/unreachable`, sem fallback.

- [ ] **Step 2: Executar o smoke remoto somente-observação**

Run:

```bash
$ORGANOUN_PROJECT_ROOT/scripts/smoke-remote.sh
```

Expected: `ORGAN_ASVERAS_SMOKE_OK`. Qualquer outro resultado encerra antes do envio.

### Task 5: Despachar uma vez e observar visualmente

**Files:**
- Create at runtime: receipt/job privado remoto pelo Organoun
- No project file edits

**Interfaces:**
- Consumes: transporte read-only aprovado e sessão remota inexistente ou corretamente ausente.
- Produces: uma sessão gerenciada `organoun-remote`, uma tentativa de envio e resposta exata observável.

- [ ] **Step 1: Fixar a mensagem inerte**

Exact bytes:

```text
Teste remoto visual Organoun. Não use ferramentas e não leia nem altere arquivos. Responda exatamente: ORGANOUN_ASVERAS_CANARY_OK
```

- [ ] **Step 2: Fazer uma única chamada de dispatch**

Run:

```bash
printf '%s' 'Teste remoto visual Organoun. Não use ferramentas e não leia nem altere arquivos. Responda exatamente: ORGANOUN_ASVERAS_CANARY_OK' |
  organ dispatch remote-managed --mode read --stdin --json
```

Expected: envelope JSON de `dispatch`, host `$ORGANOUN_REMOTE_HOST`, um `job_id` qualificado e exatamente uma tentativa. Não repetir sob nenhum resultado.

- [ ] **Step 3: Tornar a sessão remota visível**

Run visibly in `PANE_ASVERAS`:

```bash
tmux attach-session -t organoun-remote
```

Expected: operador vê Claude processando no cwd `$ORGANOUN_REMOTE_CWD`; nenhuma sessão preexistente é adotada.

- [ ] **Step 4: Observar por status e read, sem replay**

Run no host local, em ciclos limitados:

```bash
organ status remote-managed --json
organ read remote-managed --json
```

Expected: o excerpt contém uma linha exatamente igual a `ORGANOUN_ASVERAS_CANARY_OK`. Estado ambíguo autoriza somente novos `read`, nunca novo `dispatch`.

- [ ] **Step 5: Obter atestação visual do operador**

Expected: operador confirma conexão, processamento, resposta exata e ausência de segunda submissão.

### Task 6: Desprovisionar e registrar o aceite

**Files:**
- Create: `docs/acceptance/2026-08-17-remote-first-proof.md`
- Modify: `docs/superpowers/plans/2026-08-17-organoun-remote-first-proof.md` para marcar os passos observados

**Interfaces:**
- Consumes: receipt gerenciado, `PANE_ASVERAS` e atestação da Task 5.
- Produces: sessão encerrada, layout restaurado e evidência sanitizada versionada.

- [ ] **Step 1: Parar somente a sessão possuída**

Run:

```bash
organ stop remote-managed --json
```

Expected: envelope `ok:true`, `state:stopped`; o attach remoto retorna ao shell. Sem receipt válido, não usar `tmux kill-session` como atalho.

- [ ] **Step 2: Encerrar SSH e desprovisionar o pane lateral**

Run visibly:

```bash
exit
```

Depois, por metadados locais, confirmar que `PANE_ASVERAS` terminou; se o shell permaneceu após SSH, matar somente esse pane pelo `pane_id` registrado.

Expected: apenas o pane controlador original permanece.

- [ ] **Step 3: Registrar evidência sanitizada**

O documento de aceite deve registrar:

- commit executado;
- target e cwd aprovados;
- estados `READY` sem paths ou credenciais adicionais;
- uma tentativa de dispatch e job ID redigido para prefixo/forma;
- marcador exato observado;
- atestação do operador;
- resultado do `stop` e restauração do layout;
- qualquer limitação ou etapa de onboarding que permaneça pendente.

- [ ] **Step 4: Verificar e versionar somente documentação**

Run:

```bash
git -C $ORGANOUN_PROJECT_ROOT diff --check
git -C $ORGANOUN_PROJECT_ROOT status --short
```

Expected: somente plano/aceite intencionais. Depois, commit separado:

```bash
git add docs/superpowers/plans/2026-08-17-organoun-remote-first-proof.md docs/acceptance/2026-08-17-remote-first-proof.md
git commit -m "docs: record $ORGANOUN_REMOTE_HOST first proof"
```
