---
name: viralefy-ops-and-github
description: viralefy_ops (installer destrutivo + systemd) e os 5 repos do GitHub Viralefy
metadata: 
  node_type: memory
  type: project
  originSessionId: 156ce2c8-a44d-4b68-83b1-2ec311c4d144
---

Em 2026-05-30 criei o repositório `viralefy_ops` e publiquei os 5 repos do stack em **github.com/Viralefy** (org `Viralefy`, default branch `main`):

- https://github.com/Viralefy/viralefy_ops (novo — installer)
- https://github.com/Viralefy/viralefy_api
- https://github.com/Viralefy/viralefy_front
- https://github.com/Viralefy/viralefy_backoffice
- https://github.com/Viralefy/viralefy_archive

Todos **públicos** (pode trocar pra privado com `gh repo edit Viralefy/<repo> --visibility private`). Branches em todos: `main` + (api/front/backoffice) `feat/product-mvp-v2`. `master` → renomeado `main` antes do push. Autor: `Viralefy <dev@viralefy.local>` + Co-Authored-By Claude. `.env` gitignored em todo lugar.

## viralefy_ops em uma frase

Instala o stack inteiro em `/viralefy/{api,front,backoffice,ops,archive}` rodando via **systemd** com **um usuário system por serviço** (`viralefy-api`/`viralefy-front`/`viralefy-backoffice`, grupo `viralefy`, sem shell), Postgres 16 + role dedicada, segredos persistentes em `/etc/viralefy/.env` (sobrevive a updates), Resend pré-configurado.

## Bootstrap em máquina nova

```bash
curl -fsSL https://raw.githubusercontent.com/Viralefy/viralefy_ops/main/bin/bootstrap.sh \
  | sudo RESEND_API_KEY=re_xxx bash
```

## Deploy HML (2026-05-30)

Servidor HML: **62.238.41.231** (viralefy.com), Debian 13 (trixie), 4 GB RAM, 38 GB disco. SSH `root@62.238.41.231` com chave Ed25519 (a do chat — **rotacionar**). DNS dos 3 subdomínios já apontavam pro IP. Bootstrap rodou em **~3m25s** (Go + Node 24 + PG + Caddy + clone + 3 builds + Let's Encrypt). Cert ativo `viralefy.com` issuer `Let's Encrypt CN=YE1`, válido 90 dias (Caddy renova auto). `viralefy-status` no servidor mostra 4/4 serviços + 5/5 portas + healthchecks loopback e públicos verdes. Em Debian 13, `postgresql-16` específico não existe (vem PG 17); o fallback do installer `apt install postgresql postgresql-client` pega a versão atual da distro — sem ajuste manual.

## Update destrutivo

`sudo viralefy-update` → para serviços → `rm -rf /viralefy/{api,front,backoffice,ops,archive}` → clona ops num `/tmp/viralefy-ops.*` → `exec` no installer dali. Sobrevive ao próprio rm porque se copia pro tmp antes. `/etc/viralefy/.env` e o banco Postgres ficam intocados.

## Estrutura do ops

```
bin/{bootstrap.sh,viralefy-install,viralefy-update,viralefy-status,viralefy-logs}
installer/{lib.sh,00-prereqs,10-users,20-postgres,30-secrets,40-clone,50-build,60-systemd,70-start}.sh
systemd/viralefy-{api,front,backoffice}.service   # hardened
config/env.template
```

## Caddy (v3.1, branch feat/caddy-https)

Caddy é a única superfície pública. Apps escutam só em 127.0.0.1 (API via `BIND_HOST` env, front/backoffice via `-H 127.0.0.1` na `ExecStart` do systemd). Caddyfile em `/etc/caddy/Caddyfile` (lido do `viralefy_ops/config/Caddyfile`) define 3 subdomínios com TLS automático: `{$DOMAIN_FRONT}` → :3000, `{$DOMAIN_BACKOFFICE}` → :3001, `{$DOMAIN_API}` → :8080. Headers: HSTS preload, X-Content-Type-Options, Referrer-Policy, Permissions-Policy(interest-cohort/browsing-topics=()), COOP same-origin, Server/X-Powered-By removidos. Backoffice ganha `X-Frame-Options DENY` + CSP `frame-ancestors 'none'`. Caddy lê vars de `/etc/caddy/viralefy.env` (drop-in `EnvironmentFile`, perms 0640 root:caddy, contém SÓ `DOMAIN_*` + `CADDY_EMAIL` — Caddy não vê DATABASE_URL nem RESEND_API_KEY). `installer/35-caddy.sh` valida com `caddy validate` antes de reload — Caddyfile inválido aborta sem derrubar Caddy ativo. `30-secrets.sh` deriva `CORS_ORIGINS` e `NEXT_PUBLIC_API_URL/SITE_URL` dos domínios automaticamente (não setar à mão).

Defaults dos domínios: `localhost / admin.localhost / api.localhost` — Caddy emite via CA local nesse caso (rode `sudo caddy trust` pra confiar). Domínios reais → Let's Encrypt automático (precisa DNS A/AAAA apontando + `CADDY_EMAIL`).

## Detalhes não óbvios

- CLIs (`viralefy-update`, `-status`, `-logs`) são instaladas em `/usr/local/sbin/` pra sobreviverem ao `rm -rf /viralefy/ops` durante update.
- Systemd units: `NoNewPrivileges`/`ProtectSystem=strict`/`ReadWritePaths=/viralefy/<pkg>`/`SystemCallFilter=@system-service`/`CapabilityBoundingSet=`. `MemoryDenyWriteExecute` SÓ na API Go (Node faz JIT).
- `30-secrets.sh` carrega valores existentes do `.env` se houver, preservando segredos. Gera `JWT_SECRET` (64 bytes urandom) e `DATABASE_PASSWORD` (32) na primeira run.
- `50-build.sh` copia `NEXT_PUBLIC_*` do `/etc/viralefy/.env` para `<dir>/.env.local` antes do `npm run build` (Next precisa no build).
- `20-postgres.sh` adiciona linha SCRAM-SHA-256 específica em `pg_hba.conf` para `viralefy@127.0.0.1`.
- `lib.sh` define `PACKAGES=(api front backoffice)` + `REPO_OF[<pkg>]=viralefy_<pkg>` + helpers `user_of/dir_of/repo_of`. Adicionar pacote = uma linha no array + uma unit systemd.
- A Resend API key colada em chat anteriormente ainda precisa ser **rotacionada** — `30-secrets.sh` pergunta interativamente ou aceita `RESEND_API_KEY=...` no env.

Ver [[run-viralefy-stack-local]] para o setup local (sem ops) e [[viralefy-features-v2]] para o que cada app faz.
