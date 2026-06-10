# RUNBOOK — Cookie Consent (LGPD / ANPD)

**Última revisão:** 2026-06-10
**Owner:** DPO + Engenharia Frontend
**Base legal:** LGPD Art. 7 I (consentimento), Art. 8 §3 (consent livre),
Art. 8 §6 (comprovação), ANPD Resolução 4/2020 (cookies analíticos).

---

## 1. Modelo de Consent

O banner em `viralefy_front/src/components/CookieBanner.tsx` apresenta
**4 categorias** ao visitante:

| Categoria      | Default no banner | Cookies cobertos                                                 | Base legal                          |
|----------------|-------------------|------------------------------------------------------------------|-------------------------------------|
| Necessary      | ON (não-toggleável)| `viralefy_token` (sessão JWT), CSRF, anti-fraude                | Art. 7 IX — legítimo interesse      |
| Preferences    | ON (toggleável)   | `viralefy_theme`, idioma, moeda escolhida, `viralefy_client_id`  | Art. 7 IX + utility cookie ANPD     |
| **Analytics**  | **OFF (opt-in)**  | GTM container `GTM-K7GQ4H32`, `_ga*`, `_gid`, IP/UA no `user_events` | Art. 7 I — consentimento (LIVRE)    |
| **Marketing**  | **OFF (opt-in)**  | Meta `_fbp`/`_fbc`, Google Ads `_gcl_*`, placeholder pixels      | Art. 7 I — consentimento (LIVRE)    |

**LGPD Art. 8 §3 (consent livre):** os toggles de Analytics e Marketing
**NÃO podem vir pré-marcados**. A inversão histórica (Analytics default ON
antes desta task) constituía gap C5 do `LGPD-BASELINE-2026-06-10.md`.

Três botões no banner:

1. **Aceitar todos** → analytics=true + marketing=true + preferences=true.
2. **Apenas essenciais** → todos OFF exceto necessary + preferences.
3. **Personalizar** → modal com toggles individuais (default conservador).

Persistência: `localStorage["viralefy_gdpr_consent"]` com schema:

```json
{
  "version": 2,
  "necessary": true,
  "preferences": true,
  "analytics": false,
  "marketing": false,
  "timestamp": "2026-06-10T15:30:00.000Z"
}
```

Versão **2** invalida o storage v1 (sem `version`) — usuários antigos que
tinham consent default-ON pra analytics são forçados a reconsentir.

---

## 2. Re-prompt após 12 meses

`GDPR_MAX_AGE_MS` em `viralefy_front/src/lib/gdpr.ts` define **365 dias**.
`getConsent()` devolve `null` quando `Date.now() - timestamp > 365d` e o
banner reaparece — usuário precisa reconsentir.

Aderente a ANPD Guia de Cookies (2023): recomenda renovação anual.

---

## 3. Como auditar consents (forense)

### 3.1 Audit log em Postgres

Cada clique vira 1 row em `user_consent_log` (criado pela migration
`041_user_consent.up.sql`):

```sql
SELECT id, user_id, visitor_id, version,
       necessary, preferences, analytics, marketing,
       source, ip, user_agent, recorded_at
  FROM user_consent_log
 WHERE user_id = 'usr_xxx'
 ORDER BY recorded_at DESC;
```

`source` é um dos: `accept_all`, `essential_only`, `custom`, `reset`.

`IP` e `user_agent` são gravados aqui **sempre** — não dependem do
próprio consent porque a base legal é a comprovação do Art. 8 §6.

### 3.2 Verificar privacy-default em `user_events`

A coluna `analytics_consent` foi adicionada pela mesma migration. Sanity:

```sql
-- Eventos recentes sem consent — IP/UA precisam estar NULL.
SELECT analytics_consent, COUNT(*) AS total,
       COUNT(ip) AS leaked_ip, COUNT(user_agent) AS leaked_ua
  FROM user_events
 WHERE occurred_at > NOW() - INTERVAL '7 days'
 GROUP BY 1;
```

Esperado: para `analytics_consent = false`, `leaked_ip = 0` e `leaked_ua = 0`.

Pra `analytics_consent IS NULL` (legacy rows pré-feature), valores antigos
podem ainda ter PII — manter como histórico ou rodar NULLify (ver §4).

---

## 4. Deletar / NULLify consent history (LGPD Art. 18 IX — revogação)

Quando o usuário pede deleção:

### 4.1 Apagar `user_events` PII do usuário

```sql
UPDATE user_events
   SET ip = NULL, user_agent = NULL, analytics_consent = FALSE
 WHERE user_id = 'usr_xxx';
```

Mantém a contagem de eventos pra métricas; apaga só PII.

### 4.2 Apagar audit log de consent

```sql
DELETE FROM user_consent_log WHERE user_id = 'usr_xxx';
```

Audit log é apagado junto pois Art. 18 IV obriga eliminação dos dados
**desnecessários**. O log se torna desnecessário após a deleção da conta.

### 4.3 Honrar revogação retroativa

Quando o usuário muda de "analytics=true" pra "analytics=false" via página
`/legal/cookie-preferences`, alguns operadores entendem que rows passadas
gravadas com PII devem ser NULLificadas. Implementação opcional, **não
exigida pela LGPD**, mas se desejada:

```sql
UPDATE user_events
   SET ip = NULL, user_agent = NULL
 WHERE user_id = 'usr_xxx'
   AND analytics_consent = TRUE
   AND occurred_at < NOW();
```

Documentar a decisão no DPO log antes de rodar em prod.

---

## 5. Adicionando provider novo (ex.: Hotjar / Mixpanel)

1. Decidir categoria: **Analytics** ou **Marketing**.
2. Adicionar carregamento em `viralefy_front/src/components/GtmLoader.tsx`
   (ou novo `XxxLoader.tsx`) gateado por `hasAnalyticsConsent()` ou
   `hasMarketingConsent()`.
3. Atualizar `/legal/cookies` (lista declarada) e este RUNBOOK §1.
4. Bump `GDPR_VERSION` em `gdpr.ts` se a inclusão constitui mudança
   material — força reconsent universal.
5. Atualizar texto do banner se o provider tiver tratamento singular
   (ex.: transferência internacional pra EUA — Art. 33 LGPD).

---

## 6. Verificação manual (DevTools)

1. Incognito → abrir `https://www.viralefy.com/`.
2. Network tab → filtro `googletagmanager`: **deve ficar zero**.
3. `localStorage.getItem('viralefy_gdpr_consent')`: **null**.
4. Click "Apenas essenciais".
5. Network tab: ainda zero requests pro googletagmanager.
6. Refresh: banner não reaparece.
7. Reset via `localStorage.clear()` + reload + click "Aceitar todos".
8. Network: `gtm.js?id=GTM-K7GQ4H32` aparece.
9. Headers de `/v1/track`: `X-Analytics-Consent: 1`.

E2E automatizado: `viralefy_front/e2e/cookie-consent.spec.ts` (Playwright).

---

## 7. Sincronização com Política de Cookies

`viralefy_front/src/i18n/legal.ts` precisa ser revisado quando:
- Categorias mudarem.
- Texto do banner mudar materialmente.
- Lista de providers mudar.

Gap A4 do baseline LGPD (texto do `/legal/cookies` ainda dizia "não
exibimos banner") — corrigir junto com qualquer mudança neste runbook.
