# RUNBOOK-DR — Disaster Recovery (Viralefy)

Alvo: **restaurar produção do zero em uma VPS nova em menos de 30 minutos**, com banco íntegro do último backup, TLS válido e smoke E2E verde.

Não é um plano de HA. É um plano de RTO baixo com RPO ≤ 24h (último dump em [/var/backups/viralefy/](../viralefy_ops/bin/viralefy-backup)).

---

## 1. Pré-requisitos (ter ANTES de começar a contar o tempo)

| Item | Onde fica em condições normais | Cópia offline obrigatória |
|---|---|---|
| Chave SSH do operador (ed25519) | `~/.ssh/id_ed25519` na máquina do operador | Cofre 1Password / YubiKey backup |
| Último dump `dump-*.sql.gz` | `/var/backups/viralefy/` na VPS antiga | Sincronizado p/ S3/R2 + 1 cópia local cifrada |
| `/etc/viralefy/.env` cifrado | host antigo | `.env.gpg` no cofre — contém `RESEND_API_KEY`, `JWT_SECRET`, `DATABASE_PASSWORD`, `TWOFA_ENCRYPTION_KEY`, `INTERNAL_SHARED_SECRET`, `STORAGE_*`, `GRAFANA_ADMIN_PASSWORD`, domínios |
| Credenciais DNS do provider (Cloudflare/Route53) | dashboard | API token salvo no cofre |
| IP da nova VPS | provisionada na Fase A | — |
| `/var/lib/viralefy-storage/` (MinIO) | host antigo | Sincronizado p/ R2 ou tarball semanal em S3 |
| Org GitHub `Viralefy` acessível | público | sem segredo necessário (clone HTTPS) |

> **Se faltar o `.env.gpg`**, segredos podem ser **regerados** pelo installer (Postgres password, JWT, internal token, 2FA key, INDEXNOW secret). Custo: invalida sessões ativas (re-login), invalida 2FA enrollments (re-enroll), invalida JTI de webhooks pendentes (reemissão). **`RESEND_API_KEY` e `STORAGE_*` não podem ser regenerados sem coordenação externa** — ver Fase D e §4.

---

## 2. Inventário do que precisa ser restaurado

1. **Sistema base** — Ubuntu 24.04, swap mínimo, hostname.
2. **Pacotes** — instalados pelo [00-prereqs.sh](../viralefy_ops/installer/00-prereqs.sh): Go 1.26.3, Node 24, PostgreSQL 16, Caddy, Docker (storage).
3. **Código** — 10 repos clonados em `/viralefy/{api,front,backoffice,payments,sender,core,auth,dispatcher,ops,archive}` — ver `PACKAGES` em [lib.sh](../viralefy_ops/installer/lib.sh).
4. **Postgres** — role `viralefy`, DB `viralefy`, **39 migrations aplicadas + dados restaurados do dump**.
5. **Segredos** — `/etc/viralefy/.env` (perms 0640, root:viralefy) — ver [30-secrets.sh](../viralefy_ops/installer/30-secrets.sh).
6. **systemd units** — 7 services Viralefy + 6 obs + `viralefy-backup.timer` — ver [60-systemd.sh](../viralefy_ops/installer/60-systemd.sh).
7. **Caddy** — `/etc/caddy/Caddyfile` + `/etc/caddy/viralefy.env` — emissão Let's Encrypt automática pós DNS swap.
8. **MinIO** — `/var/lib/viralefy-storage/` + buckets `viralefy-proofs`, `viralefy-public`.
9. **Observabilidade** — Grafana/Loki/Tempo/Prometheus/Alloy/node_exporter.
10. **DNS** — A records dos 4 subdomínios apontando p/ novo IP.

---

## 3. Fases e comandos exatos

> Tempo nominal: 30min. Os tempos por fase pressupõem VPS ≥4GB RAM, 2vCPU, link ≥100Mbit. Em VPS undersized, build (Fase B) é o gargalo — pré-construir AMI/imagem cortaria ~5min.

### Fase A — Provisão + acesso (0-5 min)

```bash
# 1.1  (operador) Provisionar VPS Ubuntu 24.04 minimal, 4GB RAM, IPv4 público.
#       Hetzner CX22 / OCI A1.Flex / Vultr — qualquer um serve.
#       Anotar IP: export NEW_IP=1.2.3.4

# 1.2  Subir chave SSH na criação (não usar password). Login imediato:
ssh -o StrictHostKeyChecking=accept-new root@$NEW_IP

# 1.3  (na VPS) sanity + apt cache fresco — o installer roda apt update,
#       mas adiantamos pra paralelizar com download de pacotes.
hostnamectl set-hostname viralefy-prod
apt-get update -y && apt-get install -y curl ca-certificates
timedatectl set-timezone UTC

# 1.4  Reservar swap mínimo (Node build estoura RAM em 4GB sem swap).
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**Checkpoint A**: SSH ok, `free -m` mostra swap, `apt-get update` exit 0.

### Fase B — Install do stack (5-12 min)

```bash
# 2.1  Subir o .env.gpg do cofre p/ /root/.env.gpg ANTES de rodar o installer.
#       Assim o installer preserva os segredos existentes em vez de gerar novos.
scp ./.env.gpg root@$NEW_IP:/root/.env.gpg                       # local → VPS
ssh root@$NEW_IP                                                 # entrar

mkdir -p /etc/viralefy
gpg --decrypt /root/.env.gpg > /etc/viralefy/.env
chmod 0640 /etc/viralefy/.env
# chown root:viralefy é feito pelo installer (grupo ainda não existe).

# 2.2  Rodar o installer one-shot. Bootstrap clona viralefy_ops e exec.
#       Domínios e CADDY_EMAIL: ler do .env já decifrado (já estão lá).
curl -fsSL https://raw.githubusercontent.com/Viralefy/viralefy_ops/main/bin/bootstrap.sh | bash
```

O installer ([viralefy-install](../viralefy_ops/bin/viralefy-install)):
- instala Go/Node/PG/Caddy/Docker;
- cria users/grupo `viralefy`;
- **preserva** segredos existentes em `/etc/viralefy/.env` (linha 24 de [30-secrets.sh](../viralefy_ops/installer/30-secrets.sh));
- cria role + DB Postgres vazios + 39 migrations aplicadas no boot da API;
- clona os 10 repos, builda Go (paralelo) + Node, instala units, habilita.

**Importante**: nesta fase o **DB ainda está vazio** (só schema das migrations). API vai subir, mas dados de produção ainda não voltaram. A próxima fase substitui o conteúdo.

**Checkpoint B**:
```bash
systemctl is-active viralefy-{api,payments,sender,front,backoffice,core,auth,dispatcher} caddy postgresql
# Esperado: active em api/payments/sender/front/backoffice/caddy/postgresql.
# core/auth/dispatcher podem estar inactive — são phase-9, opcionais.
```

### Fase C — Restore Postgres do dump (12-18 min)

```bash
# 3.1  Subir o dump mais recente do cofre. Dump nasce de pg_dump --format=plain,
#       então é gzip de SQL bruto — restore = psql, não pg_restore.
scp ./dump-LATEST.sql.gz root@$NEW_IP:/var/backups/viralefy/dump-restore.sql.gz

# 3.2  Parar quem escreve no banco ANTES de dropar — evita race.
systemctl stop viralefy-api viralefy-payments viralefy-sender \
                viralefy-core viralefy-auth viralefy-dispatcher 2>/dev/null

# 3.3  Drop + recreate. Schema completo vem do dump (migrations já estavam
#       aplicadas no momento do pg_dump).
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
DROP DATABASE IF EXISTS viralefy;
CREATE DATABASE viralefy OWNER viralefy;
SQL

# 3.4  Restore. --format=plain ⇒ pipe direto pro psql como user viralefy
#       (gera com --no-owner --no-acl no backup, então roda limpo).
gunzip -c /var/backups/viralefy/dump-restore.sql.gz \
  | sudo -u postgres psql -v ON_ERROR_STOP=1 -d viralefy

# 3.5  Sanity: contar linhas em 3 tabelas críticas.
sudo -u postgres psql -d viralefy -c "
  SELECT 'users' AS t, count(*) FROM users
  UNION ALL SELECT 'plans', count(*) FROM plans
  UNION ALL SELECT 'orders', count(*) FROM orders;
"

# 3.6  Re-subir os services.
systemctl start viralefy-payments viralefy-sender
sleep 3
systemctl start viralefy-api
```

**Se `pg_restore` for necessário** (dump em formato custom em vez de plain):
```bash
gunzip -c dump-restore.sql.gz > /tmp/dump.sql                # detect formato
file /tmp/dump.sql                                          # "PostgreSQL custom database dump"?
# Se custom:
sudo -u postgres pg_restore -d viralefy --no-owner --no-acl --clean --if-exists /tmp/dump.sql
```
O backup atual ([viralefy-backup](../viralefy_ops/bin/viralefy-backup) linha 47) usa `--format=plain`, então `psql` é o caminho normal.

**Checkpoint C**:
```bash
curl -fsS http://127.0.0.1:8080/health             # → 200
curl -fsS http://127.0.0.1:8080/v1/plans | jq 'length'   # > 0 se dump tinha planos
```

### Fase D — Restore de storage + segredos remanescentes (18-22 min)

```bash
# 4.1  MinIO data. Se houver snapshot:
systemctl stop docker
tar -xzf storage-snapshot.tar.gz -C /var/lib/viralefy-storage/
chown -R root:root /var/lib/viralefy-storage
systemctl start docker
cd /etc/viralefy-storage && docker compose --env-file /etc/viralefy/.env up -d

# 4.2  Se NÃO houver snapshot: buckets viralefy-proofs e viralefy-public
#       voltam vazios. Comprovantes históricos perdidos. Front continua
#       funcional (uploads novos OK). Documentar como dano aceito.

# 4.3  Validar credenciais MinIO bateram com .env:
docker exec viralefy-storage \
  mc alias set local http://127.0.0.1:9000 "$STORAGE_ACCESS_KEY" "$STORAGE_SECRET_KEY" \
  && docker exec viralefy-storage mc ls local/

# 4.4  Re-aplicar perms se vier de cofre cifrado:
chown root:viralefy /etc/viralefy/.env && chmod 0640 /etc/viralefy/.env
```

**Checkpoint D**: `docker ps | grep viralefy-storage` healthy; `mc ls local/viralefy-proofs` lista (mesmo que vazio).

### Fase E — DNS swap + TLS issuance (22-27 min)

```bash
# 5.1  No DNS provider, atualizar A records dos 4 hostnames p/ $NEW_IP.
#       TTL deve ter sido reduzido pra 60s ANTES do incidente (parte do drill).
#       viralefy.com         A  $NEW_IP
#       www.viralefy.com     A  $NEW_IP   (ou CNAME viralefy.com)
#       backoffice.viralefy.com  A  $NEW_IP
#       api.viralefy.com     A  $NEW_IP
#       obs.viralefy.com     A  $NEW_IP

# 5.2  Validar propagação (usar resolvers múltiplos):
for dns in 1.1.1.1 8.8.8.8 9.9.9.9; do
  dig @$dns +short viralefy.com api.viralefy.com backoffice.viralefy.com obs.viralefy.com
done

# 5.3  Caddy emite Let's Encrypt automaticamente assim que resolve.
#       Forçar reload pra acelerar (Caddy detecta mudança, mas reload é instantâneo):
systemctl reload caddy
journalctl -u caddy -n 100 --no-pager | grep -E 'certificate|obtained|error'

# 5.4  Em caso de rate-limit do Let's Encrypt (renovações repetidas no drill),
#       cair pro staging temporariamente — ver §4.
```

**Checkpoint E**:
```bash
for d in viralefy.com www.viralefy.com api.viralefy.com backoffice.viralefy.com obs.viralefy.com; do
  echo -n "$d: "; curl -sSI "https://$d" | head -1
done
# Esperado: HTTP/2 200 (ou 308 redirect www→apex p/ apex sem www)
```

### Fase F — Smoke E2E + validação (27-30 min)

```bash
# 6.1  Smoke loopback (definição em viralefy-smoke).
/usr/local/sbin/viralefy-smoke

# 6.2  Smoke pelo Caddy (TLS público).
curl -fsS https://api.viralefy.com/health
curl -fsS https://api.viralefy.com/v1/plans | jq 'length'
curl -fsSI https://viralefy.com | head -1
curl -fsSI https://backoffice.viralefy.com | head -1

# 6.3  Auth gate (espera 401):
curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://api.viralefy.com/v1/me/2fa/status

# 6.4  Backup imediato pós-restore (defesa em profundidade — se algo der
#       errado nas próximas horas, este novo dump cobre o pós-restore):
systemctl start viralefy-backup.service
ls -la /var/backups/viralefy/ | tail -3

# 6.5  Confirmar status final:
viralefy-status
```

**Critério Fase F**: ver §6.

---

## 4. Decisões críticas em degradação parcial

| Sintoma | Diagnóstico | Decisão |
|---|---|---|
| **DB restore OK, Caddy não emite TLS** | LE rate limit (5 certs/semana/domínio) ou DNS ainda não propagou | (a) Esperar 5min mais (propagação); (b) trocar pra LE staging via `acme_ca https://acme-staging-v02.api.letsencrypt.org/directory` no Caddyfile pra validar fluxo; (c) usar `tls internal` pra subir HTTPS com CA local, atestar fluxo, só re-trocar quando rate limit zerar |
| **`.env.gpg` perdido** | Cofre comprometido / chave PGP esquecida | Aceitar regeneração. Installer gera `JWT_SECRET`, `DATABASE_PASSWORD`, `TWOFA_ENCRYPTION_KEY`, `INTERNAL_SHARED_SECRET`, `INDEXNOW_SECRET`. **Manual**: pegar `RESEND_API_KEY` no dashboard Resend (key dedicada DR, criada antes), MinIO `STORAGE_*` aceita rotação (novos uploads vão pra credencial nova; objetos antigos viram inacessíveis até backfill). Custo: invalida sessões + 2FA. Comunicar usuários. |
| **Dump corrompido (`pg_restore` aborta a meio)** | gzip truncado / disco cheio durante backup | Voltar pro dump anterior (`ls /var/backups/viralefy/ | sort`). Comunicar RPO degradado p/ a data do dump anterior. |
| **DB OK mas API loop em crash** | `.env` com `DATABASE_URL` apontando p/ outro host, ou `JWT_SECRET` diferente do dump | `journalctl -u viralefy-api -n 200`. Geralmente: senha do role Postgres regenerada não bate. Fix: `sudo -u postgres psql -c "ALTER ROLE viralefy WITH PASSWORD '<da .env>';"` |
| **MinIO sem snapshot** | Bucket de proofs vazio | Continuar. Front aceita uploads novos. Documentar perda em `viralefy_archive/CONTEXT.md`. |
| **Grafana/Loki dados perdidos** | `/var/lib/{grafana,loki,tempo,prometheus}` não foram backupados | Dano aceito. Reconfigurar Grafana admin pwd no primeiro login. Métricas históricas vão ser perdidas. Stack sobe limpa. |
| **VPS nova com IP em blacklist Resend** | E-mails sumindo silenciosamente | Trocar `RESEND_FROM` por subdomínio dedicado pré-aquecido, ou aceitar degradação temporária. |
| **VPS nova com kernel < 5.15** | systemd `MemoryDenyWriteExecute` falha em SystemCallFilter | Editar unit `viralefy-api.service` e remover `MemoryDenyWriteExecute=true`. Documentar. |

---

## 5. Procedimento de TESTE da própria runbook (drill mensal)

Frequência: **toda primeira segunda do mês**, 22:00 UTC.

```bash
# 5.1  Provisionar sandbox VPS (CX22 Hetzner, ~€0.01/h). Não tocar produção.
hcloud server create --name viralefy-dr-drill --type cx22 --image ubuntu-24.04 \
  --ssh-key ops --location nbg1
NEW_IP=$(hcloud server ip viralefy-dr-drill)

# 5.2  Cronometrar:
START=$(date +%s)

# 5.3  Rodar Fases A-F na sandbox, usando:
#      - Dump de PRODUÇÃO da noite anterior (cópia de leitura, não destrói o prod).
#      - .env.gpg de PRODUÇÃO (descifrado só na sandbox; já tem RESEND_API_KEY válida).
#      - Domínios temporários: drill.viralefy.com / api-drill.viralefy.com (A records
#        já mantidos no DNS apontando p/ 127.0.0.1; durante o drill, swap pro IP da
#        sandbox por 1h e devolve).

# 5.4  Critério de sucesso (§6) deve passar em < 30min:
END=$(date +%s)
echo "drill durou $((END - START))s"

# 5.5  Tear-down:
hcloud server delete viralefy-dr-drill
# Devolver DNS dos hosts drill.* pra 127.0.0.1.

# 5.6  Registrar resultado em viralefy_archive/CONTEXT.md:
#      data, duração total, fase mais lenta, achados, ações corretivas.
```

**Acionar revisão da runbook se**:
- duração total > 30min em **2 drills consecutivos**;
- qualquer fase > 150% do tempo nominal;
- procedimento documentado divergir do real (script mudou e ninguém atualizou MD).

---

## 6. Critério "DR drill passou"

Todos devem ser verdadeiros:

1. **Tempo total ≤ 30min** desde provisão da VPS até checkpoint F passar.
2. **`viralefy-smoke` exit 0** — todos os 5 checks (api/pay/sender/health + /v1/plans 200 + 401 em /v1/me/2fa/status sem token).
3. **`systemctl is-active`** retorna `active` para: `viralefy-api`, `viralefy-payments`, `viralefy-sender`, `viralefy-front`, `viralefy-backoffice`, `caddy`, `postgresql`, `viralefy-backup.timer`.
4. **TLS válido** nos 4 hostnames (cert emitido por Let's Encrypt R3/R10, não staging, não local CA — `curl -v https://… 2>&1 | grep 'issuer:'`).
5. **`GET https://api.viralefy.com/v1/plans` → 200** com array não-vazio (prova que dump restaurou).
6. **`viralefy-backup.service` executado pós-restore** com sucesso (`ls /var/backups/viralefy/` mostra dump novo + métricas em `/var/lib/prometheus/node_exporter/viralefy_backup.prom`).
7. **Grafana acessível** em `https://obs.viralefy.com` com login admin/`GRAFANA_ADMIN_PASSWORD`.

Se 1-6 passam e só 7 falha → DR é **aceito**; observabilidade entra em backlog (não é caminho crítico).

---

## Referências de arquivo

- [bin/viralefy-install](../viralefy_ops/bin/viralefy-install) — orquestrador
- [bin/viralefy-backup](../viralefy_ops/bin/viralefy-backup) — gera os dumps que esta runbook consome
- [bin/viralefy-smoke](../viralefy_ops/bin/viralefy-smoke) — smoke pós-restore
- [bin/bootstrap.sh](../viralefy_ops/bin/bootstrap.sh) — one-liner do Fase B
- [installer/lib.sh](../viralefy_ops/installer/lib.sh) — constantes globais (PACKAGES, versões)
- [installer/00-prereqs.sh](../viralefy_ops/installer/00-prereqs.sh) — Go/Node/PG/Caddy
- [installer/10-users.sh](../viralefy_ops/installer/10-users.sh) — users de serviço
- [installer/20-postgres.sh](../viralefy_ops/installer/20-postgres.sh) — role + DB
- [installer/30-secrets.sh](../viralefy_ops/installer/30-secrets.sh) — .env (preserva existentes)
- [installer/35-caddy.sh](../viralefy_ops/installer/35-caddy.sh) — Caddyfile + TLS auto
- [installer/40-clone.sh](../viralefy_ops/installer/40-clone.sh) — clone dos 10 repos
- [installer/50-build.sh](../viralefy_ops/installer/50-build.sh) — Go (paralelo) + Node
- [installer/60-systemd.sh](../viralefy_ops/installer/60-systemd.sh) — units + CLIs em /usr/local/sbin
- [installer/70-start.sh](../viralefy_ops/installer/70-start.sh) — enable+start+wait healthy
- [installer/80-observability.sh](../viralefy_ops/installer/80-observability.sh) — Grafana/Loki/Tempo/Prom/Alloy
- [installer/85-storage.sh](../viralefy_ops/installer/85-storage.sh) — MinIO via docker compose
- [systemd/viralefy-api.service](../viralefy_ops/systemd/viralefy-api.service) — exemplo de hardening
- [systemd/viralefy-backup.timer](../viralefy_ops/systemd/viralefy-backup.timer) — 03:00 UTC diário
- [README.md](../viralefy_ops/README.md) — visão geral do ops

---

## Drill executado 2026-06-10 (simulação local)

Drill local em `/tmp/viralefy-dr-drill/`, sem tocar produção. Hardware do dev (Ryzen + NVMe), Docker `29.1.3`, Go `1.26.3`, Rust stable. Imagens Postgres/Caddy estavam em cache local; MinIO foi puxada na hora.

**Resultado: PASS** (smoke 8/8, total muito abaixo do orçamento de 30min — mesmo na projeção fria).

### Tempo por fase

| Fase | Budget | Real (cache quente) | Projeção fria (mesmo HW) |
|---|---|---|---|
| A — sandbox + dump restore | 300s | 4s | ~6s (pull MinIO domina) |
| B — build paralelo Go(5) + Rust(1) | 420s | <1s (cache) | ~85s (Rust é o gargalo; Go cold=51s) |
| C — start services + migrate up | 360s | 2s | ~5s |
| D — MinIO bucket via `mc` | 240s | 1s | ~3s (pull `mc` image) |
| E — Caddy local reverse-proxy | 300s | 2s | ~3s |
| F — Smoke E2E (8 checks) | 180s | <1s | <1s |
| **Total** | **1800s** | **9s** | **~105s (≈1m45s)** |

### Smoke E2E — 8/8 PASS

- `GET /v1/plans` → 200
- `POST /v1/auth/user/login` (creds inválidas) → 401
- `POST /v1/auth/user/register` → 422 (DB tem schema mas falta seed de país/PPP — esperado em drill)
- `viralefy-api /health` → 200
- `viralefy-payments /internal/health` → 200
- `viralefy-sender /internal/health` → 200
- `viralefy-auth /internal/v1/health` → 200
- `viralefy-core /health` → 200
- `viralefy-dispatcher /internal/health` → 200
- Hot-set: `INSERT INTO revoked_jtis (jti, expires_at)` → row visível em SELECT

### Achados (issues encontrados no drill)

1. **`docker-compose` v1 no Ubuntu 24.04 está quebrado** (`distutils` removido do Python 3.12). Em VPS Ubuntu 24.04 fresca o installer precisa instalar **`docker-compose-plugin`** (v2) e usar `docker compose` em vez de `docker-compose`. Atualmente o [85-storage.sh](../viralefy_ops/installer/85-storage.sh) provavelmente assume um deles — auditar antes do próximo DR real.
2. **Ordem de migrations**: `viralefy-api migrate up` aplica 38, mas faltam 2 (`039_auth_tokens.up.sql`, `040_proof_storage_key.up.sql`) que vivem em [viralefy_core/internal/.../migrations/](../viralefy_core/internal/infrastructure/persistence/postgres/migrations/). Se Fase C só rodar o `viralefy-api migrate up`, o serviço `viralefy-auth` falha no `schema assert` de `refresh_tokens` e fica em crash loop. **Ação**: o installer + a runbook precisam rodar **`viralefy-core migrate up` explicitamente** depois do api. Hoje a runbook documenta só o boot do api — atualizar §3 Fase B/C ou garantir que `70-start.sh` ordene `core` antes de `auth`.
3. **Imagem do `mc` (MinIO Client)** tem `ENTRYPOINT ["mc"]`, então `docker run minio/mc sh -c "..."` falha com `sh is not a recognized command`. Usar `--entrypoint sh`. Pequeno, mas trava o passo 4.3 da §3 se copy-paste literal.
4. **Health paths heterogêneos**: cada serviço expõe um path diferente — api/core em `/health`, payments/sender/dispatcher em `/internal/health`, auth em `/internal/v1/health`. O `viralefy-smoke` precisa cobrir todos; recomendo padronizar em `/internal/v1/health` em todos os repos para um próximo ciclo.
5. **Sem `caddy:2.11`** localmente — usei `caddy:2`. Em prod fresh, o pull do image `caddy:2.11` está no caminho crítico do Fase E. Sugiro pin de `caddy:2-alpine` (menor) ou pré-pull no installer.

### Buracos conhecidos da simulação (não testados aqui)

- TLS Let's Encrypt issuance — pulado (drill HTTP-only). Em DR real é o passo mais imprevisível (rate limit + propagação DNS).
- Coraza WAF — pulado por escolha (simplificar).
- Restore real de `pg_dump --format=plain` de produção (drill usou schema mínimo + migrations limpas).
- `/var/lib/viralefy-storage/` snapshot tarball — bucket subiu vazio.
- Systemd hardening (`MemoryDenyWriteExecute`, etc) — drill rodou via `setsid`, não via systemd unit.
- Observabilidade (Grafana/Loki/Tempo/Prometheus/Alloy) — não testado.

### Recomendações concretas para o próximo DR real

1. **Pré-pullar imagens Docker** no installer (`postgres:16-alpine`, `caddy:2.11`, `minio/minio:latest`, `minio/mc:latest`). Em VPS undersized isso domina A+D+E.
2. **Compilar binários em CI** (release tarballs no GitHub Releases) — Fase B cai de ~85s pra ~3s de download. Maior ganho de RTO disponível.
3. **Migration sequencing**: garantir que `70-start.sh` rode `viralefy-core migrate up` **antes** de subir o `viralefy-auth.service`, ou que o `viralefy-api migrate up` seja substituído por um meta-comando que execute todas as migrations relevantes em ordem.
4. **Smoke script unificado** (`viralefy-smoke`) precisa conhecer os 4 paths de health (`/health`, `/internal/health`, `/internal/v1/health`) ou — melhor — padronizar todos os serviços em `/internal/v1/health`.
5. **Trocar `docker-compose` v1 por `docker compose` (plugin v2)** em todos os scripts. v1 está quebrado em Ubuntu 24.04 com Python 3.12.
6. **`--entrypoint sh` em qualquer `docker run minio/mc`** — refletir na runbook (§3.4 / Fase D).
7. **Documentar a ordem real** de migrations entre os repos (api=38, core+=2) num diagrama curto, pra futuro maintainer não tropeçar.

### Próximo drill: 2026-07-06 (primeira segunda do mês, 22:00 UTC)
