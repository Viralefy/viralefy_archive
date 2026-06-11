# ADR-0004 — viralefy_api LEGACY em soak até 2026-06-24

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §2 (um repo = um bounded context), §21 (Estratégia de Deploy), §36 (Evolução incremental)
- **Reavaliação:** 2026-06-24 (fim da janela de soak)

## Contexto e Problem Statement

Em 2026-06-10 07:36 UTC, no encerramento da PHASE-9 (cutover de 104 rotas para o dispatcher Rust + microservices), o serviço `viralefy-api` (Go, porta 8080) foi **stopped + disabled** no systemd. O repositório `viralefy_api/` permanece no workspace porque:

1. **Soak window de 14 dias** (até 2026-06-24) para confirmar que nenhuma rota legacy ainda é necessária.
2. Conteúdo do repo é **espelho do `viralefy_core`** (mesmo código, divergência mínima); manter por enquanto facilita rollback emergencial.
3. `viralefy_archive/CHECKLIST.md` lista repo como "STOPPED, soak".

Estado verificado (2026-06-11):

- `viralefy-update` (instalador ops) **pula** o legacy via marker `/etc/viralefy/.legacy-deprecated`.
- `viralefy-smoke` aponta para `:8090` (dispatcher), não `:8080`.
- Prometheus scrape do `viralefy-api` está **comentado** em `prometheus.yml` para não disparar `ApiDown`.
- Caddyfile default fallback aponta para dispatcher `:8090`.
- Nenhum tráfego legítimo deveria atingir `:8080`.

## Decision Drivers

- Rollback safety: cutover de 104 rotas precisa janela de soak para garantir que nenhum cliente externo, cron interno ou job batch ainda usa caminho legacy.
- Disk/git history: arquivar agora é destrutivo; arquivar pós-soak preserva flexibilidade.
- Custo de manter: zero (processo parado), mas confunde devs futuros.

## Decision Outcome

**Aceito:** manter `viralefy_api/` em soak até **2026-06-24 00:00 UTC**.

Pós-soak (a partir de 2026-06-25), executar:

### Cleanup plan (a executar em 2026-06-25)

1. **Confirmar zero tráfego em `:8080`** nas últimas 14 dias via logs (`journalctl -u viralefy-api --since "14 days ago"` deve mostrar apenas startup ou nada).
2. **Confirmar zero referências externas:**
   - Cloudflare/DNS aponta apenas para dispatcher.
   - Nenhum cron interno chama `:8080`.
3. **Snapshot final** do repo (tag `legacy-final-2026-06-25`).
4. **Arquivar no GitHub:** Repository Settings → Archive (read-only, mantém histórico).
5. **Remover do workspace local:** `rm -rf viralefy_api/`.
6. **Atualizar referências:**
   - `viralefy_archive/CHECKLIST.md` — marcar legacy como `ARCHIVED`.
   - `viralefy_archive/CONTEXT.md` — remover linha "Legacy api stopped".
   - `viralefy_ops/installer/` — remover marker `/etc/viralefy/.legacy-deprecated` (não mais necessário).
   - `prometheus.yml` — remover scrape comentado.
7. **Remover systemd unit** `viralefy-api.service` do `viralefy_ops/systemd/`.

### Rollback emergencial (se necessário antes do soak fim)

Se algum problema crítico surgir antes de 2026-06-24:

```bash
systemctl enable --now viralefy-api
# Editar Caddyfile: rota afetada → :8080 em vez de :8090
caddy reload
```

Não esperar a janela acabar para arquivar se incidente acontecer; a soak existe para detectar problemas, não para esperá-los.

## Triggers para Reabertura

- Tráfego inesperado em `:8080` durante soak → investigar antes de arquivar.
- Rota não migrada descoberta → estender soak + plano de migração explícito.

## Consequences

### Positivas

- Janela razoável para detectar regressões silenciosas pós-cutover.
- Rollback de 1 comando se necessário.
- Histórico git preservado pós-archive no GitHub.

### Negativas

- Confusão potencial para devs novos: "por que tem dois repos quase iguais?".
- Custo de revisar PRs de bots (Renovate, Dependabot) em repo morto. Mitigação: configurar Renovate para `dependencyDashboard: false` no `viralefy_api` durante soak, ou pausar.

## Links

- Diretrizes §21, §36
- `viralefy_archive/CHECKLIST.md` — seção "Cutover PHASE-9"
- `viralefy_archive/PHASE-9-ARCHITECTURE.md`
- Marker: `/etc/viralefy/.legacy-deprecated` (prod)
