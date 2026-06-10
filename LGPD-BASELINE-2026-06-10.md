# LGPD — Self-Audit Baseline

**Data:** 2026-06-10
**Escopo:** Viralefy (marketplace BR de engajamento Instagram/TikTok)
**Status do produto:** HML/POC pré-lançamento PRD
**Autor:** Engenharia (self-audit pré-jurídico)

> AVISO: Este documento é auditoria **técnica interna** e NÃO substitui
> parecer jurídico. Toda afirmação aqui é baseada em evidência no código
> citada. A revisão por advogado especialista em proteção de dados (LGPD +
> GDPR, dado o atendimento a 130 países) é **obrigatória** antes de
> publicar a Política de Privacidade e ir ao ar em produção.

---

## 0. Sumário Executivo

**Score qualitativo geral: BAIXA-MÉDIA conformidade.**

Pontos fortes inesperados pra fase HML:
- Endpoints LGPD/GDPR de export e deletion já existem
  (`/v1/me/data/export`, `/v1/me/data/deletion` GET/POST/DELETE — vide
  `viralefy_core/internal/interface/http/router.go:144-146`).
- Política de Privacidade, Termos, Cookies e Reembolso publicados em 8
  idiomas com versionamento (`viralefy_front/src/i18n/legal.ts:10`,
  `updatedAt: "2026-05-30"`).
- Cookie banner com 4 categorias (necessary/preferences/analytics/marketing),
  defaults LGPD-compliant (Art. 8 §3) e audit log em `user_consent_log`,
  rejeição por padrão de marketing, e mecanismo de revogação
  (`viralefy_front/src/components/CookieBanner.tsx`,
  `viralefy_front/src/lib/gdpr.ts`).
- Senhas em bcrypt; refresh tokens rotativos com TTL 30d; password reset
  com hash do token e single-use; revogação por jti
  (`viralefy_core/internal/infrastructure/persistence/postgres/migrations/039_auth_tokens.up.sql`).
- 2FA TOTP opcional pra users, obrigatório pra admins; secrets cifrados
  AES-256-GCM (`migrations/036_twofa.up.sql:10`).
- Audit log imutável de mutações administrativas
  (`migrations/012_idempotency_audit.up.sql:27-41`).

Pontos críticos:
- **Não há "encarregado pelo tratamento de dados" (DPO) designado** —
  Art. 41 LGPD exige indicação pública. Nenhum email `dpo@`, `privacy@`,
  `lgpd@` foi encontrado em legal docs, configs ou repos
  (`grep` retornou vazio em todo o monorepo).
- **A Política de Privacidade não cumpre Art. 9 (informação ao
  titular)** — não lista bases legais por finalidade, retenção exata
  por dado, transferência internacional, identificação do controlador,
  nem direitos do Art. 18 enumerados.
- ~~**Hard-delete físico nunca executa**~~ **RESOLVIDO** em 2026-06-10:
  implementado `cmd/user-deletion-cron` (binário Go), migrations
  042/043 (snapshot fiscal em orders + drop FK pra preservar auditoria
  post-exclusão), systemd timer `viralefy-user-deletion.timer` (03:45
  UTC daily). Métricas expostas via textfile collector. Detalhes:
  `viralefy_archive/RUNBOOK-USER-DELETION.md`.
- **Logs estruturados ainda não mascaram PII**
  (`viralefy_archive/COMPLIANCE.md:159` "Mascaramento de PII ❌").
- **Postgres não cifrado em repouso**
  (`viralefy_archive/COMPLIANCE.md:284`).
- **Sem plano de resposta a incidente / runbook ANPD 72h** (Art. 48).

---

## 1. Inventário de Dados Pessoais Coletados

Levantamento via leitura de **todas** as migrations
`viralefy_core/internal/infrastructure/persistence/postgres/migrations/*.up.sql`.

### 1.1 Tabela `users` (PII de titular principal)

| Coluna | Tipo PII | Migration | Finalidade declarada | Sensível LGPD? |
|---|---|---|---|---|
| `email` UNIQUE | Identificação direta | `001_init.up.sql:16` | Autenticação, contato transacional, recuperação de senha | Não-sensível (Art. 5 I) |
| `name` | Identificação direta | `001_init.up.sql:17` | Personalização de email, suporte | Não-sensível |
| `password_hash` (bcrypt) | Credencial (NÃO PII per se) | `001_init.up.sql:19` | Autenticação | N/A — não persiste a senha |
| `instagram` | Identificação indireta (handle público) | `001_init.up.sql:18` | Histórico do primeiro perfil; legado | Não-sensível (público) |
| `created_at` | Metadado de cadastro | `001_init.up.sql:20` | Auditoria | N/A |
| `deleted_at` | Marca de soft-delete | `020_user_data.up.sql:33` | LGPD/right to be forgotten | N/A |
| `notif_prefs` JSONB | Preferências de notificação | `019_user_notif_prefs.up.sql:4` | Opt-in/out de canais | N/A |
| `tracking_data` JSONB | first-touch UTM + landing | `013_tracking.up.sql:20` | Atribuição de marketing | Identificação indireta |
| `whatsapp_number` (E.164) | Identificação direta + contato | `028_user_whatsapp.up.sql:14` | Notificação transacional opt-in | Não-sensível |
| `whatsapp_opt_in` | Flag de consentimento | `028:15` | Base de processamento | N/A |
| `whatsapp_verified_at` | Metadado verificação | `028:16` | Anti-fraude WhatsApp | N/A |
| `phone` | Identificação direta + contato | `037_user_contact.up.sql:14` | Canal de contato alternativo | Não-sensível |
| `telegram` | Identificação indireta (handle) | `037_user_contact.up.sql:15` | Canal de contato alternativo | Não-sensível |
| `twofa_prompt_dismissed_count` | Behavior counter | `036_twofa.up.sql:43` | UX de nag de 2FA | N/A |
| `twofa_prompt_last_dismissed_at` | Timestamp | `036_twofa.up.sql:44` | UX | N/A |

### 1.2 Tabelas relacionadas (PII indireto / derivado)

| Tabela | Coluna(s) PII | Migration | Notas |
|---|---|---|---|
| `profiles` | `handle`, `display_name` | `007:6-7` | Username público da rede social do titular |
| `orders` | `tracking` JSONB | `013:18` | Pode conter `ip`, `user_agent`, `fbclid`, `gclid`, `client_id` — PII indireta + dado comportamental |
| `orders` | `publication_url` | `007:21` | URL pública mas pode revelar conta |
| `orders` | `external_ref` | `001:41` | Referência no gateway (Stripe/Woovi/Heleket) |
| `invoices` | `payment_extra` JSONB | `007:67` | Pode conter `wallet_address`, `qr_code` — dado financeiro |
| `audit_log` | `actor_id` + `metadata` JSONB | `012:36` | Comentário do migration menciona "IP, user agent, motivo" — verificar PII real em metadata |
| `email_events` | `email` | `016:18` | Endereço do destinatário + payload bruto do webhook Resend (PII em texto livre) |
| `email_reputation` | `email` (PK) | `016:29` | Status de reputação por endereço |
| `coupon_redemptions` | `user_email` | `017:45` | Email do redentor |
| `vendors.contact_email` | Email | `029:20` | B2B contact (não titular consumidor, mas PII de PF) |
| `fraud_signals` | `actor` (email ou IP) | `024:21` | Identificador anti-fraude |
| `fraud_blocks` | `actor` (PK, email ou IP) | `024:31` | Bloqueio efetivo |
| `user_events` | `visitor_id`, `user_id`, `ip`, `user_agent`, `path`, `referrer`, `payload`, `utm` | `033:13-25` | **Tracking comportamental granular — maior superfície de PII no sistema** |
| `user_journeys` | `landing_path`, `landing_referrer`, `landing_utm` | `033:31-40` | Agregado 1:1 — first-touch persistente |
| `refresh_tokens` | `issue_ip`, `issue_user_agent` | `039:34-35` | Forense de sessão |
| `password_resets` | `requested_ip`, `requested_user_agent` | `039:83-84` | Forense de reset |
| `revoked_jtis` | `revoked_by_user_id` | `039:64` | Audit de revogação |
| `admin_2fa.secret_encrypted` / `user_2fa.secret_encrypted` | AES-256-GCM | `036:16,25` | Credencial 2FA cifrada |
| `reviews` | `title`, `body`, `country_code` | `015:22-23` | Texto livre — pode conter PII em UGC |

### 1.3 Categorias de dados sensíveis (Art. 5 II LGPD)

**Não foram identificadas** colunas de origem racial/étnica, convicção
religiosa, opinião política, filiação sindical, saúde, vida sexual,
dado genético ou biométrico. **Não há tratamento de dado sensível** no
schema atual. Confirmar com jurídico se UGC livre (reviews.body) tem
risco de coletar sensível por engano.

### 1.4 Dados de crianças/adolescentes (Art. 14)

Termos de Uso (`legal.ts:196` PT) exigem 18+. **NÃO há validação
técnica de idade no register** — confiamos apenas no auto-declarado.
GAP de baixa probabilidade mas alto impacto se materializar.

---

## 2. Base Legal por Finalidade (Art. 7 LGPD)

| Dado | Finalidade | Base Legal Proposta | Justificativa |
|---|---|---|---|
| `email`, `password_hash` | Autenticação na plataforma | Art. 7 V — execução de contrato | Sem login não há prestação de serviço |
| `name` | Personalização + suporte | Art. 7 V — execução de contrato | |
| `phone`, `telegram`, `whatsapp_number` | Notificação transacional + suporte | Art. 7 I — consentimento (com `whatsapp_opt_in` registrado em DB) | Opt-in explícito; verificar coleta de consentimento separada de "Aceito Termos" pra phone/telegram (hoje vem do form de register sem flag dedicada — REVER) |
| `profiles.handle` + `orders.publication_url` (alvo do serviço) | Entrega do pacote contratado | Art. 7 V — execução de contrato | Dado central pro serviço |
| `tracking` (UTM, fbclid, gclid, client_id) em orders | Atribuição de marketing + anti-fraude | Art. 7 IX — legítimo interesse | Necessita LIA (Legitimate Interest Assessment) documentada |
| `user_events.ip`, `.user_agent` | Anti-fraude + analytics | Art. 7 IX — legítimo interesse + Art. 7 I — consentimento (analytics) | ✅ 2026-06-10: backend NULLifica IP/UA quando `X-Analytics-Consent != "1"`; coluna `analytics_consent` registra o estado da decisão por row. |
| `user_consent_log.*` | Comprovação de consent (LGPD Art. 8 §6) | Art. 7 II — obrigação legal | Append-only. IP/UA aqui são intencionais (comprovação). Hard-delete só no exercício do Art. 18 IX. |
| `refresh_tokens.issue_ip/ua`, `password_resets.requested_ip/ua` | Forense de segurança | Art. 7 IX — legítimo interesse | LIA: prevenção a fraude e proteção de conta |
| `audit_log.metadata` (IP, UA, motivo) | Auditoria de mudanças admin | Art. 7 II — cumprimento de obrigação legal/regulatória + IX | |
| `orders.amount_cents`, `invoices`, `credit_transactions` | Cobrança + faturamento | Art. 7 V — contrato + Art. 7 II — obrigação legal fiscal | Receita Federal exige guarda 5 anos |
| `fraud_signals`, `fraud_blocks` | Prevenção a abuso | Art. 7 IX — legítimo interesse + Art. 7 X — proteção do crédito | |
| `email_events`, `email_reputation` | Higiene de envio + obrigação contratual com Resend | Art. 7 IX — legítimo interesse | |
| `reviews.body` | Conteúdo gerado pelo usuário publicado no site | Art. 7 I — consentimento (no formulário "publicar") | Verificar texto do form |
| `notif_prefs` | Registro de opt-in/out | Art. 7 I — consentimento + execução do próprio direito | |
| `admin_2fa.secret_encrypted` | Segurança do admin | Art. 7 II — obrigação legal (boa prática de segurança) + V | |

**GAP:** Nenhum desses raciocínios está formalizado em documento
interno (LIA, ROPA — Registro de Atividades de Tratamento). Art. 37
LGPD exige ROPA pra controladores.

---

## 3. Política de Retenção (Art. 16 LGPD)

| Categoria | Retenção Recomendada | Implementação Atual | Status |
|---|---|---|---|
| Usuário ativo | Indefinido enquanto conta existir | OK | ✅ |
| Usuário com pedido de exclusão | 30d janela cancelamento → hard-delete | Janela + cron implementados (`cmd/user-deletion-cron`, timer 03:45 UTC). Anonimização de orders preserva 5y fiscal | ✅ |
| Faturas / orders pagas | 5 anos (Receita Federal, Art. 195 CTN) | Sem TTL — retenção indefinida (aceitável p/ orders, **mas precisa documento de política**) | ⚠️ |
| `audit_log` | 6 anos (boa prática) | Sem TTL — indefinido | ⚠️ |
| `refresh_tokens` | Até `expires_at` (30d) + cleanup | TTL natural; cron de cleanup **não localizado** (deve haver — verificar) | ⚠️ |
| `revoked_jtis` | Até `expires_at` (TTL do access token, ~1h) | TTL natural | ✅ |
| `password_resets` | 1h (single-use) | TTL natural; cleanup idem | ⚠️ |
| `idempotency_keys` | 24h | `expires_at default NOW() + INTERVAL '24 hours'` (`012:23`) | ✅ |
| `email_events` | 90d | Cron `EventRetentionCron` apaga em 90d default (`event_retention_cron.go:54`) | ✅ |
| `user_events` | 90d | Mesmo cron (`event_retention_cron.go:14-22`) | ✅ |
| `ab_events` | 90d | Mesmo cron | ✅ |
| `fraud_signals` | Indefinido (proteção do negócio) | Sem TTL — adequado a legítimo interesse continuado | ✅ |
| `email_reputation` | Indefinido (lista de suppression) | Sem TTL — adequado | ✅ |
| `user_journeys` | Indefinido (agregado) | Sem TTL — comentário no migration declara "retém valor indefinidamente" (`event_retention_cron.go:21-22`) | ⚠️ Conflita com retenção do `user_events` que o agrega — REVISAR base legal |
| `tracking_data` (em `users`) | Vida útil da conta | Sem TTL | ⚠️ |

**GAP:** Não há documento "Política de Retenção" interna nem na
Política de Privacidade pública. Retenção é definida ad-hoc em código.

---

## 4. Direitos do Titular (Art. 18 LGPD)

| Direito | Endpoint / Caminho | Status Implementação | Evidência |
|---|---|---|---|
| **Confirmação de existência + Acesso (Art. 18 I, II)** | `GET /v1/me/data/export` | ✅ Implementado | `router.go:144`, `user_data_service.go:42-154` (dump JSON de user, orders, tickets, profiles, reviews, notif_prefs, deletion_request) |
| **Portabilidade (Art. 18 V)** | Mesmo endpoint acima | ✅ Parcial — formato JSON | Não há ainda CSV / formato "interoperável" exigível pelo Art. 18 §5. Aceitável tecnicamente. |
| **Correção (Art. 18 III)** | `PUT /v1/me/whatsapp`, `/v1/me/notif-prefs`, `POST /v1/me/profiles`, `DELETE /v1/me/profiles/{id}` | ✅ Parcial | `router.go:134-150`. **Não há endpoint pra editar `email`, `name`, `phone`, `telegram` do próprio usuário.** GAP. |
| **Anonimização / bloqueio / eliminação (Art. 18 IV)** | `POST /v1/me/data/deletion` | ⚠️ Parcial — grava intenção, sem execução | `user_data_service.go:214-232` UPSERT em `user_deletion_requests`. **Cron de execução físico não existe** (`user_data_service.go:20-21`) |
| Cancelamento de pedido de exclusão | `DELETE /v1/me/data/deletion` | ✅ | `router.go:146`, `user_data_service.go:236-249` |
| **Informação sobre compartilhamento (Art. 18 VII)** | — | ❌ Ausente | Política de Privacidade lista subprocessadores (Woovi, Heleket, Resend, Hetzner, Cloudflare) mas sem detalhe por finalidade |
| **Revogação de consentimento (Art. 18 IX)** | `PUT /v1/me/notif-prefs`, `PUT /v1/me/whatsapp` | ✅ | Granular por canal |
| **Oposição a tratamento (Art. 18 §2)** | — | ❌ Ausente | Sem fluxo dedicado; cobre-se via deletion |
| **Revisão de decisões automatizadas (Art. 20)** | — | ❌ Ausente | `fraud_blocks` decide block automaticamente; sem canal documentado pra contestação humana |

---

## 5. Documentos Legais Publicados

| Documento | Localização | Última atualização | Status |
|---|---|---|---|
| Política de Privacidade | `/legal/privacy?lang=pt` (8 idiomas) | 2026-05-30 (`legal.ts:161`) | ⚠️ Existe mas **incompleta para LGPD** — vide §6 abaixo |
| Termos de Uso | `/legal/terms?lang=pt` | 2026-05-30 | ✅ Existe; revisar 18+ + foro |
| Política de Cookies | `/legal/cookies?lang=pt` | 2026-05-30 | ⚠️ Diz "não exibimos banner" (`legal.ts:232`) mas o banner **EXISTE e está mounted** — texto contradiz implementação |
| Política de Reembolso | `/legal/refund?lang=pt` | 2026-05-31 | ✅ |
| Sobre | `/legal/about` | 2026-05-30 | ✅ |
| Contato | `/legal/contact` | 2026-05-30 | ✅ |
| DPO designado + contato público | — | — | ❌ Inexistente |
| Registro de Atividades de Tratamento (ROPA) interno | — | — | ❌ Inexistente |
| Avaliação de Impacto à Proteção de Dados (DPIA / RIPD) | — | — | ❌ Inexistente |
| LIA (Legitimate Interest Assessment) | — | — | ❌ Inexistente |
| Plano de Resposta a Incidente (Art. 48) | — | — | ❌ Inexistente (verificado: `viralefy_archive/` não contém runbook ANPD) |
| Política de Retenção interna | — | — | ❌ Inexistente |
| Acordos com subprocessadores (DPA) | — | — | ❓ A confirmar com jurídico (Stripe, Woovi, Heleket, Resend, Hetzner, Cloudflare) |

---

## 6. Conteúdo da Política de Privacidade atual vs Art. 9 LGPD

Inspeção do texto em `viralefy_front/src/i18n/legal.ts:162-184` (PT):

| Item exigido pelo Art. 9 LGPD | Presente? |
|---|---|
| Finalidade específica do tratamento | ⚠️ Genérica ("entregar o serviço", "emitir faturas") |
| Forma e duração do tratamento (retenção) | ❌ Apenas "30 dias" pra deletion, sem retenção por categoria |
| Identificação do controlador (razão social, CNPJ, endereço) | ❌ Ausente |
| Contato do controlador | ⚠️ Só "email no rodapé" (não tem rodapé com email visível em todos os layouts — verificar) |
| Compartilhamento com terceiros + finalidade | ⚠️ Lista subprocessadores mas sem finalidade detalhada |
| Responsabilidades dos agentes que realizarão o tratamento | ❌ |
| Direitos do titular (enumerar Art. 18 I-IX) | ❌ Cita "exportação ou exclusão" — incompleto |
| **DPO (encarregado) + contato** | ❌ Ausente |
| Transferência internacional + país de destino | ❌ Ausente (Resend US/EU, Stripe IE, Cloudflare US, Heleket?, Woovi BR) |
| Base legal por finalidade | ❌ Ausente |
| Direito de revogar consentimento + como | ⚠️ Implícito |
| Direito de peticionar perante ANPD | ❌ Ausente |

**Conclusão:** O documento atual é uma "privacy policy genérica
estilo SaaS internacional" e não atende Art. 9 LGPD. Refactor
obrigatório antes do PRD.

---

## 7. Cookies & Tracking

### 7.1 Cookie Banner

✅ Existe em `viralefy_front/src/components/CookieBanner.tsx`.
**Atualizado 2026-06-10 (gap C5)** — comportamento corrente:

- Aparece quando `getConsent()` devolve null (storage vazio, versão
  antiga ou consent expirado >12 meses).
- 3 botões diretos: **Aceitar todos** / **Apenas essenciais** /
  **Personalizar** (PT-BR default; fallback EN via `navigator.language`).
- Modal "Personalizar" com 4 toggles: Necessary (always-on, disabled),
  Preferences (default ON — utility cookie), **Analytics (default OFF)**,
  **Marketing (default OFF)**. Conforme LGPD Art. 8 §3 (consent livre).
- Schema versionado (`version=2`); upgrade força reconsent universal.
- Re-prompt automático após 365 dias (recomendação ANPD).
- Cada decisão é logada em `user_consent_log` via POST `/v1/me/consent`
  (audit trail Art. 8 §6).
- Página de gerenciamento `/legal/cookie-preferences` permite reset
  (vide `gdpr.ts:resetConsent`).
- Runbook operacional: `viralefy_archive/RUNBOOK-COOKIE-CONSENT.md`.

### 7.2 Tracking ativo no front

- **GTM container `GTM-K7GQ4H32`**: 2026-06-10 movido pra
  `components/GtmLoader.tsx` — carregamento lazy via `next/script`
  **somente após consent analytics**. Google Consent Mode v2 com
  `default: denied` é setado antes do GTM inicializar.
- **Sentry** (`sentry.client.config.ts`): no-op quando `NEXT_PUBLIC_SENTRY_DSN`
  vazio. Em produção deve gateá-lo no consent `analytics` (TODO A5
  documentado, não impede o gap C5).
- **Cookies essenciais declarados**: `viralefy_token` (sessão),
  cookie de moeda. Documentado em `/legal/cookies`.

### 7.3 Tracking backend (RESOLVED 2026-06-10)

✅ `user_events` (migration 033) **agora respeita o header
`X-Analytics-Consent`** enviado pelo `viralefy_front/src/lib/track.ts`:

- Header "1" (consent dado) → IP + UA gravados normalmente,
  `analytics_consent = TRUE` na nova coluna (migration 041).
- Header "0" / ausente → IP + UA viram NULL (`UserEventRepo.Record`
  faz o NULLify), `analytics_consent = FALSE`. Mantém contagem de
  eventos pra produto sem PII.
- Coluna `analytics_consent BOOLEAN` na `user_events` permite
  auditoria a posteriori + backfill seletivo.

Audit log de cada decisão de consent fica em `user_consent_log`
(migration 041) — IP+UA dele são intencionais (base legal Art. 8 §6,
comprovação).

---

## 8. Segurança Técnica (Art. 46)

| Controle | Status | Evidência |
|---|---|---|
| TLS 1.2+ em trânsito | ✅ | Caddy (`COMPLIANCE.md:283`) |
| Hash de senha (bcrypt) | ✅ | `users.password_hash` |
| Rotação de refresh token + anti-replay | ✅ | `migration 039`, `replaced_by_id` |
| Revogação de access token (jti) | ✅ | `revoked_jtis` |
| 2FA TOTP cifrado AES-256-GCM | ✅ | `migration 036` |
| Auditoria imutável (admin) | ✅ | `audit_log` |
| Idempotency em writes financeiros | ✅ | `idempotency_keys` |
| Anti-fraude (velocity) | ✅ | `fraud_signals`, `fraud_blocks` |
| Rate-limiting | ⚠️ Login limiter aplicado; resto a confirmar | `router.go:101,109,110` |
| Criptografia em repouso (Postgres) | ❌ | `COMPLIANCE.md:284` |
| Mascaramento de PII em logs | ❌ | `COMPLIANCE.md:159` |
| Secret management (Vault/KMS) | ❌ | `.env` em `/etc/viralefy/` `COMPLIANCE.md:128` |
| Backup criptografado + DR runbook | ⚠️ | `RUNBOOK-BACKUP-VERIFY.md`, `RUNBOOK-DR.md` existem; revisar cifragem do backup |
| Container scan / SAST / SCA | ❌ | `COMPLIANCE.md:119-129` |
| JWT RS256 (vs HS256) | ❌ | `COMPLIANCE.md:139` (HS256 em uso — débito Tier 1) |

---

## 9. Transferência Internacional (Art. 33)

| Subprocessador | Função | País / Região | Salvaguarda LGPD |
|---|---|---|---|
| Stripe | Card gateway global | Irlanda (HQ EU) + US | Art. 33 II — SCC + Stripe DPA pública. Verificar cláusulas pra titulares BR. |
| Woovi | PIX (BRL) | Brasil | ✅ Nacional |
| Heleket | Cripto | **Não identificado** — `api.heleket.com` (TLD genérico). Verificar jurisdição operacional + DPA | ⚠️ |
| Resend | Email transacional | US (Delaware) | Art. 33 II — exigir DPA + SCC |
| Hetzner | Hosting | Alemanha / Finlândia (UE) | Adequação UE (Art. 45 GDPR aplicável; LGPD considera adequado) |
| Cloudflare | CDN + WAF | US (HQ) com PoP global | DPA Cloudflare + SCC |
| MinIO (object storage) | Local | BR (servidor próprio) | ✅ Local |
| Sentry | Error reporting | US (SaaS) ou self-host opcional | DSN não setado em HML; em PRD requer DPA |

**GAP:** Política de Privacidade não cita transferência internacional
nem país de destino. Art. 9 IV LGPD exige.

---

## 10. Plano de Resposta a Incidente (Art. 48)

❌ **Inexistente**.

Verificado `viralefy_archive/`:
- `RUNBOOK.md` — operacional geral.
- `RUNBOOK-DR.md` — disaster recovery (downtime).
- `RUNBOOK-BACKUP-VERIFY.md` — backup integrity.
- Nenhum runbook específico de incidente de segurança / vazamento /
  notificação ANPD 72h.
- Nenhuma menção a `ANPD`, `incident`, `breach` em
  `viralefy_archive/*.md` (`grep` confirmou).

---

## 11. GAPS Consolidados + Prioridade

### CRÍTICO (bloqueia produção)

| ID | Gap | Impacto | Esforço |
|---|---|---|---|
| C1 | DPO/encarregado não designado nem contato público | Art. 41 — controlador inadimplente | 0.5d (designar + publicar) |
| C2 | Política de Privacidade não atende Art. 9 LGPD | Multas + ação ANPD | 3d (advogado + impl) |
| C3 | Cron de hard-delete físico inexistente — pedidos ficam "pending" para sempre | Não atende Art. 18 IV | 2d (cron + testes) |
| C4 | Plano de resposta a incidente + 72h ANPD inexistente | Art. 48 inadimplência em incidente real | 1d (runbook) |
| ~~C5~~ | ~~Cookie banner default ON pra analytics + tracking backend não gateado por consent~~ | ~~Art. 8 §3~~ | **✅ RESOLVED 2026-06-10** — banner default OFF (commit em viralefy_front), backend NULLifica IP/UA via header `X-Analytics-Consent` (migration 041 em viralefy_core), audit log em `user_consent_log`. Runbook: `RUNBOOK-COOKIE-CONSENT.md`. |

### ALTO

| ID | Gap | Impacto | Esforço |
|---|---|---|---|
| A1 | ROPA (Registro de Atividades de Tratamento, Art. 37) inexistente | Não atende Art. 37 | 2d (formalizar a tabela §2 deste doc) |
| A2 | LIA pra `tracking_data`, `user_events`, `fraud_signals`, `refresh_tokens.issue_ip` ausentes | Base legal "legítimo interesse" não defensável sem LIA | 2d |
| A3 | Endpoints PUT pra editar `email`/`name`/`phone`/`telegram` ausentes | Art. 18 III (correção) | 1d |
| A4 | Política de Cookies declara "não exibimos banner" mas banner existe (texto desatualizado) | Risco reputacional + ANPD | 0.5d (atualizar texto + bump updatedAt) |
| A5 | Sentry / qualquer tracker analytics futuro não gateado por flag `analytics` do banner | Art. 8 §3 | 0.5d |
| A6 | Postgres não cifrado em repouso | Art. 46 §1 (medidas técnicas) | 1d (LUKS no disk OU pgcrypto seletivo) |
| A7 | Logs sem mascaramento de PII | Art. 46 + risco vazamento via journalctl | 2d (middleware redact) |
| A8 | Validação 18+ no register apenas autodeclarada | Art. 14 (dado de criança) | 0.5d (checkbox + DOB opcional) |

### MÉDIO

| ID | Gap | Impacto | Esforço |
|---|---|---|---|
| M1 | Política de Retenção interna formalizada | Boa governança Art. 50 | 1d (escrever .md + publicar) |
| M2 | Direito a contestação de decisão automatizada (Art. 20) — `fraud_blocks` | Art. 20 §1 (revisão humana) | 1d (endpoint contesta + queue admin) |
| M3 | Format de portabilidade — adicionar CSV além do JSON | Art. 18 V (interoperável) | 0.5d |
| M4 | DPA com Heleket — verificar jurisdição operacional | Art. 33 II | 1d (jurídico) |
| M5 | DPA explícita com Stripe / Resend / Cloudflare / Hetzner assinada e arquivada | Art. 33 + Art. 39 | 1d (juntar links públicos) |
| M6 | Atualização anual obrigatória da Política de Privacidade — workflow de bump | Boa prática | 0.5d (cron + lembrete) |

### BAIXO

| ID | Gap | Impacto | Esforço |
|---|---|---|---|
| B1 | Banner default OFF pra analytics — uniformizar com marketing | Reforço Art. 8 §3 | 0.5d |
| B2 | Endpoint `GET /v1/me/data/export?format=csv` | Art. 18 V | 1d |
| B3 | Logo de "Compromisso LGPD" no rodapé linkando pra Política | Boa governança | 0.5d |

---

## 12. Roadmap Sugerido (sprint pré-PRD)

### Sprint 1 — Bloqueadores legais (5d total)

1. **C1** Designar encarregado (interno ou externo) + publicar contato (`dpo@viralefy.com` ou similar) — 0.5d
2. **C4** Escrever `RUNBOOK-INCIDENTE-LGPD.md` no `viralefy_archive` — 1d
3. **C5** Cookie banner default OFF + middleware backend que respeita consent pra `user_events` insert — 1d
4. **A4** Sincronizar texto da Política de Cookies com implementação real — 0.5d
5. **A8** Checkbox de "tenho 18 anos ou mais" no register + persist — 0.5d
6. **A3** Endpoint `PUT /v1/me/profile` (name, email, phone, telegram) — 1d

### Sprint 2 — Documentação e governança (5d)

7. **C2** Refactor da Política de Privacidade com advogado (LGPD-compliant Art. 9) — 3d
8. **A1** Formalizar ROPA em `viralefy_archive/ROPA.md` — 1d
9. **A2** LIA pra tracking + anti-fraude — 1d

### Sprint 3 — Implementação técnica residual (5d)

10. **C3** Implementar `UserDeletionExecutionCron` (hard-delete + cascade) — 2d
11. **A6** Cifragem em repouso (LUKS no volume Postgres ou pgcrypto seletivo) — 1d
12. **A7** Middleware de redact de PII nos logs estruturados — 2d

### Sprint 4 — Refinos (3d)

13. **M1, M2, M3, B1, B2, B3** — incrementais — 3d

**Estimativa total para fechar gaps internos (até "advogado-ready"):
~18 dias úteis** (3-4 semanas single-dev).

---

## 13. Checklist para Revisão Jurídica

Quando o roadmap acima estiver concluído, leve ao advogado:

- [ ] ROPA preenchido
- [ ] LIA pra cada finalidade baseada em legítimo interesse
- [ ] Política de Privacidade revisada
- [ ] Termos de Uso revisados (foro, lei aplicável, 18+, jurisdição multi-país)
- [ ] Política de Cookies sincronizada com banner
- [ ] Política de Retenção interna
- [ ] Runbook de incidente LGPD (74h ANPD + comunicação aos titulares)
- [ ] DPAs assinadas / referenciadas: Stripe, Woovi, Heleket, Resend, Hetzner, Cloudflare, Sentry
- [ ] Confirmação da designação do DPO + termo de responsabilidade
- [ ] Acordo de processador (caso vendors B2B virem controlador conjunto)
- [ ] Avaliação de necessidade de DPIA pra (a) tracking comportamental
      granular `user_events`, (b) anti-fraude com decisão automatizada
      `fraud_blocks`
- [ ] Confirmar enquadramento de "operações de pequeno porte" (Resolução
      CD/ANPD 2/2022) — provável aplicável durante HML/POC

---

## 14. Opinião Técnica Final

A engenharia entregou uma fundação melhor do que muitas startups BR em
estágio similar: endpoints de export e deletion já existem, cookie
banner com 3 categorias, audit log imutável, 2FA cifrado, rotação de
refresh token. **Mas isso não é conformidade — é só infraestrutura
técnica que sustenta conformidade.**

O bloqueio crítico real pra PRD é:
1. **Designar DPO** (qualquer pessoa, mesmo terceirizada — Art. 41 §3
   admite escritório terceirizado).
2. **Refazer Política de Privacidade com advogado** — o texto atual
   passa em "GDPR genérico" mas não em LGPD.
3. **Implementar o cron de hard-delete** que está como TODO no código.
4. **Escrever o runbook de incidente** com gatilho de notificação ANPD.

Sem esses 4 itens a Viralefy está exposta a multa Art. 52 LGPD
(simples advertência → 2% faturamento, limitada a R$ 50M por
infração).

**Revisão por advogado especialista em LGPD é mandatória antes do
PRD.** Este documento é apenas o material de input.
