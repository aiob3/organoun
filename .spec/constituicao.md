# Constituição Organoun — RFC-0001 v1.1.0

Este é o único documento normativo do Organoun. O texto explicativo auxilia a leitura humana; a autoridade operacional é o bloco estruturado e os princípios `P-xxx [DEVE]`, todos sujeitos a verificação executável pelo ONP-SPEC.

<!-- ORGANOUN_CONSTITUTION_POLICY_BEGIN -->
```json
{
  "schema_id": "urn:organoun:schema:constitution-policy:v1",
  "schema_version": 1,
  "policy_id": "urn:organoun:rfc:0001",
  "rfc_id": "RFC-0001",
  "constitution_id": "organoun-constitution",
  "version": "1.1.0",
  "canonical_path": ".spec/constituicao.md",
  "integrity": {
    "algorithm": "sha256",
    "canonicalization": "jq-sort-keys-compact",
    "digest_scope": "policy-object-with-integrity.self_digest-omitted",
    "self_digest": "sha256:fc567587c7edcdee3f1b431003d00e60d72ed8f9249769b993dc2c73092d4586"
  },
  "approval": {
    "design_record": "confirmed-in-session",
    "written_approval_receipt": "required",
    "receipt_must_match": [
      "constitution_id",
      "constitution_version",
      "constitution_digest"
    ],
    "policy_self_authorizes": false
  },
  "execution_authority": {
    "default": "deny",
    "derivation": "all-required-evidence",
    "required_evidence": [
      "written-constitution-approval-receipt",
      "constitutional-review-pass",
      "onp-spec-verify-pass",
      "onp-spec-audit-ci-pass"
    ]
  },
  "scope": [
    "organoun-control-plane",
    "parallel-session-initialization",
    "local-and-remote-agent-lifecycle",
    "operational-presentation",
    "observability",
    "git-promotion"
  ],
  "authority": {
    "operator_role": "pilot",
    "control_plane_count": 1,
    "owner_kind": "local-owner-session",
    "only_dispatcher": "owner-session",
    "automatic_owner_election": false,
    "operator_override_of_invariants": false
  },
  "topology": {
    "allowed": "one-local-owner-with-direct-local-subordinate-panes",
    "remote_role": "execution-endpoint-only",
    "remote_control_components": [],
    "nested_dispatch": false,
    "distributed_state": false,
    "remote_host_is_control_plane": false,
    "ssh_transport_role": "local-subordinate-pane-to-execution-endpoint",
    "remote_ssh_dispatcher": false,
    "remote_runtime_requirements": [
      "authorized-ssh-transport",
      "authenticated-claude",
      "explicit-target-directory"
    ]
  },
  "observability": {
    "default": "deny",
    "layout_reservation_effect": "local-empty-pane-only",
    "session_entry_requires": [
      "operator-client-attached",
      "owner-window-active",
      "owner-pane-visible",
      "subordinate-pane-visible",
      "layout-digest-matches",
      "single-use-operator-attestation"
    ],
    "revalidate_before": [
      "session-entry",
      "session-send",
      "session-close",
      "layout-release"
    ],
    "on_loss": "deny-new-effects-without-hidden-fallback",
    "physical-attention_inference": false
  },
  "initialization": {
    "deployment_path": ".organoun/deployment.json",
    "state_path": ".organoun/state",
    "state_machine": [
      "UNCONFIGURED",
      "ONBOARD_INPUT_RECEIVED",
      "DEPLOYMENT_VALIDATED",
      "CONNECTIVITY_OK",
      "DEPLOYMENT_PUBLISHED",
      "CONNECTED",
      "INITIALIZED"
    ],
    "onboard_submission_count": 1,
    "onboard_write_count": 1,
    "onboard_retry": false,
    "init_loads_deployment": true,
    "parallel_effects_require": "INITIALIZED",
    "missing_or_invalid_deployment": "ONBOARD_REQUIRED",
    "runtime_state_scope": "deployment-local"
  },
  "policy": {
    "default": "deny",
    "combiner": "all",
    "required_predicates": [
      "constitution-loaded-first",
      "constitution-self-valid",
      "manifest-strict",
      "deployment-strict",
      "deployment-digest-matches",
      "initialization-state-is-initialized",
      "owner-alive",
      "origin-is-owner",
      "controller-observable",
      "single-control-plane",
      "target-allowlisted",
      "execution-endpoint-only",
      "adapter-allowlisted",
      "no-remote-control-components",
      "no-nested-dispatch",
      "lifecycle-invariants-hold",
      "visibility-policy-satisfied",
      "manifest-unchanged"
    ],
    "action_policy": {
      "layout.reserve": {
        "visibility": "owner-visible",
        "requires_owned_pane": false,
        "endpoint_effect": false
      },
      "session.enter": {
        "visibility": "owner-and-target-attested",
        "requires_owned_pane": true,
        "endpoint_effect": true
      },
      "session.observe": {
        "visibility": "owner-and-target-visible",
        "requires_owned_pane": true,
        "endpoint_effect": false
      },
      "session.send": {
        "visibility": "owner-and-target-attested",
        "requires_owned_pane": true,
        "endpoint_effect": true
      },
      "session.close": {
        "visibility": "owner-and-target-attested",
        "requires_owned_pane": true,
        "endpoint_effect": true
      },
      "layout.release": {
        "visibility": "owner-and-target-attested",
        "requires_owned_pane": true,
        "endpoint_effect": false
      }
    }
  },
  "operator_event": {
    "schema_version": 1,
    "event": "operator.authorize-visible-operation",
    "required_fields": [
      "operation_id",
      "owner_id",
      "operator_client_id",
      "manifest_digest",
      "layout_digest",
      "attestation_nonce"
    ],
    "free_text_authorization": false,
    "single_use": true
  },
  "pre_presentation_review": {
    "required": true,
    "reviewer": "codex",
    "verdict_required": "eligible-for-operator",
    "unresolved_findings_required": 0,
    "receipt_required_fields": [
      "constitution_id",
      "constitution_version",
      "constitution_digest",
      "artifact_digest",
      "reviewer",
      "verdict",
      "unresolved_findings"
    ],
    "review_authorizes_execution": false
  },
  "document_governance": {
    "read_order": [
      ".spec/constituicao.md",
      "requested-derived-document"
    ],
    "protected_paths": [
      "CONTEXT.md",
      "docs/operations.md",
      "docs/acceptance/**/*.md",
      "docs/adr/**/*.md",
      "docs/superpowers/specs/**/*organoun*.md",
      "docs/superpowers/plans/**/*organoun*.md",
      "skills/organoun/**/*.md"
    ],
    "required_binding_fields": [
      "governed_by",
      "governance_version",
      "governance_digest",
      "execution_authority"
    ],
    "missing_or_stale_binding": "deny",
    "derived_document_can_override": false
  },
  "lifecycle_invariants": {
    "claim_required_for_adopted_reply": true,
    "stop_adopted": false,
    "replay_unknown_delivery": false,
    "independent_verify_required": true,
    "provider_and_model_must_be_explicit": true
  },
  "promotion": {
    "repository_id": "github.com/aiob3/organoun",
    "source_root_ref": "deployment.local_project_root",
    "source_branch": "main",
    "destination_branch": "main",
    "remote_branch": "main",
    "authorized_git_operations": [
      "commit",
      "fetch",
      "pull-ff-only",
      "merge",
      "push",
      "sync-verify"
    ],
    "force_push": false,
    "push_tags": false,
    "push_other_branches": false,
    "required_conditions": [
      "written-constitution-approved",
      "constitutional-review-pass",
      "unresolved-findings-zero",
      "onp-spec-verify-pass",
      "onp-spec-audit-ci-pass",
      "reviewed-diff-equals-current-diff",
      "main-base-equals-reviewed-main-base",
      "post-merge-audit-pass",
      "remote-main-fast-forward-safe",
      "remote-ref-equals-audited-main-after-push"
    ],
    "operational_state_after": "post-merge-audit-and-remote-sync-proved"
  },
  "denial_codes": [
    "GOVERNANCE_CONTEXT_REQUIRED",
    "CONSTITUTION_INVALID",
    "DOCUMENT_GOVERNANCE_STALE",
    "DISTRIBUTED_CONTROL_FORBIDDEN",
    "NESTED_ORCHESTRATION_FORBIDDEN",
    "REMOTE_CONTROL_COMPONENT_FORBIDDEN",
    "CONTROLLER_OWNERSHIP_REQUIRED",
    "CONTROLLER_OWNERSHIP_MISMATCH",
    "CONTROLLER_LOST",
    "TARGET_NOT_AUTHORIZED",
    "OPERATOR_CLIENT_NOT_ATTACHED",
    "CONTROLLER_PANE_NOT_VISIBLE",
    "TARGET_PANE_NOT_VISIBLE",
    "VISIBILITY_ATTESTATION_REQUIRED",
    "VISIBILITY_ATTESTATION_STALE",
    "OBSERVABILITY_LOST",
    "LIFECYCLE_INVARIANT_VIOLATION",
    "ONBOARD_ROOT_INVALID",
    "ONBOARD_REQUIRED",
    "DEPLOYMENT_ALREADY_EXISTS",
    "DEPLOYMENT_INVALID",
    "DEPLOYMENT_CHANGED",
    "ROUTE_INVALID",
    "INITIALIZATION_REQUIRED",
    "PARALLEL_EFFECT_BEFORE_INIT",
    "VISIBLE_PROTOCOL_ACTION_REQUIRED",
    "MANIFEST_INVALID",
    "PREOPERATIONAL_REVIEW_REQUIRED",
    "PROMOTION_SOURCE_NOT_AUTHORIZED",
    "PUSH_DESTINATION_NOT_CONFIGURED",
    "REMOTE_MAIN_DIVERGED",
    "PUSH_COMMIT_NOT_AUDITED",
    "FORCE_PUSH_FORBIDDEN"
  ]
}
```
<!-- ORGANOUN_CONSTITUTION_POLICY_END -->

## P-001 [DEVE] Todo requisito possui prova executável

Nenhuma feature, revisão ou promoção é declarada concluída sem prova mecânica e auditoria ONP-SPEC limpa.

- verificação(gate): intrínseca ao audit

## P-002 [DEVE] A Constituição é carregada antes de qualquer leitura Organoun

Toda leitura de documento derivado e toda ação operacional começa pela Constituição canônica e valida sua identidade, versão e integridade.

- verificação(teste): @principle:P-002

## P-003 [DEVE] Existe um único plano de controle

Somente a Sessão Proprietária local concentra autoridade, estado e orquestração; múltiplos controladores são proibidos.

- verificação(teste): @principle:P-003

## P-004 [DEVE] Somente a Sessão Proprietária realiza dispatch

Panes subordinados e endpoints não originam dispatch, não elegem sucessor e não herdam autoridade automaticamente.

- verificação(teste): @principle:P-004

## P-005 [DEVE] Endpoints são somente execução

O Organoun não instala, exige nem usa `tmux`, Organoun, Outsourcerer, helper, claims, jobs, receipts ou targets no endpoint para formar controle remoto.

- verificação(teste): @principle:P-005

## P-006 [DEVE] Ingresso e atuação em sessão exigem observabilidade comprovada

SSH, Claude e qualquer efeito de sessão somente começam ou continuam a receber novas ações quando owner e pane subordinado estão simultaneamente expostos ao operador no layout atestado.

- verificação(teste): @principle:P-006

## P-007 [DEVE] Toda operação nasce de Manifesto Operacional estrito

Opções e comandos livres não autorizam efeitos; o runtime aceita somente manifesto canônico, política `allow` e digest inalterado.

- verificação(teste): @principle:P-007

## P-008 [DEVE] Operação inválida não é apresentada ao operador

Antes de qualquer apresentação, a revisão Codex e o Gate de Política Executável precisam produzir os recibos requeridos sem achados pendentes.

- verificação(teste): @principle:P-008

## P-009 [DEVE] Perda do owner falha de forma fechada

Perda ou divergência da Sessão Proprietária bloqueia novas ações; recuperação exige rito separado e autorização explícita do operador.

- verificação(teste): @principle:P-009

## P-010 [DEVE] A revisão Codex integra o ciclo ONP-SPEC

A revisão constitucional ocorre depois do projeto e antes da apresentação ao operador; ela produz recibo estruturado, mas não substitui audit nem aprovação do operador.

- verificação(teste): @principle:P-010

## P-011 [DEVE] Documentos derivados não criam variantes constitucionais

Todo artefato protegido declara Constituição, versão, digest e ausência de autoridade própria; vínculo ausente ou obsoleto invalida sua leitura operacional.

- verificação(teste): @principle:P-011

## P-012 [DEVE] Somente a raiz autorizada pode ser promovida

A única origem de promoção é `deployment.local_project_root`, branch `main`, com destino local `main` depois de revisão e gates limpos.

- verificação(teste): @principle:P-012

## P-013 [DEVE] Sincronização Git usa somente o destino autorizado

Commit, pull fast-forward, merge, push e comprovação de sincronismo limitam-se a `github.com/aiob3/organoun`, branch `main`, sem force-push, tags ou outras branches.

- verificação(teste): @principle:P-013

## P-014 [DEVE] Invariantes de lifecycle não admitem override

Claim obrigatório, proibição de `stop` em sessão adotada, ausência de replay após entrega desconhecida, `verify` independente e provider/model explícitos permanecem vinculantes.

- verificação(teste): @principle:P-014

## P-015 [DEVE] Onboarding e inicialização formam um protocolo único

`organ onboard` recebe uma única submissão, valida a rota sem abrir conexão, publica uma única vez o deployment local ignorado pelo Git e encerra em `CONNECTED`. Em janela posterior, `organ init` carrega esse deployment, vincula o estado ao digest e somente então alcança `INITIALIZED`; ausência, invalidade ou divergência retorna `ONBOARD_REQUIRED` sem criar pane, conexão, dispatch ou fallback paralelo.

- verificação(teste): @principle:P-015
