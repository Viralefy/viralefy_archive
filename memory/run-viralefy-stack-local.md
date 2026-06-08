---
name: run-viralefy-stack-local
description: "How to build/run the viralefy stack locally given this machine's environment quirks"
metadata: 
  node_type: memory
  type: project
  originSessionId: 156ce2c8-a44d-4b68-83b1-2ec311c4d144
---

Rodar o ecossistema viralefy (api Go + front/backoffice Next.js) nesta máquina:

- **Go** não está no PATH; binário em `/usr/local/go/bin` (Go 1.26.3). Use `export PATH=$PATH:/usr/local/go/bin`.
- **Postgres do sistema** roda na 5432 mas **não tem o papel `viralefy`** e `docker compose`/`docker-compose` v2 não existem (só docker-compose v1 quebrado). Em vez do `docker-compose.yml` do repo, suba um container: `docker run -d --name viralefy_pg_test -e POSTGRES_USER=viralefy -e POSTGRES_PASSWORD=viralefy -e POSTGRES_DB=viralefy -p 15432:5432 postgres:16-alpine` e aponte `DATABASE_URL=postgres://viralefy:viralefy@localhost:15432/viralefy?sslmode=disable`.
- API: `cd viralefy_api && go run ./cmd/api` (migrations + seed rodam no startup; admin seed `admin@viralefy.local` / `SimTest!Admin2026`). Porta 8080.
- Front: `cd viralefy_front && npm run dev` (porta 3000). Backoffice: `npm run dev` (porta 3001) — backoffice precisava de `npm install` na primeira vez.

**E-mail (SMTP):** o checkout envia e-mail real via `net/smtp` (config por env `SMTP_ADDR/SMTP_USER/SMTP_PASS/SMTP_FROM/SMTP_FROM_NAME`). Sem `SMTP_ADDR` → LogSender (só loga). Para testar local sem provedor, suba Mailpit: `docker run -d --name viralefy_mailpit -p 18025:8025 -p 11025:1025 axllent/mailpit` e use `SMTP_ADDR=localhost:11025`; UI dos e-mails em http://localhost:18025 (API em /api/v1/messages). Em prod, aponte SMTP_ADDR pro provedor (587 STARTTLS).

Em 2026-05-27 o stack como commitado **não compilava**; correções e features adicionadas em [[viralefy-stack-initial-build-fixes]] e [[viralefy-features-v2]]. Node 25 / npm 9 presentes.
