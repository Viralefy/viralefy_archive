# RUNBOOK — Incident Response + On-Call Playbook (Viralefy)

Snapshot 2026-06-10. Resposta a incidentes técnicos **e** organizacionais. Stack atual: VPS única em produção (`62.238.41.231`, Hetzner), 7 services Viralefy + Caddy/Coraza WAF + Postgres 16 + observability stack. Backups automatizados (daily + verify + weekly restore drill). Operação 1–2 pessoas, sem PagerDuty.

Documentos correlatos:
- [RUNBOOK.md](RUNBOOK.md) — runbook operacional geral
- [RUNBOOK-DR.md](RUNBOOK-DR.md) — disaster recovery (VPS perdida)
- [RUNBOOK-BACKUP-VERIFY.md](RUNBOOK-BACKUP-VERIFY.md) — verificação de backups
- [COMPLIANCE.md](COMPLIANCE.md) — LGPD / Article 48

---

## 0. TL;DR — o que fazer nos primeiros 5 minutos

1. **Acknowledge** o alerta no canal de war room (Slack/Discord webhook).
2. **Classifica SEV** (matriz §1). Se em dúvida, classifica como SEV mais alto.
3. **Abre war room** dedicado: thread/canal `#inc-YYYYMMDD-HHMM-<slug>`.
4. **Status update inicial** pros stakeholders (template §6).
5. **Investiga**:
   ```bash
   ssh -i /media/sonne/Archives/projects/viralefy/credentials root@62.238.41.231 \
     'viralefy-status && viralefy-smoke'
   ```
6. **Stop the bleeding** antes de procurar causa raiz (rollback > debug).
7. **Loga timeline** no war room — cada ação com timestamp.

> Regra de ouro: **mitigar primeiro, entender depois**. Post-mortem se faz a frio.

---

## 1. Severity Matrix

| SEV | Critério | Ack SLA | Update freq | War room | Status público |
|---|---|---|---|---|---|
| **SEV1 — CRÍTICO** | Prod totalmente down · dados perdidos/corrompidos · security breach confirmado · vazamento PII | 15 min | a cada 30 min | obrigatório | sim, imediato |
| **SEV2 — ALTO** | Feature crítica quebrada (login, checkout, webhook payment) · DB degradada (queries > 5s p99) · WAF bloqueando usuários reais em massa | 30 min | a cada 1h | obrigatório | sim, se > 30 min |
| **SEV3 — MÉDIO** | Feature secundária quebrada (busca, filtros, notificações) · drift reconcile > 5% · backup falhou 1× (próximo pode rodar) · alerta isolado | 2h | a cada 4h | opcional | não |
| **SEV4 — BAIXO** | Warning de slow query · log spam · cosmético · drift < 1% · queda transitória que auto-recuperou | next business day | diário | não | não |

### Critérios de escalação

- SEV1 nunca é "downgrade-ável" durante o incidente. Só após resolução, no PIR.
- Se SEV2 persiste > 2h sem ETA, **promove pra SEV1** automaticamente.
- Backup falhou 2 dias seguidos → SEV2 (RPO em risco).
- Restore drill falhou → SEV2 (DR comprometido).
- Qualquer suspeita de PII vazado → SEV1 instantâneo + COMPLIANCE.md §LGPD.

---

## 2. Detection Sources

| Fonte | Como dispara | Quem ouve |
|---|---|---|
| Prometheus alerts (`/media/sonne/Archives/projects/viralefy/viralefy_ops/config/alerts.yml`) | Alertmanager → webhook | on-call primário |
| Smoke tests (`viralefy-smoke`) | timer/CI falha | on-call primário |
| Backup verify (`viralefy-backup-verify.service`) | systemd OnFailure | on-call primário |
| Reconcile drift | `journalctl -u viralefy-core \| grep stripe_reconcile` mostra mismatch | revisão diária |
| Sentry (quando cliente fornecer DSN) | spike de errors | webhook |
| User report | Telegram do operador / email `viralefy@gmail.com` | manual triagem |
| Grafana dashboard `obs.viralefy.com` | observação ativa | rotina diária |

### Acknowledge SLA por canal

- Alerta automático com webhook → ack no canal em até 15 min (SEV1) / 30 min (SEV2).
- User report manual → resposta em até 1h em horário comercial.
- Fora de horário (SEV3/SEV4) → fila pra manhã seguinte.

---

## 3. First Response Checklist (qualquer SEV)

```
[ ] 1. Acknowledge dentro do SLA (responde no canal: "ack, investigando")
[ ] 2. Cria war room: canal/thread #inc-YYYYMMDD-HHMM-<slug>
[ ] 3. Status inicial pro cliente (template em §6, ajusta por SEV)
[ ] 4. SSH na VPS + colhe estado inicial:
        ssh -i /media/sonne/Archives/projects/viralefy/credentials root@62.238.41.231
        viralefy-status
        viralefy-smoke
        systemctl list-units --failed
        journalctl --since '15 min ago' -p err --no-pager | tail -100
[ ] 5. Abre dashboards: https://obs.viralefy.com (Grafana)
[ ] 6. Decide stop-the-bleeding (rollback? disable feature? maintenance page?)
[ ] 7. Aplica mitigação
[ ] 8. Verifica mitigação: viralefy-smoke + spot check manual
[ ] 9. Status update conforme freq da SEV
[ ] 10. Agenda PIR (post-incident review) — 24-72h após resolução
[ ] 11. Pós-resolução: atualiza CHECKLIST.md + CONTEXT.md no archive
```

---

## 4. Playbooks específicos por scenario

### Playbook A — Site down (api.viralefy.com retorna 5xx)

**Sintoma**: `curl https://api.viralefy.com/v1/status` retorna 5xx ou timeout.

**Quick checks**:
```bash
ssh -i /media/sonne/Archives/projects/viralefy/credentials root@62.238.41.231 \
  'viralefy-smoke && for s in core auth dispatcher payments sender caddy; do
     echo -n "$s: "; systemctl is-active viralefy-$s 2>/dev/null || systemctl is-active $s
   done'
```

**Árvore de decisão**:

| Sintoma | Provável causa | Ação |
|---|---|---|
| Caddy down/failed | OOM, audit log lotado, cert expirou | `systemctl restart caddy` + checar `du -sh /var/log/caddy-waf/` |
| viralefy-dispatcher down | JWKS cache cold-start, revocation bootstrap falhou | `systemctl restart viralefy-dispatcher` + `journalctl -u viralefy-dispatcher --since '5 min ago'` |
| viralefy-core down | DB connection lost, migration travou, panic Go | `systemctl restart viralefy-core` + checar Postgres `pg_isready` |
| viralefy-auth down | token mint falhou, secret faltando | `systemctl restart viralefy-auth` + checar `/etc/viralefy/.env` perms |
| Todos up mas 5xx | DB lock, conexões esgotadas, migração corrompida | seção §Playbook H (DB degradada) |
| 502 Bad Gateway | upstream porta errada, processo crashou silent | `ss -tlnp \| grep -E '3000\|3001\|3002\|3003\|3004'` |

**Comandos diagnóstico**:
```bash
# Logs combinados últimos 5 min, só erros:
journalctl -u 'viralefy-*' --since '5 min ago' -p err --no-pager

# Caddy upstream errors:
journalctl -u caddy --since '5 min ago' | grep -iE 'upstream|502|503|504'

# Conexões abertas Postgres:
sudo -u postgres psql -c \
  "SELECT count(*), state FROM pg_stat_activity WHERE datname='viralefy' GROUP BY state;"
```

**Stop bleeding**: se causa não óbvia em < 10 min, ativa maintenance page (§Playbook E) e faz rollback do último deploy (§5).

---

### Playbook B — Login não funciona

**Sintoma**: usuário reporta "não consigo logar" / front mostra erro genérico.

**Checklist**:
```bash
# 1. CORS preflight OK? (já tem fix em Caddyfile, regredir rompe tudo)
curl -i -X OPTIONS https://api.viralefy.com/v1/auth/login \
  -H 'Origin: https://www.viralefy.com' \
  -H 'Access-Control-Request-Method: POST'
# Esperado: 204 + Access-Control-Allow-Origin

# 2. viralefy-auth health
systemctl status viralefy-auth
curl -i https://api.viralefy.com/v1/auth/health 2>&1 | head -5

# 3. Token mint logs (últimos 10 min)
journalctl -u viralefy-auth --since '10 min ago' | grep -iE 'mint|token|error'

# 4. Postgres ativo + role users acessível
sudo -u postgres psql -d viralefy -c "SELECT count(*) FROM users;"

# 5. Rate limit? IP em iptables/journal?
iptables -L -n | grep -i drop
journalctl --since '15 min ago' | grep -iE 'rate.?limit|too.?many'

# 6. Coraza bloqueando login? (raro mas acontece)
tail -100 /var/log/caddy-waf/audit.log | grep -i '/auth/login'
```

**Mitigações**:
- Auth crashou: `systemctl restart viralefy-auth` + observar
- Rate limit: revisar `viralefy-dispatcher` config; aumentar threshold temporário
- WAF bloqueando real user: §Playbook F
- Senha/2FA quebrado pra usuário específico: backoffice → reset password

---

### Playbook C — Checkout/payment fail

**Sintoma**: pedidos não confirmam, usuário paga mas não recebe acesso.

**Checklist**:
```bash
# 1. Webhook chegando? (Stripe/Heleket/Woovi/AbacatePay em /v1/webhooks/*)
journalctl -u viralefy-payments --since '30 min ago' | \
  grep -iE 'webhook|stripe|heleket|woovi|abacate'

# 2. Order criada no DB?
sudo -u postgres psql -d viralefy -c "
  SELECT id, status, gateway, total_cents, created_at
  FROM orders ORDER BY created_at DESC LIMIT 10;"

# 3. Stripe reconcile cron rodando?
journalctl -u viralefy-core --since '24h ago' | grep stripe_reconcile

# 4. Idempotency keys batendo?
sudo -u postgres psql -d viralefy -c "
  SELECT count(*) FROM webhook_events
  WHERE created_at > now() - interval '1 hour'
  GROUP BY status;"

# 5. Gateway ativo no DB?
sudo -u postgres psql -d viralefy -c \
  "SELECT name, active, mode FROM payment_gateways WHERE active=true;"
```

**Mitigações**:
- Webhook não chega: confirma URL no dashboard do provider; checa firewall/Caddy
- Order pendente mas pagamento confirmado externamente: backoffice `/orders/<id>` → "Mark paid" (requer `admins:manage`)
- Reprocessar webhook: providers têm retry; ou replay manual com mesmo payload via curl
- Gateway inativo: ativa via backoffice ou `UPDATE payment_gateways SET active=true WHERE name='stripe'`

---

### Playbook D — Backup/restore failure

**Sintoma**: alerta `BackupStale` ou `viralefy-backup-verify.service` em estado failed.

**Checklist**:
```bash
# 1. Última execução do timer
systemctl list-timers viralefy-backup.timer viralefy-backup-verify.timer

# 2. Log do último backup
journalctl -u viralefy-backup.service --since '48h ago' --no-pager

# 3. Verify report
journalctl -u viralefy-backup-verify.service --since '48h ago' --no-pager

# 4. Espaço em disco
df -h / /var/backups

# 5. Lista de backups existentes
ls -lah /var/backups/viralefy/dump-*.sql.gz | tail -10

# 6. Restore drill recente
systemctl status viralefy-restore-drill.service
journalctl -u viralefy-restore-drill.service --since '8 days ago' | tail -30
```

**Mitigações**:
- Disco cheio: §Playbook G
- Backup manual imediato: `viralefy-backup` (interativo, roda na hora)
- Backup corrompido: `viralefy-backup-verify` reporta qual dump; descarta e força próximo ciclo
- Emergência (DB primário ameaçado): hot copy com `pg_basebackup -h localhost -U viralefy -D /var/backups/hot-$(date +%s) -Ft -z -P`

> Se 2+ backups consecutivos falharem → escalar pra SEV2 e parar deploys até resolver. RPO < 24h é constraint duro.

---

### Playbook E — Security incident (suspect breach)

**Sintoma**: acesso não autorizado suspeito, dados expostos, logs com padrão de exploit, ransomware, leak de credenciais, denúncia externa.

> **Trate como SEV1 imediatamente.** Não tente debugar antes de isolar.

**Fases (NIST 800-61 adaptado)**:

#### E.1. ISOLATE (minutos 0-5)
```bash
# Maintenance page via Caddyfile (corta tráfego de usuário)
ssh -i /media/sonne/Archives/projects/viralefy/credentials root@62.238.41.231
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.incident-$(date +%s)
# Edita Caddyfile pra responder 503 + página estática em tudo exceto admin IP
# (template em §5 — rollback Caddyfile)
systemctl reload caddy

# Opcional extremo: bloqueia tráfego externo na firewall
iptables -I INPUT -p tcp --dport 443 -j DROP
iptables -I INPUT -p tcp --dport 443 -s <IP-DO-OPERADOR> -j ACCEPT
```

#### E.2. PRESERVE evidence (minutos 5-15)
```bash
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p /var/backups/incident-$STAMP
# DB snapshot
sudo -u postgres pg_dump viralefy | gzip > /var/backups/incident-$STAMP/db.sql.gz
# Config + secrets snapshot (cifrar antes de mover!)
tar czf /var/backups/incident-$STAMP/etc-viralefy.tar.gz /etc/viralefy /etc/caddy
# Logs completos
journalctl --since '7 days ago' > /var/backups/incident-$STAMP/journal.log
cp /var/log/caddy-waf/audit.log /var/backups/incident-$STAMP/
# Audit log do app (DB)
sudo -u postgres psql -d viralefy -c "\copy audit_log TO '/var/backups/incident-$STAMP/audit_log.csv' CSV HEADER"
# Hash de tudo (chain of custody)
cd /var/backups/incident-$STAMP && sha256sum * > MANIFEST.sha256
```

#### E.3. COMMUNICATE (minutos 15-60)
- Notifica stakeholders internos (war room SEV1).
- **Se há indício de vazamento de PII** (CPF, e-mail, telefone, dados de pagamento):
  - Aciona **DPO** (ver §8).
  - Prazo **LGPD Art. 48**: notificar ANPD em até **72h**. Ver [COMPLIANCE.md](COMPLIANCE.md).
  - Notificar usuários afetados conforme escala/risco.
- Provider de pagamento (Stripe/Heleket): abrir ticket se há suspeita de fraude/chargebacks coordenados.

#### E.4. INVESTIGATE (horas 1-N)
```bash
# Padrões de acesso anormais
grep -iE 'union|sleep\(|/etc/passwd|\\.\\./|<script' /var/log/caddy-waf/audit.log | tail -50

# Sessões ativas suspeitas
sudo -u postgres psql -d viralefy -c "
  SELECT user_id, ip, user_agent, created_at
  FROM sessions WHERE created_at > now() - interval '7 days'
  ORDER BY created_at DESC LIMIT 100;"

# Tentativas de login anormais
sudo -u postgres psql -d viralefy -c "
  SELECT ip, count(*) FROM audit_log
  WHERE action='auth.login.failed' AND created_at > now() - interval '7 days'
  GROUP BY ip ORDER BY count DESC LIMIT 20;"

# Admins recentes / promoções de role
sudo -u postgres psql -d viralefy -c "
  SELECT * FROM audit_log
  WHERE action LIKE 'role.%' OR action LIKE 'admin.%'
  ORDER BY created_at DESC LIMIT 50;"
```

#### E.5. ERADICATE
```bash
# Revoga TODAS as sessões ativas (força re-login global)
sudo -u postgres psql -d viralefy -c "DELETE FROM sessions;"

# Adiciona JTIs comprometidos à revocation list (dispatcher carrega no boot)
sudo -u postgres psql -d viralefy -c "
  INSERT INTO revoked_jtis (jti, revoked_at, reason)
  SELECT jti, now(), 'incident-$STAMP' FROM active_tokens WHERE ...;"
systemctl restart viralefy-dispatcher

# Rotaciona secrets críticos em /etc/viralefy/.env:
# - JWT_SECRET (invalida todos tokens)
# - INTERNAL_SHARED_SECRET (entre services)
# - DATABASE_PASSWORD (com ALTER USER no Postgres)
# - TWOFA_ENCRYPTION_KEY (se DB foi exposta — invalida 2FA enrollments)
# - RESEND_API_KEY (coordenação externa com Resend dashboard)
# - STORAGE_* (MinIO root creds)

# Reset password forçado pra admins:
sudo -u postgres psql -d viralefy -c "
  UPDATE users SET force_password_reset=true
  WHERE id IN (SELECT user_id FROM user_roles WHERE role IN ('superadmin','admin'));"
```

#### E.6. RECOVER
- Remove maintenance page gradualmente (whitelist IPs de teste primeiro).
- Monitora `audit_log`, `caddy-waf/audit.log`, error rate por 72h pós-recovery.
- Não declara "resolvido" antes de 24h sem repetição do indicator.

#### E.7. POST-INCIDENT
- PIR obrigatório com timeline minute-by-minute.
- Atualiza [COMPLIANCE.md](COMPLIANCE.md) com lição aprendida.
- Se LGPD acionado: arquiva ofício/notificação no archive.

---

### Playbook F — Coraza WAF false positive bloqueando usuário real

**Sintoma**: usuário reporta erro genérico (403) em ação legítima. Audit log mostra match em regra CRS. Tipicamente o response NÃO tem JSON envelope (Caddy responde diretamente) e header `server: Caddy` aparece — distinguindo do 403 do app.

**Caso de referência — Incidente 2026-06-10** (ver `INCIDENT-ORDER-450F0E6F.md`):
- Sintoma: POST /v1/checkout retornando 403 em massa.
- Causa raiz: CRS rule 942100 (SQLi detector PL2) interpretou `tracking.landing_url = "https://www.viralefy.com/us/instagram-followers"` como SQLi pattern (hyphen + multi-segment path + scheme).
- Fix: exclusion targetada por `REQUEST_URI @beginsWith /v1/checkout` + `ruleRemoveById=942100`.
- Detection gap: smoke não cobria POST /v1/checkout com payload real — só `/v1/plans` GET. Fix preventivo em `viralefy-smoke` (2026-06-11) adiciona check #6 com payload REAL do CheckoutModal incluindo `tracking.landing_url`.

**Checklist**:
```bash
# 1. Identifica o request bloqueado
tail -200 /var/log/caddy-waf/audit.log | grep -iE 'blocked|denied|score' | tail -20

# 2. Pega o ID da rule (campo "id" ou "ruleId")
# Ex: 942100 (SQLi false positive em campo descrição/URL), 941100 (XSS em rich text)

# 3. Identifica path/método/payload do request real
journalctl -u caddy --since '15 min ago' | grep -i "<request_id_do_audit>"

# 4. Confirma que é FP (não ataque real) — repete request controlado
curl -i 'https://api.viralefy.com/<endpoint>' -d '<payload-do-user>'

# 5. Confirma com smoke (mais rápido que reproduzir cliente)
viralefy-smoke 2>&1 | tail -15
# Smoke #6 já cobre POST /v1/checkout com tracking real desde 2026-06-11.
```

**Mitigação — exclusão temporária**:
```bash
# Edita o arquivo de exclusions (template em /etc/caddy/coraza/coraza-crs-exclusions.conf)
vim /etc/caddy/coraza/coraza-crs-exclusions.conf

# Exemplo: desliga rule 942100 só pro path /v1/checkout
# SecRule REQUEST_URI "@beginsWith /v1/checkout" \
#   "id:90099,phase:1,nolog,pass,ctl:ruleRemoveById=942100"

# Valida sintaxe
caddy validate --config /etc/caddy/Caddyfile

# Reload (zero-downtime)
systemctl reload caddy

# Verifica que real user passa
curl -i 'https://api.viralefy.com/<endpoint>' -d '<payload-do-user>'
tail -5 /var/log/caddy-waf/audit.log

# E roda smoke pra confirmar regression test passa
viralefy-smoke
```

**Follow-up obrigatório** (vira ticket SEV3):
- Avalia se a regra precisa ajuste permanente (mover pra `coraza-crs-setup.conf`) ou se exclusion específica basta.
- Roda full smoke pra garantir que exclusion não abriu hole nem regrediu outro endpoint.
- Documenta no `CORAZA-SOAK-STATUS.md`.
- Se exclusion foi pra novo endpoint, considera adicionar check #N no `viralefy-smoke` com payload representativo (lição 2026-06-10).

**Prevenção sistêmica**:
- `viralefy-smoke` deve incluir POST com payloads REAIS pra TODO endpoint mutativo que aceita campos de URL/path-like de usuário (landing_url, referrer, return_url, callback_url, etc.). Esses campos são o vetor #1 de FP Coraza.
- Fixtures usam pattern `*@viralefy.test` — cleanup automático via `viralefy-test-cleanup.timer` (hourly).
- Métricas `viralefy_test_cleanup_rows_total` no Grafana — spike indica smoke ou CI maluco.

---

### Playbook G — Disk space alert

**Sintoma**: alerta `DiskFull` (> 85% raiz) ou `df -h /` mostra pressure.

**Triagem**:
```bash
df -h /
du -sh /var/log /var/backups /var/lib/postgresql /var/lib/viralefy-storage /var/lib/docker 2>/dev/null
du -sh /var/log/caddy-waf /var/log/journal 2>/dev/null

# Top 20 maiores arquivos
find / -xdev -type f -size +100M 2>/dev/null | head -20
```

**Suspeitos comuns**:

| Local | Causa típica | Cleanup seguro |
|---|---|---|
| `/var/backups/viralefy/dump-*.sql.gz` | retention policy não rodou | `find /var/backups/viralefy -name 'dump-*.sql.gz' -mtime +30 -delete` (preserva ≥ 30 dias) |
| `/var/log/caddy-waf/audit.log` | WAF em DetectionOnly verbose | logrotate: `logrotate -f /etc/logrotate.d/caddy-waf` ou trunca após cópia |
| `/var/log/journal` | journal sem cap | `journalctl --vacuum-time=14d` |
| `/var/lib/prometheus` | retention longo | revisa `--storage.tsdb.retention.time` em `viralefy_ops/systemd/prometheus.service` |
| `/var/lib/loki` | retention default infinito | revisa `loki.yaml` retention_period |
| `/var/lib/docker` | imagens órfãs (storage stack) | `docker system prune -af --volumes` (CUIDADO: confirma que MinIO data está em bind mount) |

**Nunca apaga sem confirmar**:
- backups < 7 dias
- WAL do Postgres em `/var/lib/postgresql/16/main/pg_wal/`
- dados em `/var/lib/viralefy-storage/` (MinIO buckets)

**Último recurso**: upgrade da VPS (snapshot Hetzner + resize). Requer janela de manutenção.

---

### Playbook H — Database degraded (queries slow)

**Sintoma**: latência p99 > 5s, dashboard mostra DB saturation, `viralefy-smoke` lento.

**Diagnóstico**:
```bash
# Conexões ativas e estados
sudo -u postgres psql -d viralefy -c "
  SELECT state, count(*) FROM pg_stat_activity
  WHERE datname='viralefy' GROUP BY state;"

# Queries mais longas em execução
sudo -u postgres psql -d viralefy -c "
  SELECT pid, now()-query_start AS duration, state, left(query, 100) AS query
  FROM pg_stat_activity
  WHERE state != 'idle' AND datname='viralefy'
  ORDER BY duration DESC NULLS LAST LIMIT 20;"

# Locks
sudo -u postgres psql -d viralefy -c "
  SELECT l.locktype, l.mode, l.granted, a.query, a.pid, a.usename
  FROM pg_locks l JOIN pg_stat_activity a ON l.pid=a.pid
  WHERE NOT l.granted;"

# Tamanho das tabelas (bloat?)
sudo -u postgres psql -d viralefy -c "
  SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
  FROM pg_catalog.pg_statio_user_tables
  ORDER BY pg_total_relation_size(relid) DESC LIMIT 15;"

# Conexões vs max
sudo -u postgres psql -c "SHOW max_connections;"
```

**Mitigação**:
```bash
# Mata query específica (CUIDADO: só queries SELECT, nunca DML em produção sem confirmar)
sudo -u postgres psql -d viralefy -c "SELECT pg_terminate_backend(<pid>);"

# Conexões esgotadas: restart dos services consome todo o pool, reinicia em ordem
systemctl restart viralefy-dispatcher viralefy-auth viralefy-core viralefy-payments viralefy-sender

# Estatísticas stale (planner errado)
sudo -u postgres psql -d viralefy -c "ANALYZE;"

# Bloat severo (último recurso, lock pesado): VACUUM FULL <tabela>
# NÃO roda VACUUM FULL em produção sem maintenance window
```

**Follow-up**: investiga query no Tempo/Grafana, adiciona índice se padrão se repetir, considera connection pooler (pgbouncer).

---

## 5. Recovery & Rollback Procedures

### 5.1. Code rollback (deploy ruim)

```bash
# Identifica SHA anterior do repo afetado
ssh -i /media/sonne/Archives/projects/viralefy/credentials root@62.238.41.231
cd /viralefy/<repo>           # ex: /viralefy/core
git log --oneline -10

# Checkout do SHA anterior
git checkout <prev-sha>

# Re-build + restart (zero-downtime)
viralefy-update --yes

# Fallback rápido (binário anterior preservado pelo updater)
mv /viralefy.prev/<svc> /viralefy/<svc> && systemctl restart viralefy-<svc>

# Verifica
viralefy-smoke
```

### 5.2. Caddyfile rollback

```bash
# Lista backups (gerados a cada edit pelo installer/manual)
ls -lt /etc/caddy/Caddyfile.bak.* | head -10

# Restaura
cp /etc/caddy/Caddyfile.bak.<timestamp> /etc/caddy/Caddyfile

# Valida ANTES de reload
caddy validate --config /etc/caddy/Caddyfile

# Reload zero-downtime
systemctl reload caddy

# Se falhar reload: restart (causa breve 502)
systemctl restart caddy
```

**Maintenance page template** (quando precisa cortar tráfego):
```caddy
# /etc/caddy/Caddyfile.maintenance
{
  admin off
}
*.viralefy.com, viralefy.com {
  respond "Manutenção em andamento. Voltamos em breve. — equipe Viralefy" 503
}
```

### 5.3. Database rollback (catastrófico — apaga e restaura)

> Use só se DB foi corrompido por incidente. Perde dados desde último dump (RPO ≤ 24h).

```bash
# Confirma último dump válido
ls -lt /var/backups/viralefy/dump-*.sql.gz | head -5
viralefy-backup-verify --latest    # verifica integridade

# Para todos os services (writers)
systemctl stop 'viralefy-*'

# Snapshot do estado atual ANTES de destruir (forense)
sudo -u postgres pg_dump viralefy | gzip > /var/backups/pre-rollback-$(date +%s).sql.gz

# Drop + recreate
sudo -u postgres psql -c "DROP DATABASE viralefy;"
sudo -u postgres psql -c "CREATE DATABASE viralefy OWNER viralefy;"

# Restore
zcat /var/backups/viralefy/dump-<incident-stamp>.sql.gz | \
  sudo -u postgres psql -d viralefy

# Sobe services
systemctl start viralefy-core viralefy-auth viralefy-dispatcher viralefy-payments viralefy-sender viralefy-api viralefy-front viralefy-backoffice

# Smoke
viralefy-smoke
```

### 5.4. Coraza/CRS rollback

```bash
ls -lt /etc/caddy/coraza/coraza.conf.bak.* | head -5
cp /etc/caddy/coraza/coraza.conf.bak.<ts> /etc/caddy/coraza/coraza.conf

# Exclusions também:
ls -lt /etc/caddy/coraza/coraza-crs-exclusions.conf.bak.* | head -5

caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
```

### 5.5. Migration rollback (Postgres)

```bash
# schema_migrations tracker (estilo Laravel) controla aplicadas
sudo -u postgres psql -d viralefy -c "SELECT * FROM schema_migrations ORDER BY id DESC LIMIT 10;"

# Se migration N quebrou em prod, mas DB ainda íntegro:
# 1. Para services
# 2. Aplica reverse manual (não temos `down` automático no tracker)
# 3. DELETE da row em schema_migrations
# 4. Re-deploy versão anterior do código (sem essa migration)

# Se DB corrompido: prefere §5.3 (full restore)
```

---

## 6. Communication Templates

### 6.1. Internal — abertura war room (Slack/Discord webhook)

```
:rotating_light: SEV-{1|2|3|4} declarado — {YYYY-MM-DD HH:MM BRT}

Service: {core|auth|dispatcher|payments|sender|caddy|postgres|todos}
Sintoma: {descrição em 1 linha}
Causa hipótese: {1-2 linhas, ou "investigando"}
Impacto: {usuários afetados / features down}
ETA mitigação: {tempo estimado, ou "investigando"}
Owner: {nome do on-call}
War room: {link/canal}
Updates a cada: {30min SEV1 / 1h SEV2 / 4h SEV3}
```

### 6.2. Internal — update progress

```
:hourglass_flowing_sand: SEV-{N} update — {HH:MM BRT}

Status: {investigando | mitigando | monitorando | resolvido}
Ações desde último update:
- {ação 1}
- {ação 2}
Próximos passos:
- {passo 1}
ETA: {hora estimada / "monitorando estabilidade"}
```

### 6.3. Internal — resolução

```
:white_check_mark: SEV-{N} RESOLVIDO — {HH:MM BRT}

Duração total: {Xh Ym}
Causa raiz: {1-2 linhas}
Mitigação aplicada: {1-2 linhas}
Impacto final: {usuários afetados, dados perdidos sim/não, downtime}
Post-mortem: agendado para {data} — owner: {nome}
```

### 6.4. External — user-facing (status page / email / banner)

**Inicial (SEV1/SEV2)**:
> "Estamos investigando uma instabilidade em algumas funcionalidades da Viralefy. Nosso time já está trabalhando na correção. Próxima atualização em {tempo}. Pedimos desculpas pelo transtorno."

**Progress**:
> "Atualização: identificamos a causa e estamos aplicando a correção. Algumas funcionalidades podem estar lentas ou indisponíveis. Próxima atualização em {tempo}."

**Resolução**:
> "Funcionalidades restabelecidas a partir das {HH:MM}. Se você ainda estiver com problemas, por favor entre em contato com nosso suporte. Agradecemos a paciência."

**Security (LGPD — só se acionar Art. 48)**:
> Coordenado com DPO e jurídico. Template em [COMPLIANCE.md](COMPLIANCE.md).

### 6.5. Post-resolution — anúncio interno

```
Post-mortem disponível: {link archive}
Action items: {N} itens, owners atribuídos, prazo {data}
Trends a observar: {métricas no dashboard}
```

---

## 7. Post-Incident Review (PIR) Template

Cria arquivo `viralefy_archive/post-mortems/PIR-YYYY-MM-DD-<slug>.md`:

```markdown
# PIR — <título curto do incidente>

**Data**: YYYY-MM-DD
**SEV**: 1|2|3|4
**Duração**: Xh Ym (detecção → resolução)
**Owner do PIR**: <nome>

## Resumo executivo
<3-5 linhas: o que aconteceu, impacto, como foi mitigado>

## Timeline (BRT, minuto a minuto)
| Hora | Ator | Ação | Resultado |
|---|---|---|---|
| HH:MM | <alerta/usuário> | <evento> | <observado> |
| HH:MM | <on-call> | <comando/ação> | <resultado> |
| ... | ... | ... | ... |

## Detecção
- Como foi detectado: <alerta / user report / observação>
- Tempo até detecção (TTD): X min
- Tempo até acknowledge (TTA): X min
- Tempo até mitigação (TTM): X min
- Tempo até resolução (TTR): X min

## Causa raiz (5 Whys)
1. Por que <sintoma>? — <resposta>
2. Por que <resposta 1>? — <resposta>
3. Por que <resposta 2>? — <resposta>
4. Por que <resposta 3>? — <resposta>
5. Por que <resposta 4>? — <causa raiz>

## Impacto
- Usuários afetados: <número ou %>
- Dados perdidos: sim/não — <detalhes>
- PII/LGPD: sim/não — <detalhes>
- Receita perdida estimada: <R$ ou "não mensurável">
- Downtime: <minutos>

## O que funcionou bem
- <ponto 1>
- <ponto 2>

## O que poderia melhorar
- <ponto 1>
- <ponto 2>

## Action items
| ID | Item | Owner | Prazo | Tipo |
|---|---|---|---|---|
| AI-1 | <ação> | <nome> | YYYY-MM-DD | preventivo/detecção/processo |
| AI-2 | ... | ... | ... | ... |

## Lições aprendidas (pra MEMORY/CHECKLIST)
- <lição 1>
- <lição 2>
```

**Regras de PIR**:
- Blameless. Foca em sistemas e processos, nunca em pessoas.
- Roda em até 5 dias úteis após resolução.
- Action items entram no CHECKLIST.md com owner real e deadline real.
- Lições viram updates no CONTEXT.md / MEMORY.

---

## 8. Contacts

### Internos
| Papel | Contato | Notas |
|---|---|---|
| Operador primário | (definir) | on-call default |
| Operador secundário | (definir) | backup |
| DPO (LGPD) | (a definir antes de prod com PII real) | bloqueante pra security incident com PII |
| Cliente principal | viralefy@gmail.com | comunicação de SEV1/SEV2 |

### Externos
| Serviço | Contato | Quando usar |
|---|---|---|
| Hetzner (hosting) | support@hetzner.com / console.hetzner.com | VPS down, rede, snapshot |
| Domain registrar | (definir — Cloudflare / Registro.br) | DNS issues, transferência |
| Stripe Brasil | dashboard.stripe.com → Help | fraudes, chargebacks coordenados, webhook |
| Heleket | (a definir — dashboard) | webhook crypto, settlement |
| AbacatePay | (a definir — dashboard) | PIX issues |
| Resend | resend.com/dashboard | email transacional não chega |
| ANPD (LGPD) | comunicacao@anpd.gov.br | Art. 48 — 72h notification |

> **TODO crítico**: preencher contatos pendentes ANTES de aceitar PII real em produção. Ver [COMPLIANCE.md](COMPLIANCE.md).

---

## 9. Anexo — Cheat sheet de comandos críticos

### Acesso rápido
```bash
# SSH
ssh -i /media/sonne/Archives/projects/viralefy/credentials root@62.238.41.231

# Psql como app
PGPASSWORD=$(grep DATABASE_URL /etc/viralefy/.env | sed 's/.*:\(.*\)@.*/\1/') \
  psql -U viralefy -h localhost -d viralefy

# Psql como superuser
sudo -u postgres psql -d viralefy
```

### Triagem em 30 segundos
```bash
viralefy-status                   # systemd + binários
viralefy-smoke                    # E2E curl em todos endpoints críticos
systemctl list-units --failed     # qualquer unit em estado failed
journalctl --since '15 min ago' -p err --no-pager | tail -50
df -h /                            # disco
free -h                            # memória
uptime                             # load average
```

### Logs por service
```bash
journalctl -u viralefy-core       -f --since '10 min ago'
journalctl -u viralefy-auth       -f --since '10 min ago'
journalctl -u viralefy-dispatcher -f --since '10 min ago'
journalctl -u viralefy-payments   -f --since '10 min ago'
journalctl -u viralefy-sender     -f --since '10 min ago'
journalctl -u viralefy-api        -f --since '10 min ago'
journalctl -u viralefy-front      -f --since '10 min ago'
journalctl -u viralefy-backoffice -f --since '10 min ago'
journalctl -u caddy               -f --since '10 min ago'

# Combinado (todos services Viralefy)
journalctl -u 'viralefy-*' -f --since '10 min ago' -p info
```

### Restarts
```bash
# Single
systemctl restart viralefy-<svc>

# Todos (em ordem: infra → backend → frontend)
systemctl restart viralefy-dispatcher viralefy-auth viralefy-core
systemctl restart viralefy-payments viralefy-sender
systemctl restart viralefy-api viralefy-front viralefy-backoffice
systemctl reload caddy
```

### Deploy & rollback
```bash
# Deploy padrão (zero-downtime)
viralefy-update --yes

# Deploy destrutivo (rebuild completo, ~5min)
viralefy-update --legacy

# Rollback binário rápido
mv /viralefy.prev/<svc> /viralefy/<svc> && systemctl restart viralefy-<svc>

# Rollback de SHA
cd /viralefy/<repo> && git checkout <prev-sha> && viralefy-update --yes
```

### Backups
```bash
# Manual on-demand
viralefy-backup

# Verifica último
viralefy-backup-verify

# Lista
ls -lah /var/backups/viralefy/dump-*.sql.gz | tail -10

# Restore (full, destrói DB atual — ver §5.3)
zcat /var/backups/viralefy/dump-<stamp>.sql.gz | sudo -u postgres psql -d viralefy
```

### Postgres triagem
```bash
# Conexões
sudo -u postgres psql -d viralefy -c \
  "SELECT state, count(*) FROM pg_stat_activity WHERE datname='viralefy' GROUP BY state;"

# Queries longas
sudo -u postgres psql -d viralefy -c "
  SELECT pid, now()-query_start AS dur, left(query,80) FROM pg_stat_activity
  WHERE state != 'idle' AND datname='viralefy' ORDER BY dur DESC NULLS LAST LIMIT 10;"

# Kill query
sudo -u postgres psql -d viralefy -c "SELECT pg_terminate_backend(<pid>);"

# Tamanhos
sudo -u postgres psql -d viralefy -c "
  SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
  FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;"
```

### Caddy / WAF
```bash
# Valida config antes de reload
caddy validate --config /etc/caddy/Caddyfile

# Reload zero-downtime
systemctl reload caddy

# Logs WAF (audit)
tail -100 /var/log/caddy-waf/audit.log

# Audit log filtrado por blocked
grep -i 'blocked\|denied' /var/log/caddy-waf/audit.log | tail -20

# Backups Caddyfile
ls -lt /etc/caddy/Caddyfile.bak.* | head -5
```

### Sessions & secrets (security incident)
```bash
# Revoga todas as sessions
sudo -u postgres psql -d viralefy -c "DELETE FROM sessions;"

# Restart dispatcher pra recarregar revocation set
systemctl restart viralefy-dispatcher

# Edita secrets (perms 0640 root:viralefy)
vim /etc/viralefy/.env
chmod 0640 /etc/viralefy/.env
chown root:viralefy /etc/viralefy/.env

# Rotaciona Postgres password
sudo -u postgres psql -c "ALTER USER viralefy WITH PASSWORD '<nova>';"
# Atualiza DATABASE_URL em /etc/viralefy/.env
# Restart todos services
systemctl restart 'viralefy-*'
```

### Maintenance mode (cortar tráfego)
```bash
# Salva config atual
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.maint-$(date +%s)

# Aplica config maintenance (template em §5.2)
cp /etc/caddy/Caddyfile.maintenance /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

# Reverte
cp /etc/caddy/Caddyfile.bak.maint-<ts> /etc/caddy/Caddyfile
systemctl reload caddy
```

### Espaço em disco — cleanup safe
```bash
# Journal antigo
journalctl --vacuum-time=14d

# Backups antigos (preserva ≥ 30 dias)
find /var/backups/viralefy -name 'dump-*.sql.gz' -mtime +30 -delete

# Logs rotacionados antigos
find /var/log -name '*.gz' -mtime +30 -delete

# Docker (storage stack) — CUIDADO
docker system prune -af   # NÃO use --volumes sem confirmar bind mounts
```

### Observability
```bash
# Grafana
https://obs.viralefy.com   # admin / GRAFANA_ADMIN_PASSWORD em /etc/viralefy/.env

# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job,health}'

# Alerts ativos
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name:.labels.alertname,state}'
```

---

## 10. Manutenção deste runbook

- **Após CADA incidente SEV1/SEV2**: revisa playbook usado, adiciona caso novo, refina checklist.
- **Trimestral**: tabletop exercise — simula SEV1 random com a equipe.
- **Quando stack mudar** (novo service, novo provider, mudança de infra): atualiza §4 e §8.
- **Versão**: este arquivo segue mesma cadência de update do CHECKLIST.md/CONTEXT.md.

> Quem encerrar uma task de operação atualiza este runbook + CONTEXT.md + CHECKLIST.md, commit + push. Sem exceções.
